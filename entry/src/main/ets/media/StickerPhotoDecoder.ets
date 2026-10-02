import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { colorSpaceManager } from '@kit.ArkGraphics2D';
import { subjectSegmentation } from '@kit.CoreVisionKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { copySubjectMask, mergeSubjectMasks } from './StickerSubjectMask';

export interface DecodedStickerPhoto {
  pixels: ArrayBuffer;
  width: number;
  height: number;
  premultiplied: boolean;
  colorSpace: colorSpaceManager.ColorSpaceManager;
  fullMask: Uint8Array;
  subjects: Uint8Array[];
  warning: string;
}

/** PixelMap、ImageSource、文件句柄及全局视觉引擎仅由此服务拥有。 */
export class StickerPhotoDecoder {
  private static visionBusy: boolean = false;

  async decode(path: string, detectSubjects: boolean): Promise<DecodedStickerPhoto> {
    let file: fs.File | undefined = undefined;
    let source: image.ImageSource | undefined = undefined;
    let pixels: image.PixelMap | undefined = undefined;
    let diagnosticWidth = 0;
    let diagnosticHeight = 0;
    try {
      file = await fs.open(path, fs.OpenMode.READ_ONLY | fs.OpenMode.NOFOLLOW);
      source = image.createImageSource(file.fd);
      const info: image.ImageInfo = await source.getImageInfo(0);
      const width: number = info.size.width;
      const height: number = info.size.height;
      diagnosticWidth = width; diagnosticHeight = height;
      if (width < 1 || height < 1 || !Number.isSafeInteger(width * height)) throw new Error('照片尺寸无效。');
      const ratio: number = Math.min(1, 1280 / Math.max(width, height));
      pixels = await source.createPixelMap({ index: 0, editable: true,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888, desiredDynamicRange: image.DecodingDynamicRange.SDR,
        desiredSize: { width: Math.max(1, Math.floor(width * ratio)), height: Math.max(1, Math.floor(height * ratio)) } });
      await this.orient(source, pixels);
      let pixelInfo: image.ImageInfo = await pixels.getImageInfo();
      const edge: number = Math.max(pixelInfo.size.width, pixelInfo.size.height);
      if (edge > 1280) { await pixels.scale(1279 / edge, 1279 / edge); pixelInfo = await pixels.getImageInfo(); }
      const w: number = pixelInfo.size.width;
      const h: number = pixelInfo.size.height;
      diagnosticWidth = w; diagnosticHeight = h;
      if (w > 1280 || h > 1280 || pixelInfo.pixelFormat !== image.PixelMapFormat.RGBA_8888) {
        throw new Error('照片无法转换为安全的处理尺寸。');
      }
      const expectedBytes: number = w * h * 4;
      const nativeBytes: number = pixels.getPixelBytesNumber();
      if (!Number.isSafeInteger(nativeBytes) || nativeBytes < expectedBytes || nativeBytes > 16 * 1024 * 1024) {
        throw new Error('照片像素缓冲区无效。');
      }
      const raw: ArrayBuffer = new ArrayBuffer(nativeBytes);
      // PositionArea readPixels converts to BGRA + UNPREMUL, irrespective of the
      // input format. Full-buffer reading retains the verified RGBA format and
      // original alpha type, and the SDK copies logical rows without padding.
      await pixels.readPixelsToBuffer(raw);
      const buffer: ArrayBuffer = nativeBytes === expectedBytes ? raw : raw.slice(0, expectedBytes);
      const result: DecodedStickerPhoto = { pixels: buffer, width: w, height: h,
        premultiplied: pixelInfo.alphaType === image.AlphaType.PREMUL,
        // Raw RGBA has no ICC metadata. Keep the decoded SDR color definition alongside it.
        colorSpace: pixels.getColorSpace(),
        fullMask: new Uint8Array(0), subjects: [], warning: '' };
      hilog.info(0x0, 'StickerCutout', 'stage=decoded size=%{public}dx%{public}d', w, h);
      if (detectSubjects) await this.segment(pixels, result);
      return result;
    } catch (error) {
      this.logError('decode_error', error as BusinessError, diagnosticWidth, diagnosticHeight);
      throw new Error((error as Error).message || '照片无法解码，请重新选择。');
    } finally {
      if (pixels !== undefined) { try { await pixels.release(); } catch (_) {} }
      if (source !== undefined) { try { await source.release(); } catch (_) {} }
      if (file !== undefined) { try { await fs.close(file); } catch (_) {} }
    }
  }

  private async segment(input: image.PixelMap, output: DecodedStickerPhoto): Promise<void> {
    if (!canIUse('SystemCapability.AI.Vision.SubjectSegmentation')) {
      hilog.warn(0x0, 'StickerCutout', 'stage=capability_unavailable size=%{public}dx%{public}d',
        output.width, output.height);
      output.warning = '当前设备不支持主体抠图，保留完整照片；仍可裁切和调整方向。'; return;
    }
    if (StickerPhotoDecoder.visionBusy) {
      hilog.warn(0x0, 'StickerCutout', 'stage=engine_busy size=%{public}dx%{public}d', output.width, output.height);
      output.warning = '主体识别正忙，先保留完整照片。'; return;
    }
    StickerPhotoDecoder.visionBusy = true;
    let attempted: boolean = false;
    let native: subjectSegmentation.SegmentationResult | undefined = undefined;
    try {
      attempted = true;
      if (!await subjectSegmentation.init()) {
        hilog.warn(0x0, 'StickerCutout', 'stage=init_unavailable size=%{public}dx%{public}d', output.width, output.height);
        output.warning = '主体识别暂不可用，已保留完整照片。'; return;
      }
      hilog.info(0x0, 'StickerCutout', 'stage=init_ready size=%{public}dx%{public}d', output.width, output.height);
      native = await subjectSegmentation.doSegmentation({ pixelMap: input },
        { maxCount: 6, enableSubjectDetails: true, enableSubjectForegroundImage: false });
      // Candidate masks remain useful even when the SDK's combined result is missing or invalid.
      if (native.subjectDetails !== undefined) {
        for (const subject of native.subjectDetails) {
          const mask: Uint8Array = copySubjectMask(subject.mattingList, output.width, output.height);
          if (mask.length > 0) output.subjects.push(mask);
        }
      }
      const nativeLength = native.fullSubject?.mattingList?.length ?? 0;
      if (native.fullSubject !== undefined && native.fullSubject !== null) {
        output.fullMask = copySubjectMask(native.fullSubject.mattingList, output.width, output.height);
      }
      if (output.fullMask.length === 0 && output.subjects.length > 0) {
        output.fullMask = mergeSubjectMasks(output.subjects, output.width, output.height);
      }
      hilog.info(0x0, 'StickerCutout',
        'stage=mask_ready size=%{public}dx%{public}d native_count=%{public}d native_mask_length=%{public}d mask_length=%{public}d candidates=%{public}d',
        output.width, output.height, native.subjectCount, nativeLength, output.fullMask.length, output.subjects.length);
      if (output.fullMask.length === 0) {
        output.warning = native.subjectCount < 1 ? '没有识别到清晰主体，已保留完整照片。' :
          '抠图结果不可用，已保留完整照片。';
        return;
      }
      if (output.subjects.length === 0) output.subjects.push(output.fullMask);
    } catch (error) {
      this.logError('segment_error', error as BusinessError, output.width, output.height);
      output.warning = '主体识别未完成，已保留完整照片；可重拍或继续保存。';
    } finally {
      // SDK 即使关闭 foreground 输出，也可能返回其引用；按身份去重后释放。
      if (native !== undefined) {
        const maps: image.PixelMap[] = [];
        if (native.fullSubject?.foregroundImage && native.fullSubject.foregroundImage !== input) maps.push(native.fullSubject.foregroundImage);
        if (native.subjectDetails !== undefined) {
          for (const detail of native.subjectDetails) {
            if (detail.foregroundImage && detail.foregroundImage !== input && !maps.includes(detail.foregroundImage)) maps.push(detail.foregroundImage);
          }
        }
        for (const map of maps) { try { await map.release(); } catch (_) {} }
      }
      if (attempted) {
        try { await subjectSegmentation.release(); }
        catch (error) { this.logError('release_error', error as BusinessError, output.width, output.height); }
      }
      StickerPhotoDecoder.visionBusy = false;
    }
  }

  private logError(stage: string, error: BusinessError, width: number, height: number): void {
    const nativeCode: number = error?.code ?? -1;
    const code = Number.isFinite(nativeCode) ? nativeCode : -1;
    // No error message/stack is logged: SDK strings can include private source paths.
    hilog.warn(0x0, 'StickerCutout', 'stage=%{public}s code=%{public}d size=%{public}dx%{public}d',
      stage, code, width, height);
  }

  private async orient(source: image.ImageSource, pixels: image.PixelMap): Promise<void> {
    let orientation: string = '';
    try { orientation = (await source.getImageProperty(image.PropertyKey.ORIENTATION)).trim().toLowerCase(); }
    catch (_) { return; }
    switch (orientation) {
      case '2': case 'top-right': await pixels.flip(true, false); break;
      case '3': case 'bottom-right': await pixels.rotate(180); break;
      case '4': case 'bottom-left': await pixels.flip(false, true); break;
      case '5': case 'left-top': await pixels.rotate(90); await pixels.flip(true, false); break;
      case '6': case 'right-top': await pixels.rotate(90); break;
      case '7': case 'right-bottom': await pixels.rotate(90); await pixels.flip(false, true); break;
      case '8': case 'left-bottom': await pixels.rotate(270); break;
      default: break;
    }
  }
}
