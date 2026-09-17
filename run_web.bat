@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

rem ============================================================
rem  Pixel Bird - local web preview launcher
rem
rem  This is a thin wrapper. The real logic lives in
rem  tool\serve_web.py, because timestamp comparison and path
rem  handling are too fragile in batch.
rem
rem  NOTE: This file is intentionally pure ASCII.
rem  cmd.exe parses .bat files using the OEM codepage (GBK on
rem  zh-CN systems). UTF-8 Chinese text gets mis-decoded, and
rem  the resulting byte pairs can contain control characters
rem  like & or | which break the script. All user-facing
rem  Chinese messages are printed by the Python script instead.
rem
rem  Usage:
rem    run_web.bat              auto-detect whether to rebuild
rem    run_web.bat --rebuild    force a rebuild
rem    run_web.bat --fast       skip build, use existing output
rem    run_web.bat --port 9000  use a different port
rem    run_web.bat --no-open    do not open the browser
rem ============================================================

rem Bypass the corporate proxy: it blocks pub.dev and also
rem breaks flutter_tester's local WebSocket handshake.
set http_proxy=
set https_proxy=
set HTTP_PROXY=
set HTTPS_PROXY=
set PUB_CACHE=%USERPROFILE%\.pub-cache

rem ------------------------------------------------------------
rem  Locate Python
rem
rem  On this machine "python" is NOT on the Windows PATH - only
rem  the WorkBuddy-managed copy exists. So we cannot rely on a
rem  bare "python" command and must probe several sources.
rem ------------------------------------------------------------
set "PY="

where python >nul 2>&1
if not errorlevel 1 set "PY=python"

if not defined PY (
    where py >nul 2>&1
    if not errorlevel 1 set "PY=py"
)

if not defined PY (
    for /d %%d in ("%USERPROFILE%\.workbuddy-ai\binaries\python\versions\*") do (
        if exist "%%~fd\python.exe" set "PY=%%~fd\python.exe"
    )
)

if not defined PY (
    for /d %%d in ("%LOCALAPPDATA%\Programs\Python\*") do (
        if exist "%%~fd\python.exe" set "PY=%%~fd\python.exe"
    )
)

if not defined PY (
    echo.
    echo [ERROR] Python interpreter not found.
    echo.
    echo This launcher needs Python to host the local static
    echo file server. To fix it, either:
    echo   1. Install Python and tick "Add Python to PATH", or
    echo   2. Open this file in Notepad and point PY at the full
    echo      path of python.exe
    echo.
    pause
    exit /b 1
)

echo Using Python: %PY%
echo.

rem Use a relative path here (we already cd'd to this script's
rem directory). Passing the absolute path would send the non-ASCII
rem characters of the project folder name through cmd's argument
rem encoding, which is an avoidable risk.
"%PY%" "tool\serve_web.py" %*

rem Capture the exit code before pausing, then pause on error so a
rem double-clicked window does not vanish.
set "RC=%errorlevel%"
if not "%RC%"=="0" pause
exit /b %RC%
