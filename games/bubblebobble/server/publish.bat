@echo off
:: Builds the C64 Game Server and the test bot as single self-contained executables
::   publish\win-x64\C64GameServer.exe, C64Bot.exe      (Windows)
::   publish\linux-arm64\C64GameServer, C64Bot          (Raspberry Pi, 64 bit OS)
cd /d "%~dp0"
dotnet test tests\C64GameServer.Tests || exit /b 1
for %%r in (win-x64 linux-arm64) do (
  dotnet publish src\C64GameServer -c Release -r %%r --self-contained -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o publish\%%r || exit /b 1
  dotnet publish src\C64Bot -c Release -r %%r --self-contained -p:PublishSingleFile=true -o publish\%%r || exit /b 1
)
echo.
echo Done: publish\win-x64 and publish\linux-arm64
