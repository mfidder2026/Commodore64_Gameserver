/* Standard lobby: network layer over the Ultimate Command Interface, the WiC64 or RR-Net */
#ifndef NET_H
#define NET_H

#define DRV_NONE 0
#define DRV_UCI  1
#define DRV_RR   2
#define DRV_WIC  3

/* finds the hardware; RR-Net: makes up a MAC address if mac[0] == 0 */
unsigned char net_init(unsigned char *mac, const char *server);
/* text for the screen (Ultimate: our IP address) */
const char *net_info(void);
/* opens the "connection" to the server: 0 = ok
   (UDP port for the Ultimate; the WiC64 uses TCP on port + 1) */
unsigned char net_connect(const char *server, unsigned int port);
void net_disconnect(void);
void net_send(const unsigned char *data, unsigned char len);
/* a received message: length, 0 = nothing */
unsigned char net_recv(unsigned char *buf);
/* for the game: UCI socket, server MAC (RR-Net) */
unsigned char net_socket(void);
const unsigned char *net_server_mac(void);
void net_close_socket(unsigned char socket);

/* head-to-head, two C64s without the server (direct.c) */
unsigned char net_direct_ok(void);              /* RR-Net, or an Ultimate whose firmware has $0A */
const unsigned char *net_ipcfg(void);           /* Ultimate: IP address (4) and netmask (4) */
void net_direct_begin(void);                    /* RR-Net: broadcast, and hear every C64 */
/* Ultimate $0A: a UDP socket from local port lport to host:rport, 0xFF = failed */
unsigned char net_open_local(const char *host, unsigned int rport, unsigned int lport);
void net_use_socket(unsigned char s);           /* net_send / net_recv use this socket */
void net_set_peer_mac(const unsigned char *mac);/* RR-Net: send to this C64 (also the game's) */
const unsigned char *net_from_mac(void);        /* RR-Net: the sender of the last message */

/* loader.s */
void __fastcall__ start_game(const char *name);

#endif
