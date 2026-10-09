/*
 * Bubble Bobble OME - settings for the framework's standard lobby
 * (framework/c64/lobby, see framework/c64/lobby/README.md)
 *
 * Strings are compiled by cc65 for the C64's lower/upper case character set:
 * write them in normal mixed case.
 */
#ifndef GAME_H
#define GAME_H

/* the game on the server (server.json "games": id 3, module "bubblebobble") */
#define GAME_ID       3
#define GAME_VERSION  1

/* title lines of the lobby screens (max. 40 characters) */
#define GAME_TITLE    "     BUBBLE BOBBLE  *  ONLINE"
#define GAME_TAGLINE  "     two C64s, one game, one network"

/* settings file on the disk */
#define CFG_FILE      "bblan.cfg"

/* game file to load per network type (the lobby itself is "bblan") */
#define FILE_UCI      "bbu"   /* C64 Ultimate / Ultimate 64 */
#define FILE_WIC      "bbw"   /* WiC64 */
#define FILE_RR       "bbr"   /* RR-Net (VICE) */

/* what the players are called in the game: slot 0 invited, slot 1 accepted */
#define SLOT0_NAME    "BUB (green)"
#define SLOT1_NAME    "BOB (blue)"

#endif
