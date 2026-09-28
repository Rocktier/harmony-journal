# Rock私记 / RockJournal

纯离线加密日记本 · HarmonyOS（鸿蒙家族第二应用）。

- **包名**：`com.rocktier.rockjournal`
- **核心承诺**：零权限、零联网、AES-256-GCM 本地加密、数据不出设备
- **家族规范**：`f:\AI\HarmonyOS\MEMORY.md` + `.planning/findings.md`（快/小/离线三铁律）

## 构建与测试

```bash
# 纯逻辑单测（不依赖鸿蒙 SDK）
npm install && npm test

# CI：GitHub Actions（build.yml）—— 编译校验 + 单测，tag v* 触发发 Release
# 正式签名包：等 AGC 证书到位后由 default/release product 产出（见 build-profile.json5 注释）
```

## 图标

家族分层图标（纯黑底 + 白色主体 + 右上红点 `#FF4A3D`）由
`f:\AI\HarmonyOS\.planning\brand\family-logo.ps1` 生成：

```powershell
powershell -File f:\AI\HarmonyOS\.planning\brand\family-logo.ps1 -ProjectRoot 'f:\AI\HarmonyOS\RockJournal'
```

主体几何 = 日记便签（Journal 定制），红点位置全家族固定。
设计源稿（SVG）：`f:\AI\HarmonyOS\brand\rockjournal-foreground.svg`。
