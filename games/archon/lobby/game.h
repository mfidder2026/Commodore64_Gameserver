/*
 * Archon OME - settings for the framework's standard lobby
 * (framework/c64/lobby, see framework/c64/lobby/README.md)
 *
 * Strings are compiled by cc65 for the C64's lower/upper case character set:
 * write them in normal mixed case.
 */
#ifndef GAME_H
#define GAME_H

/* the game on the server (server.json "games": id 7, module "lockstep") */
#define GAME_ID       7
#define GAME_VERSION  1

/* title lines of the lobby screens (max. 40 characters) */
#define GAME_TITLE    "          ARCHON  *  ONLINE"
#define GAME_TAGLINE  "     the light and the dark, one C64 each"

/* settings file on the disk */
#define CFG_FILE      "archon.cfg"

/* game file to load per network type (the lobby itself is "archon") */
#define FILE_UCI      "archu"   /* C64 Ultimate / Ultimate 64 */
#define FILE_WIC      "archw"   /* WiC64 */
#define FILE_RR       "archr"   /* RR-Net (VICE) */

/* the game runs on PAL and NTSC alike (tools/dettest.py) */
#define GAME_PAL_ONLY 0

/* menu key L: the original game (two players, or one against the computer) */
#define LOCAL_GAME_TEXT "original game, 1-2 players"
#define LOCAL_GAME_FILE "archl"

/* what the players are called in the game: slot 0 invited, slot 1 accepted */
#define SLOT0_NAME    "the light side"
#define SLOT1_NAME    "the dark side"

#endif
