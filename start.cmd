@echo off
rem ============================================================
rem  Fiber Twig Remake - Windows launcher
rem
rem  Usage:
rem    start.cmd                        run the game (windowed)
rem    start.cmd --headless -- ARGS     pass arguments straight to Godot
rem    start.cmd edit                   open the project in the editor
rem    start.cmd level N                run level N (0..17)
rem    start.cmd screen NAME            start on a screen, e.g. WTitle,
rem                                     WLoad, WGame, WOptions, WHelp ...
rem    start.cmd test                   quick headless self-checks
rem                                     (wintest / testsound / autotest=0 /
rem                                      closetest / piecetest / filltest=0)
rem    start.cmd test all               autotest levels 0..17
rem
rem  Any other arguments are forwarded to Godot, e.g.:
rem    start.cmd --headless --path remake -- --autotest=6
rem    start.cmd --headless --path remake -- --beltspeed=25 --screen=WGame
rem ============================================================
setlocal EnableExtensions
cd /d "%~dp0"

set "GODOT_EXE=tools\Godot_v4.7.2-stable_win64.exe"
set "GODOT_CONSOLE=tools\Godot_v4.7.2-stable_win64_console.exe"
set "GODOT=%GODOT_EXE%"
if not exist "%GODOT%" set "GODOT=%GODOT_CONSOLE%"
if not exist "%GODOT%" (
    where godot >nul 2>nul
    if not errorlevel 1 set "GODOT=godot"
)
if not exist "%GODOT%" if /i not "%GODOT%"=="godot" (
    echo [start] Godot not found in tools\ and not on PATH.
    echo [start] Download Godot 4.7.2 Windows build:
    echo [start]   https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip
    exit /b 1
)

if "%~1"=="" goto :run
if /i "%~1"=="edit"   goto :edit
if /i "%~1"=="level"  goto :level
if /i "%~1"=="screen" goto :screen
if /i "%~1"=="test"   goto :test

rem --- pass-through: prefer the console build so output stays visible ---
echo %* | findstr /i /c:"--headless" >nul
if not errorlevel 1 if exist "%GODOT_CONSOLE%" set "GODOT=%GODOT_CONSOLE%"
goto :run

:run
echo [start] %GODOT% --path remake %*
"%GODOT%" --path remake %*
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" echo [start] Godot exited with code %RC%.
exit /b %RC%

:edit
echo [start] opening the project in the editor ...
"%GODOT%" --editor --path remake
exit /b %ERRORLEVEL%

:level
if "%~2"=="" (
    echo usage: start.cmd level N        ^(N = 0..17^)
    exit /b 2
)
echo [start] running level %~2 ...
"%GODOT%" --path remake -- --level=%~2
exit /b %ERRORLEVEL%

:screen
if "%~2"=="" (
    echo usage: start.cmd screen NAME    ^(e.g. WTitle, WLoad, WOptions^)
    exit /b 2
)
echo [start] running --screen=%~2 ...
"%GODOT%" --path remake -- --screen=%~2
exit /b %ERRORLEVEL%

:test
if not exist "%GODOT_CONSOLE%" set "GODOT_CONSOLE=%GODOT%"
if /i "%~2"=="all" goto :test_all

echo [test] --wintest
"%GODOT_CONSOLE%" --headless --path remake -- --wintest 2>&1 | findstr /i /c:"[wintest]" /c:"SCRIPT ERROR"
echo [test] --testsound
"%GODOT_CONSOLE%" --headless --path remake -- --testsound 2>&1 | findstr /i /c:"ERROR" /c:"[sound]" | findstr /v /c:"-> ok"
echo [test] --langtest
"%GODOT_CONSOLE%" --headless --path remake -- --langtest 2>&1 | findstr /i /c:"[langtest]" /c:"SCRIPT ERROR"
echo [test] --autotest=0
"%GODOT_CONSOLE%" --headless --path remake -- --autotest=0 2>&1 | findstr /i /c:"[autotest]" /c:"SCRIPT ERROR"
echo [test] --closetest
"%GODOT_CONSOLE%" --headless --path remake -- --closetest 2>&1 | findstr /i /c:"[closetest]" /c:"SCRIPT ERROR"
echo [test] --piecetest
"%GODOT_CONSOLE%" --headless --path remake -- --piecetest 2>&1 | findstr /i /c:"[piecetest]" /c:"SCRIPT ERROR"
echo [test] --filltest=0
"%GODOT_CONSOLE%" --headless --path remake -- --filltest=0 2>&1 | findstr /i /c:"[filltest]" /c:"SCRIPT ERROR"
echo [test] done.
exit /b 0

:test_all
echo [test] autotest levels 0..17 ...
set "FAIL=0"
for /l %%i in (0,1,17) do (
    "%GODOT_CONSOLE%" --headless --path remake -- --autotest=%%i > "%TEMP%\ft_autotest_%%i.log" 2>&1
    findstr /c:"SCRIPT ERROR" "%TEMP%\ft_autotest_%%i.log" >nul && (
        set "FAIL=1"
        echo [test] level %%i: SCRIPT ERROR
    )
    findstr /c:"[autotest]" "%TEMP%\ft_autotest_%%i.log"
)
if "%FAIL%"=="1" (
    echo [test] FAILED - see "%TEMP%\ft_autotest_*.log"
    exit /b 1
)
echo [test] all 18 levels clean.
exit /b 0
