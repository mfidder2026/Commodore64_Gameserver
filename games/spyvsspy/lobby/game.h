/*
 * Spy vs Spy OME - settings for the framework's standard lobby
 * (framework/c64/lobby, see framework/c64/lobby/README.md)
 *
 * Strings are compiled by cc65 for the C64's lower/upper case character set:
 * write them in normal mixed case.
 */
#ifndef GAME_H
#define GAME_H

/* the game on the server (server.json "games": id 8, module "lockstep") */
#define GAME_ID       8
#define GAME_VERSION  1

/* title lines of the lobby screens (max. 40 characters) */
#define GAME_TITLE    "        SPY VS SPY  *  ONLINE"
#define GAME_TAGLINE  "      white against black, one C64 each"

/* settings file on the disk */
#define CFG_FILE      "spyvsspy.cfg"

/* game file to load per network type (the lobby itself is "spyvsspy") */
#define FILE_UCI      "spyu"    /* C64 Ultimate / Ultimate 64 */
#define FILE_WIC      "spyw"    /* WiC64 */
#define FILE_RR       "spyr"    /* RR-Net (VICE) */

/* the game runs on PAL and NTSC alike (tools/dettest.py) */
#define GAME_PAL_ONLY 0

/* menu key L: the original game (two players, or one against the computer) */
#define LOCAL_GAME_TEXT "original game, 1-2 players"
#define LOCAL_GAME_FILE "spyl"

/* what the players are called in the game: slot 0 the host, slot 1 the guest */
#define SLOT0_NAME    "the white spy"
#define SLOT1_NAME    "the black spy"

/* tables instead of invitations: the host picks the level; alone at the table
   the host plays white against the computer's black spy */
#define GAME_TABLES
#define TABLE_SEATS       2
#define TABLE_OPTION_NAME "Choose"
#define TABLE_OPTIONS     "Level 1", "Level 2", "Level 3", "Level 4", "Level 5", "Level 6", "Level 7", "Level 8"
#define SEAT_NAME         "spy"

#endif
