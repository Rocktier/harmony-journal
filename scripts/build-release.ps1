# 打上架用的 .app 包（AGC 提审格式，含发布签名）
#
# 用法：pwsh scripts/build-release.ps1
# 产物：build/outputs/release/RockJournal-release-signed.app
#
# ⚠️ 前置条件（证书到位后才能跑，否则 signingConfigs 没有 release 项会报签名错）：
#   1. AGC 发布证书（.p12/.cer/.p7b）到手，材料放 f:\AI\HarmonyOS\keys\rockjournal-v1\（不进 git）
#   2. DevEco「文件 > 项目结构 > 签名配置」里配好 release 签名（口令是 DevEco 加密串，
#      明文直填 hvigor 不接受 —— 00303116/00303117，见 RockReader findings §6.9）
#   3. build-profile.json5 放开注释占位的 release product（products 里）+
#      signingConfigs.release（照 RockReader 的 keys/rockreader-v2 结构），
#      并把 modules[].targets[0].applyToProducts 加上 "release"
#
# 日常调试仍走 default product + DevEco 自动签名，本脚本不动它。

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$ide = "E:\Program Files\Huawei\DevEco Studio"

$env:DEVECO_SDK_HOME = "$ide\sdk"
$env:JAVA_HOME = "$ide\jbr"
$env:PATH = "$ide\tools\node;$ide\tools\ohpm\bin;$ide\jbr\bin;$env:PATH"

Push-Location $root
node "$ide\tools\hvigor\bin\hvigorw.js" assembleApp --mode project -p product=release -p buildMode=release --no-daemon
Pop-Location

$app = Get-ChildItem (Join-Path $root "build\outputs\release") -Filter *signed.app |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $app) { throw "构建结束但未找到 signed .app 产物 —— 视为失败" }
"==> 产物：$($app.FullName)（$([math]::Round($app.Length/1KB)) KB）"
"==> SHA256：$((Get-FileHash $app.FullName -Algorithm SHA256).Hash)"
