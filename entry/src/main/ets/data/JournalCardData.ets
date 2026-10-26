import { dateKeyOf } from './NoteMeta';

/**
 * Journal 桌面服务卡片的数据层（**零泄漏版**，2026-10-26 党哥拍板）
 *
 * ── 为什么卡片里一个字日记内容都没有 ────────────────────────────────
 * Rock私记是隐私日记：正文与索引**整份加密**（`notes/<id>.rkd` + `index.rkd`，
 * AES-256-GCM，主密钥只存在应用进程内存里）。而服务卡片跑在
 * `FormExtensionAbility` 里 —— 它与应用主进程**不共享内存**，拿不到主密钥，
 * 也就**无法解密任何一条日记**。
 *
 * 这不是"暂时没做"，而是**结构上做不到**：卡片进程没有密钥。
 * 所以卡片只放"公共信息"（今天的日期）+ 一个动作入口（写今天）。
 * 党哥 2026-10-26 明确选了「零泄漏」档：不写任何明文快照，
 * 磁盘上的数据依旧 100% 加密，隐私承诺一个字不改。
 *
 * ── 为什么不放"今天已写 N 字 / 连续 N 天" ──────────────────────────
 * 那需要主进程把统计数字写成**明文快照**给卡片读 ⇒ 磁盘上多一份可读元数据。
 * 与"全加密"的承诺冲突，收益又只是好看 —— 不做。
 *
 * ── 数据从哪来 ──────────────────────────────────────────────────────
 * 只有"今天是几月几号星期几" —— 系统时间，谁都能算，零隐私成本。
 * ⚠️ 一律**本地时区**（家族铁律）：`toISOString()` 是 UTC，东八区 00:00–08:00
 * 会写成"昨天"。这里用 `getMonth()/getDate()/getDay()`，天然本地。
 */

/** 卡片规格：2×2 / 2×4（与 Reader 卡片同一套尺寸约定） */
export const CARD_DIM_SMALL: string = '2*2';
export const CARD_DIM_WIDE: string = '2*4';

/** 星期几（getDay()：0=周日） */
const WEEKDAY_CN: string[] = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];

/** 卡片绑定数据（字段名即 WidgetCard 里 @LocalStorageProp 的 key） */
export interface JournalCardData {
  /** '2*2' | '2*4' */
  dimension: string;
  /** 10月26日 */
  dateText: string;
  /** 星期一 */
  weekdayText: string;
  /** 2026-10-26（本地时区；供跨天判定与调试） */
  todayKey: string;
}

/** '10月26日' */
export function cardDateText(d: Date): string {
  return `${d.getMonth() + 1}月${d.getDate()}日`;
}

/** '星期一' */
export function cardWeekdayText(d: Date): string {
  const i: number = d.getDay();
  if (i < 0 || i > 6) {
    return '';
  }
  return WEEKDAY_CN[i];
}

/**
 * 组装卡片绑定数据。
 * @param dimension 卡片规格（来自系统 form 参数）
 * @param now       当前时间（**本地时区**）
 */
export function journalCardData(dimension: string, now: Date): JournalCardData {
  return {
    dimension: dimension.length > 0 ? dimension : CARD_DIM_SMALL,
    dateText: cardDateText(now),
    weekdayText: cardWeekdayText(now),
    todayKey: dateKeyOf(now)
  };
}

/** 卡片点击后传给应用的意图（写今天） */
export const CARD_INTENT_WRITE_TODAY: string = 'writeToday';
