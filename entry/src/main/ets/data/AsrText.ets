/**
 * 语音转文字（ASR）纯逻辑层
 *
 * **不引任何 @kit** —— 照 NoteBlocks.ets 的规矩，可被 esbuild 当 TS 编译进单测。
 *
 * 为什么要把这些抽出来（2026-10-27，对标 Day One 语音能力时定的纪律）：
 * 语音识别**必须真机才能跑**（模拟器没有离线识别引擎，详见 AsrService 头注），
 * 而党哥手上没真机 ⇒ 能自动验证的就只剩"跟 API 无关的判断"：
 *   · 引擎吐出的一串结果怎么拼成一句话（结果累积）
 *   · 失败了界面上该说什么（如实提示，不做"正在努力识别…"这种无信息量的话）
 * 把这两块收在这里，就等于把"没真机也能守住的部分"最大化。
 */

/** 引擎吐出的一条结果。`isFinal=true` = 这一句已定稿，不会再改 */
export interface AsrPart {
  text: string;
  isFinal: boolean;
}

/** 空闲（没在听） */
export const ASR_PHASE_IDLE: number = 0;
/** 正在聆听 */
export const ASR_PHASE_LISTENING: number = 1;
/**
 * 这台设备用不了语音转文字（引擎起不来）。
 * ⚠️ **这是一等公民状态，不是异常**：模拟器、没有中文离线模型的设备都会走到这里，
 *    必须给一句人话、且按钮禁用 —— 不能让用户对着一个永远转不动的按钮干等。
 */
export const ASR_PHASE_UNREADY: number = 2;
/** 这一轮出错了（还能再试） */
export const ASR_PHASE_FAILED: number = 3;

/** 官方口径：短语音模式单次最长 60000ms（60 秒）。口述一段日记够用 */
export const ASR_MAX_AUDIO_MS: number = 60000;

/** 音频参数（官方口径：只有这一组值合法，写别的值直接报 401） */
export const ASR_AUDIO_TYPE: string = 'pcm';
export const ASR_SAMPLE_RATE: number = 16000;
export const ASR_SOUND_CHANNEL: number = 1;
export const ASR_SAMPLE_BIT: number = 16;
/** 语种：官方明说只有中文普通话（含中文语境下的英文） */
export const ASR_LANGUAGE: string = 'zh-CN';

/** 麦克风权限被拒（不是引擎错误码，是我们自己约定的负值，避免和官方 10022xxxxx 撞号） */
export const ASR_ERR_NO_PERMISSION: number = -1;
/** 引擎起不来 = 设备不支持 / 没有离线模型 */
export const ASR_ERR_NO_ENGINE: number = -2;
/** 官方错误码：识别引擎正忙 */
export const ASR_ERR_BUSY: number = 1002200006;
/** 官方错误码：超过最大音频长度 */
export const ASR_ERR_TOO_LONG: number = 1002200003;

/**
 * 已定稿的部分：把所有 `isFinal` 的结果按顺序拼起来。
 *
 * ⚠️ 语义假设（**待真机验证**）：每条 isFinal 结果是一个"已说完的小句"，
 *    之间要累加。若真机上发现引擎发的是"累计全文"，这里要改成取最后一条
 *    —— 改一行即可，UI 层不用动（这也是把逻辑收在这层的价值）。
 */
export function collectFinalText(parts: AsrPart[]): string {
  let s: string = '';
  for (let i: number = 0; i < parts.length; i++) {
    if (parts[i].isFinal) {
      s += parts[i].text;
    }
  }
  return s;
}

/**
 * 还在修的那一段：引擎会把当前这一句**越修越准地重发**（不是累加），
 * 所以取最后一条非定稿的，而不是把中间态全拼起来。
 */
export function asrPendingText(parts: AsrPart[]): string {
  let s: string = '';
  for (let i: number = 0; i < parts.length; i++) {
    if (!parts[i].isFinal) {
      s = parts[i].text;
    }
  }
  return s;
}

/** 聆听中的实时显示 = 已定稿 + 正在修的那一段 */
export function asrLiveText(parts: AsrPart[]): string {
  return collectFinalText(parts) + asrPendingText(parts);
}

/**
 * 最终要落进正文的文本。
 * 为什么要 trim：识别结果常在首尾带空格，直接灌进正文会出现" 今天… "。
 */
export function asrFinalText(parts: AsrPart[]): string {
  return collectFinalText(parts).trim();
}

/**
 * 给用户的如实提示。
 *
 * 纪律：**说人话、给原因、给下一步**。
 * "语音识别失败，错误码 1002200001"这种是甩锅，不写。
 */
export function asrNoticeOf(phase: number, errCode: number): string {
  if (phase === ASR_PHASE_LISTENING) {
    return '正在聆听，说完点「完成」';
  }
  if (phase === ASR_PHASE_UNREADY) {
    return '这台设备用不了语音转文字：系统的离线识别引擎不可用';
  }
  if (phase === ASR_PHASE_FAILED) {
    if (errCode === ASR_ERR_NO_PERMISSION) {
      return '需要麦克风权限才能语音转文字';
    }
    if (errCode === ASR_ERR_BUSY) {
      return '识别引擎正忙，稍等一下再试';
    }
    if (errCode === ASR_ERR_TOO_LONG) {
      return '说得太久了，一段最长 60 秒，请分段说';
    }
    return '这次没听清，可以再说一次';
  }
  return '';
}

/**
 * 麦克风按钮是否可点。
 *
 * 不可用 = **禁用并说明原因，而不是把按钮藏掉** ——
 * 藏掉的话用户以为根本没这个功能，换个设备也不会来找。
 * `locked` = 时间胶囊锁着（只读守卫，这时候连字都打不了，自然也不能说）。
 */
export function asrButtonEnabled(phase: number, locked: boolean): boolean {
  if (locked) {
    return false;
  }
  return phase === ASR_PHASE_IDLE || phase === ASR_PHASE_FAILED;
}
