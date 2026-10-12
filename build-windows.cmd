@echo off
rem ============================================================
rem  Fiber Twig Remake - build the Windows distribution
rem
rem  build-windows.cmd                full build + smoke test
rem  build-windows.cmd --no-smoke     export only (faster)
rem  build-windows.cmd --fetch-templates   download the export template if missing
rem
rem  Output: build\windows\FiberTwigRemake.exe
rem          build\FiberTwigRemake-Windows-x86_64.zip
rem ============================================================
setlocal EnableExtensions
cd /d "%~dp0"

set "PY=.venv\Scripts\python.exe"
if not exist "%PY%" set "PY=python"

"%PY%" tools\build_windows.py %*
exit /b %ERRORLEVEL%
