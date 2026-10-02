import { common } from '@kit.AbilityKit';
import { DayPlacement, StickerAsset, StickerRecipe, StickerRepository, StickerRevision, StickerStore } from '../domain/StickerModels';
import { StickerFactory } from '../domain/StickerFactory';
import { StickerCopies } from '../domain/StickerCopies';
import { DateTools } from '../domain/DateTools';
import { LocalStickerRepository } from '../data/StickerRepository';
import { LocalPreferences } from '../data/LocalPreferences';
import { StickerCommands } from '../application/StickerCommands';
import { StickerAcquisitionService } from '../media/StickerAcquisitionService';
import { StickerMediaSession } from '../media/StickerMediaSession';
import { AppPreferences, LegalDocument, LegalDocuments } from '../legal/LegalDocuments';
import { Theme } from '../components/Theme';
import { PaperBodyStyle } from '../components/PaperStyles';
import { MainDock } from '../components/MainDock';
import { StickerAddSheet } from '../components/StickerAddSheet';
import { DayCanvas } from '../components/DayCanvas';
import { StickerLibrary } from '../components/StickerLibrary';
import { StickerWorkbench } from '../components/StickerWorkbench';
import { CameraView } from '../components/CameraView';
import { CalendarView } from '../components/CalendarView';
import { SettingsView } from '../components/SettingsView';
import { CategoryManagerView } from '../components/CategoryManagerView';
import { LegalView } from '../components/LegalView';
import { ConsentView } from '../components/ConsentView';
import { PageMotion } from '../platform/PageMotion';
import { MotionPreferences } from '../platform/MotionPreferences';

/** 装配入口串联页面意图，资源和落盘事务分别由相机、媒体和仓库拥有。 */
@Entry
@Component
struct Index {
  @StorageLink('stickerTopInset') topInset: number = 0;
  @StorageLink('stickerBottomInset') bottomInset: number = 0;
  @StorageLink('stickerAppForeground') @Watch('foregroundChanged') foreground: boolean = true;
  @State private page: string = 'boot';
  @State private tab: string = 'today';
  @State private pageOpacity: number = 1;
  @State private pageOffset: number = 0;
  @State private pageSwitching: boolean = false;
  @State private tabOpacity: number = 1;
  @State private tabOffset: number = 0;
  @State private tabSwitching: boolean = false;
  @State private reducedMotion: boolean = false;
  @State private libraryQuery: string = '';
  @State private libraryCategory: string = '';
  @State private libraryFavoritesOnly: boolean = false;
  @State private store: StickerStore = { schemaVersion: 2, assets: [], revisions: [], placements: [], categories: [] };
  @State private selectedDate: string = DateTools.key();
  @State private loading: boolean = false;
  @State private busy: boolean = false;
  @State private showAddSheet: boolean = false;
  @State private errorMessage: string = '';
  @State private message: string = '';
  @State private prefs: AppPreferences = LegalDocuments.defaults();
  @State private legalDocument: LegalDocument | undefined = undefined;
  @State private legalLoading: boolean = false;
  @State private storageBytes: number = 0;
  @State private sourceBytes: number = 0;
  @State private renderedBytes: number = 0;
  @State private maskBytes: number = 0;
  @State private editing: boolean = false;
  @State private selectedPlacementId: string = '';
  @State private draftAsset: StickerAsset = StickerFactory.createAsset('', '', 'legacy', 0, 0);
  @State private draftRevision: StickerRevision = StickerFactory.createRevision('', '', '', '', 0, 0, StickerFactory.defaultRecipe());
  @State private draftRecipe: StickerRecipe = StickerFactory.defaultRecipe();
  @State private draftNote: string = '';
  @State private subjectCount: number = 0;
  @State private canRemake: boolean = false;
  private context: common.UIAbilityContext | undefined = undefined;
  private repository: StickerRepository | undefined = undefined;
  private commands: StickerCommands | undefined = undefined;
  private photos: StickerAcquisitionService | undefined = undefined;
  private preferences: LocalPreferences | undefined = undefined;
  private session: StickerMediaSession | undefined = undefined;
  private cameraReturn: string = 'main';
  private categoriesReturn: string = 'main';
  private legalReturn: string = 'consent';
  private editingPlacementId: string = '';
  private retaking: boolean = false;
  private legalGeneration: number = 0;
  private undo: DayPlacement[][] = [];
  private renderingRecipe: boolean = false;
  private pendingRecipe: StickerRecipe | undefined = undefined;
  private pendingAddSource: string = '';
  private mounted: boolean = false;
  private readonly pageMotion: PageMotion = new PageMotion();
  private readonly tabMotion: PageMotion = new PageMotion();

  aboutToAppear(): void {
    this.mounted = true;
    this.reducedMotion = MotionPreferences.reduced();
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.repository = new LocalStickerRepository(this.context);
    this.commands = new StickerCommands(this.repository);
    this.photos = new StickerAcquisitionService(this.context);
    this.preferences = new LocalPreferences(this.context);
    this.initialize();
  }
  aboutToDisappear(): void {
    this.mounted = false; this.pendingAddSource = '';
    this.pageMotion.invalidate(); this.tabMotion.invalidate(); this.legalGeneration += 1;
    this.session?.cancel().catch(() => {});
  }

  private foregroundChanged(): void {
    if (this.foreground) this.reducedMotion = MotionPreferences.reduced();
    else { this.pendingAddSource = ''; this.showAddSheet = false; }
  }

  private switching(): boolean { return this.pageSwitching || this.tabSwitching; }

  private navigate(page: string, direction: number = 1, revealOnly: boolean = false): void {
    if (page === this.page) return;
    const camera: boolean = page === 'camera' || this.page === 'camera';
    this.getUIContext().getFocusController().clearFocus();
    this.tabMotion.invalidate(); this.tabOpacity = 1; this.tabOffset = 0; this.tabSwitching = false;
    this.reducedMotion = MotionPreferences.reduced();
    if (camera || revealOnly) {
      this.pageMotion.enter(this.getUIContext(), this.reducedMotion, (): void => { this.page = page; },
        (opacity: number, offset: number): void => { this.pageOpacity = opacity; this.pageOffset = offset; },
        (active: boolean): void => { this.pageSwitching = active; });
    } else {
      this.pageMotion.transition(this.getUIContext(), this.reducedMotion, direction, (): void => { this.page = page; },
        (opacity: number, offset: number): void => { this.pageOpacity = opacity; this.pageOffset = offset; },
        (active: boolean): void => { this.pageSwitching = active; });
    }
  }

  private selectTab(tab: string, resetDate: boolean = false): void {
    if (this.busy || this.loading || this.switching()) return;
    if (tab === this.tab && (!resetDate || this.selectedDate === DateTools.key())) return;
    this.getUIContext().getFocusController().clearFocus();
    this.finishLayout(); this.reducedMotion = MotionPreferences.reduced();
    this.tabMotion.transition(this.getUIContext(), this.reducedMotion, tab === 'library' ? 1 : -1,
      (): void => { this.tab = tab; if (resetDate) this.selectedDate = DateTools.key(); },
      (opacity: number, offset: number): void => { this.tabOpacity = opacity; this.tabOffset = offset; },
      (active: boolean): void => { this.tabSwitching = active; });
  }

  onBackPress(): boolean {
    if (this.showAddSheet) { this.showAddSheet = false; return true; }
    if (this.busy || this.switching()) return true;
    if (this.page === 'workbench') { this.requestCancel(); return true; }
    if (this.page === 'camera') { this.closeCamera(); return true; }
    if (this.page === 'legal') { this.navigate(this.legalReturn, -1); this.message = ''; return true; }
    if (this.page === 'categories') { this.navigate(this.categoriesReturn, -1); this.message = ''; return true; }
    if (this.page !== 'main' && this.page !== 'consent' && this.page !== 'boot') { this.navigate('main', -1); return true; }
    if (this.editing) { this.finishLayout(); return true; }
    if (this.tab === 'library') { this.selectTab('today'); return true; }
    return false;
  }

  private async initialize(): Promise<void> {
    try {
      if (!this.preferences) throw new Error('偏好存储尚未就绪。');
      this.prefs = await this.preferences.load();
      if (this.prefs.acceptedVersion !== LegalDocuments.VERSION) { this.page = 'consent'; return; }
      this.page = 'main'; await this.refresh(true);
      if (this.prefs.startWithCamera && this.errorMessage.length === 0) this.openCamera();
    } catch (_) { this.page = 'consent'; this.message = '启动偏好读取失败，请重试。现有贴纸未改动。'; }
  }
  private async accept(): Promise<void> {
    if (this.busy || !this.preferences) return;
    this.busy = true; this.message = '';
    try { this.prefs = await this.preferences.accept(); await this.refresh(true); this.navigate('main'); }
    catch (_) { this.message = '同意状态保存失败，请重试。'; }
    finally { this.busy = false; }
  }
  private async refresh(showLoading: boolean = false): Promise<void> {
    if (!this.repository) return;
    if (showLoading) this.loading = true;
    try {
      this.store = await this.repository.load(); this.errorMessage = '';
      if (this.libraryCategory.length > 0 && !this.store.categories.includes(this.libraryCategory)) this.libraryCategory = '';
    }
    catch (error) { this.errorMessage = this.reason(error, '本地贴纸无法读取，原数据已保留。'); }
    finally { this.loading = false; }
  }
  private paper(): string { return Theme.paperColor(this.prefs.paperStyle); }
  private toast(text: string): void { this.getUIContext().getPromptAction().showToast({ message: text }); }
  private reason(error: Object, fallback: string): string {
    const text: string = error instanceof Error ? error.message : '';
    return text.length > 0 && text.length < 180 && !text.includes('/data/') && !text.includes('stack') ? text : fallback;
  }

  private openCamera(): void {
    if (this.busy || this.loading || this.switching() || this.errorMessage.length > 0) return;
    this.finishLayout(); this.cameraReturn = 'main'; this.retaking = false; this.message = ''; this.navigate('camera');
  }
  private openAddSheet(): void {
    if (!this.foreground || this.busy || this.loading || this.switching() || this.errorMessage.length > 0) return;
    this.pendingAddSource = ''; this.showAddSheet = true;
  }
  private chooseAddSource(source: string): void {
    if (this.pendingAddSource.length > 0) return;
    this.pendingAddSource = source; this.showAddSheet = false;
  }
  private finishAddSheet(): void {
    const source: string = this.pendingAddSource;
    this.pendingAddSource = '';
    // 等原生弹层完成关闭后再交接到相机或选图器，避免两个模态界面争用焦点。
    // 后台或宿主退出会使待交接来源失效，不在后台启动权限或选图界面。
    if (!this.mounted || !this.foreground || this.page !== 'main' || this.busy || this.loading || this.switching()) return;
    if (source === 'camera') this.openCamera();
    else if (source === 'gallery') { this.finishLayout(); this.retaking = false; this.acquire(); }
    else if (source === 'library') this.selectTab('library');
  }
  private selectDay(date: string): void {
    if (date === this.selectedDate || this.busy || this.loading || this.switching()) return;
    this.finishLayout(); this.selectedDate = date;
  }
  private closeCamera(): void { this.navigate(this.cameraReturn, -1); this.retaking = false; }
  private async acquire(capturedPath: string = ''): Promise<void> {
    if (this.busy || !this.photos) return;
    const isRetake: boolean = this.retaking;
    this.navigate(isRetake ? 'workbench' : 'main', -1); this.busy = true; this.message = '正在制作贴纸…';
    try {
      const next: StickerMediaSession | undefined = capturedPath.length > 0 ? await this.photos.capture(capturedPath) : await this.photos.pick();
      if (next === undefined) { this.message = ''; return; }
      if (isRetake) {
        next.asset.title = this.draftAsset.title; next.asset.category = this.draftAsset.category;
        next.asset.favorite = this.draftAsset.favorite; next.asset.note = this.draftNote;
        try { await this.session?.cancel(); } catch (_) { this.toast('新照片已生成，旧草稿有部分文件未清理。'); }
      } else { this.draftNote = ''; this.editingPlacementId = ''; }
      this.session = next; this.installDraft(next); this.navigate('workbench');
    } catch (error) { this.message = this.reason(error, '照片处理失败，请换一张照片。'); this.toast(this.message); }
    finally { this.retaking = false; this.busy = false; }
  }
  private installDraft(session: StickerMediaSession): void {
    this.draftAsset = StickerCopies.asset(session.asset); this.draftRevision = session.revision;
    this.draftRecipe = StickerFactory.copyRecipe(session.revision.recipe); this.subjectCount = session.subjectCount;
    this.canRemake = session.canRemake; this.message = session.warning;
  }
  private async openAsset(assetId: string, placementId: string = ''): Promise<void> {
    if (this.busy || !this.photos) return;
    const asset: StickerAsset | undefined = this.store.assets.find((value: StickerAsset): boolean => value.id === assetId);
    const placement: DayPlacement | undefined = this.store.placements.find((value: DayPlacement): boolean => value.id === placementId);
    const revision: StickerRevision | undefined = placement === undefined ? this.store.revisions
      .filter((value: StickerRevision): boolean => value.assetId === assetId)
      .sort((left: StickerRevision, right: StickerRevision): number => right.createdAt - left.createdAt)[0] :
      this.store.revisions.find((value: StickerRevision): boolean => value.id === placement.revisionId);
    if (asset === undefined || revision === undefined) { this.toast('贴纸无法打开，请重新读取。'); return; }
    this.busy = true; this.message = '正在打开原图…'; this.finishLayout();
    try {
      this.session = await this.photos.reopen(asset, revision); this.editingPlacementId = placementId; this.draftNote = placement?.note ?? asset.note;
      this.installDraft(this.session); this.navigate('workbench');
    } catch (error) { this.toast(this.reason(error, '原图无法打开，已有成品没有改动。')); this.message = ''; }
    finally { this.busy = false; }
  }
  private updateDraft(title: string, category: string, note: string): void {
    const next: StickerAsset = StickerCopies.asset(this.draftAsset); next.title = title; next.category = category; next.note = note;
    this.draftAsset = next; this.draftNote = note;
  }
  private retake(): void { if (!this.busy && !this.switching()) { this.retaking = true; this.cameraReturn = 'workbench'; this.navigate('camera'); } }
  private async changeRecipe(recipe: StickerRecipe): Promise<void> {
    if (!this.session || (this.busy && !this.renderingRecipe)) return;
    this.pendingRecipe = StickerFactory.copyRecipe(recipe);
    if (this.renderingRecipe) return;
    this.renderingRecipe = true; this.busy = true;
    try {
      while (this.pendingRecipe !== undefined && this.session !== undefined) {
        const next: StickerRecipe = this.pendingRecipe; this.pendingRecipe = undefined;
        if (JSON.stringify(next) === JSON.stringify(this.draftRevision.recipe)) continue;
        try {
          this.draftRevision = await this.session.render(next);
          this.draftRecipe = StickerFactory.copyRecipe(this.draftRevision.recipe); this.message = this.session.warning;
        } catch (error) { this.message = this.reason(error, '制作未完成，上一版预览保留。'); }
      }
    } finally { this.renderingRecipe = false; this.busy = false; }
  }
  private async save(title: string, category: string, note: string, placeOnDay: boolean): Promise<void> {
    if (this.busy || !this.session || !this.commands) return;
    this.busy = true; let committed: boolean = false;
    try {
      await this.commands.save(this.draftAsset, this.draftRevision, this.store, this.selectedDate, this.editingPlacementId, title, category, note, placeOnDay);
      committed = true;
      const cleaned: boolean = await this.session.markCommitted(); this.session = undefined;
      this.tab = placeOnDay ? 'today' : 'library'; this.message = ''; await this.refresh(); this.navigate('main', -1);
      this.toast(cleaned ? (placeOnDay ? `已贴入${DateTools.label(this.selectedDate)}` : '已收入贴纸盒') : '贴纸已保存，有部分预览文件未清理。');
    } catch (error) {
      if (committed) { this.session = undefined; await this.refresh(); this.navigate('main', -1); this.toast('贴纸已保存，请重新打开查看。'); }
      else this.message = this.reason(error, '保存失败，编辑内容仍在，请重试。');
    } finally { this.busy = false; }
  }
  private requestCancel(): void {
    if (this.busy) return;
    this.getUIContext().showAlertDialog({ title: '放弃这次制作？', message: '只丢弃未保存的修改，已有贴纸和历史纸面保留。',
      primaryButton: { value: '继续制作', action: (): void => {} }, secondaryButton: { value: '放弃', action: (): void => { this.cancel(); } } });
  }
  private async cancel(): Promise<void> {
    this.busy = true;
    try { await this.session?.cancel(); } catch (_) { this.toast('已退出编辑，有部分草稿文件未清理。'); }
    // 草稿文件已经释放，立即离开旧预览，只给返回页入场动画。
    finally { this.session = undefined; this.message = ''; this.busy = false; this.navigate('main', -1, true); }
  }

  private async mutate(action: () => Promise<void>, remember: boolean = false): Promise<void> {
    if (this.busy) return;
    this.busy = true; this.message = '';
    const before: DayPlacement[] = StickerCopies.placements(this.store.placements.filter((value: DayPlacement): boolean => value.dateKey === this.selectedDate));
    try { await action(); if (remember) { this.undo.push(before); if (this.undo.length > 20) this.undo.shift(); } await this.refresh(); }
    catch (error) { this.message = this.reason(error, '操作未完成，原记录保留。'); this.toast(this.message); }
    finally { this.busy = false; }
  }
  private selectPlacement(id: string): void { if (!this.busy) { this.editing = true; this.selectedPlacementId = id; } }
  private finishLayout(): void { this.editing = false; this.selectedPlacementId = ''; this.undo = []; }
  private async restoreLayout(): Promise<void> {
    if (this.busy || !this.commands) return;
    const last: DayPlacement[] | undefined = this.undo[this.undo.length - 1];
    if (last === undefined) { this.toast('没有可撤销的摆放修改。'); return; }
    this.busy = true;
    try { await this.commands.restore(last); this.undo.pop(); await this.refresh(); }
    catch (error) { this.toast(this.reason(error, '撤销未完成，当前纸面保留。')); }
    finally { this.busy = false; }
  }
  private removePlacement(id: string): void {
    if (id.length === 0 || this.busy) return;
    this.getUIContext().showAlertDialog({ title: '从这一天移除？', message: '贴纸仍留在贴纸盒，可以再次使用。',
      primaryButton: { value: '取消', action: (): void => {} }, secondaryButton: { value: '移除', action: (): void => {
        this.mutate(async (): Promise<void> => { await this.repository?.removePlacement(id); }, true);
      } } });
  }
  private requestDeleteAsset(): void {
    if (this.busy || this.session?.isNew) return;
    const count: number = this.store.placements.filter((value: DayPlacement): boolean => value.assetId === this.draftAsset.id).length;
    if (count > 0) { this.toast(`这张贴纸仍有 ${count} 处摆放，请先从对应日期移除。`); return; }
    this.getUIContext().showAlertDialog({ title: '永久删除这张贴纸？', message: '删除原图和全部制作版本，不能恢复。',
      primaryButton: { value: '取消', action: (): void => {} }, secondaryButton: { value: '删除', fontColor: '#B04435', action: (): void => { this.deleteAsset(); } } });
  }
  private async deleteAsset(): Promise<void> {
    if (this.busy || !this.repository || !this.photos) return;
    this.busy = true; let committed: boolean = false;
    try {
      const paths: string[] = await this.repository.removeAsset(this.draftAsset.id); committed = true;
      await this.session?.cancel(); this.session = undefined; this.tab = 'library'; await this.refresh(); this.navigate('main', -1, true);
      await this.photos.discardUnreferenced(paths); this.toast('已删除贴纸。');
    } catch (error) {
      if (committed) { this.session = undefined; this.tab = 'library'; await this.refresh(); this.navigate('main', -1, true); this.toast('贴纸已移除，有部分无引用图片未清理。'); }
      else this.message = this.reason(error, '删除未完成，贴纸仍然保留。');
    } finally { this.busy = false; }
  }
  private toggleDraftFavorite(): void { const next: StickerAsset = StickerCopies.asset(this.draftAsset); next.favorite = !next.favorite; this.draftAsset = next; }
  private async placeAsset(id: string): Promise<void> {
    if (!this.commands || this.busy) return;
    await this.mutate(async (): Promise<void> => { await this.commands?.place(this.store, id, this.selectedDate); });
    if (this.message.length === 0 && this.errorMessage.length === 0) { this.selectTab('today'); this.toast(`已贴入${DateTools.label(this.selectedDate)}`); }
  }

  private async openSettings(): Promise<void> {
    if (this.busy || this.switching()) return;
    this.finishLayout(); this.message = ''; this.storageBytes = -1; this.navigate('settings'); await this.updateUsage();
  }
  private async updateUsage(): Promise<void> {
    try {
      const usage = await this.photos?.usage();
      if (usage !== undefined) {
        this.sourceBytes = usage.sourceBytes; this.renderedBytes = usage.renderedBytes; this.maskBytes = usage.maskBytes;
        this.storageBytes = usage.sourceBytes + usage.renderedBytes + usage.maskBytes;
      }
    }
    catch (_) { this.message = '暂时无法读取存储占用；贴纸未改动。'; }
  }
  private byteLabel(bytes: number): string { return bytes < 1024 ? `${bytes} B` : bytes < 1048576 ? `${(bytes / 1024).toFixed(1)} KB` : `${(bytes / 1048576).toFixed(1)} MB`; }
  private async showStorage(): Promise<void> {
    this.message = ''; await this.updateUsage();
    if (this.message.length > 0) return;
    this.getUIContext().showAlertDialog({ title: '本机图片存储',
      message: `原图 ${this.byteLabel(this.sourceBytes)}\n成品与相机照片 ${this.byteLabel(this.renderedBytes)}\n主体蒙版 ${this.byteLabel(this.maskBytes)}\n\n${this.store.assets.length} 张贴纸，${this.store.revisions.length} 个制作版本。卸载会丢失本机数据，当前还没有云备份。`,
      primaryButton: { value: '知道了', action: (): void => {} } });
  }
  private async savePreferences(value: AppPreferences): Promise<void> {
    if (this.busy || !this.preferences) return;
    this.busy = true; this.message = '';
    try { await this.preferences.save(value); this.prefs = value; } catch (_) { this.message = '偏好保存失败，请重试。'; }
    finally { this.busy = false; }
  }
  private async openLegal(kind: string): Promise<void> {
    if (this.context === undefined) return;
    if (this.page !== 'legal') this.legalReturn = this.page;
    const generation: number = ++this.legalGeneration;
    this.legalLoading = true; this.legalDocument = undefined; this.message = ''; this.navigate('legal');
    try { const document: LegalDocument = await LegalDocuments.load(this.context, kind); if (generation === this.legalGeneration) this.legalDocument = document; }
    catch (_) { this.message = '协议暂时无法打开，请返回后重试。'; }
    finally { if (generation === this.legalGeneration) this.legalLoading = false; }
  }
  private openCategories(): void {
    if (this.busy || this.switching()) return;
    this.categoriesReturn = this.page; this.message = ''; this.navigate('categories');
  }
  private async addCategory(name: string): Promise<void> {
    await this.mutate(async (): Promise<void> => { await this.repository?.saveCategories(this.store.categories.concat([name.trim()])); });
  }
  private async moveCategory(name: string, direction: number): Promise<void> {
    const names: string[] = this.store.categories.slice(); const index: number = names.indexOf(name); const target: number = index + direction;
    if (index < 0 || target < 0 || target >= names.length || index === 0 || target === 0) return;
    const other: string = names[target]; names[target] = names[index]; names[index] = other;
    await this.mutate(async (): Promise<void> => { await this.repository?.saveCategories(names); });
  }
  private removeCategory(name: string): void {
    if (name === '未分类') { this.toast('未分类入口保留。'); return; }
    if (this.store.assets.some((value: StickerAsset): boolean => value.category === name)) { this.toast('分类里仍有贴纸，请先移到其他分类。'); return; }
    this.getUIContext().showAlertDialog({ title: `删除“${name}”分类？`, message: '这个分类目前没有贴纸。',
      primaryButton: { value: '取消', action: (): void => {} }, secondaryButton: { value: '删除', action: (): void => {
        this.mutate(async (): Promise<void> => { await this.repository?.saveCategories(this.store.categories.filter((value: string): boolean => value !== name)); });
      } } });
  }

  @Builder
  private mainContent() {
    Column() {
      // 两个内容页保持挂载，回到贴纸盒时保留滚动、搜索与筛选；隐藏页不接收输入或无障碍焦点。
      Stack() {
        DayCanvas({ store: this.store, selectedDate: this.selectedDate, paperColor: this.paper(), loading: this.loading,
          errorMessage: this.errorMessage, editing: this.editing, selectedPlacementId: this.selectedPlacementId,
          busy: this.busy, reducedMotion: this.reducedMotion,
          onSelectDate: (date: string): void => this.selectDay(date),
          onCalendar: (): void => { this.finishLayout(); this.navigate('calendar'); }, onSettings: (): void => { this.openSettings(); },
          onCamera: (): void => this.openCamera(), onLibrary: (): void => this.selectTab('library'),
          onRetry: (): void => { this.refresh(true); }, onSelectPlacement: (id: string): void => this.selectPlacement(id),
          onEditAsset: (assetId: string, placementId: string): void => { this.openAsset(assetId, placementId); },
          onMovePlacement: (id: string, x: number, y: number): void => { this.mutate(async (): Promise<void> => { await this.commands?.move(this.store, id, x, y); }, true); },
          onTransformPlacement: (id: string, scale: number, rotation: number): void => { this.mutate(async (): Promise<void> => { await this.commands?.transform(this.store, id, scale, rotation); }, true); },
          onLayerPlacement: (id: string, forward: boolean): void => { this.mutate(async (): Promise<void> => { await this.commands?.layer(this.store, id, forward); }, true); },
          onRemovePlacement: (id: string): void => this.removePlacement(id),
          onArrange: (): void => { this.mutate(async (): Promise<void> => { await this.commands?.arrange(this.store, this.selectedDate); }, true); },
          onUndo: (): void => { this.restoreLayout(); }, onFinishLayout: (): void => this.finishLayout() })
          .visibility(this.tab === 'today' ? Visibility.Visible : Visibility.Hidden)
          .accessibilityLevel(this.tab === 'today' ? 'auto' : 'no-hide-descendants')
          .hitTestBehavior(this.tab === 'today' ? HitTestMode.Default : HitTestMode.None)
        StickerLibrary({ store: this.store, selectedDate: this.selectedDate, paperColor: this.paper(), busy: this.busy,
          query: $libraryQuery, category: $libraryCategory, favoritesOnly: $libraryFavoritesOnly,
          onCamera: (): void => this.openCamera(),
          onOpenAsset: (id: string): void => { this.openAsset(id); }, onPlaceAsset: (id: string): void => { this.placeAsset(id); },
          onToggleFavorite: (id: string): void => { this.mutate(async (): Promise<void> => { await this.commands?.favorite(this.store, id); }); },
          onManageCategories: (): void => this.openCategories(), onSettings: (): void => { this.openSettings(); } })
          .visibility(this.tab === 'library' ? Visibility.Visible : Visibility.Hidden)
          .accessibilityLevel(this.tab === 'library' ? 'auto' : 'no-hide-descendants')
          .hitTestBehavior(this.tab === 'library' ? HitTestMode.Default : HitTestMode.None)
      }.width('100%').layoutWeight(1).clip(true).opacity(this.tabOpacity).translate({ x: this.tabOffset })
        .enabled(!this.switching())
        .hitTestBehavior(this.switching() ? HitTestMode.None : HitTestMode.Default)
      MainDock({ selectedTab: this.tab, disabled: this.busy || this.loading || this.switching() || this.errorMessage.length > 0,
        paperColor: this.paper(), onToday: (): void => this.selectTab('today', true),
        onAdd: (): void => this.openCamera(), onLibrary: (): void => this.selectTab('library') })
    }.width('100%').height('100%')
  }
  @Builder
  private paperContent() {
    if (this.page === 'boot') {
      Column() { LoadingProgress().width(28).height(28).color(Theme.ACCENT) }.width('100%').height('100%').justifyContent(FlexAlign.Center)
    } else if (this.page === 'consent') {
      ConsentView({ busy: this.busy, message: this.message, onLegal: (kind: string): void => { this.openLegal(kind); },
        onAccept: (): void => { this.accept(); }, onDecline: (): void => { this.context?.terminateSelf(); } })
    } else if (this.page === 'workbench') {
      StickerWorkbench({ asset: this.draftAsset, revision: this.draftRevision, recipe: this.draftRecipe, paperColor: this.paper(),
        subjectCount: this.subjectCount, sourceWidth: this.session?.sourceWidth ?? 0,
        sourceHeight: this.session?.sourceHeight ?? 0,
        categories: this.store.categories, busy: this.busy, message: this.message,
        canRemake: this.canRemake, canDelete: this.session?.isNew === false, note: this.draftNote, selectedDate: this.selectedDate,
        onRecipeChange: (recipe: StickerRecipe): void => { this.changeRecipe(recipe); },
        onDraftChange: (title: string, category: string, note: string): void => this.updateDraft(title, category, note),
        onSave: (title: string, category: string, note: string, placeOnDay: boolean): void => { this.save(title, category, note, placeOnDay); },
        onBack: (): void => this.requestCancel(), onRetake: (): void => this.retake(),
        onDelete: (): void => this.requestDeleteAsset(), onFavorite: (): void => this.toggleDraftFavorite() })
    } else if (this.page === 'calendar') {
      CalendarView({ store: this.store, selectedDate: this.selectedDate, paperColor: this.paper(),
        reducedMotion: this.reducedMotion,
        onSelectDate: (date: string): void => { this.selectedDate = date; this.tab = 'today'; this.navigate('main', -1); },
        onBack: (): void => this.navigate('main', -1) })
    } else if (this.page === 'settings') {
      SettingsView({ preferences: this.prefs, paperColor: this.paper(), busy: this.busy, storageBytes: this.storageBytes,
        assetCount: this.store.assets.length, revisionCount: this.store.revisions.length, message: this.message,
        onBack: (): void => this.navigate('main', -1), onPreferencesChange: (value: AppPreferences): void => { this.savePreferences(value); },
        onLegal: (kind: string): void => { this.openLegal(kind); }, onManageCategories: (): void => this.openCategories(), onStorage: (): void => { this.showStorage(); } })
    } else if (this.page === 'categories') {
      CategoryManagerView({ categories: this.store.categories, paperColor: this.paper(), busy: this.busy, message: this.message,
        onBack: (): void => { this.navigate(this.categoriesReturn, -1); this.message = ''; }, onAdd: (name: string): void => { this.addCategory(name); },
        onRename: (oldName: string, newName: string): void => { this.mutate(async (): Promise<void> => {
          await this.repository?.renameCategory(oldName, newName.trim());
          if (this.libraryCategory === oldName) this.libraryCategory = newName.trim();
        }); },
        onRemove: (name: string): void => this.removeCategory(name), onMove: (name: string, direction: number): void => { this.moveCategory(name, direction); } })
    } else if (this.page === 'legal') {
      LegalView({ document: this.legalDocument, loading: this.legalLoading, errorMessage: this.message, paperColor: this.paper(),
        onBack: (): void => { this.navigate(this.legalReturn, -1); this.message = ''; } })
    }
  }
  @Builder
  private addSheetContent() {
    StickerAddSheet({ onSelect: (source: string): void => this.chooseAddSource(source),
      onCancel: (): void => { this.showAddSheet = false; } })
  }
  build() {
    Stack() {
      Column() {
        Stack() {
          Column() { this.mainContent() }.width('100%').height('100%')
            .visibility(this.page === 'main' ? Visibility.Visible : Visibility.Hidden)
            .accessibilityLevel(this.page === 'main' ? 'auto' : 'no-hide-descendants')
          if (this.page !== 'main' && this.page !== 'camera') {
            Column() { this.paperContent() }.width('100%').height('100%')
          }
        }.width('100%').height('100%')
      }.width('100%').height('100%').opacity(this.pageOpacity).translate({ x: this.pageOffset })
        .padding({ top: this.topInset, bottom: Math.max(this.bottomInset, 12) }).backgroundColor(this.paper())
        .visibility(this.page === 'camera' ? Visibility.Hidden : Visibility.Visible)
        .enabled(!this.pageSwitching)
        .hitTestBehavior(this.pageSwitching ? HitTestMode.None : HitTestMode.Default)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      if (this.page === 'camera') {
        CameraView({ paperColor: this.paper(), onCapture: (path: string): void => { this.acquire(path); }, onClose: (): void => this.closeCamera(),
          onGallery: (): void => { this.acquire(); } }).opacity(this.pageOpacity)
          .enabled(!this.pageSwitching)
          .hitTestBehavior(this.pageSwitching ? HitTestMode.None : HitTestMode.Default)
      }
      if (this.busy && this.page === 'main') {
        Column({ space: 12 }) { LoadingProgress().width(30).height(30).color(Theme.ACCENT)
          Text(this.message.length > 0 ? this.message : '正在保存…').attributeModifier(new PaperBodyStyle())
        }.padding(Theme.PAGE_GUTTER).backgroundColor(Theme.CARD).borderRadius(Theme.CARD_RADIUS)
      }
    }.width('100%').height('100%').backgroundColor(this.paper())
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .bindSheet($$this.showAddSheet, this.addSheetContent(), {
        height: SheetSize.FIT_CONTENT, showClose: false, dragBar: false, backgroundColor: Theme.CARD,
        onDisappear: (): void => this.finishAddSheet()
      })
  }
}
