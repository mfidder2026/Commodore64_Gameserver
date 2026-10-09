/*
 * BB-LAN lobby - Bubble Bobble over the LAN
 *
 * Finds the network hardware, connects to the BB-LAN game server, shows the
 * other players and lets you invite one. When the server starts a session
 * this program writes a handoff block to $03C0 and loads the game, which
 * takes over the connection (see src/bbnet.s). After the game the game loads
 * this program again; it then shows how the game ended and reconnects.
 *
 * Hardware:
 *   Ultimate 64 / C64 Ultimate  UDP through the Ultimate Command Interface
 *   RR-Net (VICE)               raw Ethernet to the server's pcap interface
 *
 * Config file BBLAN.CFG (written by this program):
 *   name=...   your name (A-Z, 0-9, max 8)
 *   server=... IP address of the game server (Ultimate only)
 *   mac=...    MAC address of the RR-Net (made up once, RR-Net only)
 *   auto=...   tests: "invite" or "accept"
 *   bot=1      tests: a bot plays instead of the joystick (test game files)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <conio.h>
#include <time.h>
#include <peekpoke.h>
#include <unistd.h>
#include <errno.h>

#include "net.h"

#define GAME_ID      3
#define GAME_VERSION 1
#define PROTO        1
#define SERVER_PORT  6465

/* messages */
#define M_HELLO     0x01
#define M_WELCOME   0x02
#define M_REJECT    0x03
#define M_LOBBY     0x04
#define M_CHALLENGE 0x05
#define M_ACCEPT    0x06
#define M_DECLINE   0x07
#define M_START     0x08
#define M_START_ACK 0x09
#define M_SESS_END  0x0B
#define M_PING      0x0C
#define M_PONG      0x0D
#define M_BYE       0x0E
#define M_CANCELLED 0x0F
#define M_PLAYERS   0x10
#define M_INVITE    0x11

/* handoff block for the game ($03C0, see src/bbnet.s) */
#define HB          ((unsigned char *)0x03C0)
#define HB_DRIVER   2
#define HB_SLOT     3
#define HB_SESSION  4
#define HB_SEED     5
#define HB_DELAY    7
#define HB_SOCKET   8
#define HB_FLAGS    9
#define HB_DEVICE   10
#define HB_DSTMAC   12
#define HB_MYMAC    18
#define HB_SIZE     24

/* result the game leaves at $033C: "BR", reason, UCI socket */
#define RESULT      ((unsigned char *)0x033C)

#define MAXPLAYERS 16
#define NICK_MAX   8

static char nick[NICK_MAX + 1];
static char server[32];
static unsigned char mymac[6];
static unsigned char auto_mode;          /* 0, 'i'nvite, 'a'ccept */
static unsigned char bot;
static unsigned char cfg_dirty;

static unsigned char drv;                /* DRV_* */
static unsigned char msg[256];
static unsigned char msglen;

struct player { unsigned char id, flags; char nick[NICK_MAX + 1]; };
static struct player players[MAXPLAYERS];
static unsigned char nplayers, total_players;
static unsigned char sel;
static unsigned char myid;

static const char *const end_text[] = {
    "", "game over", "desync - the C64s disagreed", "timeout - no answer",
    "ended by the server", "a player quit", "your opponent left"
};

/* ------------------------------------------------------------- helpers */

static clock_t now(void) { return clock(); }
static unsigned char elapsed(clock_t since, unsigned int ticks) { return clock() - since >= ticks; }

static void title(void)
{
    bgcolor(COLOR_BLACK);
    bordercolor(COLOR_BLACK);
    clrscr();
    textcolor(COLOR_LIGHTGREEN);
    cputs("        BUBBLE BOBBLE  *  LAN\r\n");
    textcolor(COLOR_GRAY2);
    cputs("     two C64s, one game, one network\r\n\r\n");
    textcolor(COLOR_WHITE);
}

/* names are kept as ASCII upper case ($41-$5A); show them in capitals */
static void put_nick(const char *n, unsigned char width)
{
    unsigned char i = 0;
    for (; n[i]; ++i) cputc(n[i] >= 0x41 && n[i] <= 0x5A ? n[i] + 0x80 : n[i]);
    for (; i < width; ++i) cputc(' ');
}

static void status(const char *s)
{
    gotoxy(0, 23);
    cclearxy(0, 23, 40);
    gotoxy(0, 23);
    textcolor(COLOR_YELLOW);
    cputs(s);
    textcolor(COLOR_WHITE);
}

static unsigned char valid_nick(const char *s)
{
    unsigned char i, c;
    if (!*s || strlen(s) > NICK_MAX) return 0;
    for (i = 0; (c = s[i]) != 0; ++i)
        if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'))) return 0;
    return 1;
}

/* read a line; keeps the old text on RETURN; ESC (left arrow) cancels */
static unsigned char input(char *buf, unsigned char max, unsigned char digits_dots)
{
    char tmp[33];
    unsigned char n = 0, c;
    cursor(1);
    for (;;) {
        c = cgetc();
        if (c == CH_ENTER) break;
        if (c == 0x5F) { cursor(0); return 0; }          /* left arrow */
        if (c == 0x14) {                                 /* DEL */
            if (n) { --n; gotox(wherex() - 1); cputc(' '); gotox(wherex() - 1); }
            continue;
        }
        if (n < max && ((c >= 'a' && c <= 'z' && !digits_dots) || (c >= '0' && c <= '9') ||
                        (c == '.' && digits_dots))) {
            tmp[n++] = c;
            cputc(c);
        }
    }
    cursor(0);
    if (n) { tmp[n] = 0; strcpy(buf, tmp); }
    return 1;
}

static unsigned char joy2(void)
{
    POKE(0xDC00, 0x7F);
    return ~PEEK(0xDC00) & 0x1F;
}

/* -------------------------------------------------------------- config */

static void cfg_load(void)
{
    FILE *f = fopen("bblan.cfg", "r");
    char line[40];
    char *v;
    if (!f) return;
    while (fgets(line, sizeof line, f)) {
        v = strchr(line, '=');
        if (!v) continue;
        *v++ = 0;
        v[strcspn(v, "\r\n")] = 0;
        if (!strcmp(line, "name") && valid_nick(v)) strcpy(nick, v);
        else if (!strcmp(line, "server")) { strncpy(server, v, 31); }
        else if (!strcmp(line, "mac") && strlen(v) == 12) {
            unsigned char i;
            for (i = 0; i < 6; ++i) {
                char h[3];
                h[0] = v[i * 2]; h[1] = v[i * 2 + 1]; h[2] = 0;
                mymac[i] = (unsigned char)strtoul(h, 0, 16);
            }
        }
        else if (!strcmp(line, "auto")) auto_mode = v[0];
        else if (!strcmp(line, "bot")) bot = v[0] == '1';
    }
    fclose(f);
}

static void cfg_save(void)
{
    FILE *f;
    if (!cfg_dirty) return;
    remove("bblan.cfg");
    f = fopen("bblan.cfg", "w");
    if (!f) return;
    fprintf(f, "name=%s\r", nick);
    if (*server) fprintf(f, "server=%s\r", server);
    if (mymac[0])
        fprintf(f, "mac=%02x%02x%02x%02x%02x%02x\r", mymac[0], mymac[1], mymac[2], mymac[3], mymac[4], mymac[5]);
    if (auto_mode) fprintf(f, "auto=%c\r", auto_mode);
    if (bot) fprintf(f, "bot=1\r");
    fclose(f);
    cfg_dirty = 0;
}

static void settings(unsigned char ask_server)
{
    title();
    cputs("Your name (A-Z, 0-9, max. 8)\r\n");
    if (*nick) cprintf("[%s] ", nick);
    do {
        input(nick, NICK_MAX, 0);
        cputs("\r\n");
    } while (!valid_nick(nick));
    if (ask_server) {
        cputs("\r\nIP address of the game server\r\n");
        if (*server) cprintf("[%s] ", server);
        input(server, 31, 1);
        cputs("\r\n");
    }
    cfg_dirty = 1;
}

/* ----------------------------------------------------------- messages */

static void send(unsigned char len) { net_send(msg, len); }

static void send_hello(void)
{
    unsigned char n = strlen(nick);
    msg[0] = M_HELLO; msg[1] = PROTO; msg[2] = GAME_ID; msg[3] = GAME_VERSION;
    msg[4] = n;
    memcpy(msg + 5, nick, n);
    send(5 + n);
}

static void send2(unsigned char type, unsigned char a) { msg[0] = type; msg[1] = a; send(2); }

static unsigned char rx(void)
{
    msglen = net_recv(msg);
    return msglen;
}

/* ---------------------------------------------------------- the lobby */

static void draw_players(void)
{
    unsigned char i, y;
    gotoxy(0, 4);
    textcolor(COLOR_GRAY2);
    cprintf("Players online: %u\r\n\r\n", total_players);
    for (i = 0; i < MAXPLAYERS; ++i) {
        y = 6 + i;
        cclearxy(0, y, 40);
        if (i >= nplayers) continue;
        gotoxy(1, y);
        revers(i == sel);
        textcolor(players[i].id == myid ? COLOR_GRAY2 : COLOR_WHITE);
        put_nick(players[i].nick, 8);
        revers(0);
        gotoxy(12, y);
        textcolor(players[i].flags & 1 ? COLOR_LIGHTBLUE : COLOR_YELLOW);
        cputs(players[i].flags & 1 ? "bot   " : "player");
        gotoxy(20, y);
        switch (players[i].flags & 6) {
        case 0: textcolor(COLOR_GREEN); cputs("free"); break;
        case 2: textcolor(COLOR_ORANGE); cputs("busy"); break;
        default: textcolor(COLOR_RED); cputs("playing"); break;
        }
    }
    textcolor(COLOR_WHITE);
}

static void take_players(void)
{
    unsigned char first = msg[2], count = msg[3], p = 4, i, n;
    total_players = msg[1];
    for (i = 0; i < count && first + i < MAXPLAYERS && p + 3 <= msglen; ++i) {
        struct player *pl = &players[first + i];
        pl->id = msg[p];
        pl->flags = msg[p + 1];
        n = msg[p + 2];
        if (n > NICK_MAX) n = NICK_MAX;
        memcpy(pl->nick, msg + p + 3, n);
        pl->nick[n] = 0;
        p += 3 + msg[p + 2];
    }
    nplayers = total_players < MAXPLAYERS ? total_players : MAXPLAYERS;
    if (sel >= nplayers) sel = nplayers ? nplayers - 1 : 0;
}

/* the game file for this network hardware */
static const char *game_file(void)
{
    return drv == DRV_UCI ? "bbu" : drv == DRV_WIC ? "bbw" : "bbr";
}

/* START: write the handoff block and load the game */
static void start_session(void)
{
    unsigned char session = msg[1], slot = msg[2];
    unsigned char *params = msg + 5;          /* msg[4] = parameter length */
    unsigned char i;

    for (i = 0; i < 3; ++i) send2(M_START_ACK, session);
    memset(HB, 0, HB_SIZE);
    HB[0] = 'b'; HB[1] = 'l';                 /* PETSCII "BL" = $42 $4C */
    HB[HB_DRIVER] = drv;
    HB[HB_SLOT] = slot;
    HB[HB_SESSION] = session;
    HB[HB_SEED] = params[0];
    HB[HB_SEED + 1] = params[1];
    HB[HB_DELAY] = params[2];
    HB[HB_SOCKET] = net_socket();
    HB[HB_FLAGS] = bot;
    HB[HB_DEVICE] = PEEK(0xBA) ? PEEK(0xBA) : 8;
    memcpy(HB + HB_DSTMAC, net_server_mac(), 6);
    memcpy(HB + HB_MYMAC, mymac, 6);
    cfg_save();
    title();
    cprintf("You play %s.\r\n\r\nLoading the game...", slot ? "BOB (blue)" : "BUB (green)");
    start_game(game_file());
}

static void lobby(void)
{
    enum { CONNECTING, LOBBY, INVITING, CHALLENGED } st = CONNECTING;
    clock_t last_send = 0, last_heard = now();
    unsigned char seq = 0, challenge = 0, redraw = 1, key, joy, lastjoy = 0;
    unsigned char target = 0;

    title();
    status("Connecting to the server...");
    for (;;) {
        /* --- network */
        while (rx()) {
            last_heard = now();
            switch (msg[0]) {
            case M_WELCOME:
                myid = msg[2];
                if (st == CONNECTING) { st = LOBBY; redraw = 1; cfg_save(); status("FIRE/RETURN: invite   F1: back"); }
                break;
            case M_REJECT:
                status(msg[1] == 1 ? "That name is already in use." : msg[1] == 2 ? "Wrong version." : "Rejected by the server.");
                sleep(3);
                return;
            case M_PLAYERS:
                if (st == CONNECTING) { st = LOBBY; status("FIRE/RETURN: invite   F1: back"); }
                take_players();
                redraw = 1;
                break;
            case M_PING:
                msg[0] = M_PONG;
                send(3);
                break;
            case M_CHALLENGE:
                if (st == INVITING) break;          /* our own invitation */
                challenge = msg[1];
                if (st != CHALLENGED) {
                    char who[NICK_MAX + 1];
                    unsigned char n = msg[2] > NICK_MAX ? NICK_MAX : msg[2];
                    memcpy(who, msg + 3, n);
                    who[n] = 0;
                    st = CHALLENGED;
                    gotoxy(0, 23);
                    cclearxy(0, 23, 40);
                    gotoxy(0, 23);
                    textcolor(COLOR_LIGHTGREEN);
                    put_nick(who, 0);
                    cputs(" invites you! FIRE/Y: play N: no");
                    textcolor(COLOR_WHITE);
                }
                if (auto_mode == 'a') send2(M_ACCEPT, challenge);
                break;
            case M_CANCELLED:
                if (st == INVITING || st == CHALLENGED) {
                    st = LOBBY;
                    status(msg[2] == 1 ? "Declined.  FIRE/RETURN: invite" : "The invitation ended.");
                }
                break;
            case M_START:
                start_session();                    /* does not return */
                break;
            }
        }

        /* --- time */
        if (st == CONNECTING && elapsed(last_send, CLOCKS_PER_SEC / 2)) {
            send_hello();
            last_send = now();
            cputc('.');
        }
        if (st == INVITING && elapsed(last_send, CLOCKS_PER_SEC / 2)) {
            msg[0] = M_INVITE; msg[1] = target; msg[2] = seq;
            send(3);
            last_send = now();
        }
        if (st != CONNECTING && elapsed(last_heard, CLOCKS_PER_SEC * 8)) {
            st = CONNECTING;
            nplayers = 0;
            title();
            status("No answer from the server, trying again...");
            last_heard = now();
        }
        if (redraw && st != CONNECTING) { draw_players(); redraw = 0; }

        /* --- automatic play (tests) */
        if (auto_mode == 'i' && st == LOBBY) {
            unsigned char i;
            for (i = 0; i < nplayers; ++i)
                if (players[i].id != myid && !(players[i].flags & 7)) {
                    target = players[i].id; ++seq; st = INVITING; last_send = 0;
                    status("Inviting...  N: cancel");
                    break;
                }
        }

        /* --- keys and joystick */
        key = kbhit() ? cgetc() : 0;
        joy = joy2();
        if (joy & ~lastjoy & 1) key = CH_CURS_UP;
        if (joy & ~lastjoy & 2) key = CH_CURS_DOWN;
        if (joy & ~lastjoy & 16) key = CH_ENTER;
        lastjoy = joy;
        if (!key) continue;

        if (key == CH_F1 && st != CHALLENGED) {
            msg[0] = M_BYE;
            send(1);
            return;
        }
        switch (st) {
        case LOBBY:
            if (key == CH_CURS_UP && sel) { --sel; redraw = 1; }
            if (key == CH_CURS_DOWN && sel + 1 < nplayers) { ++sel; redraw = 1; }
            if ((key == CH_ENTER || key == ' ') && sel < nplayers) {
                if (players[sel].id == myid) status("That is you.");
                else if (players[sel].flags & 6) status("That player is not free.");
                else {
                    target = players[sel].id; ++seq; st = INVITING; last_send = 0;
                    status("Inviting...  N: cancel");
                }
            }
            break;
        case INVITING:
            if (key == 'n') { send2(M_DECLINE, 0); st = LOBBY; status("FIRE/RETURN: invite   F1: back"); }
            break;
        case CHALLENGED:
            if (key == CH_ENTER || key == 'y' || key == ' ') { send2(M_ACCEPT, challenge); status("Accepted, starting..."); }
            if (key == 'n') { send2(M_DECLINE, challenge); st = LOBBY; status("FIRE/RETURN: invite   F1: back"); }
            break;
        }
    }
}

/* --------------------------------------------------------------- main */

int main(void)
{
    unsigned char key, came_back = 0, reason = 0;

    POKE(0xD015, 0);                                 /* the game's sprites */
    if (RESULT[0] == 'b' && RESULT[1] == 'r') {      /* back from a game */
        came_back = 1;
        reason = RESULT[2];
        RESULT[0] = 0;
    }
    cfg_load();

    title();
    cputs("Looking for network hardware...\r\n\r\n");
    drv = net_init(mymac, server);
    if (drv == DRV_RR && !mymac[0]) cfg_dirty = 1;   /* a new MAC was made up */
    if (came_back && drv == DRV_UCI) net_close_socket(RESULT[3]);

    for (;;) {
        title();
        if (PEEK(0x02A6) == 0)
            cputs("NTSC C64: the LAN game needs PAL.\r\n\r\n");
        switch (drv) {
        case DRV_UCI: cprintf("Network: Ultimate, IP %s\r\n", net_info()); break;
        case DRV_RR:  cputs("Network: RR-Net (VICE)\r\n"); break;
        case DRV_WIC: cprintf("Network: WiC64, IP %s\r\n", net_info()); break;
        default:      cputs("Network: none found\r\n"); break;
        }
        cputs("Name:    "); put_nick(*nick ? nick : "-", 0); cputs("\r\n");
        if (drv == DRV_UCI || drv == DRV_WIC) cprintf("Server:  %s\r\n", *server ? server : "-");
        if (came_back && reason && reason < 7) {
            textcolor(COLOR_YELLOW);
            cprintf("\r\nLast game: %s\r\n", end_text[reason]);
            textcolor(COLOR_WHITE);
        }
        cputs("\r\n\r\n  F1/RETURN  play on the LAN\r\n"
              "  L          local game (2 joysticks)\r\n"
              "  S          settings\r\n");

        if ((came_back || auto_mode) && drv != DRV_NONE && *nick) key = CH_ENTER;
        else key = cgetc();
        came_back = 0;

        if (key == 's') { settings(drv == DRV_UCI || drv == DRV_WIC); cfg_save(); continue; }
        if (key == 'l') { memset(HB, 0, HB_SIZE); start_game(game_file()); }
        if (key != CH_ENTER && key != CH_F1) continue;
        if (drv == DRV_NONE || PEEK(0x02A6) == 0) continue;
        if (!*nick || ((drv == DRV_UCI || drv == DRV_WIC) && !*server)) { settings(drv == DRV_UCI || drv == DRV_WIC); cfg_save(); }
        if (net_connect(server, SERVER_PORT)) {
            status("Cannot open a connection to the server.");
            sleep(3);
            continue;
        }
        lobby();
        net_disconnect();
        auto_mode = 0;
    }
    return 0;
}
