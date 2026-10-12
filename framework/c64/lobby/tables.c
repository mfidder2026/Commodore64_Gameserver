/*
 * Tables: the lobby of a game with more than two seats (game.h: GAME_TABLES).
 * Included by main.c, which has the helpers and the connection.
 *
 * A host opens a table with an option (TABLE_OPTIONS: e.g. the level),
 * others sit down until it is full (TABLE_SEATS), and the host starts the
 * session; the game plays the empty seats. Protocol: docs/protocol.md
 * (TABLE_OPEN $12, TABLE_JOIN $13, TABLE_LEAVE $14, TABLE_START $15,
 * TABLES $16, TABLE $17).
 *
 * Tests (config file): auto=i opens a table and starts it when seats=n
 * players sit at it (default 2); auto=a sits down at the first table with
 * a free seat.
 */

#define M_TABLE_OPEN  0x12
#define M_TABLE_JOIN  0x13
#define M_TABLE_LEAVE 0x14
#define M_TABLE_START 0x15
#define M_TABLES      0x16
#define M_TABLE       0x17

#define MAXTABLES 8

struct table { unsigned char id, option, seats; char host[NICK_MAX + 1]; };
static struct table tables[MAXTABLES];
static unsigned char ntables;


static const char *const option_text[] = { TABLE_OPTIONS };
#define NOPTIONS (sizeof option_text / sizeof option_text[0])

/* my table (TABLE) */
static unsigned char my_table, my_option, my_seat = 0xFF, my_count;
static char my_nicks[TABLE_SEATS][NICK_MAX + 1];

static void take_tables(void)
{
    unsigned char i, n, p = 2;
    ntables = msg[1] < MAXTABLES ? msg[1] : MAXTABLES;
    for (i = 0; i < ntables && p + 4 <= msglen; ++i) {
        tables[i].id = msg[p];
        tables[i].option = msg[p + 1];
        tables[i].seats = msg[p + 2];
        n = msg[p + 3] > NICK_MAX ? NICK_MAX : msg[p + 3];
        memcpy(tables[i].host, msg + p + 4, n);
        tables[i].host[n] = 0;
        p += 4 + msg[p + 3];
    }
    ntables = i;
    if (sel >= ntables) sel = ntables ? ntables - 1 : 0;
}

static void take_table(void)
{
    unsigned char i, n, p = 5;
    my_table = msg[1];
    my_option = msg[2];
    my_seat = msg[3];
    my_count = msg[4] < TABLE_SEATS ? msg[4] : TABLE_SEATS;
    for (i = 0; i < my_count && p + 1 <= msglen; ++i) {
        n = msg[p] > NICK_MAX ? NICK_MAX : msg[p];
        memcpy(my_nicks[i], msg + p + 1, n);
        my_nicks[i][n] = 0;
        p += 1 + msg[p];
    }
}

static const char *option_name(unsigned char o) { return o < NOPTIONS ? option_text[o] : "?"; }

static void draw_tables(void)
{
    unsigned char i, y;
    gotoxy(0, 4);
    textcolor(COLOR_GRAY2);
    cprintf("Tables (players online: %u)    \r\n\r\n", total_players + 1);
    for (i = 0; i < MAXTABLES; ++i) {
        y = 6 + i;
        cclearxy(0, y, 40);
        if (i >= ntables) {
            if (i == 0) { gotoxy(1, y); textcolor(COLOR_GRAY2); cputs("No tables yet: N opens one."); }
            continue;
        }
        gotoxy(1, y);
        revers(i == sel);
        textcolor(COLOR_WHITE);
        put_nick(tables[i].host, 8);
        revers(0);
        gotoxy(11, y);
        textcolor(COLOR_YELLOW);
        cputs(option_name(tables[i].option));
        gotoxy(24, y);
        textcolor(tables[i].seats < TABLE_SEATS ? COLOR_GREEN : COLOR_ORANGE);
        cprintf("%u/%u", tables[i].seats, TABLE_SEATS);
    }
    for (y = 6 + MAXTABLES; y < 22; ++y) cclearxy(0, y, 40);
    textcolor(COLOR_WHITE);
}

static void draw_my_table(void)
{
    unsigned char i, y;
    gotoxy(0, 4);
    textcolor(COLOR_GRAY2);
    cclearxy(0, 4, 40);
    gotoxy(0, 4);
    cputs("Table of ");
    put_nick(my_nicks[0], 0);
    cputs(": ");
    textcolor(COLOR_YELLOW);
    cputs(option_name(my_option));
    for (i = 0; i < 16; ++i) cclearxy(0, 6 + i, 40);
    for (i = 0; i < TABLE_SEATS; ++i) {
        y = 7 + i * 2;
        gotoxy(2, y);
        textcolor(COLOR_GRAY2);
        cprintf("%s %u  ", SEAT_NAME, i + 1);
        if (i < my_count) {
            textcolor(i == my_seat ? COLOR_LIGHTGREEN : COLOR_WHITE);
            put_nick(my_nicks[i], 8);
            if (i == 0) { textcolor(COLOR_GRAY2); cputs("  (host)"); }
        } else {
            textcolor(COLOR_LIGHTBLUE);
            cputs("computer");
        }
    }
    textcolor(COLOR_WHITE);
}

static void table_lobby(void)
{
    enum { CONNECTING, LOBBY, CHOOSING, OPENING, JOINING, AT_TABLE, LEAVING, STARTING } st = CONNECTING;
    clock_t last_send = 0, last_heard = now();
    unsigned char redraw = 1, key, joy, lastjoy = 0, option = 0, target = 0;

    title();
    if (last_reason) {
        gotoxy(0, 21);
        textcolor(COLOR_YELLOW);
        cprintf("Last game: %s", end_text[last_reason]);
        textcolor(COLOR_WHITE);
        last_reason = 0;
    }
    status("Connecting to the server...   F1: setup");
    for (;;) {
        /* --- network */
        while (rx()) {
            last_heard = now();
            switch (msg[0]) {
            case M_WELCOME:
                myid = msg[2];
                if (st == CONNECTING) {
                    st = LOBBY; redraw = 1; cfg_save();
                    status("FIRE: sit down  N: new table  F1: setup");
                }
                break;
            case M_REJECT:
                status(msg[1] == 1 ? "That name is already in use." : msg[1] == 2 ? "Wrong version." : "Rejected by the server.");
                sleep(3);
                return;
            case M_PLAYERS:
                if (st == CONNECTING) { st = LOBBY; status("FIRE: sit down  N: new table  F1: setup"); }
                total_players = msg[1];
                if (st == LOBBY) redraw = 1;
                break;
            case M_TABLES:
                take_tables();
                if (st == LOBBY) redraw = 1;
                break;
            case M_TABLE:
                take_table();
                if (my_seat == 0xFF) {                  /* at no table (left, closed, full) */
                    if (st == AT_TABLE || st == OPENING || st == JOINING || st == LEAVING) {
                        status(st == JOINING ? "That table is full or closed."
                               : st == AT_TABLE ? "The host closed the table." : "FIRE: sit down  N: new table  F1: setup");
                        st = LOBBY; title(); redraw = 1;
                    }
                } else if (st != STARTING) {
                    if (st != AT_TABLE) {
                        title();
                        status(my_seat == 0 ? "FIRE/RETURN: start  N: close the table"
                                            : "Waiting for the host...  N: leave");
                    }
                    st = AT_TABLE;
                    redraw = 1;
                }
                break;
            case M_PING:
                msg[0] = M_PONG;
                send(3);
                break;
            case M_START:
                start_session();                    /* does not return */
                break;
            }
        }

        /* --- time: repeat the request until its answer comes */
        if (elapsed(last_send, CLOCKS_PER_SEC / 2)) {
            switch (st) {
            case CONNECTING: send_hello(); cputc('.'); last_send = now(); break;
            case OPENING:    send2(M_TABLE_OPEN, option); last_send = now(); break;
            case JOINING:    send2(M_TABLE_JOIN, target); last_send = now(); break;
            case LEAVING:    msg[0] = M_TABLE_LEAVE; send(1); last_send = now(); break;
            case STARTING:   msg[0] = M_TABLE_START; send(1); last_send = now(); break;
            default: break;
            }
        }
        if (st != CONNECTING && elapsed(last_heard, CLOCKS_PER_SEC * 8)) {
            st = CONNECTING;
            ntables = 0;
            title();
            status("No answer from the server, trying again...");
            last_heard = now();
        }
        if (redraw) {
            if (st == LOBBY || st == CHOOSING) draw_tables();
            else if (st == AT_TABLE) draw_my_table();
            redraw = 0;
        }

        /* --- automatic play (tests) */
        if (auto_mode == 'i' && st == LOBBY) { st = OPENING; last_send = 0; }
        if (auto_mode == 'i' && st == AT_TABLE && my_seat == 0 && my_count >= auto_seats) { st = STARTING; last_send = 0; }
        if (auto_mode == 'a' && st == LOBBY) {
            unsigned char i;
            for (i = 0; i < ntables; ++i)
                if (tables[i].seats < TABLE_SEATS) { target = tables[i].id; st = JOINING; last_send = 0; break; }
        }

        /* --- keys and joystick */
        key = kbhit() ? cgetc() : 0;
        joy = joy2();
        if (joy & ~lastjoy & 1) key = CH_CURS_UP;
        if (joy & ~lastjoy & 2) key = CH_CURS_DOWN;
        if (joy & ~lastjoy & 4) key = CH_CURS_LEFT;
        if (joy & ~lastjoy & 8) key = CH_CURS_RIGHT;
        if (joy & ~lastjoy & 16) key = CH_ENTER;
        lastjoy = joy;
        if (!key) continue;

        if (key == CH_F1 && (st == LOBBY || st == CONNECTING)) {
            msg[0] = M_BYE;
            send(1);
            return;
        }
        switch (st) {
        case LOBBY:
            if (key == CH_CURS_UP && sel) { --sel; redraw = 1; }
            if (key == CH_CURS_DOWN && sel + 1 < ntables) { ++sel; redraw = 1; }
            if ((key == CH_ENTER || key == ' ') && sel < ntables) {
                if (tables[sel].seats >= TABLE_SEATS) status("That table is full.");
                else { target = tables[sel].id; st = JOINING; last_send = 0; status("Sitting down..."); }
            }
            if (key == 'n') { st = CHOOSING; key = 0; }
            break;
        case AT_TABLE:
            if (key == 'n') { st = LEAVING; last_send = 0; status("Leaving..."); }
            else if (my_seat == 0 && (key == CH_ENTER || key == ' ')) { st = STARTING; last_send = 0; status("Starting..."); }
            break;
        default:
            break;
        }
        if (st == CHOOSING) {
            if (key == CH_CURS_LEFT || key == CH_CURS_UP) option = option ? option - 1 : NOPTIONS - 1;
            if (key == CH_CURS_RIGHT || key == CH_CURS_DOWN || key == CH_F3) option = (option + 1) % NOPTIONS;
            if (key == CH_ENTER || key == ' ') { st = OPENING; last_send = 0; status("Opening a table..."); continue; }
            if (key == 'n' || key == CH_F1) { st = LOBBY; status("FIRE: sit down  N: new table  F1: setup"); continue; }
            gotoxy(0, 23);
            cclearxy(0, 23, 40);
            gotoxy(0, 23);
            textcolor(COLOR_YELLOW);
            cprintf("%s: <%s>  FIRE: open", TABLE_OPTION_NAME, option_name(option));
            textcolor(COLOR_WHITE);
        }
    }
}
