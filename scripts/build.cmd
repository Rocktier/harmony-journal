@echo off
REM RockJournal 本机构建入口（装机测试范畴，照 RockReader 的 scripts/build.cmd）
REM 用法：cmd //c scripts/build.cmd assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
setlocal
set "PATH=E:\Program Files\Huawei\DevEco Studio\jbr\bin;E:\Program Files\Huawei\DevEco Studio\tools\node;%PATH%"
set "DEVECO_SDK_HOME=E:\Program Files\Huawei\DevEco Studio\sdk"
set "JAVA_HOME=E:\Program Files\Huawei\DevEco Studio\jbr"
node "E:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js" %*
exit /b %ERRORLEVEL%
