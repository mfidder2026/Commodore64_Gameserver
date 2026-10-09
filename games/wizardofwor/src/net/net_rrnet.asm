;============================================================
;
; NET: RR-NET BACKEND (ip65 UDP stack, for VICE and RR-Net)
;
; Same calls as the UCI backend (uci.asm) so nettest and later
; the game can use either. UDP only: ip65's TCP waits for the
; ACK of every packet (stop-and-wait), unusable for a game.
;
; The blob (build/ip65_*.bin, see src/net/ip65_glue.s) must be
; included at IP65_BLOB_START, with the generated include file
; for its labels (ip65.xxx).
;
; UDP and the Ultimate: an Ultimate UDP socket sends from its
; own (ephemeral) source port, so we answer to the source port
; of the last packet from the peer instead of a fixed port.
;
; Interface (same as uci.asm where it applies)
;   net_detect          C=0: RR-Net found (also initializes it, A = last MAC byte)
;   net_dhcp            C=0: got an address
;   net_set_ip          ip config from net_ipcfg (ip, netmask, gateway: 12 bytes)
;   net_get_ip          current config -> net_ipcfg
;   net_open            UDP "socket" to net_host (dotted ip), port net_port
;   net_listen          UDP on net_port, the first sender becomes the peer (host)
;   net_close
;   net_write           net_tx_buf / net_tx_len, C=1: failed
;   net_read_start      (nothing to do)
;   net_read_poll       C=1: nothing yet; C=0, A=0: datagram at net_rx_ptr/net_rx_len
;
;============================================================

	IP65_JT_INIT = IP65_BLOB_START + 0
	IP65_JT_DHCP = IP65_BLOB_START + 3
	IP65_JT_PROCESS = IP65_BLOB_START + 6
	IP65_JT_LISTEN = IP65_BLOB_START + 9
	IP65_JT_SEND = IP65_BLOB_START + 12
	IP65_JT_UNLISTEN = IP65_BLOB_START + 15

	NET_SEND_RETRIES = 200 ; ip65_process + retry while the ARP lookup of the peer is pending

; -----------------------------------------

net_detect .proc
	; A = last byte of the MAC address
	JSR IP65_JT_INIT
	RTS
.pend

net_dhcp .proc
	JSR IP65_JT_DHCP
	RTS
.pend

net_set_ip .proc
	LDX #3
-	LDA net_ipcfg,X
	STA ip65.cfg_ip,X
	LDA net_ipcfg+4,X
	STA ip65.cfg_netmask,X
	LDA net_ipcfg+8,X
	STA ip65.cfg_gateway,X
	DEX
	BPL -
	RTS
.pend

net_get_ip .proc
	LDX #3
-	LDA ip65.cfg_ip,X
	STA net_ipcfg,X
	LDA ip65.cfg_netmask,X
	STA net_ipcfg+4,X
	LDA ip65.cfg_gateway,X
	STA net_ipcfg+8,X
	DEX
	BPL -
	CLC
	RTS
.pend

; -----------------------------------------

net_open .proc
	; parse net_host into the destination, listen on net_port; C=1: bad address
	LDX #<net_host
	LDY #>net_host
	JSR parse_ip ; -> parsed_ip
	BCS +
	LDX #3
-	LDA parsed_ip,X
	STA ip65.udp_send_dest,X
	STA net_peer_ip,X
	DEX
	BPL -
	LDA net_port
	STA ip65.udp_send_dest_port
	STA ip65.udp_send_src_port
	LDA net_port+1
	STA ip65.udp_send_dest_port+1
	STA ip65.udp_send_src_port+1
	LDA #$00
	STA ip65.glue_rx_ready
	STA net_rx_held
	LDA net_port
	LDX net_port+1
	JSR IP65_JT_LISTEN
	LDA #$01
	STA net_socket
	STA net_peer_known
	CLC
+	RTS
.pend

net_listen .proc
	; host: receive on net_port from anybody; the first sender becomes the peer (ip and source port)
	LDA net_port
	STA ip65.udp_send_src_port
	STA ip65.udp_send_dest_port
	LDA net_port+1
	STA ip65.udp_send_src_port+1
	STA ip65.udp_send_dest_port+1
	LDA #$00
	STA ip65.glue_rx_ready
	STA net_rx_held
	STA net_peer_known
	LDA net_port
	LDX net_port+1
	JSR IP65_JT_LISTEN
	LDA #$01
	STA net_socket
	RTS
.pend

net_close .proc
	LDA net_port
	LDX net_port+1
	JSR IP65_JT_UNLISTEN
	LDA #$FF
	STA net_socket
	RTS
.pend

; -----------------------------------------

net_write .proc
	LDA net_tx_len
	STA ip65.udp_send_len
	LDA #$00
	STA ip65.udp_send_len+1
	LDA #NET_SEND_RETRIES
	STA net_retries
-	LDA #<net_tx_buf
	LDX #>net_tx_buf
	JSR IP65_JT_SEND
	BCC +
	; probably waiting for the ARP answer of the peer
	JSR IP65_JT_PROCESS
	JSR net_take_rx ; do not lose a datagram that arrives meanwhile
	DEC net_retries
	BNE -
	SEC
+	RTS
.pend

; -----------------------------------------

net_read_start .proc
	CLC
	RTS
.pend

net_read_poll .proc
	; C=1: nothing yet; C=0 + A=0: datagram at net_rx_ptr / net_rx_len
	LDA net_rx_held
	BNE _deliver
	JSR IP65_JT_PROCESS
	JSR net_take_rx
	LDA net_rx_held
	BNE _deliver
	SEC
	RTS
_deliver
	LDA #$00
	STA net_rx_held
	LDA #<net_rx_copy
	STA net_rx_ptr
	LDA #>net_rx_copy
	STA net_rx_ptr+1
	LDA net_rx_copy_len
	STA net_rx_len
	LDA #$00
	CLC
	RTS
.pend

net_take_rx .proc
	; moves a datagram from the blob's buffer to our own (unless one is still held), learns the peer's source port
	LDA ip65.glue_rx_ready
	BEQ _out
	LDA net_rx_held
	BNE _out
	LDA #$00
	STA ip65.glue_rx_ready
	LDA net_peer_known
	BNE _check
	; listening: the first sender becomes the peer
	LDX #3
-	LDA ip65.glue_rx_ip,X
	STA net_peer_ip,X
	STA ip65.udp_send_dest,X
	DEX
	BPL -
	LDA #$01
	STA net_peer_known
_check
	; only accept the peer
	LDX #3
-	LDA ip65.glue_rx_ip,X
	CMP net_peer_ip,X
	BNE _out
	DEX
	BPL -
	LDA ip65.glue_rx_port
	STA ip65.udp_send_dest_port
	LDA ip65.glue_rx_port+1
	STA ip65.udp_send_dest_port+1
	LDX ip65.glue_rx_len
	STX net_rx_copy_len
	DEX
	BMI +
-	LDA ip65.glue_rx_buf,X
	STA net_rx_copy,X
	DEX
	BPL -
+	LDA #$01
	STA net_rx_held
_out
	RTS
.pend

; -----------------------------------------

parse_ip .proc
	; parses the zero terminated dotted ip at X (lo) / Y (hi) into parsed_ip, C=1: malformed
	STX net_parse_ptr
	STY net_parse_ptr+1
	LDX #$00 ; octet index
	LDY #$00 ; string index
_octet
	LDA #$00
	STA parsed_ip,X
	STA net_digits
_digit
	LDA (net_parse_ptr),Y
	SEC
	SBC #'0'
	CMP #10
	BCS _separator
	; parsed_ip,X = parsed_ip,X * 10 + digit (overflow -> error)
	STA net_tmp
	LDA parsed_ip,X
	CMP #26
	BCS _bad
	ASL A
	ASL A
	ADC parsed_ip,X
	ASL A ; *10
	ADC net_tmp
	BCS _bad
	STA parsed_ip,X
	INC net_digits
	INY
	BNE _digit ; always branches
_separator
	LDA net_digits
	BEQ _bad
	LDA (net_parse_ptr),Y
	INY
	CPX #3
	BEQ _last
	CMP #'.'
	BNE _bad
	INX
	BNE _octet ; always branches
_last
	CMP #$00
	BNE _bad
	CLC
	RTS
_bad
	SEC
	RTS
.pend
