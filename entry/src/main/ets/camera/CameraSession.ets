import { camera } from '@kit.CameraKit';
import { image } from '@kit.ImageKit';
import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CameraPhotoFiles } from './CameraPhotoFiles';

export interface CameraViewState {
  ready: boolean;
  busy: boolean;
  message: string;
  permissionDenied: boolean;
  canSwitch: boolean;
  flash: string;
  previewRatio: number;
  zoomRatio: number;
  minZoom: number;
  maxZoom: number;
}

export class CameraSession {
  private readonly context: common.UIAbilityContext;
  private readonly notify: (state: CameraViewState) => void;
  private manager: camera.CameraManager | undefined = undefined;
  private input: camera.CameraInput | undefined = undefined;
  private preview: camera.PreviewOutput | undefined = undefined;
  private photo: camera.PhotoOutput | undefined = undefined;
  private session: camera.PhotoSession | undefined = undefined;
  private surfaceId = '';
  private position = camera.CameraPosition.CAMERA_POSITION_BACK;
  private epoch = 0;
  private running = false;
  // All resource mutations share one queue; leaving the page invalidates work immediately.
  private queue: Promise<void> = Promise.resolve();
  private captureResolve: ((path: string) => void) | undefined = undefined;
  private captureReject: ((error: Error) => void) | undefined = undefined;
  private captureTimer = -1;
  private firstFrameTimer = -1;
  private captureEpoch = -1;
  private files: CameraPhotoFiles;
  private state: CameraViewState = {
    ready: false, busy: false, message: '正在启动相机…', permissionDenied: false,
    canSwitch: false, flash: '关闭', previewRatio: 0.75,
    zoomRatio: 1.0, minZoom: 1.0, maxZoom: 6.0
  };

  constructor(context: common.UIAbilityContext, notify: (state: CameraViewState) => void) {
    this.context = context;
    this.notify = notify;
    this.files = new CameraPhotoFiles(context.filesDir);
  }

  private publish(): void {
    this.notify({ ready: this.state.ready, busy: this.state.busy, message: this.state.message,
      permissionDenied: this.state.permissionDenied, canSwitch: this.state.canSwitch,
      flash: this.state.flash, previewRatio: this.state.previewRatio,
      zoomRatio: this.state.zoomRatio, minZoom: this.state.minZoom, maxZoom: this.state.maxZoom });
  }

  private schedule(operation: () => Promise<void>): Promise<void> {
    const next = this.queue.then(operation, operation);
    this.queue = next.catch(() => {});
    return next;
  }

  start(surfaceId: string): Promise<void> {
    this.surfaceId = surfaceId;
    this.running = true;
    const generation = ++this.epoch;
    this.state.ready = false;
    this.state.message = '正在启动相机…';
    this.publish();
    return this.schedule(async () => {
      await this.releaseResources();
      if (!this.running || generation !== this.epoch) { return; }
      await this.initialize(generation);
    });
  }

  stop(): Promise<void> {
    this.running = false;
    ++this.epoch;
    this.state.ready = false;
    this.rejectCapture(new Error('拍摄已取消。'));
    this.publish();
    return this.schedule(async () => { await this.releaseResources(); });
  }

  switchCamera(): Promise<void> {
    if (!this.state.ready || this.state.busy || !this.state.canSwitch) { return Promise.resolve(); }
    this.position = this.position === camera.CameraPosition.CAMERA_POSITION_BACK ?
      camera.CameraPosition.CAMERA_POSITION_FRONT : camera.CameraPosition.CAMERA_POSITION_BACK;
    return this.start(this.surfaceId);
  }

  cycleFlash(): void {
    if (!this.state.ready || this.state.busy || this.session === undefined) { return; }
    const modes: camera.FlashMode[] = [camera.FlashMode.FLASH_MODE_CLOSE,
      camera.FlashMode.FLASH_MODE_AUTO, camera.FlashMode.FLASH_MODE_OPEN];
    const labels = ['关闭', '自动', '开启'];
    const current = labels.indexOf(this.state.flash);
    try {
      for (let step = 1; step <= modes.length; step++) {
        const index = (current + step) % modes.length;
        if (this.session.isFlashModeSupported(modes[index])) {
          this.session.setFlashMode(modes[index]);
          this.state.flash = labels[index];
          this.publish();
          return;
        }
      }
    } catch (_) { this.state.message = '此镜头暂时无法调整闪光灯。'; this.publish(); }
  }

  setZoomRatio(ratio: number): void {
    if (!this.state.ready || this.state.busy || this.session === undefined) { return; }
    if (!Number.isFinite(ratio)) { return; }
    const clamped = Math.max(this.state.minZoom, Math.min(this.state.maxZoom, ratio));
    const rounded = Number(clamped.toFixed(2));
    try {
      this.session.setZoomRatio(rounded);
      this.state.zoomRatio = rounded;
      this.publish();
    } catch (_) {
      // 变焦超出硬件可用范围或设备正忙
    }
  }

  capture(): Promise<string> {
    const output = this.photo;
    if (!this.state.ready || this.state.busy || output === undefined) {
      return Promise.reject(new Error('取景尚未就绪，请稍候。'));
    }
    this.state.busy = true;
    this.state.message = '正在保存照片…';
    this.captureEpoch = this.epoch;
    const generation = this.captureEpoch;
    this.publish();
    const pending = new Promise<string>((resolve, reject) => {
      this.captureResolve = resolve;
      this.captureReject = reject;
    });
    this.captureTimer = setTimeout(() => {
      this.rejectCapture(new Error('相机返回照片超时，请重试。'));
      // Recreate the output before another capture so a late JPEG cannot satisfy the next request.
      this.state.ready = false;
      this.stop().catch(() => {});
    }, 20000);
    try {
      // The capture page is portrait-locked. CameraKit supplies sensor-specific JPEG orientation.
      const setting: camera.PhotoCaptureSetting = {
        quality: camera.QualityLevel.QUALITY_LEVEL_HIGH,
        rotation: output.getPhotoRotation(0)
      };
      if (output.isMirrorSupported()) {
        setting.mirror = this.position === camera.CameraPosition.CAMERA_POSITION_FRONT;
      }
      output.capture(setting).catch(() => {
        if (this.running && generation === this.epoch) {
          this.rejectCapture(new Error('拍摄失败，请重试。'));
        }
      });
    } catch (_) {
      if (this.running && generation === this.epoch) {
        this.rejectCapture(new Error('拍摄失败，请重试。'));
      }
    }
    return pending;
  }

  private rejectCapture(error: Error): void {
    const reject = this.captureReject;
    this.clearCapture();
    if (reject !== undefined) {
      this.state.message = error.message;
      reject(error);
    }
    this.publish();
  }

  private clearCapture(): void {
    if (this.captureTimer !== -1) { clearTimeout(this.captureTimer); }
    this.captureTimer = -1;
    this.captureResolve = undefined;
    this.captureReject = undefined;
    this.state.busy = false;
  }

  private chooseProfile(profiles: camera.Profile[], maximumPixels: number, preferredRatio: number): camera.Profile {
    if (profiles.length === 0) { throw new Error('此镜头没有兼容的拍照配置。'); }
    let selected = profiles[0];
    let score = Number.MAX_VALUE;
    for (const profile of profiles) {
      if (profile.size.width <= 0 || profile.size.height <= 0) { continue; }
      const pixels = profile.size.width * profile.size.height;
      const ratio = profile.size.width / profile.size.height;
      const next = Math.abs(ratio - preferredRatio) * 100 +
        (pixels > maximumPixels ? 50 + pixels / maximumPixels : (maximumPixels - pixels) / maximumPixels);
      if (next < score) { selected = profile; score = next; }
    }
    return selected;
  }

  private async initialize(generation: number): Promise<void> {
    try {
      const result = await abilityAccessCtrl.createAtManager()
        .requestPermissionsFromUser(this.context, ['ohos.permission.CAMERA']);
      if (!this.running || generation !== this.epoch) { return; }
      if (result.authResults.length !== 1 || result.authResults[0] !== 0) {
        this.state.permissionDenied = true;
        throw new Error('需要相机权限才能拍摄。你仍可从相册制作贴纸；也可在系统设置中允许相机后重试。');
      }
      this.state.permissionDenied = false;
      this.manager = camera.getCameraManager(this.context);
      const devices = this.manager.getSupportedCameras();
      const device = devices.find((item: camera.CameraDevice) => item.cameraPosition === this.position);
      if (device === undefined) { throw new Error('没有找到可用镜头，请从相册选择照片。'); }
      this.state.canSwitch = devices.some((item: camera.CameraDevice) =>
        item.cameraPosition !== this.position &&
        (item.cameraPosition === camera.CameraPosition.CAMERA_POSITION_BACK ||
          item.cameraPosition === camera.CameraPosition.CAMERA_POSITION_FRONT));
      const capabilities = this.manager.getSupportedOutputCapability(device, camera.SceneMode.NORMAL_PHOTO);
      const photoProfile = this.chooseProfile(capabilities.photoProfiles.filter((item: camera.Profile) =>
        item.format === camera.CameraFormat.CAMERA_FORMAT_JPEG), 12000000, 4 / 3);
      const previewProfile = this.chooseProfile(capabilities.previewProfiles, 1920 * 1080,
        photoProfile.size.width / photoProfile.size.height);
      this.state.previewRatio = previewProfile.size.height / previewProfile.size.width;
      this.input = this.manager.createCameraInput(device);
      this.input.on('error', device, () => { this.handleCameraFailure(generation); });
      await this.input.open();
      if (!this.running || generation !== this.epoch) { await this.releaseResources(); return; }
      this.preview = this.manager.createPreviewOutput(previewProfile, this.surfaceId);
      this.photo = this.manager.createPhotoOutput(photoProfile);
      this.photo.on('photoAvailable', (error: BusinessError, photo: camera.Photo) => {
        if (error !== undefined && error !== null && error.code !== 0) {
          if (photo !== undefined) { photo.release().catch(() => {}); }
          if (this.running && generation === this.epoch) {
            this.rejectCapture(new Error('照片获取失败，请重试。'));
          }
          return;
        }
        this.receivePhoto(photo, generation).catch(() => {
          if (this.running && generation === this.epoch) {
            this.rejectCapture(new Error('照片保存失败，请重试。'));
          }
        });
      });
      this.photo.on('error', () => { this.handleCameraFailure(generation); });
      this.preview.on('error', () => { this.handleCameraFailure(generation); });
      this.preview.on('frameStart', (error: BusinessError) => {
        if (!this.running || generation !== this.epoch ||
          (error !== undefined && error !== null && error.code !== 0)) { return; }
        if (this.firstFrameTimer !== -1) { clearTimeout(this.firstFrameTimer); this.firstFrameTimer = -1; }
        this.state.ready = true;
        this.state.message = '';
        this.publish();
      });
      this.session = this.manager.createSession<camera.PhotoSession>(camera.SceneMode.NORMAL_PHOTO);
      this.session.on('error', () => { this.handleCameraFailure(generation); });
      this.session.beginConfig();
      this.session.addInput(this.input);
      this.session.addOutput(this.preview);
      this.session.addOutput(this.photo);
      await this.session.commitConfig();
      this.preview.setPreviewRotation(this.preview.getPreviewRotation(0), true);
      this.state.flash = '关闭';
      if (this.session.isFlashModeSupported(camera.FlashMode.FLASH_MODE_CLOSE)) {
        this.session.setFlashMode(camera.FlashMode.FLASH_MODE_CLOSE);
      }
      try {
        const range = this.session.getZoomRatioRange();
        if (Array.isArray(range) && range.length >= 2 && Number.isFinite(range[0]) && Number.isFinite(range[1])) {
          this.state.minZoom = Math.max(0.1, Number(range[0].toFixed(2)));
          this.state.maxZoom = Math.max(this.state.minZoom, Number(range[1].toFixed(2)));
        } else {
          this.state.minZoom = 1.0;
          this.state.maxZoom = 6.0;
        }
        const current = this.session.getZoomRatio();
        this.state.zoomRatio = Number.isFinite(current) ?
          Math.max(this.state.minZoom, Math.min(this.state.maxZoom, Number(current.toFixed(2)))) : 1.0;
      } catch (_) {
        this.state.minZoom = 1.0;
        this.state.maxZoom = 6.0;
        this.state.zoomRatio = 1.0;
      }
      if (!this.running || generation !== this.epoch) { await this.releaseResources(); return; }
      await this.session.start();
      if (!this.state.ready && this.running && generation === this.epoch) {
        this.firstFrameTimer = setTimeout(() => { this.handleCameraFailure(generation); }, 10000);
      }
      this.publish();
    } catch (error) {
      await this.releaseResources();
      if (!this.running || generation !== this.epoch) { return; }
      this.state.ready = false;
      this.state.message = this.state.permissionDenied ?
        '需要相机权限才能拍摄。可使用相册，或在系统设置中允许相机后重试。' :
        '相机暂时不可用，可能被其他应用占用。请重试或从相册选择。';
      this.publish();
    }
  }

  private handleCameraFailure(generation: number): void {
    if (!this.running || generation !== this.epoch) { return; }
    this.state.ready = false;
    this.state.message = '相机连接已中断，请重试或从相册选择。';
    this.rejectCapture(new Error('相机连接已中断。'));
    this.stop().catch(() => {});
  }

  private async receivePhoto(photo: camera.Photo, generation: number): Promise<void> {
    let path = '';
    try {
      if (photo === undefined || photo.main === undefined) { throw new Error('相机未返回图片。'); }
      if (!this.running || generation !== this.epoch || this.captureResolve === undefined ||
        this.captureEpoch !== generation) { return; }
      const component: image.Component = await photo.main.getComponent(image.ComponentType.JPEG);
      path = await this.files.saveJpeg(component.byteBuffer);
      const resolve = this.captureResolve;
      if (!this.running || generation !== this.epoch || resolve === undefined || this.captureEpoch !== generation) {
        await this.files.discard(path);
        path = '';
        return;
      }
      this.clearCapture();
      this.state.message = '';
      this.publish();
      // Caller now owns this private JPEG and must delete the draft after import or cancel.
      resolve(path);
      path = '';
    } finally {
      if (path.length > 0) { try { await this.files.discard(path); } catch (_) {} }
      if (photo !== undefined) { try { await photo.release(); } catch (_) {} }
    }
  }

  private async releaseResources(): Promise<void> {
    if (this.firstFrameTimer !== -1) { clearTimeout(this.firstFrameTimer); this.firstFrameTimer = -1; }
    const session = this.session;
    const preview = this.preview;
    const photo = this.photo;
    const input = this.input;
    this.session = undefined;
    this.preview = undefined;
    this.photo = undefined;
    this.input = undefined;
    this.manager = undefined;
    if (session !== undefined) {
      try { await session.stop(); } catch (_) {}
      try { await session.release(); } catch (_) {}
    }
    if (preview !== undefined) { try { await preview.release(); } catch (_) {} }
    if (photo !== undefined) { try { await photo.release(); } catch (_) {} }
    if (input !== undefined) { try { await input.close(); } catch (_) {} }
    this.state.zoomRatio = 1.0;
  }
}
