# Rock私记 1.0.7 更新说明（华为应用市场后台上传用）

> 版本：1.0.7（versionCode **1000008**）
> 状态：**已出包 + 上传前闸门全过（2026-10-29 22:55），可提交 AGC**
> 本版性质：**性能修复版**（无新增功能、无新增权限、隐私政策一字未改）
> 对应代码区间：`v1.0.6 .. HEAD`（性能提交 `beea977`）
> 上架包：`Rock私记-1.0.7-上架.app`（release 正式签名 rockjournal-v1.p7b）

---

## 更新说明正文（直接粘贴这段）

```
【优化】解锁更快更顺，界面不再卡住
输入主密码后，解锁计算改到后台执行，界面会立刻响应，
不会再出现「点了没反应、屏幕像冻住」的情况。

【优化】解锁按钮即时反馈
点击「用主密码解锁」后，按钮会马上变成「正在解锁…」并暂时禁用，
重复点击不会再触发多次运算。

【优化】密钥参数统一管理，兼容性更强
密钥派生参数集中到一处统一维护并有自动校验，
确保老用户已有的日记在任何情况下都能正常解锁打开。

本次更新不新增任何功能、不新增任何权限、不收集任何新数据，
仍然完全离线、不联网、不上传、无账号。
```

正文 3 条 —— 全是体验优化，**没有任何用户可见的新功能**。

---

## ⚠️ 本版无需改隐私政策（重要）

这一版只改了**性能**（代码在哪个线程跑），**没有新增权限、没有新增数据形态**。
⇒ AGC 后台的「权限说明」照旧（仍是麦克风一项，来自 1.0.6）；
⇒ 隐私政策链接照旧（<https://www.91hym.cn/devs/756.html#privacy>），**一个字都不用改**。

⚠️ 但请注意：**1.0.6 的博客隐私政策同步仍未做**（党哥手动）——
博客 `#privacy` 章第四节现在还写着「两款应用都不申请任何权限」，
而实现里 Rock私记 有麦克风权限。**这次上传不因此被拒（1.0.6 已用同一份政策过审）**，
但博客侧建议尽快同步，替换文本见 `docs/blog-privacy-sync-1.0.6.md`。

---

## 本版改动明细（性能整改）

### 背景

AGC 上架自检报「应用内点击操作完成快」不通过：**检测值 2666ms / 目标线 2400ms**。
官方标准值 ≤900ms。

该检测项测的是**墙钟**：手指抬起（ACTION_UP）→ **页面转场 lane 结束**。
⇒ **转场画不出来 = lane 结束被推后** —— 也就是说，点击之后主线程被同步重活堵住，
页面转场画不出来，就被判为超时。

### 根因

`security/KeyCustody.ets` 的 `deriveKek()` 用的是**同步版** `kdf.generateSecretSync(spec)`，
PBKDF2 **10 万轮**（≈ 20 万次 SHA-256 压缩）跑在**调用线程**上。
调用链是「解锁按钮 onClick → recoverByPassword → deriveKek」
⇒ 整段 KDF 在 UI 主线程上一口气跑完，中间**零帧产出**。

SDK 官方注释本身就写着（原文）：
> _"may take a long time and block the main thread … advised to invoke synchronous API within a child thread to avoid blocking it"_

### 改动

| # | 改动 | 文件 |
|---|------|------|
| ① | `deriveKek` / `recoverLegacy` 改用**异步** `await kdf.generateSecret(spec)` | `security/KeyCustody.ets` |
| ② | 新增 `security/KdfParams.ets`（纯逻辑、不引 SDK ⇒ 可单测）作为**安全参数唯一真源** | `security/KdfParams.ets` |
| ③ | 新增 `test/kdfparams.test.ts`（6 条）**锁死** KDF 参数 | `test/kdfparams.test.ts` |
| ④ | 解锁页加 **busy 态**：点击后同一同步块内换文案 + 禁用按钮 | `pages/Unlock.ets` |
| ⑤ | 顺手修 `common/AppMeta.ets` 版本号漂移（1.0.5 → 1.0.6） | `common/AppMeta.ets` |

### 两个安全底线（本次没碰）

1. **PBKDF2 迭代次数 100000 一个没动**。
   这次动的是「**在哪个线程跑**」，不是「算多少次」。
   迭代次数是安全参数、不是性能旋钮 —— 要调低需安全侧签字 + 老库迁移方案。
2. **异步版与同步版共用同一套 spec** ⇒ **派生结果逐字节一致** ⇒ **老库完全不受影响**。
   核实依据：SDK `Kdf.generateSecret(spec): Promise<DataBlob>`（d.ts:6212）与
   `generateSecretSync(spec)` 共用同一个 `KdfSpec`；官方 PBKDF2 指南把三种调用形式并列列出。
   ⇒ 新增 `KdfParams.ets` + 单测，就是为了让「参数漂移 = 老用户再也打不开日记」这件事**不可能发生**。

### busy 态的具体行为

| 场景 | 按钮显示 | 可点 |
|------|---------|------|
| 初始 | 「用主密码解锁」 | ✅ |
| 点击后（正在派生密钥） | 「正在解锁…」 | ❌ 已禁用 |
| 首次建库 | 「正在建立保险库…」 | ❌ 已禁用 |
| 校验失败 | 恢复原文案 + 显示错误 | ✅ |

⚠️ 校验失败**不置 busy**（先报错，别先转菊花）；busy 守卫同时挡住了连点触发多次运算。

---

## 验证记录（2026-10-29）

### 纯逻辑单测 **232/232 全绿**

- 新增 `test/kdfparams.test.ts`（6 条）：KDF 参数守门。
- ⚠️ 顺带修：1.0.6 发版时改了 `app.json5` 漏改 `AppMeta.ets` ⇒ smoke 测试一直红着，
  本次对齐后转绿。

### 真 SDK 编译

- `assembleHap --mode module -p product=default -p buildMode=debug` → **BUILD SUCCESSFUL**
- `assembleApp -p product=release -p buildMode=release` → **BUILD SUCCESSFUL**（含混淆）

### 出包与验收（2026-10-29 22:55，已完成）

- [x] `pwsh scripts/build-release.ps1` → `RockJournal-release-signed.app`（**327,276 字节 / 320 KB**）
- [x] 出包三步验收全过：
  ① `hap-sign-tool verify-app` → `Digest verify result: true` + `verify-app success`
  ② 包内 Profile → `type=release` + `bundle-name=com.rocktier.rockjournal` + 无 `debug-info` / `development-certificate`
  ③ 包内 Profile 与 `keys/rockjournal-v1.p7b` **逐字节一致**（md5 `45C22B87…`），证书有效期至 2029-09-24
- [x] `pwsh scripts/verify-upload.ps1` → **全部 PASS / 退出码 0**
- [x] 包内 `pack.info`：`bundleName = com.rocktier.rockjournal`，`versionCode = 1000008`，`versionName = 1.0.7`
- [x] 桌面只留一个待传包（signed/unsigned 并排只在产物目录里，那是正常的；桌面不留 unsigned）
- [x] **上传前第 0 步（只能靠人）：确认 AGC 后台当前应用 = Rock私记**
      （`com.rocktier.rockjournal`）—— 包侧全绿也发现不了传错栏目（2026-10-27 的 993 真凶）

### 上架包指纹

| 项 | 值 |
|----|----|
| 文件 | `Rock私记-1.0.7-上架.app`（桌面） |
| 大小 | 327,276 字节（320 KB） |
| md5 | `AFDDB74C6A8718D437DA4B8CB26ED042` |
| sha256 | `E14FFD76F81A58A498C7B782018D1830A9C4A195E7CCCBC00787B2ACA1D85692` |
| 产物路径 | `F:\AI\HarmonyOS\RockJournal\build\outputs\release\RockJournal-release-signed.app` |
| 签名 | `rockreader-v2.p12`（与 Rock阅读 共用）+ `rockjournal-v1.p7b`（Rock私记 专属 Profile） |

---

## 已知限制（如实记录，不要在上架说明里夸大）

- ⚠️ **本次修复未在真机实测**（党哥手上无真机，本机 `hdc list targets` 为空）。
  编译与包侧验收全过，但「解锁实际耗时」的真机数值未经测量。
  ⇒ AGC 云测会重新跑一遍「点击操作完成快」，**以它的报告为准**。
  ⇒ **装新包后请回归四件事**：① 老库主密码解锁 ② 老库 legacy 兼容路径
  ③ 首次建库 ④ 生物解锁。**老库兼容是安全关键，不能只靠"参数一致"就放心。**
- 语音识别准确率仍未在真机验证（1.0.6 起延续的限制，模拟器没有离线识别引擎）。
- 语音只支持**中文普通话**（官方能力边界）。
- 语音只落文字，**不存音频**（与 Day One 存音频附件的定位刻意不同）。
- 备份是 `.rkdbak` 加密备份；TXT / Markdown 明文导出**不含图片**。
