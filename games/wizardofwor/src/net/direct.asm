;============================================================
;
; NET: DIRECT GAMES BETWEEN TWO C64 ULTIMATES
;
; Firmware with the Command Interface command OPEN_UDP_LOCAL
; ($0A, GideonZ/1541ultimate#962 / #1016) opens a UDP socket
; from a fixed local port. With it an Ultimate can host a
; direct game, and two Ultimates play without the server:
;
;   host  $0A to 0.0.0.0, remote 6464, local 6464: lwIP matches
;         a connected socket whose remote address is "any"
;         against every sender, so it hears the HELLO of a
;         player that sends from port 6464. The HELLO carries
;         the player's ip (a read does not tell the sender);
;         then the host opens $0A to that ip, 6464 <-> 6464.
;   join  $0A to the host, remote 6464, local 6464 (the old
;         OPEN_UDP sends from a random port, which an Ultimate
;         host cannot hear). An RR-Net join already sends from
;         6464, so VICE can join an Ultimate as well.
;
; Old firmware answers the probe with 21 (unknown command):
; then everything stays as before (an Ultimate only joins).
; Included in the $C000-$CFFF area (wizard_of_wor.asm).
;
;============================================================

	NET_CMD_OPEN_UDP_LOCAL = $0A

direct_ok	.byte 0 ; 1: the firmware has $0A
direct_lport	.word 0 ; the local port of direct_open
direct_any	.null "0.0.0.0"

; -----------------------------------------

direct_probe .proc
	; $0A with remote port 0: new firmware answers 82, old firmware 21
	LDA #$00
	STA direct_ok
	JSR uci.uci_begin
	BCS +
	LDA #uci.UCI_TARGET_NET
	STA uci.UCI_CMD
	LDA #NET_CMD_OPEN_UDP_LOCAL
	STA uci.UCI_CMD
	LDA #$00
	STA uci.UCI_CMD
	STA uci.UCI_CMD
	STA uci.UCI_CMD
	STA uci.UCI_CMD
	LDA #$30 ; host "0"
	STA uci.UCI_CMD
	JSR uci.uci_push
	JSR uci.uci_wait
	BCS +
	LDA uci_code
	CMP #82
	BNE +
	INC direct_ok
+	RTS
.pend

; -----------------------------------------

can_host .proc
	; Z=1: this machine can host a direct game (RR-Net, or an Ultimate with $0A)
	LDA net_backend
	CMP #BACKEND_RRNET
	BEQ _yes
	CMP #BACKEND_UCI
	BNE _no
	LDA direct_ok
	BEQ _no
_yes
	LDA #$00
	RTS
_no
	LDA #$01
	RTS
.pend

; -----------------------------------------

direct_open .proc
	; $0A: UDP from local port direct_lport to net_host:net_port -> A and net_socket, C=1 on error
	JSR uci.uci_begin
	BCS _err
	LDA #uci.UCI_TARGET_NET
	STA uci.UCI_CMD
	LDA #NET_CMD_OPEN_UDP_LOCAL
	STA uci.UCI_CMD
	LDA net_port
	STA uci.UCI_CMD
	LDA net_port+1
	STA uci.UCI_CMD
	LDA direct_lport
	STA uci.UCI_CMD
	LDA direct_lport+1
	STA uci.UCI_CMD
	LDX #$00
-	LDA net_host,X
	BEQ +
	STA uci.UCI_CMD
	INX
	CPX #net_host_size
	BCC -
+	JSR uci.uci_push
	JSR uci.uci_wait
	BCS _err
	LDA uci_code
	BNE _err
	LDA uci_resp_len
	BEQ _err
	LDA uci_resp
	STA net_socket
	CLC
	RTS
_err
	LDA #$FF
	STA net_socket
	SEC
	RTS
.pend

; -----------------------------------------

direct_join_open .proc
	; join on an Ultimate: $0A from port 6464 when the firmware has it, else OPEN_UDP
	LDA direct_ok
	BNE +
	LDA #uci.NET_CMD_OPEN_UDP
	JMP uci.net_open
+	LDA #<GAME_PORT
	STA direct_lport
	LDA #>GAME_PORT
	STA direct_lport+1
	JMP direct_open
.pend

; -----------------------------------------

hello_add_ip .proc
	; the HELLO's bytes 4-7: our ip (net_ipcfg), for an Ultimate host
	LDX #3
-	LDA net_ipcfg,X
	STA net_tx_buf+4,X
	DEX
	BPL -
	RTS
.pend

; -----------------------------------------

ip_to_host .proc
	; the 4 bytes at direct_ip as a dotted ip in net_host (zero terminated)
	LDY #$00
	LDX #$00
_byte
	STX ip_idx
	STY direct_start ; where this number begins (leading zeros)
	LDA direct_ip,X
	LDX #100
	JSR _digit
	LDX #10
	JSR _digit
	ORA #$30
	STA net_host,Y
	INY
	LDX ip_idx
	INX
	CPX #4
	BEQ _end
	LDA #'.'
	STA net_host,Y
	INY
	BNE _byte ; always
_end
	LDA #$00
	STA net_host,Y
	RTS
_digit
	; A = value, X = 100 or 10: writes the digit unless it is a leading zero; A = the rest
	STX direct_div
	LDX #$2F ; '0' - 1
	SEC
-	INX
	SBC direct_div
	BCS -
	ADC direct_div
	CPX #$30
	BNE _put
	; a zero: leading only when nothing was written for this byte yet
	CPY direct_start
	BEQ _skip
_put
	PHA
	TXA
	STA net_host,Y
	INY
	PLA
	RTS
_skip
	RTS
.pend

direct_ip	.fill 4
direct_div	.byte 0
direct_start	.byte 0

; -----------------------------------------

direct_setup_host .proc
	; the menu's HOST: RR-Net as before; an Ultimate listens with $0A, then the same wait
	LDA net_backend
	CMP #BACKEND_UCI
	BEQ +
	JMP setup_host
+	JSR direct_listen
	BCS +
	JMP setup_host.listening
+	JMP wait_key_menu
.pend

; -----------------------------------------

direct_listen .proc
	; an Ultimate hosts: $0A to 0.0.0.0, remote 6464, local 6464; C=1 on error
	JSR print_inline
	.null 13, 13, C_CYAN, "MY IP: ", C_WHITE
	JSR print_ip
	LDX #7
-	LDA direct_any,X
	STA net_host,X
	DEX
	BPL -
	LDA #<GAME_PORT
	STA direct_lport
	LDA #>GAME_PORT
	STA direct_lport+1
	LDA #$00
	STA direct_linked
	JSR direct_open
	BCS +
	INC net_is_open
+	RTS
.pend

; -----------------------------------------

direct_hello .proc
	; host on an Ultimate, the first HELLO: its bytes 4-7 are the player's ip. Close the
	; "any" socket and open $0A to the player (6464 <-> 6464), so the WELCOME can go back
	LDA net_backend
	CMP #BACKEND_UCI
	BNE +
	LDA direct_linked
	BNE +
	LDA net_rx_len
	CMP #8
	BCC +
	LDY #7
-	LDA (net_rx_ptr),Y
	STA direct_ip-4,Y
	DEY
	CPY #4
	BCS -
	JSR ip_to_host
	JSR uci.net_close
	JSR direct_open
	BCS +
	INC direct_linked
+	RTS
.pend

direct_linked	.byte 0
