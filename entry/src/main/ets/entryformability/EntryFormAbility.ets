import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { Configuration, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { CARD_DIM_SMALL, JournalCardData, journalCardData } from '../data/JournalCardData';

const DOMAIN: number = 0x0000;
const TAG: string = 'RockJournal';

/**
 * Journal 桌面服务卡片 Extension（2026-10-26）
 *
 * 与 Rock阅读 续读卡片的差别，也是本卡片**故意**的差别：
 *   Reader 卡片要查书库（书名/进度/章节）—— 数据在应用沙箱里，Form 进程读得到。
 *   Journal 卡片**不查任何库** —— 日记正文与索引全加密，主密钥只在主进程内存里，
 *   Form 进程没有密钥 ⇒ 结构上读不出任何一条日记。
 *   所以这里只有"今天是几号" + 一个"写今天"动作，**零泄漏**（详见 JournalCardData 头注）。
 *
 * 生命周期：
 *   - onAddForm：系统把卡片加到桌面，同步返回首绘数据（日期现算）。
 *   - onUpdateForm：系统定时刷新（跨天要换日期）/ 用户手动刷新 ⇒ 重算日期推回去。
 *   - onFormEvent：卡片上的动作（本卡片整卡点击走 router，不经这里）。
 */
export default class EntryFormAbility extends FormExtensionAbility {
  /** 从 want.parameters 里取尺寸（系统给 FormDimension 枚举；容错字符串形态） */
  private dimOfParams(params: Record<string, Object> | undefined): string {
    if (params === undefined) {
      return CARD_DIM_SMALL;
    }
    const raw: Object | undefined = params[formInfo.FormParam.DIMENSION_KEY];
    if (typeof raw === 'number') {
      return raw === 2 ? '2*4' : CARD_DIM_SMALL;
    }
    if (typeof raw === 'string' && raw.indexOf('*') >= 0) {
      return raw;
    }
    return CARD_DIM_SMALL;
  }

  /**
   * 加卡片（同步签名）：卡片只有日期，现算即可，没有 IO 也不需要快照。
   *
   * 为什么不需要 Reader 那套「先读快照首绘、再异步查库推准的」：
   *   卡片数据 = 今天的日期 = 纯函数，不存在"快照过期"问题。
   */
  onAddForm(want: Want): formBindingData.FormBindingData {
    const dim: string = this.dimOfParams(want.parameters);
    const data: JournalCardData = journalCardData(dim, new Date());
    hilog.info(DOMAIN, TAG, 'onAddForm dim=%{public}s date=%{public}s', data.dimension, data.dateText);
    return formBindingData.createFormBindingData(data);
  }

  /** 系统定时刷新 / 用户手动刷新：重算日期（跨天靠这个换日期） */
  onUpdateForm(formId: string, wantParams?: Record<string, Object>): void {
    const dim: string = this.dimOfParams(wantParams);
    const data: JournalCardData = journalCardData(dim, new Date());
    formProvider.updateForm(formId, formBindingData.createFormBindingData(data)).catch((e: Error) => {
      hilog.warn(DOMAIN, TAG, 'updateForm failed: %{public}s', e.message);
    });
  }

  onCastToNormalForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onCastToNormalForm %{public}s', formId);
  }

  onChangeFormVisibility(newStatus: Record<string, number>): void {
    hilog.info(DOMAIN, TAG, 'onChangeFormVisibility');
  }

  /** 'message' 动作事件；本卡片整卡点击走 router（postCardAction），这里只留日志 */
  onFormEvent(formId: string, message: string): void {
    hilog.info(DOMAIN, TAG, 'onFormEvent %{public}s %{public}s', formId, message);
  }

  onRemoveForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onRemoveForm %{public}s', formId);
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }

  /** 深浅色/语言变化：重算一次日期（配色由系统 colorMode=auto 托管，这里只管数据） */
  onConfigurationUpdate(newConfig: Configuration): void {
    hilog.info(DOMAIN, TAG, 'onConfigurationUpdate');
  }
}
