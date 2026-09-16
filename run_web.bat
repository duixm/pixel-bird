@echo off
chcp 65001 >nul
setlocal

rem ============================================================
rem  像素小鸟 - 一键在浏览器中运行
rem
rem  为什么需要这个脚本：
rem  1. Flutter 的 web 构建会强制编译内置 shader (ink_sparkle.frag)，
rem     但当前环境的 impellerc 没有正确接收 shader_lib include 路径，
rem     导致 release 构建必然失败。脚本会手动补编译这个文件。
rem  2. dev-server 模式需要调用 reg.exe，可能被安全策略拦截，
rem     因此改用 Python 静态服务器托管构建产物。
rem ============================================================

cd /d "%~dp0"

set FLUTTER=%USERPROFILE%\flutter\bin\flutter.bat
set IMPELLERC=%USERPROFILE%\flutter\bin\cache\artifacts\engine\windows-x64\impellerc.exe
set SHADER_LIB=%USERPROFILE%\flutter\bin\cache\artifacts\engine\windows-x64\shader_lib
set SHADER_SRC=%USERPROFILE%\flutter\packages\flutter\lib\src\material\shaders\ink_sparkle.frag
set EDGE=C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe
set PORT=8090

rem 绕过公司代理，否则 pub 和测试进程通信都会失败
set http_proxy=
set https_proxy=
set HTTP_PROXY=
set HTTPS_PROXY=
set PUB_CACHE=%USERPROFILE%\.pub-cache

echo.
echo [1/5] 拉取依赖...
call "%FLUTTER%" pub get
if errorlevel 1 goto :fail

echo.
echo [2/5] 构建 Web 产物（debug 模式，约 1-2 分钟）...
call "%FLUTTER%" build web --debug
if errorlevel 1 goto :shader_fallback

:shader_fallback
echo.
echo [3/5] 补编译内置 shader...
if not exist "build\web\assets\shaders" mkdir "build\web\assets\shaders"

rem 需要把 runtime_effect.glsl 放到 impellerc 能找到的 include 路径下
if not exist "build\shader_lib\flutter" mkdir "build\shader_lib\flutter"
copy /y "%SHADER_LIB%\flutter\runtime_effect.glsl" "build\shader_lib\flutter\" >nul 2>&1

pushd build
"%IMPELLERC%" --sksl ^
  --input="%SHADER_SRC%" ^
  --input-type=frag ^
  --sl="web\assets\shaders\ink_sparkle.frag" ^
  --spirv="shader_lib\ink_sparkle.spirv" ^
  --include="shader_lib"
popd

if not exist "build\web\assets\shaders\ink_sparkle.frag" (
  echo     [警告] shader 补编译未成功。游戏主体功能不受影响，
  echo            仅 Material 水波纹特效会缺失。
) else (
  echo     shader 已就绪。
)

echo.
echo [4/5] 启动本地服务器 (http://127.0.0.1:%PORT%) ...
start "pixel-bird-server" /min cmd /c "cd /d "%~dp0build\web" && python -m http.server %PORT% --bind 127.0.0.1"

echo.
echo [5/5] 在 Edge 中打开游戏...
timeout /t 2 /nobreak >nul
start "" "%EDGE%" --new-window "http://127.0.0.1:%PORT%/"

echo.
echo ============================================================
echo   游戏已在 Edge 中打开。
echo.
echo   操作提示：
echo     - 按 F12，再按 Ctrl+Shift+M 切换到手机模拟视图
echo     - 选一个竖屏机型（如 iPhone 12 Pro）体验真实手感
echo     - 点击画面开始游戏
echo.
echo   关闭游戏：关掉那个最小化的 pixel-bird-server 窗口即可
echo ============================================================
echo.
pause
exit /b 0

:fail
echo.
echo [失败] 依赖拉取或构建出错，请查看上方输出。
pause
exit /b 1
