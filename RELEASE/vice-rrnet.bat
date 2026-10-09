@echo off
:: VICE with an RR-Net cartridge (needs Npcap: https://npcap.com/).
:: Bubble Bobble finds a server on the same network by itself (raw Ethernet, also on this PC).
:: Wizard of Wor uses UDP: the server must run on another PC (see README.md).
::   vice-rrnet.bat                 asks which game
::   vice-rrnet.bat bubblebobble    or wizardofwor, explodingfist
call "%~dp0_vice.cmd" rrnet %1
