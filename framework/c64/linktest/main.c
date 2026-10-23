/*
 * C64 Ultimate link test: two C64s find each other on the LAN and measure the link.
 *
 * The C64 Ultimate (Command Interface, network target $03) with the command
 * OPEN_UDP_LOCAL ($0A, firmware with GideonZ/1541ultimate#1016): a UDP socket
 * from a fixed local port, so two Ultimates can talk directly (6464 <-> 6464).
 * In VICE (no Command Interface): RR-Net, raw Ethernet frames (EtherType $88B5).
 *
 * Finding the other C64 ("scan"): a $0A socket is connected, it only receives
 * from the address it was opened to. Two tries that the firmware may or may not
 * allow (the screen shows each step's status):
 *   CLIENT opens $0A to 0.0.0.0, remote 6465, local 6464: "any address" (lwIP
 *          matches a connected socket with an "any" remote against every sender)
 *   HOST   sends HELLO (with its IP) from local port 6465 to the subnet's
 *          broadcast address, port 6464, and listens on 0.0.0.0:6464
 * The CLIENT answers with ACK (its IP); then both open $0A to each other,
 * 6464 <-> 6464. Manual: enter the other C64's IP address on both (key I).
 *
 * Messages (UDP payload or the RR-Net frame's message):
 *   'L' 'T' type seq(2) time(4) ip(4) name(8) [data]   (21 bytes before the data)
 *   type 1 HELLO, 2 ACK, 3 PING, 4 PONG (time = the PING's), 5 BYE, 6 DATA
 */
#include <conio.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <peekpoke.h>

/* uci.s (framework/c64/lobby) */
extern unsigned char uci_cmd[300];
extern unsigned int uci_cmdlen;
extern unsigned char uci_resp[300];
extern unsigned int uci_resplen;
extern unsigned char uci_stat[40];
extern unsigned char uci_statlen;
unsigned char uci_detect(void);
unsigned char uci_exec(void);

/* rrnet.s (framework/c64/lobby) */
extern unsigned char rr_mymac[6], rr_dst[6], rr_from[6];
extern unsigned char rr_txbuf[255], rr_txlen, rr_rxbuf[255], rr_rxlen;
unsigned char rr_init(void);
unsigned char rr_send(void);
unsigned char rr_poll(void);

/* timer.s */
void timer_init(void);
unsigned long timer_now(void);

#define PORT_LINK   6464
#define PORT_HELLO  6465

#define NET_IDENTIFY   0x01
#define NET_IFCOUNT    0x02
#define NET_GETMAC     0x04
#define NET_GETIP      0x05
#define NET_OPEN_UDP   0x08
#define NET_CLOSE      0x09
#define NET_OPEN_LOCAL 0x0A
#define NET_READ       0x10
#define NET_WRITE      0x11

#define T_HELLO 1
#define T_ACK   2
#define T_PING  3
#define T_PONG  4
#define T_BYE   5
#define T_DATA  6
#define HDR     21              /* bytes before the data */

#define R_FAIL  0               /* host(), client(), manual() */
#define R_OK    1
#define R_BACK  2

#define DRV_NONE 0
#define DRV_UCI  1
#define DRV_RR   2

static unsigned char drv;
static unsigned char ifcount, ifsel = 0xFF;
static unsigned char myip[4], mymask[4], mygw[4], mymac[6];
static char myname[9];
static unsigned char local_ok;          /* firmware knows $0A */
static char device[40];
static unsigned long cps;               /* cycles per second */

static unsigned char peerip[4];
static char peername[9];
static unsigned char sock = 0xFF, sock2 = 0xFF;
static unsigned char pkt[220], rx[256];
static unsigned char rxlen;
static const unsigned char bcast_mac[6] = { 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };

/* --- screen ---------------------------------------------------------------- */
static void header(const char *title)
{
    unsigned char i;
    clrscr();
    gotoxy(0, 0);
    textcolor(COLOR_YELLOW);
    revers(1);
    cputs(" C64 ULTIMATE  * LINK TEST *  ");
    textcolor(COLOR_LIGHTRED);
    cputs("V1.1     ");
    revers(0);
    gotoxy(0, 1);
    textcolor(COLOR_CYAN);
    cputs(title);
    gotoxy(0, 2);
    textcolor(COLOR_GRAY1);
    for (i = 0; i < 40; ++i) cputc(0xC0);   /* a line */
}

static void footer(const char *text)
{
    gotoxy(0, 24);
    textcolor(COLOR_LIGHTBLUE);
    cclear(39);
    gotoxy(0, 24);
    cputs(text);
}

static void label(unsigned char x, unsigned char y, const char *s)
{
    gotoxy(x, y);
    textcolor(COLOR_GRAY3);
    cputs(s);
}

static void value(unsigned char color, const char *s)
{
    textcolor(color);
    cputs(s);
}

static char tmp[48];
static const char *ipstr(const unsigned char *ip)
{
    sprintf(tmp, "%u.%u.%u.%u", ip[0], ip[1], ip[2], ip[3]);
    return tmp;
}

/* a log line in the scrolling area (rows 4-21) */
static unsigned char logy = 4;
static void logline(unsigned char color, const char *s)
{
    if (logy > 21) {
        /* scroll rows 5-21 up: simply start again below the title */
        unsigned char y;
        for (y = 4; y <= 21; ++y) cclearxy(0, y, 40);
        logy = 4;
    }
    gotoxy(1, logy++);
    textcolor(color);
    cputs(s);
}

/* --- the Command Interface --------------------------------------------------- */
static unsigned char uci_code(void)
{
    if (uci_statlen < 2) return 99;
    return (uci_stat[0] - '0') * 10 + (uci_stat[1] - '0');
}

static const char *uci_text(void)
{
    unsigned char n = uci_statlen < 30 ? uci_statlen : 30;
    memcpy(tmp, uci_stat, n);
    tmp[n] = 0;
    return tmp;
}

static unsigned char uci(unsigned char cmd, unsigned char a, unsigned char len)
{
    uci_cmd[0] = 0x03;
    uci_cmd[1] = cmd;
    uci_cmd[2] = a;
    uci_cmdlen = len;
    if (uci_exec()) return 99;
    return uci_code();
}

/* $0A: a UDP socket from local port lport to host:rport; 0xFF = failed (the status is in uci_stat) */
static unsigned char open_local(const char *host, unsigned int rport, unsigned int lport)
{
    unsigned char n = strlen(host);
    uci_cmd[0] = 0x03;
    uci_cmd[1] = NET_OPEN_LOCAL;
    uci_cmd[2] = rport & 0xFF;
    uci_cmd[3] = rport >> 8;
    uci_cmd[4] = lport & 0xFF;
    uci_cmd[5] = lport >> 8;
    memcpy(uci_cmd + 6, host, n);
    uci_cmd[6 + n] = 0;
    uci_cmdlen = 7 + n;
    if (uci_exec() || uci_code() != 0 || uci_resplen < 1) return 0xFF;
    return uci_resp[0];
}

static void close_socket(unsigned char *s)
{
    if (*s != 0xFF) uci(NET_CLOSE, *s, 3);
    *s = 0xFF;
}

/* time of the last UCI write and read, in cycles */
static unsigned long t_write, t_read;

static void sock_send(unsigned char s, unsigned char len)
{
    unsigned long t = timer_now();
    if (drv == DRV_RR) {
        memcpy(rr_txbuf, pkt, len);
        rr_txlen = len;
        rr_send();
    } else {
        uci_cmd[0] = 0x03;
        uci_cmd[1] = NET_WRITE;
        uci_cmd[2] = s;
        memcpy(uci_cmd + 3, pkt, len);
        uci_cmdlen = 3 + len;
        uci_exec();
    }
    t_write = timer_now() - t;
}

/* a message into rx/rxlen: 1 = yes; rx_any: a datagram came at all (also one
   that does not count), so more may be waiting */
static unsigned char rx_any;
static unsigned char sock_recv(unsigned char s)
{
    unsigned int n;
    unsigned long t = timer_now();
    rx_any = 0;
    if (drv == DRV_RR) {
        if (!rr_poll()) return 0;
        rx_any = 1;
        t_read = timer_now() - t;
        memcpy(rx, rr_rxbuf, rr_rxlen);
        rxlen = rr_rxlen;
    } else {
        if (s == 0xFF) return 0;
        uci_cmd[0] = 0x03;
        uci_cmd[1] = NET_READ;
        uci_cmd[2] = s;
        uci_cmd[3] = 255;
        uci_cmd[4] = 0;
        uci_cmdlen = 5;
        if (uci_exec()) return 0;
        t_read = timer_now() - t;
        if (uci_resplen < 3) return 0;
        n = uci_resp[0] | (uci_resp[1] << 8);
        if (n == 0 || n > 255 || n + 2 > uci_resplen) return 0;
        rx_any = 1;
        memcpy(rx, uci_resp + 2, n);
        rxlen = (unsigned char)n;
    }
    if (rxlen < HDR || rx[0] != 'L' || rx[1] != 'T') return 0;
    if (drv == DRV_RR ? !memcmp(rr_from, mymac, 6) : !memcmp(rx + 9, myip, 4)) return 0;
    return 1;
}

/* forget what arrived before: an old HELLO must not start a link (RR-Net: the
   chip's buffer; an Ultimate socket was just opened, it has nothing old) */
static void flush(unsigned char s)
{
    unsigned long t = timer_now();
    (void)s;
    if (drv == DRV_RR)                          /* 0.1 s: rr_poll() also answers 0 for */
        while (timer_now() - t < cps / 10)      /* other frames on the network (ARP ...) */
            rr_poll();
}

/* RR-Net: a MAC address of our own, made when a key starts the search (two
   VICEs started the same way would otherwise make the same one) */
static void rr_newmac(void)
{
    unsigned long t;
    if (drv != DRV_RR) return;
    t = timer_now();
    rr_mymac[0] = 0x02;                         /* locally administered, unicast */
    rr_mymac[1] = 0x4C;
    rr_mymac[2] = (unsigned char)t ^ PEEK(0xD012);
    rr_mymac[3] = (unsigned char)(t >> 8) ^ PEEK(0xDC04);
    rr_mymac[4] = (unsigned char)(t >> 16) ^ (unsigned char)t;
    rr_mymac[5] = (unsigned char)(t >> 24) ^ PEEK(0xDC05) ^ (unsigned char)(t >> 3);
    rr_init();
    memcpy(mymac, rr_mymac, 6);
    sprintf(myname, "C64-%02X%02X", mymac[4], mymac[5]);
}

/* --- messages ---------------------------------------------------------------- */
static void make(unsigned char type, unsigned int seq, unsigned long time)
{
    pkt[0] = 'L';
    pkt[1] = 'T';
    pkt[2] = type;
    pkt[3] = seq & 0xFF;
    pkt[4] = seq >> 8;
    memcpy(pkt + 5, &time, 4);
    memcpy(pkt + 9, myip, 4);
    memcpy(pkt + 13, myname, 8);
}

/* --- hardware ---------------------------------------------------------------- */
static void hardware(void)
{
    unsigned char i, y;
    static unsigned char rr_done;
    header("THE NETWORK OF THIS C64");
    if (uci_detect()) {
        drv = DRV_UCI;
        uci(NET_IDENTIFY, 0, 2);
        i = uci_resplen < 38 ? uci_resplen : 38;
        memcpy(device, uci_resp, i);
        device[i] = 0;
        ifcount = uci(NET_IFCOUNT, 0, 2) == 0 && uci_resplen ? uci_resp[0] : 0;
    } else {
        unsigned char m;
        if (!rr_done) {
            rr_mymac[0] = 0x02;                 /* a made-up MAC, locally administered */
            rr_mymac[1] = 0x4C;
            for (m = 2; m < 6; ++m) rr_mymac[m] = PEEK(0xD012) ^ PEEK(0xDC04) ^ (m * 37);
        }
        if (rr_done || rr_init() == 0) {
            rr_done = 1;
            drv = DRV_RR;
            strcpy(device, "RR-NET, RAW ETHERNET (VICE)");
            memcpy(mymac, rr_mymac, 6);
        } else {
            drv = DRV_NONE;
        }
    }

    label(0, 4, "DEVICE    ");
    if (drv == DRV_NONE) {
        value(COLOR_LIGHTRED, "NO NETWORK FOUND");
        footer("NO COMMAND INTERFACE, NO RR-NET.");
        return;
    }
    value(COLOR_WHITE, device);
    y = 6;
    if (drv == DRV_UCI) {
        label(0, 5, "INTERFACES");
        sprintf(tmp, "%u", ifcount);
        value(COLOR_WHITE, tmp);
        for (i = 0; i < ifcount && i < 3; ++i) {
            unsigned char ip[12], mac[6], hasip;
            hasip = uci(NET_GETIP, i, 3) == 0 && uci_resplen >= 12;
            if (hasip) memcpy(ip, uci_resp, 12);
            if (uci(NET_GETMAC, i, 3) == 0 && uci_resplen >= 6) memcpy(mac, uci_resp, 6);
            else memset(mac, 0, 6);
            gotoxy(0, y);
            textcolor(COLOR_YELLOW);
            cprintf("#%u ", i);
            textcolor(COLOR_LIGHTGREEN);
            cprintf("%02X:%02X:%02X:%02X:%02X:%02X", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
            gotoxy(3, y + 1);
            if (hasip && ip[0]) {
                value(COLOR_WHITE, ipstr(ip));
                textcolor(COLOR_GRAY2);
                cprintf("/%u.%u.%u.%u", ip[4], ip[5], ip[6], ip[7]);
                gotoxy(3, y + 2);
                label(3, y + 2, "GATEWAY ");
                value(COLOR_WHITE, ipstr(ip + 8));
                if (ifsel == 0xFF) {            /* the first interface with an address */
                    ifsel = i;
                    memcpy(myip, ip, 4);
                    memcpy(mymask, ip + 4, 4);
                    memcpy(mygw, ip + 8, 4);
                    memcpy(mymac, mac, 6);
                }
            } else {
                value(COLOR_ORANGE, "NO ADDRESS (OFF OR NOT CONNECTED)");
            }
            y += 3;
        }
        /* $0A: remote port 0 answers 82 on new firmware, 21 on old */
        uci_cmd[0] = 0x03;
        uci_cmd[1] = NET_OPEN_LOCAL;
        uci_cmd[2] = uci_cmd[3] = uci_cmd[4] = uci_cmd[5] = 0;
        uci_cmd[6] = '0';
        uci_cmdlen = 7;
        local_ok = uci_exec() == 0 && uci_code() == 82;
        label(0, y + 1, "DIRECT LINK ($0A) ");
        if (local_ok) value(COLOR_LIGHTGREEN, "SUPPORTED");
        else {
            value(COLOR_LIGHTRED, "NOT IN THIS FIRMWARE");
            gotoxy(0, y + 2);
            value(COLOR_GRAY2, "(STATUS ");
            value(COLOR_GRAY2, uci_text());
            value(COLOR_GRAY2, ")");
        }
    } else {
        label(0, 5, "MAC       ");
        gotoxy(10, 5);
        textcolor(COLOR_LIGHTGREEN);
        cprintf("%02X:%02X:%02X:%02X:%02X:%02X", mymac[0], mymac[1], mymac[2], mymac[3], mymac[4], mymac[5]);
        label(0, 7, "DIRECT LINK       ");
        value(COLOR_LIGHTGREEN, "BY ETHERNET ADDRESS");
        local_ok = 1;
        y = 8;
    }
    sprintf(myname, "C64-%02X%02X", mymac[4], mymac[5]);
    label(0, y + 3, "THIS C64  ");
    value(COLOR_YELLOW, myname);
    if (drv == DRV_UCI && ifsel != 0xFF) {
        value(COLOR_GRAY2, "  ");
        value(COLOR_WHITE, ipstr(myip));
    }
}

/* --- finding the other C64 ------------------------------------------------------ */
static unsigned char step(const char *what, unsigned char ok)
{
    char line[40];
    sprintf(line, "%-28s", what);
    logline(COLOR_WHITE, line);
    gotoxy(30, logy - 1);
    if (ok) value(COLOR_LIGHTGREEN, "OK");
    else {
        value(COLOR_LIGHTRED, "FAILED");
        if (drv == DRV_UCI) logline(COLOR_GRAY2, uci_text());
    }
    return ok;
}

/* a key, letters as cc65's lower case ('a'-'z' = PETSCII $41-$5A; shifted: $C1-$DA) */
static unsigned char key(void)
{
    unsigned char c = cgetc();
    return c >= 0xC1 && c <= 0xDA ? c - 0x80 : c;
}

static unsigned char key_q(void)
{
    return kbhit() && key() == 'q';
}

/* the other C64 answered: its IP and name are in rx */
static void peer_from_rx(void)
{
    memcpy(peerip, rx + 9, 4);
    memcpy(peername, rx + 13, 8);
    peername[8] = 0;
    if (drv == DRV_RR) memcpy(rr_dst, rr_from, 6);
}

static unsigned char connect_peer(void)
{
    char host[16];
    if (drv == DRV_RR) return 1;
    strcpy(host, ipstr(peerip));
    sock = open_local(host, PORT_LINK, PORT_LINK);
    sprintf(tmp, "OPEN %s:%u", host, PORT_LINK);
    return step(tmp, sock != 0xFF);
}

static unsigned char host(void)
{
    char host[16];
    unsigned long last = 0;
    unsigned int n = 0;
    header("HOST: SEARCHING THE OTHER C64");
    footer("Q: BACK");
    logy = 4;
    if (drv == DRV_UCI) {
        unsigned char b[4], i;
        for (i = 0; i < 4; ++i) b[i] = myip[i] | (unsigned char)~mymask[i];
        strcpy(host, ipstr(b));
        sprintf(tmp, "SEND TO %s:%u", host, PORT_LINK);
        if (!step(tmp, (sock2 = open_local(host, PORT_LINK, PORT_HELLO)) != 0xFF)) return R_FAIL;
        if (!step("LISTEN ON 0.0.0.0:6464", (sock = open_local("0.0.0.0", PORT_LINK, PORT_LINK)) != 0xFF)) {
            close_socket(&sock2);
            return R_FAIL;
        }
    } else {
        memcpy(rr_dst, bcast_mac, 6);
        step("ETHERNET BROADCAST", 1);
    }
    flush(sock);
    logline(COLOR_YELLOW, "SENDING HELLO...");
    for (;;) {
        if (key_q()) break;
        if (timer_now() - last > cps / 2) {         /* a HELLO every 0.5 s */
            last = timer_now();
            make(T_HELLO, n++, last);
            sock_send(sock2 == 0xFF ? sock : sock2, HDR);
            gotoxy(17, logy - 1);
            textcolor(COLOR_GRAY2);
            cprintf("%u", n);
        }
        if (sock_recv(sock) && rx[2] == T_ACK) {
            peer_from_rx();
            sprintf(tmp, "ANSWER FROM %s", peername);
            logline(COLOR_LIGHTGREEN, tmp);
            if (drv == DRV_UCI) {
                logline(COLOR_LIGHTGREEN, ipstr(peerip));
                close_socket(&sock);
                close_socket(&sock2);
                return connect_peer();
            }
            return R_OK;
        }
    }
    close_socket(&sock);
    close_socket(&sock2);
    return R_BACK;
}

/* the CLIENT's socket that hears HELLOs from any HOST (Ultimate: $0A to 0.0.0.0) */
static unsigned char client_listen(void)
{
    if (drv != DRV_UCI) return 1;
    sock = open_local("0.0.0.0", PORT_HELLO, PORT_LINK);
    return sock != 0xFF;
}

static unsigned char client(void)
{
    unsigned long t;
    unsigned char k;
    header("CLIENT: WAITING TO BE FOUND");
    footer("Q: BACK");
    logy = 4;
    if (drv == DRV_UCI) {
        if (!step("LISTEN ON 0.0.0.0:6464", client_listen())) return R_FAIL;
        sprintf(tmp, "THIS C64: %s", ipstr(myip));
        logline(COLOR_YELLOW, tmp);
    } else {
        step("ETHERNET BROADCAST", 1);
    }
    flush(sock);
    logline(COLOR_YELLOW, "WAITING FOR A HELLO...");
    for (;;) {
        if (key_q()) break;
        if (!sock_recv(sock) || rx[2] != T_HELLO) continue;
        peer_from_rx();
        sprintf(tmp, "HELLO FROM %s", peername);
        logline(COLOR_LIGHTGREEN, tmp);
        if (drv == DRV_UCI) {
            logline(COLOR_LIGHTGREEN, ipstr(peerip));
            close_socket(&sock);
            if (!connect_peer()) return R_FAIL;
        }
        for (k = 0; k < 3; ++k) {               /* the ACK three times: the HOST needs one */
            make(T_ACK, k, timer_now());
            sock_send(sock, HDR);
            t = timer_now();
            while (timer_now() - t < cps / 10) ;
        }
        /* the HOST answers with its PINGs. A HELLO can be old (a HOST that stopped
           searching; VICE delivers frames late): then nothing comes back */
        t = timer_now();
        while (timer_now() - t < 3 * cps) {
            if (key_q()) goto back;
            if (sock_recv(sock) && (rx[2] == T_PING || rx[2] == T_PONG)
                && (drv != DRV_RR || !memcmp(rr_from, rr_dst, 6)))
                return R_OK;
        }
        logline(COLOR_ORANGE, "NO ANSWER: WAITING AGAIN");
        if (drv == DRV_UCI) {
            close_socket(&sock);
            if (!step("LISTEN ON 0.0.0.0:6464", client_listen())) return R_FAIL;
        }
    }
back:
    close_socket(&sock);
    return R_BACK;
}

static unsigned char manual(void)
{
    char line[16];
    unsigned char n = 0, c, ip[4], i;
    unsigned int v;
    char *p;
    header("DIRECT: THE OTHER C64'S IP ADDRESS");
    footer("RETURN: CONNECT   Q: BACK");
    label(1, 5, "THIS C64   ");
    value(COLOR_WHITE, ipstr(myip));
    label(1, 7, "OTHER C64  ");
    sprintf(line, "%u.%u.%u.", myip[0], myip[1], myip[2]);
    n = strlen(line);
    for (;;) {
        gotoxy(12, 7);
        textcolor(COLOR_YELLOW);
        cputs(line);
        cputc(' ');
        gotoxy(12 + n, 7);
        cursor(1);
        c = key();
        cursor(0);
        if (c == 'q') return R_BACK;
        if (c == CH_DEL && n) line[--n] = 0;
        else if (((c >= '0' && c <= '9') || c == '.') && n < 15) { line[n++] = c; line[n] = 0; }
        else if (c == CH_ENTER) break;
    }
    p = line;
    for (i = 0; i < 4; ++i) {
        v = atoi(p);
        if (v > 255) return R_FAIL;
        ip[i] = v;
        p = strchr(p, '.');
        if (!p && i < 3) return R_FAIL;
        if (p) ++p;
    }
    memcpy(peerip, ip, 4);
    strcpy(peername, "?");
    logy = 9;
    return connect_peer();
}

/* --- the link ------------------------------------------------------------------ */
static unsigned long ms(unsigned long cycles)
{
    return cycles / (cps / 1000);
}

static void stat(unsigned char y, const char *name, unsigned char color, const char *v)
{
    gotoxy(1, y);
    textcolor(COLOR_GRAY3);
    cputs(name);
    gotoxy(17, y);
    textcolor(color);
    cputs(v);
    cclear(40 - wherex());
}

static void link(void)
{
    unsigned int seq = 0, rx_ping = 0, last_seq = 0xFFFF, gaps = 0;
    unsigned int sent = 0, pongs = 0, data_rx = 0;
    unsigned long rtt, rtt_min = 0xFFFFFFFF, rtt_max = 0, rtt_sum = 0, rtt_last = 0;
    unsigned long last_ping = 0, last_heard = 0, now, data_t0 = 0, data_t1 = 0;
    unsigned long w_max = 0, r_max = 0;
    unsigned int interval = 10;                 /* PINGs per second */
    unsigned char burst = 0, c, n, line = 0, named = peername[0] != '?';

    header("LINK TEST");
    gotoxy(0, 1);
    textcolor(COLOR_CYAN);
    cprintf("LINK WITH %s", peername);
    if (drv == DRV_UCI) cprintf(" %s", ipstr(peerip));
    footer("+/-: RATE  T: 100 X 200 B  R: RESET  Q");
    stat(22, "DEVICE", COLOR_GRAY2, drv == DRV_UCI ? "ULTIMATE $0A 6464<>6464" : "RR-NET, RAW ETHERNET");
    last_heard = timer_now();
    for (;;) {
        now = timer_now();
        if (kbhit()) {
            c = key();
            if (c == 'q') break;
            if (c == '+' && interval < 50) interval += 5;
            if (c == '-' && interval > 5) interval -= 5;
            if (c == 'r') {
                seq = rx_ping = gaps = sent = pongs = data_rx = 0;
                last_seq = 0xFFFF;
                rtt_min = 0xFFFFFFFF;
                rtt_max = rtt_sum = rtt_last = w_max = r_max = 0;
                cclearxy(0, 19, 40);
                cclearxy(0, 20, 40);
            }
            if (c == 't') burst = 100;
        }
        if (burst) {                            /* throughput: as fast as it goes */
            make(T_DATA, burst, now);
            memset(pkt + HDR, burst, 200);
            sock_send(sock, HDR + 200);
            --burst;
        } else if (now - last_ping > cps / interval) {
            last_ping = now;
            make(T_PING, seq++, now);
            sock_send(sock, HDR);
            ++sent;
            if (t_write > w_max) w_max = t_write;
        }
        /* everything that is waiting (up to 8): reading less than arrives makes a
           queue, and the round trip grows with it. An empty UCI read waits 40 ms. */
        for (n = 0; n < 8; ++n) {
            if (!sock_recv(sock)) {
                if (rx_any) continue;           /* one that does not count: more may wait */
                break;
            }
            now = timer_now();
            last_heard = now;
            if (t_read > r_max) r_max = t_read;
            if (!named) {                       /* found by its IP: its name comes along */
                memcpy(peername, rx + 13, 8);
                peername[8] = 0;
                gotoxy(10, 1);
                textcolor(COLOR_CYAN);
                cputs(peername);
                if (drv == DRV_UCI) cprintf(" %s", ipstr(peerip));
                named = 1;
            }
            switch (rx[2]) {
            case T_PING:
                ++rx_ping;
                {
                    unsigned int s = rx[3] | (rx[4] << 8);
                    if (last_seq != 0xFFFF && s != (unsigned int)(last_seq + 1)) ++gaps;
                    last_seq = s;
                }
                pkt[0] = 'L'; pkt[1] = 'T';
                memcpy(pkt + 2, rx + 2, HDR - 2);
                pkt[2] = T_PONG;
                memcpy(pkt + 9, myip, 4);
                memcpy(pkt + 13, myname, 8);
                sock_send(sock, HDR);
                break;
            case T_PONG:
                ++pongs;
                memcpy(&rtt, rx + 5, 4);
                rtt = now - rtt;
                rtt_last = rtt;
                rtt_sum += rtt;
                if (rtt < rtt_min) rtt_min = rtt;
                if (rtt > rtt_max) rtt_max = rtt;
                break;
            case T_DATA:
                if (!data_rx) data_t0 = now;
                data_t1 = now;
                ++data_rx;
                break;
            case T_BYE:
                goto bye;
            }
        }
        /* the screen: one line per pass (sprintf with longs is slow on a 6502;
           drawing everything at once kept the loop from reading) */
        switch (line) {
        case 0:
            stat(4, "STATE", now - last_heard < 2 * cps ? COLOR_LIGHTGREEN : COLOR_LIGHTRED,
                 now - last_heard < 2 * cps ? "CONNECTED" : "NO ANSWER");
            break;
        case 1:
            sprintf(tmp, "%u / S", interval);
            stat(6, "PING RATE", COLOR_WHITE, tmp);
            break;
        case 2:
            sprintf(tmp, "%u", sent);
            stat(7, "PINGS SENT", COLOR_WHITE, tmp);
            break;
        case 3:
            sprintf(tmp, "%u", pongs);
            stat(8, "PONGS BACK", COLOR_WHITE, tmp);
            break;
        case 4:
            sprintf(tmp, "%u.%u %%", sent ? (unsigned)((sent - pongs) * 100UL / sent) : 0,
                    sent ? (unsigned)((sent - pongs) * 1000UL / sent % 10) : 0);
            stat(9, "LOST (+ ON WAY)", sent - pongs > 2 ? COLOR_ORANGE : COLOR_LIGHTGREEN, tmp);
            break;
        case 5:
            if (pongs) {
                sprintf(tmp, "%lu MS", ms(rtt_last));
                stat(11, "ROUND TRIP NOW", COLOR_YELLOW, tmp);
            }
            break;
        case 6:
            if (pongs) {
                sprintf(tmp, "%lu / %lu / %lu MS", ms(rtt_min), ms(rtt_sum / pongs), ms(rtt_max));
                stat(12, "MIN / AVG / MAX", COLOR_YELLOW, tmp);
            }
            break;
        case 7:
            sprintf(tmp, "%u  (GAPS %u)", rx_ping, gaps);
            stat(14, "PINGS RECEIVED", COLOR_LIGHTBLUE, tmp);
            break;
        case 8:
            sprintf(tmp, "%lu.%lu / %lu.%lu MS", ms(t_write), ms(t_write * 10) % 10, ms(w_max), ms(w_max * 10) % 10);
            stat(16, "WRITE NOW / MAX", COLOR_PURPLE, tmp);
            break;
        case 9:
            sprintf(tmp, "%lu.%lu / %lu.%lu MS", ms(t_read), ms(t_read * 10) % 10, ms(r_max), ms(r_max * 10) % 10);
            stat(17, "READ NOW / MAX", COLOR_PURPLE, tmp);
            break;
        case 10:
            if (data_rx) {
                unsigned long t = ms(data_t1 - data_t0);
                sprintf(tmp, "%u X 200 B", data_rx);
                stat(19, "DATA RECEIVED", COLOR_LIGHTGREEN, tmp);
                if (t && data_rx > 1)
                    sprintf(tmp, "%lu BYTES/S", (unsigned long)(data_rx - 1) * 200000UL / t);
                else
                    strcpy(tmp, "-");
                stat(20, "SPEED", COLOR_LIGHTGREEN, tmp);
            }
            break;
        }
        if (++line > 10) line = 0;
    }
    make(T_BYE, 0, 0);
    sock_send(sock, HDR);
bye:
    close_socket(&sock);
}

/* --- menu ---------------------------------------------------------------------- */
int main(void)
{
    unsigned char c, ok;
    bgcolor(COLOR_BLACK);
    bordercolor(COLOR_BLACK);
    POKE(0xD018, 0x17);                         /* upper and lower case: cc65's text */
    timer_init();
    cps = PEEK(0x02A6) ? 985248UL : 1022727UL;  /* PAL or NTSC */
    for (;;) {
        hardware();
        if (drv == DRV_NONE) {
            cgetc();
            return 0;
        }
        gotoxy(0, 20);
        textcolor(COLOR_YELLOW);
        cputs(" H ");
        value(COLOR_WHITE, "HOST: SEARCH THE OTHER C64");
        gotoxy(0, 21);
        textcolor(COLOR_YELLOW);
        cputs(" C ");
        value(COLOR_WHITE, "CLIENT: WAIT TO BE FOUND");
        if (drv == DRV_UCI) {
            gotoxy(0, 22);
            textcolor(COLOR_YELLOW);
            cputs(" I ");
            value(COLOR_WHITE, "ENTER THE OTHER C64'S IP");
        }
        gotoxy(0, 18);
        textcolor(COLOR_GRAY2);
        cputs("        FOR THE COMMODORE 64 ULTIMATE");
        footer(drv == DRV_UCI ? "WIFI/LAN: ULTIMATE MENU (F2).    Q: END" : "Q: END");
        c = key();
        ok = 0;
        if (c == 'q') break;
        if (!local_ok && (c == 'h' || c == 'c' || c == 'i')) {
            footer("NEEDS FIRMWARE WITH $0A.  PRESS A KEY");
            cgetc();
            continue;
        }
        if (c == 'h' || c == 'c') rr_newmac();
        if (c == 'h') ok = host();
        else if (c == 'c') ok = client();
        else if (c == 'i' && drv == DRV_UCI) ok = manual();
        else continue;
        if (ok == R_OK) link();
        else if (ok == R_FAIL) {
            footer("PRESS A KEY");
            cgetc();
        }
    }
    clrscr();
    return 0;
}
