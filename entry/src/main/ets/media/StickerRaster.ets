import { StickerRecipe } from '../domain/StickerModels';

export interface StickerRaster {
  pixels: ArrayBuffer;
  width: number;
  height: number;
}

/** 一维平方距离变换；两遍处理得到圆形描边，避免方形膨胀的尖角。 */
function distanceLine(input: Float64Array, length: number): Float64Array {
  const output: Float64Array = new Float64Array(length);
  const sites: Int32Array = new Int32Array(length);
  const bounds: Float64Array = new Float64Array(length + 1);
  let k: number = 0;
  sites[0] = 0;
  bounds[0] = -Infinity;
  bounds[1] = Infinity;
  for (let q: number = 1; q < length; q++) {
    let p: number = sites[k];
    let crossing: number = ((input[q] + q * q) - (input[p] + p * p)) / (2 * (q - p));
    while (crossing <= bounds[k] && k > 0) {
      p = sites[--k];
      crossing = ((input[q] + q * q) - (input[p] + p * p)) / (2 * (q - p));
    }
    k++;
    sites[k] = q;
    bounds[k] = crossing;
    bounds[k + 1] = Infinity;
  }
  k = 0;
  for (let q: number = 0; q < length; q++) {
    while (bounds[k + 1] < q) k++;
    const delta: number = q - sites[k];
    output[q] = delta * delta + input[sites[k]];
  }
  return output;
}

function outlineDistance(alpha: Uint8Array, width: number, height: number): Float64Array {
  const distance: Float64Array = new Float64Array(width * height);
  for (let y: number = 0; y < height; y++) {
    const row: Float64Array = new Float64Array(width);
    // A weak mask fleck must not become an opaque white island. Only the confident
    // body seeds the outline; softer details retain their original color and alpha.
    for (let x: number = 0; x < width; x++) row[x] = alpha[y * width + x] >= 128 ? 0 : 1e12;
    distance.set(distanceLine(row, width), y * width);
  }
  for (let x: number = 0; x < width; x++) {
    const column: Float64Array = new Float64Array(height);
    for (let y: number = 0; y < height; y++) column[y] = distance[y * width + x];
    const transformed: Float64Array = distanceLine(column, height);
    for (let y: number = 0; y < height; y++) distance[y * width + x] = transformed[y];
  }
  return distance;
}

function orientRaster(pixels: Uint8Array, width: number, height: number,
  rotation: number, flip: boolean): StickerRaster {
  const angle: number = ((rotation % 360) + 360) % 360;
  const outWidth: number = angle === 90 || angle === 270 ? height : width;
  const outHeight: number = angle === 90 || angle === 270 ? width : height;
  const output: Uint8Array = new Uint8Array(pixels.length);
  for (let y: number = 0; y < height; y++) {
    for (let x: number = 0; x < width; x++) {
      const fx: number = flip ? width - x - 1 : x;
      let ox: number = fx;
      let oy: number = y;
      if (angle === 90) { ox = height - y - 1; oy = fx; }
      else if (angle === 180) { ox = width - fx - 1; oy = height - y - 1; }
      else if (angle === 270) { ox = y; oy = width - fx - 1; }
      const sourceOffset: number = (y * width + x) * 4;
      const targetOffset: number = (oy * outWidth + ox) * 4;
      for (let c: number = 0; c < 4; c++) output[targetOffset + c] = pixels[sourceOffset + c];
    }
  }
  return { pixels: output.buffer as ArrayBuffer, width: outWidth, height: outHeight };
}

/** 裁切发生在原始处理输入坐标系；蒙版与 RGB 绝不能独立缩放后直接拼接。 */
export function makeStickerRaster(source: ArrayBuffer, maskBuffer: ArrayBuffer, width: number,
  height: number, premultiplied: boolean, recipe: StickerRecipe): StickerRaster {
  const rgba: Uint8Array = new Uint8Array(source);
  const mask: Uint8Array = new Uint8Array(maskBuffer);
  if (!Number.isSafeInteger(width) || !Number.isSafeInteger(height) ||
    width < 1 || height < 1 || width > 1280 || height > 1280 || rgba.length !== width * height * 4) {
    throw new Error('照片处理尺寸无效。');
  }
  if (recipe.mode === 'subject' && mask.length !== width * height) throw new Error('当前没有可用的主体蒙版。');
  if (!['subject', 'original'].includes(recipe.mode) ||
    ![recipe.cropX, recipe.cropY, recipe.cropWidth, recipe.cropHeight].every((value: number): boolean => Number.isFinite(value)) ||
    ![0, 90, 180, 270].includes(((recipe.rotation % 360) + 360) % 360) ||
    !Number.isFinite(recipe.borderWidth) || recipe.borderWidth < 0 || recipe.borderWidth > 32 ||
    !/^#[0-9a-fA-F]{6}$/.test(recipe.borderColor) || recipe.cropWidth <= 0 || recipe.cropHeight <= 0 ||
    recipe.cropX < 0 || recipe.cropY < 0 || recipe.cropX + recipe.cropWidth > 1.00001 ||
    recipe.cropY + recipe.cropHeight > 1.00001) throw new Error('贴纸编辑参数无效。');
  const left: number = Math.max(0, Math.floor(recipe.cropX * width));
  const top: number = Math.max(0, Math.floor(recipe.cropY * height));
  const right: number = Math.min(width - 1, Math.ceil((recipe.cropX + recipe.cropWidth) * width) - 1);
  const bottom: number = Math.min(height - 1, Math.ceil((recipe.cropY + recipe.cropHeight) * height) - 1);
  let cropLeft: number = left;
  let cropTop: number = top;
  let cropRight: number = right;
  let cropBottom: number = bottom;
  if (recipe.mode === 'subject') {
    cropLeft = width; cropTop = height; cropRight = -1; cropBottom = -1;
    for (let y: number = top; y <= bottom; y++) {
      for (let x: number = left; x <= right; x++) {
        const index: number = y * width + x;
        // Keep every nonzero exported alpha, including low-opacity hair/fine tails.
        if (Math.round(mask[index] * rgba[index * 4 + 3] / 255) === 0) continue;
        cropLeft = Math.min(cropLeft, x); cropTop = Math.min(cropTop, y);
        cropRight = Math.max(cropRight, x); cropBottom = Math.max(cropBottom, y);
      }
    }
    if (cropRight < cropLeft || cropBottom < cropTop) throw new Error('裁切范围里没有主体，请恢复全幅或选择其他主体。');
  }
  const radius: number = Math.round(recipe.borderWidth);
  const padding: number = radius + 2;
  const outWidth: number = cropRight - cropLeft + 1 + padding * 2;
  const outHeight: number = cropBottom - cropTop + 1 + padding * 2;
  const alpha: Uint8Array = new Uint8Array(outWidth * outHeight);
  const output: Uint8Array = new Uint8Array(outWidth * outHeight * 4);
  for (let y: number = cropTop; y <= cropBottom; y++) {
    for (let x: number = cropLeft; x <= cropRight; x++) {
      const inputIndex: number = y * width + x;
      const target: number = (y - cropTop + padding) * outWidth + x - cropLeft + padding;
      const originalAlpha: number = rgba[inputIndex * 4 + 3];
      const value: number = recipe.mode === 'subject' ? Math.round(mask[inputIndex] * originalAlpha / 255) : originalAlpha;
      alpha[target] = value;
      for (let c: number = 0; c < 3; c++) {
        const color: number = rgba[inputIndex * 4 + c];
        output[target * 4 + c] = value === 0 ? 0 :
          (premultiplied && originalAlpha > 0 ? Math.min(255, Math.round(color * 255 / originalAlpha)) : color);
      }
      output[target * 4 + 3] = value;
    }
  }
  if (radius > 0) {
    const distance: Float64Array = outlineDistance(alpha, outWidth, outHeight);
    const color: number = Number.parseInt(recipe.borderColor.slice(1), 16);
    const border: number[] = [(color >> 16) & 255, (color >> 8) & 255, color & 255];
    for (let i: number = 0; i < alpha.length; i++) {
      // Outline is separate from the photograph: never flatten a white underlay
      // into nonzero subject pixels. Their RGB and alpha stay independent of border width.
      if (alpha[i] > 0) continue;
      const outline: number = 255 * Math.max(0, Math.min(1, radius + 0.5 - Math.sqrt(distance[i])));
      if (outline <= 0) continue;
      for (let c: number = 0; c < 3; c++) output[i * 4 + c] = border[c];
      output[i * 4 + 3] = Math.round(outline);
    }
  }
  return orientRaster(output, outWidth, outHeight, recipe.rotation, recipe.flipHorizontal);
}
