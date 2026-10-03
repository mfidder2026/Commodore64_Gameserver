@echo off
:: Wizard of Wor LAN - build script
:: build.bat          build cartridge (regression check), PRG and D64
:: build.bat run      build and start the PRG in VICE
:: build.bat shot     build and save a VICE screenshot in build\shot.png
python "%~dp0tools\build.py" %*
