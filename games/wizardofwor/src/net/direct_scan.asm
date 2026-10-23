;============================================================
;
; NET: DIRECT GAMES, finding the host without its ip
;
; Placed between the ip65 blob's buffers and NET_ENTRY
; ($5C10-$5CFF, netgame.asm checks both ends).
;
; An Ultimate host announces itself every ~0.5 s: HERE
; (version, its ip) from port 6465 to the subnet's broadcast
; address, port 6464. A player who presses RETURN without an
; ip listens with $0A to 0.0.0.0, remote 6465, local 6464
; (direct_search, direct.asm), takes the host's ip from the
; first HERE and joins as if it was typed in.
;
;============================================================

	PT_HERE = 6 ; host -> broadcast: version, the host's ip
	ANNOUNCE_PORT = 6465

direct_asock	.byte $FF ; the host's announce socket ($FF: none)
direct_atime	.byte 0
direct_save	.byte 0

; -----------------------------------------

direct_announce_open .proc
	; host: $0A from port 6465 to the subnet's broadcast address, port 6464 (net_port)
	JSR direct_close_announce
	LDX #3
-	LDA net_ipcfg+4,X ; ip | ~netmask
	EOR #$FF
	ORA net_ipcfg,X
	STA direct_ip,X
	DEX
	BPL -
	JSR ip_to_host
	LDA #<ANNOUNCE_PORT
	STA direct_lport
	LDA #>ANNOUNCE_PORT
	STA direct_lport+1
	JSR direct_open
	STA direct_asock ; $FF when it failed: then no announcing
	RTS
.pend

; -----------------------------------------

direct_close_announce .proc
	LDA direct_asock
	BMI +
	LDX net_socket
	STX direct_save
	STA net_socket
	JSR uci.net_close
	LDA direct_save
	STA net_socket
	LDA #$FF
	STA direct_asock
+	RTS
.pend

; -----------------------------------------

direct_announce .proc
	; the host's wait loop: HERE every ~0.5 s while nobody has come, then netio_poll
	LDA direct_asock
	BMI _out
	LDA net_connected
	BEQ +
	JSR direct_close_announce
	JMP netio_poll
+	JSR get_cycles
	LDA cycles+2 ; +1 every 65536 cycles
	SEC
	SBC direct_atime
	CMP #8
	BCC _out
	LDA cycles+2
	STA direct_atime
	JSR uci.uci_wait ; the read that runs ends (a HELLO in it comes again)
	LDA #NETIO_IDLE
	STA netio_state
	LDA #PT_HERE
	LDX #8
	JSR packet_header
	LDA #PROTO_VERSION
	STA net_tx_buf+3
	JSR hello_add_ip
	LDA net_socket
	PHA
	LDA direct_asock
	STA net_socket
	JSR uci.net_write_start ; with uci_wait: net_write, which is not in the build
	JSR uci.uci_wait
	PLA
	STA net_socket
_out
	JMP netio_poll
.pend

; -----------------------------------------

direct_join_hint .proc
	; the menu's JOIN, on an Ultimate with $0A first a hint: RETURN alone searches the host
	LDA net_backend
	CMP #BACKEND_UCI
	BNE +
	LDA direct_ok
	BEQ +
	JSR print_inline
	.null 13, 13, C_LGREY, "NO IP, ONLY RETURN: SEARCH THE HOST"
+	JMP setup_join
.pend

; -----------------------------------------

direct_rx_ip .proc
	; the received packet's bytes 4-7 (HELLO / HERE: the sender's ip) -> direct_ip, net_host
	LDY #7
-	LDA (net_rx_ptr),Y
	STA direct_ip-4,Y
	DEY
	CPY #4
	BCS -
	JMP ip_to_host
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
