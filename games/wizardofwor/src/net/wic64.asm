;============================================================
;
; NET: WiC64 driver (userport WiFi module, firmware 2.x)
;
; Included by netgame.asm inside the block "wic". Only for the
; C64 Game Server: TCP to the server's port 6466, where every
; message is framed as [length][message].
;
; Request:  "R", command, length (16 bit), payload  (C64 -> WiC64)
; Response: status, length (16 bit), payload        (WiC64 -> C64)
; Every byte goes through $DD01; the WiC64 confirms each one with
; FLAG2 ($DD0D bit 4). PA2 ($DD00 bit 2) high: the C64 sends,
; low: the C64 receives. As in the WiC64 team's wic64-library,
; and the same as the framework's lobby driver
; (framework/c64/lobby/wic64.s).
;
; A transfer costs the C64 time (about a frame per command in
; VICE), so netgame.asm sends only every 4th tick and polls only
; while it waits for the opponent (or every few frames, see
; wic_gap).
;
; Received bytes go into a stream buffer (the UCI response
; buffer, unused with a WiC64); net_read_poll hands out one
; complete message at a time.
;
;============================================================

	CMD_GET_IP = $06
	CMD_TCP_OPEN = $21
	CMD_TCP_READ = $22
	CMD_TCP_WRITE = $23
	CMD_TCP_CLOSE = $2E
	CMD_ECHO = $FE

	BUF = uci_resp ; stream buffer
	BUF_MAX = uci.UCI_RESP_MAX
	OUT_MAX = 48
	GAP = 200 ; units of 256 cycles (~50 ms): least time between two reads when wic_gap is on

	wic_ptr = uci_ptr ; zero page, free when the WiC64 is used

; -----------------------------------------

exec .proc
	; sends cmd with out[0..outlen-1]; the answer's data goes to (dst), at most dst_max bytes
	; (the rest is skipped). C=0: A = status (0 = ok), inlen = bytes stored; C=1: no WiC64
	TSX
	STX save_sp
	LDA $DD0D ; clear FLAG2
	LDA $DD02 ; PA2 is an output
	ORA #$04
	STA $DD02
	LDA $DD00 ; PA2 high: we send
	ORA #$04
	STA $DD00
	LDA #$FF
	STA $DD03
	LDA #$52 ; "R" in ASCII
	JSR out_byte
	LDA cmd
	JSR out_byte
	LDA outlen
	JSR out_byte
	LDA #0
	JSR out_byte
	LDX #0
-	CPX outlen
	BEQ +
	LDA out,X
	STX save_x
	JSR out_byte
	LDX save_x
	INX
	BNE -
+	LDA #$00 ; now receive
	STA $DD03
	LDA $DD00
	AND #$FB ; PA2 low
	STA $DD00
	JSR wait ; the WiC64 confirms the turn around
	LDA $DD01 ; and expects a handshake
	JSR in_byte
	STA status
	JSR in_byte
	STA left
	JSR in_byte
	STA left+1
	LDA dst
	STA wic_ptr
	LDA dst+1
	STA wic_ptr+1
	LDA #0
	STA inlen
	STA inlen+1
_data
	LDA left
	ORA left+1
	BEQ _done
	JSR in_byte
	TAX
	LDA inlen ; room left? (inlen < dst_max)
	CMP dst_max
	LDA inlen+1
	SBC dst_max+1
	BCS _skip
	TXA
	LDY #0
	STA (wic_ptr),Y
	INC wic_ptr
	BNE +
	INC wic_ptr+1
+	INC inlen
	BNE _skip
	INC inlen+1
_skip
	LDA left
	BNE +
	DEC left+1
+	DEC left
	JMP _data
_done
	LDA $DD0D
	LDA status
	CLC
	RTS
.pend

fail .proc
	; no handshake for about half a second: wait has reset the stack to exec's caller
	LDA #$00
	STA $DD03
	LDA $DD0D
	LDA #$FF
	SEC
	RTS
.pend

wait .proc
	LDX #0
	LDY #0
-	LDA $DD0D
	AND #$10
	BNE +
	DEY
	BNE -
	DEX
	BNE -
	LDX save_sp
	TXS
	JMP fail
+	RTS
.pend

out_byte .proc
	STA $DD01
	JMP wait
.pend

in_byte .proc
	JSR wait
	LDA $DD01
	RTS
.pend

command .proc
	; exec with A = command, X = payload length, no answer data kept; C=1: failed (no WiC64 or status <> 0)
	STA cmd
	STX outlen
	LDA #0
	STA dst_max
	STA dst_max+1
	JSR exec
	BCS +
	CMP #1 ; C=1 when the status is not 0
+	RTS
.pend

; -----------------------------------------
; the interface netgame.asm uses (like uci.asm / net_rrnet.asm)

net_detect .proc
	; C=0: a WiC64 answered the echo
	LDA #$42
	STA out
	LDA #CMD_ECHO
	STA cmd
	LDA #1
	STA outlen
	LDA #<BUF
	STA dst
	LDA #>BUF
	STA dst+1
	LDA #16
	STA dst_max
	LDA #0
	STA dst_max+1
	JSR exec
	BCS _no
	CMP #0
	BNE _no
	LDA inlen
	CMP #1
	BNE _no
	LDA BUF
	CMP #$42
	BNE _no
	CLC
	RTS
_no
	SEC
	RTS
.pend

net_print_ip .proc
	; prints the WiC64's IP address (ASCII digits and dots are the same in PETSCII)
	LDA #CMD_GET_IP
	STA cmd
	LDA #0
	STA outlen
	LDA #<BUF
	STA dst
	LDA #>BUF
	STA dst+1
	LDA #20
	STA dst_max
	LDA #0
	STA dst_max+1
	JSR exec
	BCS _unknown
	CMP #0
	BNE _unknown
	LDX #0
-	CPX inlen
	BEQ _out
	LDA BUF,X
	STX save_x
	JSR CHROUT
	LDX save_x
	INX
	BNE -
_unknown
	LDA #'?'
	JMP CHROUT
_out
	RTS
.pend

net_open .proc
	; TCP to net_host (zero terminated) port 6466; C=1: failed
	LDX #0
-	LDA net_host,X
	BEQ +
	STA out,X
	INX
	CPX #OUT_MAX-6
	BNE -
+	LDY #0
-	LDA _port,Y
	STA out,X
	INX
	INY
	CPY #5
	BNE -
	LDA #0
	STA rd
	STA rd+1
	STA fill
	STA fill+1
	LDA #CMD_TCP_OPEN
	JMP command
_port	.byte $3A, $36, $34, $36, $36 ; ":6466" in ASCII
.pend

net_close .proc
	LDA #CMD_TCP_CLOSE
	LDX #0
	JMP command
.pend

net_write .proc
	; sends net_tx_buf / net_tx_len as one framed message
	LDX net_tx_len
	STX out
-	LDA net_tx_buf-1,X
	STA out,X
	DEX
	BNE -
	LDX net_tx_len
	INX
	LDA #CMD_TCP_WRITE
	JMP command
.pend

net_read_poll .proc
	; C=0: a message at net_rx_ptr / net_rx_len (valid until the next call); C=1: nothing (yet)
	JSR take
	BCC _out
	; nothing complete: read what has arrived (not more often than every GAP when wic_gap is set)
	JSR get_cycles
	LDA wic_gap
	BEQ _read
	SEC
	LDA cycles+1
	SBC last
	TAX
	LDA cycles+2
	SBC last+1
	BNE _read
	CPX #GAP
	BCC _none
_read
	LDA cycles+1
	STA last
	LDA cycles+2
	STA last+1
	JSR compact
	CLC ; dst = BUF + fill, dst_max = BUF_MAX - fill
	LDA #<BUF
	ADC fill
	STA dst
	LDA #>BUF
	ADC fill+1
	STA dst+1
	SEC
	LDA #<BUF_MAX
	SBC fill
	STA dst_max
	LDA #>BUF_MAX
	SBC fill+1
	STA dst_max+1
	LDA #CMD_TCP_READ
	STA cmd
	LDA #0
	STA outlen
	JSR exec
	BCS _none
	CMP #0
	BNE _none
	CLC
	LDA fill
	ADC inlen
	STA fill
	LDA fill+1
	ADC inlen+1
	STA fill+1
	JMP take
_none
	SEC
_out
	RTS
.pend

take .proc
	; C=0: net_rx_ptr / net_rx_len = the next complete message of the stream
_again
	SEC ; avail = fill - rd
	LDA fill
	SBC rd
	STA avail
	LDA fill+1
	SBC rd+1
	STA avail+1
	ORA avail
	BEQ _none
	CLC
	LDA #<BUF
	ADC rd
	STA net_rx_ptr
	LDA #>BUF
	ADC rd+1
	STA net_rx_ptr+1
	LDY #0
	LDA (net_rx_ptr),Y
	STA net_rx_len
	LDX avail+1
	BNE _complete ; 256 or more bytes: surely complete
	CMP avail ; length < avail: [length] + message are there
	BCS _none
_complete
	SEC ; rd += 1 + length
	LDA rd
	ADC net_rx_len
	STA rd
	LDA rd+1
	ADC #0
	STA rd+1
	INC net_rx_ptr
	BNE +
	INC net_rx_ptr+1
+	LDA net_rx_len
	BEQ _again ; an empty message: skip it
	CLC
	RTS
_none
	SEC
	RTS
.pend

compact .proc
	; moves the unread rest of the stream to the start of the buffer
	LDA rd
	ORA rd+1
	BEQ _out
	CLC
	LDA #<BUF
	ADC rd
	STA _src+1
	LDA #>BUF
	ADC rd+1
	STA _src+2
	LDA #<BUF
	STA _dst+1
	LDA #>BUF
	STA _dst+2
	SEC
	LDA fill
	SBC rd
	STA fill
	STA count
	LDA fill+1
	SBC rd+1
	STA fill+1
	STA count+1
	LDA #0
	STA rd
	STA rd+1
_loop
	LDA count
	ORA count+1
	BEQ _out
_src	LDA $FFFF
_dst	STA $FFFF
	INC _src+1
	BNE +
	INC _src+2
+	INC _dst+1
	BNE +
	INC _dst+2
+	LDA count
	BNE +
	DEC count+1
+	DEC count
	JMP _loop
_out
	RTS
.pend

; -----------------------------------------

cmd	.byte 0
outlen	.byte 0
out	.fill OUT_MAX
dst	.word 0
dst_max	.word 0
inlen	.word 0
status	.byte 0
left	.word 0
save_sp	.byte 0
save_x	.byte 0
rd	.word 0 ; stream: read offset
fill	.word 0 ; stream: bytes in the buffer
avail	.word 0
count	.word 0
last	.word 0 ; cycles+1/+2 of the last read
