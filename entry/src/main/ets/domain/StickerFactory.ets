import { DayPlacement, StickerAsset, StickerRecipe, StickerRevision } from './StickerModels';

/** 领域默认值不依赖文件、相机或图像 SDK；文件先落盘，再提交这些元数据。 */
export class StickerFactory {
  static newId(prefix: string = 'sticker'): string {
    return `${prefix}_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 14)}`;
  }

  static defaultRecipe(mode: string = 'subject'): StickerRecipe {
    return {
      mode: mode, borderWidth: mode === 'subject' ? 8 : 0, borderColor: '#FFFFFF',
      rotation: 0, flipHorizontal: false, cropX: 0, cropY: 0, cropWidth: 1,
      cropHeight: 1, subjectIndex: -1
    };
  }

  static createAsset(id: string, sourcePath: string, sourceType: string, width: number,
    height: number, now: number = Date.now()): StickerAsset {
    return {
      id: id, sourcePath: sourcePath, sourceType: sourceType, width: width, height: height,
      title: '', note: '', category: '未分类', favorite: false, createdAt: now, updatedAt: now
    };
  }

  static createRevision(id: string, assetId: string, maskPath: string, imagePath: string,
    width: number, height: number, recipe: StickerRecipe, now: number = Date.now()): StickerRevision {
    return {
      id: id, assetId: assetId, maskPath: maskPath, imagePath: imagePath,
      width: width, height: height, recipe: StickerFactory.copyRecipe(recipe), createdAt: now
    };
  }

  static createPlacement(id: string, dateKey: string, assetId: string, revisionId: string,
    zIndex: number = 0, now: number = Date.now()): DayPlacement {
    return {
      id: id, dateKey: dateKey, assetId: assetId, revisionId: revisionId,
      x: 0.5, y: 0.5, scale: 1, rotation: 0, zIndex: zIndex, note: '', createdAt: now, updatedAt: now
    };
  }

  static copyRecipe(recipe: StickerRecipe): StickerRecipe {
    return {
      mode: recipe.mode, borderWidth: recipe.borderWidth, borderColor: recipe.borderColor,
      rotation: recipe.rotation, flipHorizontal: recipe.flipHorizontal,
      cropX: recipe.cropX, cropY: recipe.cropY, cropWidth: recipe.cropWidth,
      cropHeight: recipe.cropHeight, subjectIndex: recipe.subjectIndex
    };
  }
}
