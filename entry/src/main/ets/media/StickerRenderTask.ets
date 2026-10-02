import { StickerRecipe } from '../domain/StickerModels';
import { makeStickerRaster, StickerRaster } from './StickerRaster';

/** 纯像素计算由 TaskPool 执行，页面线程只负责预览与用户输入。 */
@Concurrent
export function renderStickerTask(source: ArrayBuffer, mask: ArrayBuffer, width: number,
  height: number, premultiplied: boolean, recipe: StickerRecipe): StickerRaster {
  return makeStickerRaster(source, mask, width, height, premultiplied, recipe);
}
