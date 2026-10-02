import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';

export interface AppPreferences {
  acceptedVersion: string;
  paperStyle: string;
  startWithCamera: boolean;
}

export interface LegalDocument {
  kind: string;
  title: string;
  version: string;
  updatedAt: string;
  body: string;
}

/** 协议版本与接受记录独立于贴纸数据；文档内置，不依赖网络可用性。 */
export class LegalDocuments {
  static readonly VERSION: string = '2026-09-29.1';
  static readonly UPDATED_AT: string = '2026年9月29日';
  static readonly DEVELOPER: string = 'lh';
  // 联系地址来自同一开发者 One Day 当前公开联系页面，不复制其功能条款。
  static readonly CONTACT_EMAIL: string = 'hapy8bit@163.com';

  static defaults(): AppPreferences {
    return { acceptedVersion: '', paperStyle: 'paper', startWithCamera: false };
  }

  static async load(context: common.UIAbilityContext, kind: string): Promise<LegalDocument> {
    const privacy: boolean = kind !== 'terms';
    const bytes: Uint8Array = await context.resourceManager.getRawFileContent(
      privacy ? 'sticker_privacy.md' : 'sticker_terms.md');
    return {
      kind: privacy ? 'privacy' : 'terms', title: privacy ? '隐私政策' : '用户服务协议',
      version: LegalDocuments.VERSION, updatedAt: LegalDocuments.UPDATED_AT,
      body: new util.TextDecoder('utf-8').decodeWithStream(bytes)
    };
  }
}
