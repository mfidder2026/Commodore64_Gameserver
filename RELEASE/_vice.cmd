@echo off
:: Starts VICE (x64sc) with the right network set-up and one of the games.
:: Used by vice-wic64.bat and vice-rrnet.bat:  _vice.cmd <wic64|rrnet> [game]
setlocal EnableDelayedExpansion
set "MODE=%~1"
set "GAME=%~2"
set "HERE=%~dp0"

:: ---- find VICE: VICE_DIR, vice-path.txt, the usual folders, the PATH, or ask once
set "X64="
if defined VICE_DIR if exist "%VICE_DIR%\x64sc.exe" set "X64=%VICE_DIR%\x64sc.exe"
if not defined X64 if exist "%HERE%vice-path.txt" (
  set /p VPATH=<"%HERE%vice-path.txt"
  if exist "!VPATH!\x64sc.exe" set "X64=!VPATH!\x64sc.exe"
)
if not defined X64 for %%d in ("%ProgramFiles%\VICE\bin" "%ProgramFiles%\GTK3VICE\bin" "C:\VICE\bin" "%USERPROFILE%\VICE\bin") do (
  if not defined X64 if exist "%%~d\x64sc.exe" set "X64=%%~d\x64sc.exe"
)
if not defined X64 for /f "delims=" %%p in ('where x64sc.exe 2^>nul') do if not defined X64 set "X64=%%p"
if not defined X64 (
  echo VICE ^(x64sc.exe^) was not found. Get VICE 3.9 or newer from https://vice-emu.sourceforge.io/
  set /p "VPATH=Folder that contains x64sc.exe (for example C:\VICE\bin): "
  if not exist "!VPATH!\x64sc.exe" (
    echo x64sc.exe is not in "!VPATH!".
    pause
    exit /b 1
  )
  >"%HERE%vice-path.txt" echo !VPATH!
  set "X64=!VPATH!\x64sc.exe"
)

:: ---- which game
if not defined GAME (
  echo.
  echo   1  Wizard of Wor OME
  echo   2  Bubble Bobble OME
  echo   3  The Way of the Exploding Fist OME
  echo.
  choice /c 123 /n /m "Which game? "
  set "GAME=wizardofwor"
  if errorlevel 2 set "GAME=bubblebobble"
  if errorlevel 3 set "GAME=explodingfist"
)
if not exist "%HERE%games\%GAME%.d64" (
  echo Unknown game "%GAME%": there is no games\%GAME%.d64
  pause
  exit /b 1
)

:: ---- your own copy of the disk: it keeps your name and the server's address
if not exist "%HERE%my-disks" mkdir "%HERE%my-disks"
if not exist "%HERE%my-disks\%GAME%.d64" copy "%HERE%games\%GAME%.d64" "%HERE%my-disks\%GAME%.d64" >nul

:: ---- the network
if /i "%MODE%"=="wic64" (
  set "NET=-userportdevice 23 +ethernetcart"
) else (
  set "NET=-userportdevice 0 -ethernetcart -ethernetcartmode 1"
  if exist "%HERE%rrnet-interface.txt" (
    set /p IFACE=<"%HERE%rrnet-interface.txt"
    set "NET=!NET! -ethernetioif "!IFACE!""
  ) else (
    echo RR-Net uses the network adapter set in VICE ^(Settings, Cartridge, Ethernet^).
    echo To choose one here, put its name in rrnet-interface.txt; "start-server.bat --list-interfaces" lists them.
  )
)

echo Starting %GAME% in VICE with %MODE% ...
start "" "%X64%" -pal !NET! +drive8truedrive -virtualdev8 -autostart "%HERE%my-disks\%GAME%.d64"
endlocal
