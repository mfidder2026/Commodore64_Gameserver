/*
 * The Way of the Exploding Fist OME - settings for the framework's standard
 * lobby (framework/c64/lobby, see framework/c64/lobby/README.md)
 *
 * Strings are compiled by cc65 for the C64's lower/upper case character set:
 * write them in normal mixed case.
 */
#ifndef GAME_H
#define GAME_H

/* the game on the server (server.json "games": id 4, module "lockstep") */
#define GAME_ID       4
#define GAME_VERSION  1

/* title lines of the lobby screens (max. 40 characters) */
#define GAME_TITLE    "  THE WAY OF THE EXPLODING FIST * ONLINE"
#define GAME_TAGLINE  "       two C64s, four bouts, one winner"

/* settings file on the disk */
#define CFG_FILE      "fist.cfg"

/* game file to load per network type (the lobby itself is "fist") */
#define FILE_UCI      "fistu"   /* C64 Ultimate / Ultimate 64 */
#define FILE_WIC      "fistw"   /* WiC64 */
#define FILE_RR       "fistr"   /* RR-Net (VICE) */

/* the game runs on PAL and NTSC alike (tools/dettest.py) */
#define GAME_PAL_ONLY 0

/* menu key L: the original game (one or two players on this C64) */
#define LOCAL_GAME_TEXT "original game, 1-2 players"

/* what the players are called in the game: slot 0 invited, slot 1 accepted */
#define SLOT0_NAME    "WHITE (left)"
#define SLOT1_NAME    "RED (right)"

#endif
