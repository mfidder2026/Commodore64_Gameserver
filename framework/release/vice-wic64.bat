@echo off
:: VICE with the WiC64 emulation (the simplest set-up; works with a server on this PC too).
::   vice-wic64.bat                 asks which game
::   vice-wic64.bat bubblebobble    or wizardofwor
call "%~dp0_vice.cmd" wic64 %1
