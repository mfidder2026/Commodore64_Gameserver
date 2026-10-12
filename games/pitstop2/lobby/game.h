/*
 * Pitstop II OME - settings for the framework's standard lobby
 * (framework/c64/lobby, see framework/c64/lobby/README.md)
 *
 * Strings are compiled by cc65 for the C64's lower/upper case character set:
 * write them in normal mixed case.
 */
#ifndef GAME_H
#define GAME_H

/* the game on the server (server.json "games": id 5, module "lockstep") */
#define GAME_ID       5
#define GAME_VERSION  1

/* title lines of the lobby screens (max. 40 characters) */
#define GAME_TITLE    "        PITSTOP II  *  ONLINE"
#define GAME_TAGLINE  "    two C64s, two cars, three laps"

/* settings file on the disk */
#define CFG_FILE      "pitstop.cfg"

/* game file to load per network type (the lobby itself is "pitstop") */
#define FILE_UCI      "pitu"    /* C64 Ultimate / Ultimate 64 */
#define FILE_WIC      "pitw"    /* WiC64 */
#define FILE_RR       "pitr"    /* RR-Net (VICE) */

/* the game runs on PAL and NTSC alike (tools/dettest.py) */
#define GAME_PAL_ONLY 0

/* menu key L: the original game (one or two players on this C64) */
#define LOCAL_GAME_TEXT "original game, 1-2 players"
#define LOCAL_GAME_FILE "pitl"

/* what the players are called in the game: slot 0 invited, slot 1 accepted */
#define SLOT0_NAME    "driver 1 (top)"
#define SLOT1_NAME    "driver 2 (bottom)"

#endif
