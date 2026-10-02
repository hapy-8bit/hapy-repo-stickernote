/** 矩形属于方向统一后的处理输入；不引用 UI、图片 SDK 或版本文件。 */
export interface NormalizedStickerCrop {
  x: number;
  y: number;
  width: number;
  height: number;
}

/**
 * 目标比例描述旋转后的内容。90/270 度时先转回源坐标比例，再求居中矩形。
 * displayRatio=0 表示恢复全幅，尺寸未知也可执行；其余情况要求真实源尺寸。
 * 白边与主体透明空白裁除由渲染层处理，不属于本函数的比例约束。
 */
export function centeredCropForDisplay(sourceWidth: number, sourceHeight: number,
  displayRatio: number, rotation: number = 0): NormalizedStickerCrop {
  if (displayRatio === 0) return { x: 0, y: 0, width: 1, height: 1 };
  if (!Number.isFinite(sourceWidth) || !Number.isFinite(sourceHeight) ||
    sourceWidth <= 0 || sourceHeight <= 0 || !Number.isFinite(displayRatio) || displayRatio <= 0 ||
    !Number.isFinite(rotation)) throw new Error('裁切需要有效的源尺寸和目标比例。');
  const angle: number = ((rotation % 360) + 360) % 360;
  if (![0, 90, 180, 270].includes(angle)) throw new Error('裁切仅支持直角方向。');
  const targetInSource: number = angle === 90 || angle === 270 ? 1 / displayRatio : displayRatio;
  const sourceRatio: number = sourceWidth / sourceHeight;
  if (sourceRatio > targetInSource) {
    const width: number = targetInSource / sourceRatio;
    return { x: (1 - width) / 2, y: 0, width: width, height: 1 };
  }
  const height: number = sourceRatio / targetInSource;
  return { x: 0, y: (1 - height) / 2, width: 1, height: height };
}
