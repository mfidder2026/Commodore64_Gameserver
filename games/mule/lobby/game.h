/*
 * M.U.L.E. OME - settings for the framework's standard lobby
 * (framework/c64/lobby, see framework/c64/lobby/README.md)
 *
 * Strings are compiled by cc65 for the C64's lower/upper case character set:
 * write them in normal mixed case.
 */
#ifndef GAME_H
#define GAME_H

/* the game on the server (server.json "games": id 6, module "lockstep", up to 4 players) */
#define GAME_ID       6
#define GAME_VERSION  1

/* title lines of the lobby screens (max. 40 characters) */
#define GAME_TITLE    "          M.U.L.E.  *  ONLINE"
#define GAME_TAGLINE  "  up to four colonists on planet Irata"

/* settings file on the disk */
#define CFG_FILE      "mule.cfg"

/* game file to load per network type (the lobby itself is "mule") */
#define FILE_UCI      "muleu"   /* C64 Ultimate / Ultimate 64 */
#define FILE_WIC      "mulew"   /* WiC64 */
#define FILE_RR       "muler"   /* RR-Net (VICE) */

/* the game runs on PAL and NTSC alike (tools/dettest.py) */
#define GAME_PAL_ONLY 0

/* no menu key L: the original game (1-4 players on one C64) does not fit on this
   disk next to the three game files; it has a disk of its own (mule-original.d64) */

/* tables instead of invitations (up to four colonists; the computer plays the empty seats) */
#define GAME_TABLES
#define TABLE_SEATS       4
#define TABLE_OPTION_NAME "Level"
#define TABLE_OPTIONS     "Beginner", "Standard", "Tournament"
#define SEAT_NAME         "colonist"

/* head-to-head without the server (menu key H): the input delay in ticks, as the
   server's inputDelay; the host chooses the table's option, the other seats are the game's */
#define DIRECT_DELAY  3

#endif
