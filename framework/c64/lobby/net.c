/* Standard lobby: network layer (Ultimate Command Interface, RR-Net or WiC64) */
#include <string.h>
#include <stdio.h>
#include <peekpoke.h>
#include "net.h"

/* uci.s */
extern unsigned char uci_cmd[300];
extern unsigned int uci_cmdlen;
extern unsigned char uci_resp[300];
extern unsigned int uci_resplen;
extern unsigned char uci_stat[40];
extern unsigned char uci_statlen;
unsigned char uci_detect(void);
unsigned char uci_exec(void);

/* wic64.s */
extern unsigned char wic_cmd, wic_outlen, wic_out[255], wic_in[512];
extern unsigned int wic_inlen;
unsigned char wic_exec(void);

#define WIC_GET_IP    0x06
#define WIC_TCP_OPEN  0x21
#define WIC_TCP_READ  0x22
#define WIC_TCP_WRITE 0x23
#define WIC_TCP_CLOSE 0x2E
#define WIC_ECHO      0xFE

/* the TCP stream carries [length][message]; what is received but not yet
   handed out waits here */
static unsigned char stream[512];
static unsigned int stream_len;

/* rrnet.s */
extern unsigned char rr_mymac[6], rr_dst[6], rr_from[6];
extern unsigned char rr_txbuf[255], rr_txlen, rr_rxbuf[255], rr_rxlen;
unsigned char rr_init(void);
unsigned char rr_send(void);
unsigned char rr_poll(void);

#define UCI_NET     0x03
#define UCI_GETIP   0x05
#define UCI_OPENUDP 0x08
#define UCI_CLOSE   0x09
#define UCI_READ    0x10
#define UCI_WRITE   0x11
#define UCI_OPENLOCAL 0x0A  /* UDP from a fixed local port (firmware with GideonZ/1541ultimate#1016) */

static unsigned char drv;
static unsigned char sock = 0xFF;
static unsigned char server_known;
static unsigned char direct;            /* head-to-head: RR-Net takes frames from any C64 */
static unsigned char direct_ok;         /* the Ultimate's firmware has $0A */
static unsigned char ipcfg[8];          /* the Ultimate's IP address and netmask */
static char info[20];
static const unsigned char broadcast[6] = { 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };

/* status of the last UCI command: the two digits of "00,OK" */
static unsigned char uci_code(void)
{
    if (uci_statlen < 2) return 99;
    return (uci_stat[0] - '0') * 10 + (uci_stat[1] - '0');
}

static unsigned char uci(unsigned char cmd, unsigned char a)
{
    uci_cmd[0] = UCI_NET;
    uci_cmd[1] = cmd;
    uci_cmd[2] = a;
    uci_cmdlen = 3;
    if (uci_exec()) return 99;
    return uci_code();
}

static unsigned char wic(unsigned char cmd, unsigned char len)
{
    wic_cmd = cmd;
    wic_outlen = len;
    return wic_exec();
}

unsigned char net_init(unsigned char *mac, const char *server)
{
    (void)server;
    if (uci_detect()) {
        unsigned char i;
        drv = DRV_UCI;
        strcpy(info, "?");
        for (i = 0; i < 3; ++i)                 /* the first interface with an address (C64 Ultimate: 0 LAN, 1 Wi-Fi) */
            if (uci(UCI_GETIP, i) == 0 && uci_resplen >= 8 && uci_resp[0]) {
                memcpy(ipcfg, uci_resp, 8);
                sprintf(info, "%u.%u.%u.%u", uci_resp[0], uci_resp[1], uci_resp[2], uci_resp[3]);
                break;
            }
        /* $0A with remote port 0: new firmware answers 82, old firmware 21 (unknown command) */
        uci_cmd[0] = UCI_NET;
        uci_cmd[1] = UCI_OPENLOCAL;
        uci_cmd[2] = uci_cmd[3] = uci_cmd[4] = uci_cmd[5] = 0;
        uci_cmd[6] = '0';
        uci_cmdlen = 7;
        direct_ok = uci_exec() == 0 && uci_code() == 82;
        return drv;
    }
    if (!mac[0]) {                              /* make up a MAC address, once */
        unsigned char i;
        mac[0] = 0x02;                          /* locally administered, unicast */
        mac[1] = 0xC6;
        for (i = 2; i < 6; ++i) {
            unsigned int w = 0;
            while (w < 300 + PEEK(0xA2)) ++w;    /* let the timers run on */
            mac[i] = PEEK(0xD012) ^ PEEK(0xDC04) ^ PEEK(0xA2) ^ (unsigned char)(w * 7);
        }
    }
    memcpy(rr_mymac, mac, 6);
    if (rr_init() == 0) {
        drv = DRV_RR;
        strcpy(info, "rr-net");
        return drv;
    }
    wic_out[0] = 0x42;
    if (wic(WIC_ECHO, 1) == 0 && wic_inlen == 1 && wic_in[0] == 0x42) {
        drv = DRV_WIC;
        if (wic(WIC_GET_IP, 0) == 0 && wic_inlen < sizeof info) {
            memcpy(info, wic_in, wic_inlen);
            info[wic_inlen] = 0;
        } else
            strcpy(info, "?");
        return drv;
    }
    drv = DRV_NONE;
    return drv;
}

const char *net_info(void) { return info; }

unsigned char net_connect(const char *server, unsigned int port)
{
    unsigned char n;
    server_known = 0;
    if (drv == DRV_RR) {
        memcpy(rr_dst, broadcast, 6);          /* the HELLO finds the server */
        return 0;
    }
    if (drv == DRV_WIC) {
        n = sprintf((char *)wic_out, "%s:%u", server, port + 1);
        stream_len = 0;
        return wic(WIC_TCP_OPEN, n) != 0;
    }
    if (drv != DRV_UCI) return 1;
    n = strlen(server);
    uci_cmd[0] = UCI_NET;
    uci_cmd[1] = UCI_OPENUDP;
    uci_cmd[2] = port & 0xFF;
    uci_cmd[3] = port >> 8;
    memcpy(uci_cmd + 4, server, n);
    uci_cmdlen = 4 + n;
    if (uci_exec() || uci_code() != 0 || uci_resplen < 1) return 1;
    sock = uci_resp[0];
    return 0;
}

void net_close_socket(unsigned char s)
{
    if (drv == DRV_UCI && s != 0xFF) uci(UCI_CLOSE, s);
}

void net_disconnect(void)
{
    if (drv == DRV_WIC) wic(WIC_TCP_CLOSE, 0);
    net_close_socket(sock);
    sock = 0xFF;
    direct = 0;
}

void net_send(const unsigned char *data, unsigned char len)
{
    if (drv == DRV_RR) {
        memcpy(rr_txbuf, data, len);
        rr_txlen = len;
        rr_send();
    } else if (drv == DRV_WIC) {
        wic_out[0] = len;
        memcpy(wic_out + 1, data, len);
        wic(WIC_TCP_WRITE, len + 1);
    } else if (drv == DRV_UCI) {
        uci_cmd[0] = UCI_NET;
        uci_cmd[1] = UCI_WRITE;
        uci_cmd[2] = sock;
        memcpy(uci_cmd + 3, data, len);
        uci_cmdlen = 3 + len;
        uci_exec();
    }
}

unsigned char net_recv(unsigned char *buf)
{
    unsigned int n;
    if (drv == DRV_RR) {
        if (!rr_poll()) return 0;
        if (direct) {
            if (!memcmp(rr_from, rr_mymac, 6)) return 0;    /* our own broadcast */
        } else if (!server_known) {
            /* only the server's answer to our HELLO tells us where it is;
               other C64s broadcast their HELLOs too */
            if (rr_rxbuf[0] != 0x02 && rr_rxbuf[0] != 0x03) return 0;
            memcpy(rr_dst, rr_from, 6);
            server_known = 1;
        } else if (memcmp(rr_from, rr_dst, 6)) {
            return 0;
        }
        memcpy(buf, rr_rxbuf, rr_rxlen);
        return rr_rxlen;
    }
    if (drv == DRV_WIC) {
        unsigned char len;
        if (stream_len == 0 || stream_len < 1u + stream[0]) {
            /* no complete message waiting: fetch what has arrived */
            if (wic(WIC_TCP_READ, 0) == 0 && wic_inlen) {
                n = wic_inlen;
                if (n > sizeof stream - stream_len) n = sizeof stream - stream_len;
                memcpy(stream + stream_len, wic_in, n);
                stream_len += n;
            }
        }
        if (stream_len == 0 || stream_len < 1u + stream[0]) return 0;
        len = stream[0];
        memcpy(buf, stream + 1, len);
        stream_len -= 1 + len;
        memmove(stream, stream + 1 + len, stream_len);
        return len;
    }
    if (drv == DRV_UCI && sock != 0xFF) {
        uci_cmd[0] = UCI_NET;
        uci_cmd[1] = UCI_READ;
        uci_cmd[2] = sock;
        uci_cmd[3] = 255;
        uci_cmd[4] = 0;
        uci_cmdlen = 5;
        if (uci_exec() || uci_resplen < 3) return 0;
        n = uci_resp[0] | (uci_resp[1] << 8);
        if (n == 0 || n > 255 || n + 2 > uci_resplen) return 0;
        memcpy(buf, uci_resp + 2, n);
        return (unsigned char)n;
    }
    return 0;
}

unsigned char net_socket(void) { return sock; }

/* ---------------------------------------------- head-to-head (direct.c) */

unsigned char net_direct_ok(void) { return drv == DRV_RR || (drv == DRV_UCI && direct_ok); }

const unsigned char *net_ipcfg(void) { return ipcfg; }

void net_direct_begin(void)
{
    direct = 1;
    memcpy(rr_dst, broadcast, 6);
}

unsigned char net_open_local(const char *host, unsigned int rport, unsigned int lport)
{
    unsigned char n = strlen(host);
    uci_cmd[0] = UCI_NET;
    uci_cmd[1] = UCI_OPENLOCAL;
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

void net_use_socket(unsigned char s) { sock = s; }

void net_set_peer_mac(const unsigned char *mac) { memcpy(rr_dst, mac, 6); }

const unsigned char *net_from_mac(void) { return rr_from; }

const unsigned char *net_server_mac(void) { return rr_dst; }
