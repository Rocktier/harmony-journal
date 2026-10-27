import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { speechRecognizer } from '@kit.CoreSpeechKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

import {
  ASR_AUDIO_TYPE, ASR_ERR_NO_ENGINE, ASR_LANGUAGE, ASR_MAX_AUDIO_MS, ASR_PHASE_FAILED, ASR_PHASE_IDLE,
  ASR_PHASE_LISTENING, ASR_PHASE_UNREADY, ASR_SAMPLE_BIT, ASR_SAMPLE_RATE, ASR_SOUND_CHANNEL,
  AsrPart, asrFinalText, asrLiveText
} from './AsrText';

const DOMAIN: number = 0xD002;
const TAG: string = 'RockJournal';

/**
 * 语音转文字服务（封装 @kit.CoreSpeechKit 的 speechRecognizer）
 *
 * ## 为什么是"离线"而不是云端
 * 官方 .d.ts 原话：_"Currently, this service is available only in Chinese and supports only the offline model."_
 * ⇒ **引擎本身就是端侧离线模型，全程不联网**。这与本族"非主动联网"的口径天然吻合，
 *    也是我们敢在日记本（最私密的文本）上开这个功能的唯一理由 —— 音频不出设备。
 *
 * ## ⚠️ 最大的坑：`online` 参数名与值是反的
 * .d.ts 原文：_"**1**: offline. Currently, only the offline mode is supported."_
 * ⇒ **1 = 离线，0 = 联网（且联网模式当前根本不支持）**。参数名叫 online，值是 1 表示离线，
 *    网上教程清一色写 `online: 0` 表示离线，那是错的。
 *    本族 TtsEngine 的 `TTS_ONLINE_MODE = 1` 是同一个口径（已交叉验证）。
 *
 * ## 没有真机时这里会走到哪儿
 * **模拟器没有离线识别引擎** ⇒ `createEngine` 失败 ⇒ 进入 `broken` 状态 ⇒
 * 阶段置 `ASR_PHASE_UNREADY`，UI 显示"用不了"并禁用按钮。
 * 这是**设计内的路径，不是 bug**：宁可如实说用不了，也不给一个转不动的按钮让用户干等。
 */
export class AsrService {
  private engine: speechRecognizer.SpeechRecognitionEngine | null = null;
  private parts: AsrPart[] = [];
  private phase: number = ASR_PHASE_IDLE;
  private errCode: number = 0;
  private seq: number = 0;
  private sessionId: string = '';
  /** 引擎起不来过 ⇒ 这台设备没这能力，别再反复重试（模拟器必走到） */
  private broken: boolean = false;

  private liveHook: ((text: string) => void) | null = null;
  private doneHook: ((text: string) => void) | null = null;
  private phaseHook: ((phase: number, errCode: number) => void) | null = null;

  /** 注册"实时文本变了"回调（编辑器据此刷新 @State） */
  onLive(hook: (text: string) => void): void {
    this.liveHook = hook;
  }

  /** 注册"这一轮结束"回调（拿到最终文本） */
  onDone(hook: (text: string) => void): void {
    this.doneHook = hook;
  }

  /** 注册"阶段变了"回调 */
  onPhaseChange(hook: (phase: number, errCode: number) => void): void {
    this.phaseHook = hook;
  }

  getPhase(): number {
    return this.phase;
  }

  getErrCode(): number {
    return this.errCode;
  }

  /** 当前累积的实时文本（进入页面/恢复时用） */
  getLiveText(): string {
    return asrLiveText(this.parts);
  }

  /** 这台设备起不来引擎（UI 据此显示"用不了"） */
  isBroken(): boolean {
    return this.broken;
  }

  /**
   * 申请麦克风权限（必须先授权，否则引擎开不了麦克风）
   *
   * 放在服务里而不是页面里：权限名与文案是一件事，别散在两处。
   */
  static async ensureMic(ctx: common.UIAbilityContext): Promise<boolean> {
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    const perms: Array<Permissions> = ['ohos.permission.MICROPHONE'];
    try {
      /**
       * ⚠️ 结果的**类型不能写出名字**（2026-10-27 编译实测）：
       *   官方 API 文本里叫 `PermissionRequestResult`，但它**没有导出到
       *   abilityAccessCtrl 命名空间** —— 写 `abilityAccessCtrl.PermissionRequestResult`
       *   直接报 `10505001 Namespace 'abilityAccessCtrl' has no exported member 'PermissionRequestResult'`，
       *   且全 SDK 的 .d.ts 里都搜不到它的声明（只存在于 DevEco 智能提示用的
       *   api-version/AbilityKit.json 里）⇒ 只能靠推断拿它，别再试图给它命名。
       */
      const res = await atManager.requestPermissionsFromUser(ctx, perms);
      if (res.authResults.length === 0) {
        return false;
      }
      // 0 = 已授权（官方口径：0 granted / -1 未授权）
      return res.authResults[0] === 0;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'asr: requestPermissionsFromUser threw: %{public}s', JSON.stringify(e));
      return false;
    }
  }

  /**
   * 开始聆听。
   *
   * 引擎是懒创建的（第一次说话时才起），起不来就进 UNREADY —— 那是设备能力问题，
   * 不是用户操作问题，所以**不进 FAILED**（FAILED 意味着"可以再试一次"）。
   */
  start(): void {
    if (this.phase === ASR_PHASE_LISTENING) {
      return; // 防重复 start（官方会报 1002200002）
    }
    if (this.broken) {
      this.setPhase(ASR_PHASE_UNREADY, ASR_ERR_NO_ENGINE);
      return;
    }
    this.parts = [];
    this.setPhase(ASR_PHASE_LISTENING, 0);
    if (this.engine !== null) {
      this.doStart(this.engine);
      return;
    }
    this.createAndStart();
  }

  private createAndStart(): void {
    const self: AsrService = this;
    // ⚠️ online: 1 = 离线（见类注释：参数名与值是反的）
    const params: speechRecognizer.CreateEngineParams = {
      language: ASR_LANGUAGE,
      online: 1
    };
    try {
      speechRecognizer.createEngine(params,
        (err: BusinessError | null | undefined, eng?: speechRecognizer.SpeechRecognitionEngine) => {
          // ⚠️ 成功时 err 是 **undefined 而不是 null**（本族 TtsEngine 2026-10-18 jscrash 的教训）：
          //    只判 `err !== null` 防不住 undefined ⇒ 误入错误分支读 err.code 会 TypeError 崩进程。
          if (err !== undefined && err !== null) {
            hilog.warn(DOMAIN, TAG, 'asr: createEngine failed: %{public}d:%{public}s', err.code, err.message);
            self.broken = true;
            self.setPhase(ASR_PHASE_UNREADY, ASR_ERR_NO_ENGINE);
            return;
          }
          if (eng === undefined) {
            hilog.warn(DOMAIN, TAG, 'asr: createEngine returned no engine');
            self.broken = true;
            self.setPhase(ASR_PHASE_UNREADY, ASR_ERR_NO_ENGINE);
            return;
          }
          eng.setListener(self.buildListener());
          self.engine = eng;
          self.doStart(eng);
        });
    } catch (e) {
      // 能力缺失时部分版本走同步 throw 而不是 err 回调（照 TtsEngine 的处理）
      hilog.error(DOMAIN, TAG, 'asr: createEngine threw: %{public}s', JSON.stringify(e));
      this.broken = true;
      this.setPhase(ASR_PHASE_UNREADY, ASR_ERR_NO_ENGINE);
    }
  }

  private doStart(eng: speechRecognizer.SpeechRecognitionEngine): void {
    this.seq++;
    this.sessionId = 'rj-' + Date.now() + '-' + this.seq;
    // 音频参数：官方只有这一组值合法（pcm / 16000 / 单声道 / 16bit），写别的直接 401
    const audio: speechRecognizer.AudioInfo = {
      audioType: ASR_AUDIO_TYPE,
      sampleRate: ASR_SAMPLE_RATE,
      soundChannel: ASR_SOUND_CHANNEL,
      sampleBit: ASR_SAMPLE_BIT
    };
    // recognizeMode **0 = 引擎自己开麦克风录音**（我们只要麦克风权限，不必自己开 AudioCapturer 喂 PCM）；
    // ⚠️ 默认值是 1（外部 writeAudio 模式），**省略 extraParams 会走到错的模式** —— 所以这条必须显式给。
    // ⚠️ 键名是字符串，编译器查不出来；若真机上发现不生效，第一嫌疑就是这里（官方参考文档口径）。
    const extra: Record<string, Object> = {
      'recognizeMode': 0,
      'maxAudioDuration': ASR_MAX_AUDIO_MS
    };
    const params: speechRecognizer.StartParams = {
      sessionId: this.sessionId,
      audioInfo: audio,
      extraParams: extra
    };
    try {
      eng.startListening(params);
      hilog.info(DOMAIN, TAG, 'asr: startListening %s', this.sessionId);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'asr: startListening threw: %{public}s', JSON.stringify(e));
      this.setPhase(ASR_PHASE_FAILED, err.code);
    }
  }

  /**
   * 说完点「完成」：finish 让引擎把最后一段吐出来（结果从 onComplete 回来）。
   * 注意与 cancel 的区别：finish 保留文本，cancel 丢弃。
   */
  stop(): void {
    if (this.engine === null || this.phase !== ASR_PHASE_LISTENING) {
      return;
    }
    try {
      this.engine.finish(this.sessionId);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'asr: finish threw: %{public}s', JSON.stringify(e));
      this.setPhase(ASR_PHASE_FAILED, err.code);
    }
  }

  /** 放弃这一轮（不落文本） */
  cancel(): void {
    if (this.engine !== null) {
      try {
        this.engine.cancel(this.sessionId);
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'asr: cancel threw: %{public}s', JSON.stringify(e));
      }
    }
    this.parts = [];
    this.setPhase(ASR_PHASE_IDLE, 0);
  }

  /** 离开页面必调：释放引擎，别占着麦克风 */
  release(): void {
    this.parts = [];
    if (this.engine !== null) {
      try {
        this.engine.shutdown();
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'asr: shutdown threw: %{public}s', JSON.stringify(e));
      }
      this.engine = null;
    }
    this.setPhase(ASR_PHASE_IDLE, 0);
  }

  private buildListener(): speechRecognizer.RecognitionListener {
    const self: AsrService = this;
    // ArkTS 铁律（本族 TtsEngine 同款）：对象字面量必须先落到接口变量再 return，
    // 且字段用**方法语法**（箭头函数属性值会踩 arkts-no-untyped-obj-literals）。
    // RecognitionListener 五个方法**全必填**，少一个编译不过。
    const listener: speechRecognizer.RecognitionListener = {
      onStart(sessionId: string, eventMessage: string): void {
        hilog.info(DOMAIN, TAG, 'asr: onStart %s %s', sessionId, eventMessage);
      },
      onEvent(sessionId: string, eventCode: number, eventMessage: string): void {
        // 1 = 开始说话，3 = 说完（可用于将来做"静音自动停"，一期不用）
        hilog.info(DOMAIN, TAG, 'asr: onEvent code=%{public}d %s', eventCode, eventMessage);
      },
      onResult(sessionId: string, result: speechRecognizer.SpeechRecognitionResult): void {
        // 过期守卫（sessionId 版）：stop 是异步的，上一轮的压哨结果不能混进新一轮
        if (sessionId !== self.sessionId) {
          hilog.info(DOMAIN, TAG, 'asr: onResult stale, dropped: %s', sessionId);
          return;
        }
        const part: AsrPart = { text: result.result, isFinal: result.isFinal };
        self.parts.push(part);
        self.fireLive(asrLiveText(self.parts));
      },
      onComplete(sessionId: string, eventMessage: string): void {
        if (sessionId !== self.sessionId) {
          hilog.info(DOMAIN, TAG, 'asr: onComplete stale, dropped: %s', sessionId);
          return;
        }
        const text: string = asrFinalText(self.parts);
        hilog.info(DOMAIN, TAG, 'asr: onComplete chars=%{public}d', text.length);
        self.setPhase(ASR_PHASE_IDLE, 0);
        self.fireDone(text);
      },
      onError(sessionId: string, errorCode: number, errorMessage: string): void {
        hilog.error(DOMAIN, TAG, 'asr: onError %{public}d %s', errorCode, errorMessage);
        self.parts = [];
        self.setPhase(ASR_PHASE_FAILED, errorCode);
      }
    };
    return listener;
  }

  private setPhase(phase: number, errCode: number): void {
    this.phase = phase;
    this.errCode = errCode;
    const hook: ((p: number, c: number) => void) | null = this.phaseHook;
    if (hook !== null) {
      hook(phase, errCode);
    }
  }

  private fireLive(text: string): void {
    const hook: ((t: string) => void) | null = this.liveHook;
    if (hook !== null) {
      hook(text);
    }
  }

  private fireDone(text: string): void {
    const hook: ((t: string) => void) | null = this.doneHook;
    if (hook !== null) {
      hook(text);
    }
  }
}
