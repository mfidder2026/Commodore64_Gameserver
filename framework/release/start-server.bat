@echo off
:: Starts the C64 Game Server (Windows). Settings: server\win-x64\server.json (written at the first start).
::   start-server.bat                     run the server, dashboard at http://localhost:8080/
::   start-server.bat --list-interfaces   list the network adapters (for RR-Net)
cd /d "%~dp0server\win-x64"
C64GameServer.exe %*
pause
