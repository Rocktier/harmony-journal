# 打上架用的 .app 包（AGC 提审格式，含发布签名）
#
# 用法：pwsh scripts/build-release.ps1
# 产物：build/outputs/release/RockJournal-release-signed.app
#
# 签名材料（2026-10-20 到位，本机 F:\AI\HarmonyOS\keys\，不进 git）：
#   1. rockreader-v2.p12 / rockreader-v2.cer —— 复用 RockReader 的 AGC 发布证书
#      （华为个人开发者账号全账号仅 1 张发布证书，多应用共用是官方常规做法）
#   2. rockjournal-v1.p7b —— Rock私记专属发布 Profile（绑定 com.rocktier.rockjournal，
#      2026-10-20 从 AGC 下载，原名「Rock私记发布Release.p7b」）
#   3. 口令字段必须是 DevEco 加密串（00000031 开头），明文直填 hvigor 不收
#      —— 00303116/00303117，见 RockReader findings §6.9
#
# 日常调试仍走 default product + DevEco 自动签名，本脚本不动它。
#
# ⚠️ 本文件必须以 UTF-8 带 BOM 保存：Windows PowerShell 5.1 按 ANSI 读无 BOM 的
#    UTF-8 文件会把中文注释读成乱码并报「表达式或语句中包含意外的标记 }」（实测）。

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$ide = "E:\Program Files\Huawei\DevEco Studio"

$env:DEVECO_SDK_HOME = "$ide\sdk"
$env:JAVA_HOME = "$ide\jbr"
$env:PATH = "$ide\tools\node;$ide\tools\ohpm\bin;$ide\jbr\bin;$env:PATH"

Push-Location $root
# hvigor 的 ArkTS 警告走 stderr；$ErrorActionPreference="Stop" 会把 native 命令的
# stderr 输出当终止错误（NativeCommandError）误杀整场构建（2026-10-21 实测）。
# 这里临时降档到 Continue：警告照常打印，只信退出码。
$ErrorActionPreference = "Continue"
node "$ide\tools\hvigor\bin\hvigorw.js" assembleApp --mode project -p product=release -p buildMode=release --no-daemon
$exitCode = $LASTEXITCODE
Pop-Location
if ($exitCode -ne 0) { throw "hvigor assembleApp 失败，退出码 $exitCode" }
$ErrorActionPreference = "Stop"

$app = Get-ChildItem (Join-Path $root "build\outputs\release") -Filter *.app |
    Where-Object { $_.Name -like "*signed*" } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $app) { throw "构建结束但未找到 signed .app 产物 —— 视为失败" }
"==> 产物：$($app.FullName)（$([math]::Round($app.Length/1KB)) KB）"
"==> SHA256：$((Get-FileHash $app.FullName -Algorithm SHA256).Hash)"
