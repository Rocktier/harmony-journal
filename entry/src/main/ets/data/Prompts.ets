/**
 * 每日写作提示（Daily Prompts，1.0.6）—— **纯逻辑，不引任何 @kit** —— 单测可跑
 *
 * 用户视角：写日记最大的障碍不是没时间，是打开空白页那一刻不知道写什么。
 * 提示不是替用户写，而是给一个**具体的切口**：
 * "今天最不想忘记的一个细节是什么？" 比 "写点什么吧" 有用一百倍。
 *
 * ⚠️ 与模板的区别（为什么两个都要）：
 *    模板是**固定的套路**（每天晨间三问，天天一样，用来养成节奏）；
 *    提示是**每天换的一句**（用来打破惯性，撞上自己没想到的角度）。
 *    Day One 也是两套并存（Templates + Daily Writing Prompts）。
 *
 * ⚠️ 与"每日提示 App"的区别：我们**不推送、不弹窗、不打扰**。
 *    提示只在用户主动打开新日记时静静躺在那里 —— 契合"零联网、零打扰"的立场。
 */

/**
 * 提示库（一句一条，都是具体切口，不是"今天心情如何"这种空话）
 *
 * ⚠️ 选句的三条标准（写新提示时照此，别往里塞鸡汤）：
 *  ① **具体到能直接往下接字**（问"什么"而不是问"怎样"）
 *  ② 不预设情绪（不写"今天最开心的事" —— 难过的人答不上来）
 *  ③ 没有正确答案（不给压力，答不上来换一条就是了）
 */
export const PROMPTS: string[] = [
  '今天有一个瞬间让我停了一下：',
  '如果今天只能用一句话记录，我会写：',
  '今天最不想忘记的一个细节是：',
  '今天我改变主意的一次是：',
  '今天听到的一句话，我想记下来：',
  '今天有一件事花的时间比预想的长：',
  '今天我本来想做但没做的是：',
  '今天身体给我的一个信号是：',
  '今天让我觉得"还好"的一件小事：',
  '今天我想对某人说但没说出口的：',
  '今天最安静的十分钟我在做什么：',
  '今天有人对我做了一个小动作，我记到现在：',
  '今天我做得比上次好的一点是：',
  '今天有点卡住的地方是：',
  '如果今天能重来，我会在哪里慢一点：',
  '今天我在想一件还没发生的事：',
  '今天我忍住没说的一句话是：',
  '今天让我意外的一个反应（别人的或我的）：',
  '今天我路过时多看了一眼的东西：',
  '今天有一件事，我决定不再等了：',
  '今天我为自己的一个选择负责：',
  '今天有人在等我，那感觉是：',
  '今天我学到的一个没用的知识：',
  '今天手边最常碰到的东西是：',
  '今天我低估了的一件事：',
  '今天有一件小事我要谢谢它：',
  '今天的天气让我想要：',
  '今天我读到的 / 看到的一句打动我的话：',
  '今天有个念头出现过两次：',
  '今天我终于做完的那件事是：',
  '今天我想少做一点的是：',
  '今天有人让我觉得被理解了：',
  '今天我做的一个没被看见的努力：',
  '今天我推开了一扇什么门：',
  '今天有件事我做得比想象中好：',
  '今天我想保留下来的一个念头：',
  '今天的我，和上周的我不一样的地方：',
  '今天有件事我想再想想：',
  '今天我拒绝了一次，原因是：',
  '今天我在赶什么？赶上了吗：',
  '今天有东西让我觉得旧了：',
  '今天我为一个别人不会注意到的事费了心：',
  '今天我走神的时候想到了什么：',
  '今天有个问题我没敢问出口：',
  '今天我原谅了自己的一次：',
  '今天我看见的一个陌生人在做什么：',
  '今天有一件事，我觉得"就这样也挺好"：',
  '今天我做了件不需要被表扬的事：',
  '今天有个瞬间我想拍照但没拍：',
  '今天我有点在意别人的一句评价：',
  '今天有件事我终于想明白了：',
  '今天我让自己休息了，方式是：',
  '今天有个东西坏掉了 / 用完了：',
  '今天我想起了一个很久没想起的人：',
  '今天有个念头让我笑了一下：',
  '今天我说的最后一句重要的话是：',
  '今天有个地方我想再去一次：',
  '今天我改变了环境（收拾、挪动、开窗）：',
  '今天我担心的一件事，现在看：',
  '今天我收到 / 给出的一个回应：',
  '今天有一件事，我决定先放着不做：',
  '今天最让我踏实的一个时刻：',
  '今天我为了别人调整了一次自己：',
  '今天有个想法我还不敢告诉别人：',
  '今天我重复做了很多次的一个动作是：',
  '今天我回头看了一眼之前写的东西：',
  '今天有个瞬间我觉得时间变慢了：',
  '今天我想成为的那种人，我做了一次：',
  '今天有一件事让我意识到时间在过：',
  '今天我给自己的一个小奖励：',
  '今天有个人说了句我以为他不会说的话：',
  '今天我在一件小事上坚持了：',
  '今天有个声音 / 气味我记得很清楚：',
  '今天我想对明天的自己说一句：'
];

/** 日期字符串 → 一个稳定的槽位（djb2 变体；无符号避免负数取模） */
function hashOf(s: string): number {
  let h: number = 5381;
  for (let i: number = 0; i < s.length; i++) {
    // ⚠️ `>>> 0` 不能省：int32 乘法会溢出成负数，负数 % N 在 JS 里仍是负数
    h = ((h * 33 + s.charCodeAt(i)) >>> 0);
  }
  return h;
}

/**
 * 取某一天的提示（**确定性**：同一天永远同一条，跨天几乎必变）
 *
 * ⚠️ 为什么按日期哈希而不是随机：
 *    用户今天打开三次必须看到同一句（否则"每日提示"名不副实，
 *    还会让人以为这个功能是坏的）。哈希保证了这一点，且不需要存任何状态。
 *
 * ⚠️ 非日期入参返回空串（调用方据此不显示提示条，而不是显示一句随机的）：
 *    日期不合法说明调用方用错了，静默给条提示会掩盖 bug。
 */
export function promptOfDate(dateKey: string): string {
  if (typeof dateKey !== 'string' || dateKey.length !== 10) {
    return '';
  }
  if (PROMPTS.length === 0) {
    return '';
  }
  return PROMPTS[hashOf(dateKey) % PROMPTS.length];
}

/**
 * 取某天提示在库里的序号（测试与排错用：能反查"为什么今天这句"）
 * -1 = 入参不合法
 */
export function promptIndexOn(dateKey: string): number {
  if (typeof dateKey !== 'string' || dateKey.length !== 10) {
    return -1;
  }
  if (PROMPTS.length === 0) {
    return -1;
  }
  return hashOf(dateKey) % PROMPTS.length;
}

/**
 * 相邻两天会不会撞同一句（**单测守门**：提示库变化时用来体检分布）
 *
 * 用法：给定一段时间范围，统计有多少个"下一天和今天撞句"的次数。
 * 撞得多说明哈希分布差或库太小 —— 用户会连着看到同一句，那就不叫"每日"了。
 */
export function repeatedNeighborDays(from: string, to: string): number {
  if (typeof from !== 'string' || typeof to !== 'string' || from.length !== 10 || to.length !== 10) {
    return 0;
  }
  if (from > to) {
    return 0;
  }
  let count: number = 0;
  let cursor: string = from;
  let guard: number = 0;
  while (cursor < to && guard < 4000) {
    const next: string = nextDateKey(cursor);
    if (next.length === 0) {
      break;
    }
    if (promptIndexOn(cursor) === promptIndexOn(next)) {
      count = count + 1;
    }
    cursor = next;
    guard = guard + 1;
  }
  return count;
}

/** 下一天的日期键（跨月跨年闰年都对；入参不合法返回空串） */
export function nextDateKey(key: string): string {
  if (typeof key !== 'string' || key.length !== 10) {
    return '';
  }
  const y: number = Number(key.substring(0, 4));
  const m: number = Number(key.substring(5, 7));
  const d: number = Number(key.substring(8, 10));
  if (!isFinite(y) || !isFinite(m) || !isFinite(d) || m < 1 || m > 12 || d < 1 || d > 31) {
    return '';
  }
  const last: number = daysInMonth(y, m);
  if (d < last) {
    return key.substring(0, 8) + pad2(d + 1);
  }
  if (m < 12) {
    return y + '-' + pad2(m + 1) + '-01';
  }
  return (y + 1) + '-01-01';
}

function pad2(n: number): string {
  return n < 10 ? '0' + n : '' + n;
}

function daysInMonth(year: number, month: number): number {
  if (month === 2) {
    return isLeapYear(year) ? 29 : 28;
  }
  const big: number[] = [1, 3, 5, 7, 8, 10, 12];
  for (let i: number = 0; i < big.length; i++) {
    if (big[i] === month) {
      return 31;
    }
  }
  return 30;
}

function isLeapYear(y: number): boolean {
  return (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0;
}
