;============================================================
;
; NET: DIRECT GAMES, the part after the aligned buffers in
; $5D00-$7FFF (net/direct.asm has the rest, in $C000-$CFFF)
;
;============================================================

direct_code	.byte $FF ; the status of the $0A probe (82: the firmware has $0A)
net_if		.byte 0 ; the interface of uci.net_get_ip

; -----------------------------------------

direct_get_ip .proc
	; net_ipcfg of the first interface with an address (a C64 Ultimate: 0 = LAN, 1 = WiFi)
	LDX #$00
-	STX net_if
	JSR uci.net_get_ip
	LDA net_ipcfg
	BNE +
	LDX net_if
	INX
	CPX #3
	BCC -
	DEX ; none: the last one asked (0.0.0.0)
+	RTS
.pend

; -----------------------------------------

direct_status .proc
	; the menu: whether this Ultimate can host direct games
	; (YES: an Ultimate hosts; NO (nn): the $0A probe's status, an Ultimate only joins)
	JSR print_inline
	.null 13, C_CYAN, "DIRECT:  ", C_WHITE
	LDA direct_ok
	BEQ +
	JSR print_inline
	.null "YES"
	RTS
+	JSR print_inline
	.null "NO ("
	LDA direct_code
	JSR print_u8
	LDA #')'
	JMP CHROUT
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
