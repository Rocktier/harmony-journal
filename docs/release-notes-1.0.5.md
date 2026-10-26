# Rock私记 1.0.5 更新说明（华为应用市场后台上传用）

> 版本：1.0.5（versionCode **1000006**）
> 状态：**已通过模拟器实测验证（2026-10-26 22:00–22:10），可提交 AGC**
> 对应代码区间：`1.0.4 上架 commit .. HEAD`
> 上架包：`Rock私记-1.0.5-上架.app`（264 KB，release 正式签名 rockjournal-v1.p7b）

---

## 更新说明正文（直接粘贴这段）

```
【修复】跟随系统深色模式即时生效
外观选「跟随系统」后，把系统切到深色模式，本应用会立刻跟着变深色，
不用再先切到别的模式、切回来才生效。

【隐私】权限不变，仍为零
本应用不申请任何权限，所有数据只留在这台设备上，不联网、不上传、无账号。
```

正文 2 条。这一版的用户可见变更只有深色模式这一处（其余是内部修复，不写）。

---

## 为什么这次坚持先验证再提交（重要）

**1.0.4 的说明里已经写过「【修复】跟随系统深浅生效」** —— 当时宣称修了，实际没修好，
所以复评又提了一遍。这条反馈的原文是：

> 测试步骤：1.首页-设置-外观：选择跟随系统，打开系统深色模式后，
> 需切换其他模式重新选择跟随系统才可变为深色
> 测试环境：WIFI联网、HarmonyOS 6.1(Mate 70)、API6.1.0(23)、中文环境

也就是说：**上一轮"修好了"是没有验证过的宣称**。这次如果不做真机/模拟器验证就再写一条
同款文案，等于第二次虚假宣传 —— 审核员第三次提同样问题时，代价远大于第一次。

**所以这一版的文案是先验证、后定稿**（实测结果见下节）。

---

## 验证清单（模拟器实测结果 · 2026-10-26）

**这次是真的逐条跑过的**（上一轮 1.0.4 的同款文案没验证就写，这次不重复那个错）。

| # | 场景 | 期望 | 实测 |
|---|---|---|---|
| 1 | 跟随系统 + 系统深色 | 应用深色 | ✅ 背景 #000000，文字 #FFFFFF |
| 2 | 跟随系统下切系统深色 | **应用立即变深，不用切别的模式** | ✅ 回应用已是深色 |
| 3 | 跟随系统下切系统浅色 | 应用变浅 | ✅ 背景 #FAF8F3 |
| 4 | 固定「深色」+ 系统切浅 | **不被系统覆盖** | ✅ 仍深色 |
| 5 | 固定「浅色」+ 系统切深 | **不被系统覆盖** | ✅ 仍浅色 |
| 6 | 切回「跟随系统」 | 立即跟随系统当前深浅 | ✅ 切回即变色 |

补充证据（系统日志，`RockJournal` tag）：

```
22:07:19.141  appearance follows system, colorMode=0 dark=yes   ← onConfigurationUpdate 回调
22:07:19.159  onForeground
```

即：**系统主题变化是由 `onConfigurationUpdate` 收到的（用回调参数 `newConfig.colorMode`，
不是读可能还是旧值的 `ctx.config.colorMode`）**，色板在应用回前台前就已换好，
回前台看到的就是新配色 —— 审核员复现路径（跟随系统 → 开系统深色 → 回应用）已覆盖并通过。

---

## 技术备注（留存，不上传）

### 三条根因（这次是真的挖到底了）

1. **`onConfigurationUpdate` 读错了值**：回调里读 `ctx.config.colorMode`，
   而它在回调触发那一刻可能还是**旧值** ⇒ 算出来等于「系统没变」。
   改用回调参数 `newConfig.colorMode`（官方用法）。
2. **app 被 `setColorMode(DARK/LIGHT)` 钉死**：一旦钉死，系统主题变化就
   **不再回调** `onConfigurationUpdate` ⇒ "跟随系统"永远跟不上。
   改为 app 层面**一律 NOT_SET（跟随系统）**，深/浅偏好只落在 palette 上。
   （本应用 UI 100% 走 palette，`$r('app.color.*')` 引用数 = 0，资源限定符不参与视觉，
   两套机制不冲突。）
3. **兜底**：`onForeground` 对一次账，覆盖「应用在后台时系统切深色」。

附带收益：运行时切色不再有任何 `setColorMode` 调用 ⇒ 2026-10-16 那个
「切色后页面栈保不住、直接退回桌面」的风险一并消失（现在只在启动时调一次）。

### 顺手修的 CI 红灯

`notemeta.test.ts` 的「文件名里绝不能出现 UTC 日期键」断言**漏了时区守卫**：
CI 跑在 UTC（ubuntu）时 localKey 与 utcKey 本来就是同一天，断言必挂。
改为仅在二者确实跨天时才断言。（Journal 本地是 UTC+8，所以本地 139/139 全绿也盖不住。）

### 其他

- 单测 139/139（新增 3 条守门：`isSystemDarkColorMode` / `paletteNeedsRefresh`）；
- ArkTS debug + release 编译 BUILD SUCCESSFUL；
- release 签名：rockreader-v2.p12 + **rockjournal-v1.p7b**（DevEco 加密口令，同机可复制）；
- 包内版本核对：`pack.info → summary.app.version = {code: 1000006, name: 1.0.5}`；
- **出包三步验收全过**（2026-10-26）：
  ① `verify-app -inFile RockJournal-release-signed.app -inForm zip` → *Verify success*；
  ② 抠出包内 Profile → `type=release` + `bundle-name=com.rocktier.rockjournal` + 无 `debug-info`；
  ③ 包内 Profile 与本地 `keys/rockjournal-v1.p7b` **SHA256 一致**（ab74152d…）。
- **模拟器实测通过**（2026-10-26 22:00–22:10，DevEco 模拟器，Pura/Mate 系 API 20+）：
  6 项场景全过（见上表），日志实证 `appearance follows system, colorMode=0 dark=yes`。

### 模拟器实测踩的坑（留给下一次）

- **安全键盘会把截图拍成全黑**：解锁页是密码输入框（安全键盘 / secure 窗口），
  键盘弹出期间 `uitest screenCap` 拍到的 Journal 区域是**纯黑**，而 `dumpLayout`
  仍能读到完整 UI 树 ⇒ 极易误判成"深色模式下应用渲染成黑屏"。
  判据：**关掉键盘（Back）再截图**，画面立刻正常。真配色没问题。
- **模拟器会自动息屏**（约 30s），息屏后截图同样是一片黑（特征：整屏纯黑、无状态栏）。
  解法：`hdc shell "power-shell wakeup"` 点亮；`power-shell timeout -o <ms>` 可覆盖息屏时间。
- **系统设置应用**：桌面第 2 页有「设置」图标；也可用
  `aa start -a com.huawei.hmos.settings.MainAbility -b com.huawei.hmos.settings` 直接拉起，
  且**会保留上次所在页面**（停在「显示和亮度」）。深浅色切换在
  「显示和亮度 → 显示模式 → 浅色/深色」两个 Radio 上（不是「深色模式」那一行定时规则）。
- **不要信 dumpLayout 的过期树**：一律以截图为准；配色深浅用纯 Python PNG 解码
  （zlib + 手动 unfilter）取背景主色判定：主色 ≈ #FAF8F3 = 浅色，≈ #000000 = 深色。

