/*
 * Standard lobby: head-to-head, two C64s on the same LAN without the server
 * (included by main.c when the game's game.h defines DIRECT_DELAY).
 *
 * One C64 hosts, the other joins. The lobbies agree on a session and hand it to
 * the game exactly as a server's START would; the game then sends its INPUTs to
 * the other C64 instead of the server, which relays them unchanged anyway.
 *
 *   C64 Ultimate  needs firmware with OPEN_UDP_LOCAL ($0A, GideonZ/1541ultimate#962,
 *                 pull request #1016): UDP from a fixed local port, 6464 <-> 6464.
 *                 The host announces itself (HERE) every 0.5 s from port 6465 to
 *                 the subnet's broadcast address, port 6464, and listens with $0A
 *                 to 0.0.0.0 (lwIP matches an "any" remote against every sender).
 *                 The joiner listens with $0A to 0.0.0.0, remote 6465, for a HERE.
 *   RR-Net        raw Ethernet: HERE goes to the broadcast MAC, the rest to the
 *                 other C64's MAC (the game's "server" MAC).
 *
 * Messages (docs/protocol.md, "Head-to-head"):
 *   HERE      $18 proto game version ip(4) n nick       host -> broadcast
 *   HELLO     $01 proto game version n nick ip(4)      joiner -> host
 *   START     $08 session slot(1) players(2) 3 seed(2) delay   host -> joiner
 *   START_ACK $09 session                              joiner -> host
 * The host's game is slot 0, the joiner's slot 1.
 */

#define M_HERE        0x18
#define PORT_GAME     6464
#define PORT_HERE     6465

static char peer_nick[NICK_MAX + 1];
static char peer_ip[16];

static void ipstr(char *s, const unsigned char *ip)
{
    sprintf(s, "%u.%u.%u.%u", ip[0], ip[1], ip[2], ip[3]);
}

static unsigned char ours(unsigned char at)
{
    return msg[at] == PROTO && msg[at + 1] == GAME_ID && msg[at + 2] == GAME_VERSION;
}

static void take_nick(unsigned char at)
{
    unsigned char n = msg[at] > NICK_MAX ? NICK_MAX : msg[at];
    memcpy(peer_nick, msg + at + 1, n);
    peer_nick[n] = 0;
}

static unsigned char put_hdr(unsigned char type)
{
    msg[0] = type; msg[1] = PROTO; msg[2] = GAME_ID; msg[3] = GAME_VERSION;
    return 4;
}

static unsigned char put_nick_msg(unsigned char p)
{
    unsigned char n = strlen(nick);
    msg[p] = n;
    memcpy(msg + p + 1, nick, n);
    return p + 1 + n;
}

static void dline(unsigned char y, unsigned char color, const char *s)
{
    cclearxy(0, y, 40);
    gotoxy(0, y);
    textcolor(color);
    cputs(s);
    textcolor(COLOR_WHITE);
}

static unsigned char any_key(void)
{
    if (!kbhit()) return 0;
    cgetc();
    return 1;
}

/* the game: the same handoff as a server's START (msg holds a START) */
static void direct_start(unsigned char role)
{
    if (direct_role != role) { direct_role = role; cfg_dirty = 1; }
    start_session();                            /* does not return */
}

/* ------------------------------------------------------------------- host */

static void direct_host(void)
{
    unsigned char ann = 0xFF, lst = 0xFF, peer = 0xFF, linked = 0;
    unsigned char session, seed0, seed1, n;
    clock_t last = 0, since = 0;
    char line[40];

    title();
    cputs("Head-to-head: hosting\r\n\r\n");
    if (drv == DRV_UCI) {
        unsigned char b[4], i;
        const unsigned char *ip = net_ipcfg();
        for (i = 0; i < 4; ++i) b[i] = ip[i] | (unsigned char)~ip[4 + i];
        ipstr(line, b);
        ann = net_open_local(line, PORT_GAME, PORT_HERE);
        lst = net_open_local("0.0.0.0", PORT_GAME, PORT_GAME);
        if (ann == 0xFF || lst == 0xFF) {
            net_close_socket(ann);
            net_close_socket(lst);
            status("Cannot open the sockets.");
            sleep(3);
            return;
        }
        ipstr(line, ip);
        cprintf("This C64: %s\r\n", line);
        net_use_socket(lst);
    }
    net_direct_begin();
    dline(23, COLOR_YELLOW, "Waiting for the other C64. Key: back");

    session = (PEEK(0xD012) ^ PEEK(0xDC04) ^ (unsigned char)clock()) | 1;
    seed0 = PEEK(0xDC04) ^ PEEK(0xD012);
    seed1 = (PEEK(0xDC05) ^ (unsigned char)(clock() >> 3)) | 0x80;    /* never 0 */

    for (;;) {
        if (any_key() && auto_mode != 'h') break;
        if (!linked && elapsed(last, CLOCKS_PER_SEC / 2)) {          /* HERE every 0.5 s */
            last = now();
            if (drv == DRV_UCI) net_use_socket(ann);
            n = put_hdr(M_HERE);
            memcpy(msg + n, net_ipcfg(), 4);
            n = put_nick_msg(n + 4);
            send(n);
            if (drv == DRV_UCI) net_use_socket(lst);
        }
        if (linked && elapsed(last, CLOCKS_PER_SEC / 4)) {           /* START every 0.25 s */
            last = now();
            msg[0] = M_START; msg[1] = session; msg[2] = 1; msg[3] = 2; msg[4] = 3;
            msg[5] = seed0; msg[6] = seed1; msg[7] = DIRECT_DELAY;
            send(8);
            if (elapsed(since, CLOCKS_PER_SEC * 5)) {                 /* no answer: wait again */
                linked = 0;
                dline(21, COLOR_ORANGE, "No answer, waiting again.");
                if (drv == DRV_UCI) {
                    net_close_socket(peer);
                    lst = net_open_local("0.0.0.0", PORT_GAME, PORT_GAME);
                    net_use_socket(lst);
                } else
                    net_direct_begin();
            }
        }
        if (!rx()) continue;
        if (!linked && msg[0] == M_HELLO && msglen >= 5 && ours(1) && msglen >= 5 + msg[4] + 4) {
            take_nick(4);
            ipstr(peer_ip, msg + 5 + msg[4]);
            if (drv == DRV_UCI) {
                net_close_socket(lst);
                lst = 0xFF;
                peer = net_open_local(peer_ip, PORT_GAME, PORT_GAME);
                if (peer == 0xFF) {
                    lst = net_open_local("0.0.0.0", PORT_GAME, PORT_GAME);
                    net_use_socket(lst);
                    continue;
                }
                net_use_socket(peer);
            } else
                net_set_peer_mac(net_from_mac());
            linked = 1;
            last = 0;
            since = now();
            gotoxy(0, 21);
            cclearxy(0, 21, 40);
            gotoxy(0, 21);
            textcolor(COLOR_LIGHTGREEN);
            put_nick(peer_nick, 0);
            textcolor(COLOR_WHITE);
            if (drv == DRV_UCI) cprintf(" (%s)", peer_ip);
            cputs(" joins.");
            continue;
        }
        if (linked && msg[0] == M_START_ACK && msg[1] == session) {
            net_close_socket(ann);
            msg[0] = M_START; msg[1] = session; msg[2] = 0; msg[3] = 2; msg[4] = 3;
            msg[5] = seed0; msg[6] = seed1; msg[7] = DIRECT_DELAY;
            direct_start('h');
        }
    }
    net_close_socket(ann);
    net_close_socket(lst);
    net_close_socket(peer);
    net_use_socket(0xFF);
}

/* ------------------------------------------------------------------- join */

/* the host's IP typed in: 1 = ok */
static unsigned char ask_ip(void)
{
    title();
    cputs("Head-to-head: the host's IP address\r\n\r\n");
    if (!input(peer_ip, 15, 1) || !*peer_ip) return 0;
    strcpy(peer_nick, "host");
    return 1;
}

static void direct_join(unsigned char typed)
{
    unsigned char srch = 0xFF, peer = 0xFF, found = 0, n;
    clock_t last = 0, since = 0;
    char line[40];

    if (typed && !ask_ip()) return;
    title();
    cputs("Head-to-head: joining\r\n\r\n");
    if (drv == DRV_UCI) {
        ipstr(line, net_ipcfg());
        cprintf("This C64: %s\r\n", line);
    }
    net_direct_begin();
    dline(23, COLOR_YELLOW, typed ? "Calling the host. Key: back" : "Searching the host. Key: back");
search:
    if (drv == DRV_UCI && !typed) {
        srch = net_open_local("0.0.0.0", PORT_HERE, PORT_GAME);
        if (srch == 0xFF) { status("Cannot open the socket."); sleep(3); return; }
        net_use_socket(srch);
    }
    found = typed;
    for (;;) {
        if (any_key() && auto_mode != 'j') break;
        if (found == 1) {                                             /* connect to the host */
            if (drv == DRV_UCI) {
                net_close_socket(srch);
                srch = 0xFF;
                peer = net_open_local(peer_ip, PORT_GAME, PORT_GAME);
                if (peer == 0xFF) { status("Cannot open the socket."); sleep(3); break; }
                net_use_socket(peer);
            }
            found = 2;
            since = now();
            last = 0;
            gotoxy(0, 21);
            cclearxy(0, 21, 40);
            gotoxy(0, 21);
            cputs("Host: ");
            textcolor(COLOR_LIGHTGREEN);
            put_nick(peer_nick, 0);
            textcolor(COLOR_WHITE);
            if (drv == DRV_UCI) cprintf(" (%s)", peer_ip);
        }
        if (found == 2 && elapsed(last, CLOCKS_PER_SEC / 2)) {        /* HELLO every 0.5 s */
            last = now();
            n = put_nick_msg(4);
            put_hdr(M_HELLO);
            memcpy(msg + n, net_ipcfg(), 4);
            send(n + 4);
            if (!typed && elapsed(since, CLOCKS_PER_SEC * 4)) {       /* an old HERE: search again */
                dline(21, COLOR_ORANGE, "No answer, searching again.");
                if (drv == DRV_UCI) { net_close_socket(peer); peer = 0xFF; }
                else net_direct_begin();
                goto search;
            }
        }
        if (!rx()) continue;
        if (found == 0 && msg[0] == M_HERE && msglen >= 9 && ours(1)) {
            ipstr(peer_ip, msg + 4);
            take_nick(8);
            if (drv == DRV_RR) net_set_peer_mac(net_from_mac());
            found = 1;
            continue;
        }
        if (found == 2 && msg[0] == M_START && msglen >= 8 && msg[4] >= 3
            && (drv != DRV_RR || !memcmp(net_from_mac(), net_server_mac(), 6)))
            direct_start('j');
    }
    net_close_socket(srch);
    net_close_socket(peer);
    net_use_socket(0xFF);
}

/* ------------------------------------------------------------------ menu */

static void direct_menu(void)
{
    unsigned char key;
    char line[20];
    for (;;) {
        title();
        textcolor(COLOR_YELLOW);
        cputs("Head-to-head: two C64s, no server\r\n\r\n");
        textcolor(COLOR_WHITE);
        if (drv == DRV_UCI) {
            ipstr(line, net_ipcfg());
            cprintf("This C64: %s\r\n\r\n", line);
        }
        cputs("  1          host a game\r\n"
              "  2          join: search the host\r\n");
        if (drv == DRV_UCI) cputs("  3          join: type the host's IP\r\n");
        cputs("  <-         back\r\n");
        if (last_reason) {
            gotoxy(0, 21);
            textcolor(COLOR_YELLOW);
            cprintf("Last game: %s", end_text[last_reason]);
            textcolor(COLOR_WHITE);
            last_reason = 0;
        }
        if (auto_mode == 'h') key = '1';
        else if (auto_mode == 'j') key = '2';
        else key = cgetc();
        if (key == '1') direct_host();
        else if (key == '2') direct_join(0);
        else if (key == '3' && drv == DRV_UCI) direct_join(1);
        else if (key == 0x5F) return;                                 /* left arrow */
        net_disconnect();
    }
}
