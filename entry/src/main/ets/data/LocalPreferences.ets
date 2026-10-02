import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { AppPreferences, LegalDocuments } from '../legal/LegalDocuments';

/** 偏好不与资产索引共用文件。调用方等待 flush 后再更新页面，失败可明确重试。 */
export class LocalPreferences {
  private readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) { this.context = context; }

  async load(): Promise<AppPreferences> {
    const store: preferences.Preferences = await preferences.getPreferences(this.context,
      { name: 'daily_sticker_preferences' });
    const accepted: preferences.ValueType = await store.get('acceptedVersion', '');
    const paper: preferences.ValueType = await store.get('paperStyle', 'paper');
    const camera: preferences.ValueType = await store.get('startWithCamera', false);
    return {
      acceptedVersion: typeof accepted === 'string' ? accepted : '',
      paperStyle: typeof paper === 'string' && ['paper', 'cream', 'sage'].includes(paper) ? paper : 'paper',
      startWithCamera: camera === true
    };
  }

  async save(value: AppPreferences): Promise<void> {
    if (!['paper', 'cream', 'sage'].includes(value.paperStyle)) throw new Error('纸色偏好无效。');
    const store: preferences.Preferences = await preferences.getPreferences(this.context,
      { name: 'daily_sticker_preferences' });
    await store.put('acceptedVersion', value.acceptedVersion);
    await store.put('paperStyle', value.paperStyle);
    await store.put('startWithCamera', value.startWithCamera);
    await store.flush();
  }

  async accept(): Promise<AppPreferences> {
    const value: AppPreferences = await this.load();
    value.acceptedVersion = LegalDocuments.VERSION;
    await this.save(value);
    return value;
  }
}
