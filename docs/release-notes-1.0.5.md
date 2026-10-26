# Rock私记 1.0.5 更新说明（华为应用市场后台上传用）

> 版本：1.0.5（versionCode **1000006**）
> 状态：**已通过模拟器实测验证（2026-10-26 22:00–23:10），可提交 AGC**
> 本版含两项：**桌面服务卡片（新增）+ 跟随系统深色模式（修复）**
> 对应代码区间：`1.0.4 上架 commit .. HEAD`
> 上架包：`Rock私记-1.0.5-上架.app`（278 KB，release 正式签名 rockjournal-v1.p7b）

---

## 更新说明正文（直接粘贴这段）

```
【新增】桌面卡片：看一眼今天几号，点一下直接写今天
把「写今天」卡片添加到桌面，随时看到今天的日期；
点卡片直接开始写今天的日记，不用先翻列表。
卡片不显示任何日记内容 —— 日记全部加密，卡片也读不到。

【修复】跟随系统深色模式即时生效
外观选「跟随系统」后，把系统切到深色模式，本应用会立刻跟着变深色，
不用再先切到别的模式、切回来才生效。

【隐私】权限不变，仍为零
本应用不申请任何权限，所有数据只留在这台设备上，不联网、不上传、无账号。
```

正文 3 条。用户可见变更有两处：桌面卡片（新增）+ 深色模式（修复）。

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

### 桌面服务卡片（新增功能，党哥 2026-10-26 拍板「零泄漏」档）

**为什么卡片里一个字日记内容都没有**（这是设计决定，不是没做完）：
日记正文与索引**整份加密**（`notes/<id>.rkd` + `index.rkd`，AES-256-GCM），
主密钥只存在应用主进程内存里；而服务卡片跑在 `FormExtensionAbility` 里，
与主进程**不共享内存** ⇒ 它**结构上就拿不到密钥、读不出任何一条日记**。
党哥明确选了零泄漏档：**不写任何明文快照**，磁盘上的数据依旧 100% 加密，
隐私承诺一个字不改。所以卡片只有：今天几号 + 一个「写今天」按钮。

**交互链路**（模拟器实拍全部通过）：

```
点卡片 → postCardAction('router') 带 intent=writeToday
   ├─ 应用已在运行 → onNewWant → AppStorage('pendingIntent') → Index @Watch 消费
   │                  → 直接 pushUrl('pages/Editor')，标题就是今天
   └─ 应用未运行/锁屏 → onCreate → 存意图 → 停在解锁页
                        → 用户解锁 → replaceUrl(Index) → onPageShow 消费
                        → 自动续跳编辑器
```

**三个 form 页面特有的坑**（RockReader 那边也会遇到，见 Reader 台账）：

1. **卡片自定义参数会被系统改键名**：卡片里写 `params: { intent: 'writeToday' }`，
   系统拉起 ability 时传的是 `{"a9":"writeToday", "params":"{\"a9\":\"writeToday\"}"}`
   —— **键被重命名成 a0/a1/…（按位置排）**。
   ⇒ 只认 `params['intent']` 必然读不到（症状：点了卡片应用起来了，但什么也没发生）。
   ⇒ 正确姿势：**按"值"找，不按"键"找**（意图值是唯一语义标记）。
2. **form 页面禁用 @StorageLink / hilog / onAreaChange**：ArkTS 编译直接报
   `11706006 can't support form application`。
   ⇒ 只能用 @LocalStorageProp，而它读到的 dimension 在 2×4 实例上是**默认值**
   ⇒ 想按尺寸分支出两套排版**在 form 页面里做不到**
   ⇒ 定稿：**统一布局通吃 2×2 / 2×4**（四行内容，2×2 也放得下）。
3. 卡片页**不能打日志**，调试只能打在 `FormExtensionAbility` 里（那里可以）。

**验证结果（模拟器实拍）**：桌面添加 2×2 / 2×4 各一张 → 渲染正确（深浅色跟随系统）；
点 2×2 → 直达编辑器（标题 2026-10-26）；点 2×4 → 解锁页 → 解锁 → 自动续跳编辑器。

### 顺手修的 CI 红灯

`notemeta.test.ts` 的「文件名里绝不能出现 UTC 日期键」断言**漏了时区守卫**：
CI 跑在 UTC（ubuntu）时 localKey 与 utcKey 本来就是同一天，断言必挂。
改为仅在二者确实跨天时才断言。（Journal 本地是 UTC+8，所以本地 139/139 全绿也盖不住。）

### 其他

- 单测 148/148（新增 9 条卡片守门：本地时区日期/星期映射/零泄漏字段白名单）；
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

