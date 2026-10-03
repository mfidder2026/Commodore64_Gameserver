;============================================================
;
; NET: NETWORK MEASUREMENT PROGRAM (phase 0)
;
; Measures what the network costs on a C64: round trip time,
; packet loss, how long the Ultimate takes for a socket read
; (with and without data) and for a write, and how long a send
; has to wait for an outstanding read.
;
; Both sides send a PING every N frames and answer every PING
; with a PONG that carries the original time stamp back. The
; other side can be a second C64 running this program or the
; PC test peer (tools/netpeer.py).
;
; Modes:  1 = UDP to peer ip:6464
;         2 = TCP connect to peer ip:6464
;         3 = TCP listen on port 6464
;
; Keys during the test: +/- send interval, R reset statistics,
;                       Q quit to the menu
;
; Time is measured with CIA2 timer A+B chained into a 32 bit
; cycle counter (no interrupts enabled on CIA2).
;
; Two builds: NET_RRNET=0 for the Ultimate (UCI), NET_RRNET=1
; for VICE / RR-Net (ip65, UDP only). With RR-Net a "read" only
; completes when a datagram arrived, so READ EMPTY stays 0 and
; READ DATA shows the time between datagrams.
;
;============================================================

	; text is printed with CHROUT: PETSCII, upper case letters $41-$5A
	; (64tass' default encoding would turn upper case letters into shifted PETSCII)
	.enc "petscii_upper"
	.cdef " @", $20
	.cdef "AZ", $41
	.cdef "[[", $5B
	.cdef "]]", $5D

	.weak
NET_RRNET = 0 ; 0: Ultimate (UCI), 1: RR-Net (ip65)
	.endweak

	PORT = 6464
	MODE_UDP = 1
	MODE_TCP = 2
	MODE_LISTEN = 3
	PKT_SIZE = 16
	PKT_PING = 1
	PKT_PONG = 2

	; KERNAL
	CHROUT = $FFD2
	CHRIN = $FFCF
	GETIN = $FFE4
	PLOT = $FFF0
	PALNTSC = $02A6 ; 1: PAL

	; CIA2 timers
	CIA2_TA_LO = $DD04
	CIA2_TA_HI = $DD05
	CIA2_TB_LO = $DD06
	CIA2_TB_HI = $DD07
	CIA2_ICR = $DD0D
	CIA2_CRA = $DD0E
	CIA2_CRB = $DD0F

	; zero page
	uci_ptr = $FB ; 2 bytes, used by uci.asm
	str_ptr = $FD ; 2 bytes
	net_rx_ptr = $F7 ; 2 bytes (RS232 buffer pointer, unused here), used by uci.asm
	net_parse_ptr = $F9 ; 2 bytes, used by net_rrnet.asm
	; the ip65 blob of the RR-Net build uses $50-$5E (BASIC work area, unused while this program runs)

;============================================================

	* = $0801
	.word +, 10
	.null $9e, format("%d", start)
+	.word 0

start
	JSR init_timer
	JSR init_irq
	.if !NET_RRNET
	LDA #2
	STA uci_timeout_secs
	.fi
	LDA #$FF
	STA net_socket
	LDA #$00
	STA net_host
	LDA #<PORT
	STA net_port
	LDA #>PORT
	STA net_port+1
	; cycles per 0.1 ms: PAL 98.5 -> 99, NTSC 102.3 -> 102
	LDA #99
	LDX PALNTSC
	BNE +
	LDA #102
+	STA cyc_per_tenth

	.if NET_RRNET

menu
	JSR print_inline
	.null 147, 5, "WOW-LAN NETTEST (RR-NET)", 13, 13, "MY IP (RETURN = DHCP): "
	JSR read_line
	LDA host_len
	BNE _static
	LDA $D012 ; some last MAC byte
	JSR net_detect
	BCC +
	JMP _no_card
+
	JSR print_inline
	.null "DHCP... "
	JSR net_dhcp
	BCC _have_ip
	JSR print_inline
	.null "FAILED", 13, "PRESS A KEY"
-	JSR GETIN
	BEQ -
	JMP menu
_static
	LDX #<host_input
	LDY #>host_input
	JSR parse_ip
	BCC +
	JMP menu
+
	LDA parsed_ip+3 ; last MAC byte = last ip byte, unique per machine
	JSR net_detect
	BCC +
	JMP _no_card
+
	LDX #3
-	LDA parsed_ip,X
	STA net_ipcfg,X
	STA net_ipcfg+8,X
	LDA #255
	STA net_ipcfg+4,X
	DEX
	BPL -
	LDA #0
	STA net_ipcfg+7 ; netmask 255.255.255.0
	LDA #1
	STA net_ipcfg+11 ; gateway x.x.x.1
	JSR net_set_ip
_have_ip
	JSR print_inline
	.null 13, "MY IP: "
	JSR net_get_ip
	LDX #0
	JSR print_ip
	LDA #MODE_UDP
	STA mode
	JSR ask_peer
	JSR net_open
	BCC +
	JMP menu
+
	JSR print_inline
	.null "UDP PORT 6464 OPEN", 13
	JMP run_test
_no_card
	JSR print_inline
	.null 13, "NO RR-NET FOUND.", 13, "VICE: SETTINGS -> CARTRIDGE ->", 13, "ETHERNET CARTRIDGE, MODE RR-NET", 13, "(OR START VICE WITH -ETHERNETCART -RRNET)", 13
	JMP *

	.else

menu
	JSR print_inline
	.null 147, 5, "WOW-LAN NETTEST (UCI)", 13, 13
	JSR uci_detect
	BCS +
	JMP _found
+	JSR print_inline
	.null "NO ULTIMATE COMMAND INTERFACE FOUND.", 13, "ENABLE IT IN THE ULTIMATE MENU:", 13, "C64 AND CARTRIDGE SETTINGS ->", 13, "COMMAND INTERFACE: ENABLED", 13
	JMP *
_found
	JSR uci_reset
	JSR print_inline
	.null "MY IP: "
	JSR net_get_ip
	BCC +
	JSR print_inline
	.null "?", 13
	JMP _menu_items
+	LDX #0
	JSR print_ip
	JSR print_inline
	.null 13
_menu_items
	JSR print_inline
	.null 13, "1 UDP TO PEER IP:6464", 13, "2 TCP CONNECT TO PEER IP:6464", 13, "3 TCP LISTEN ON PORT 6464", 13, 13, "CHOICE? "
-	JSR GETIN
	CMP #'1'
	BEQ _udp
	CMP #'2'
	BEQ _tcp
	CMP #'3'
	BNE -
	JMP _listen

_udp
	LDA #MODE_UDP
	STA mode
	JSR ask_peer
	JSR print_inline
	.null "OPENING UDP SOCKET... "
	LDA #NET_CMD_OPEN_UDP
	JSR net_open
	JMP _opened

_tcp
	LDA #MODE_TCP
	STA mode
	JSR ask_peer
	JSR print_inline
	.null "CONNECTING (UP TO 30 S)... "
	LDA #NET_CMD_OPEN_TCP
	JSR net_open
	JMP _opened

_listen
	LDA #MODE_LISTEN
	STA mode
	JSR print_inline
	.null 13, 13, "LISTEN ON PORT 6464... "
	LDA #NET_CMD_LISTEN_START
	JSR net_listen_cmd
	BCS _failed
	LDA uci_code
	BNE _failed
	JSR print_inline
	.null "WAITING", 13, "(ANY KEY = CANCEL)", 13
-	JSR GETIN
	BNE _cancel
	LDA #NET_CMD_LISTEN_STATE
	JSR net_listen_cmd
	BCS _failed
	CMP #LISTEN_CONNECTED
	BEQ +
	CMP #LISTEN_LISTENING
	BEQ -
	BNE _failed ; bind error / port in use
+
	LDA #NET_CMD_LISTEN_SOCKET
	JSR net_listen_cmd
	BCS _failed
	STA net_socket
	CLC

_opened
	BCS _failed
	JSR print_inline
	.null "OK", 13
	JMP run_test

_cancel
	LDA #NET_CMD_LISTEN_STOP
	JSR net_listen_cmd
	JMP menu

_failed
	JSR print_inline
	.null "FAILED", 13, "STATUS: "
	JSR print_status
	JSR print_inline
	.null 13, "PRESS A KEY"
-	JSR GETIN
	BEQ -
	JMP menu

	.fi ; NET_RRNET

; -----------------------------------------

read_line .proc
	; reads a line with the screen editor into host_input (zero terminated), length in host_len
	LDX #$00
-	JSR CHRIN
	CMP #13
	BEQ _done
	CPX #net_host_size-1
	BCS -
	STA host_input,X
	INX
	BNE - ; always branches
_done
	LDA #$00
	STA host_input,X
	STX host_len
	JSR print_inline
	.null 13
	RTS
.pend

; -----------------------------------------

ask_peer .proc
	; reads the peer ip into net_host, RETURN keeps the previous one
	JSR print_inline
	.null 13, 13, "PEER IP"
	LDA net_host
	BEQ +
	JSR print_inline
	.null " ["
	JSR print_host
	JSR print_inline
	.null "]"
+	JSR print_inline
	.null ": "
	JSR read_line
	LDX host_len
	BEQ _keep ; empty: keep the previous one
-	LDA host_input,X
	STA net_host,X
	DEX
	BPL -
_keep
	RTS
.pend

;============================================================
;
; the measurement loop
;
;============================================================

run_test .proc
	JSR reset_stats
	LDA #10
	STA interval
	LDA #$00
	STA seq
	STA seq+1
	STA read_pending
	STA send_due
	STA stream_len
	LDA frame_count
	STA last_frame
	LDA #$01
	STA interval_cnt
	JSR draw_labels

_loop
	JSR net_service

	; new frame?
	LDA frame_count
	CMP last_frame
	BEQ _loop
	STA last_frame

	DEC interval_cnt
	BNE +
	LDA interval
	STA interval_cnt
	LDA #$01
	STA send_due
	JSR get_time
	LDX #3
-	LDA now,X
	STA due_time,X
	DEX
	BPL -
+
	; display every 25 frames
	DEC display_cnt
	BPL +
	LDA #24
	STA display_cnt
	JSR draw_values
+
	JSR GETIN
	CMP #'Q'
	BEQ _quit
	CMP #'R'
	BNE +
	JSR reset_stats
+	CMP #'+'
	BNE +
	LDA interval
	CMP #50
	BCS +
	INC interval
+	CMP #'-'
	BNE +
	LDA interval
	CMP #2
	BCC +
	DEC interval
+	JMP _loop

_quit
	.if !NET_RRNET
	; finish an outstanding read, then close
	LDA read_pending
	BEQ +
	JSR uci_wait
+
	.fi
	JSR net_close
	JMP menu
.pend

; -----------------------------------------

net_service .proc
	; keeps one read outstanding; a due send goes first as soon as the interface is free
	.if NET_RRNET
	; RR-Net has no single command channel: a read only completes when data arrives, so send right away
	LDA send_due
	BEQ +
	JSR _send
+
	.fi
	LDA read_pending
	BEQ _idle
	JSR net_read_poll
	BCC +
	RTS ; still busy
+
	STA read_result
	LDA #$00
	STA read_pending
	JSR get_time
	LDX #<read_start
	JSR time_since ; -> delta
	LDA read_result
	BNE _not_data
	LDX #stat_read_data
	JSR stat_add
	JSR handle_rx
	JMP _idle
_not_data
	CMP #$02
	BNE _error
	LDX #stat_read_empty
	JSR stat_add
	JMP _idle
_error
	INC errors
	BNE _idle
	INC errors+1

_idle
	LDA send_due
	BEQ _start_read
	JSR _send
	JMP _start_read

_send
	LDA #$00
	STA send_due
	; how long did the send wait for the interface?
	JSR get_time
	LDX #<due_time
	JSR time_since
	LDX #stat_send_wait
	JSR stat_add
	JMP send_ping

_start_read
	LDA #PKT_SIZE * 4
	STA net_read_max
	JSR get_time
	LDX #3
-	LDA now,X
	STA read_start,X
	DEX
	BPL -
	JSR net_read_start
	BCS +
	LDA #$01
	STA read_pending
+	RTS
.pend

; -----------------------------------------

send_ping .proc
	LDA #PKT_PING
	STA net_tx_buf+2
	INC seq
	BNE +
	INC seq+1
+	LDA seq
	STA net_tx_buf+3
	LDA seq+1
	STA net_tx_buf+4
	JSR get_time
	LDX #3
-	LDA now,X
	STA net_tx_buf+5,X
	DEX
	BPL -
	INC pings_sent
	BNE send_packet
	INC pings_sent+1
	; fall through
.pend

send_packet .proc
	; sends the packet in net_tx_buf (type, seq and time stamp already filled in) and measures the write
	LDA #'W'
	STA net_tx_buf
	LDA #'L'
	STA net_tx_buf+1
	LDA #PKT_SIZE
	STA net_tx_len
	JSR get_time
	LDX #3
-	LDA now,X
	STA write_start,X
	DEX
	BPL -
	JSR net_write
	BCC +
	INC errors
	BNE +
	INC errors+1
+	JSR get_time
	LDX #<write_start
	JSR time_since
	LDX #stat_write
	JMP stat_add
.pend

; -----------------------------------------

handle_rx .proc
	; append the received bytes to the stream buffer (TCP may split or join packets), then handle complete packets
	LDY #$00
-	CPY net_rx_len
	BEQ _parse
	LDX stream_len
	CPX #stream_size
	BCS _parse ; overflow: drop
	LDA (net_rx_ptr),Y
	STA stream,X
	INC stream_len
	INY
	BNE -
_parse
	LDA stream_len
	CMP #PKT_SIZE
	BCS +
	RTS
+
	; resync on the magic bytes
	LDA stream
	CMP #'W'
	BNE _skip_byte
	LDA stream+1
	CMP #'L'
	BEQ +
_skip_byte
	JMP _skip1
+

	LDA stream+2
	CMP #PKT_PING
	BNE _not_ping
	; answer with a PONG carrying seq and time stamp back
	INC pings_rcvd
	BNE +
	INC pings_rcvd+1
+	LDX #PKT_SIZE-1
-	LDA stream,X
	STA net_tx_buf,X
	DEX
	BPL -
	LDA #PKT_PONG
	STA net_tx_buf+2
	JSR send_packet
	JMP _consume

_not_ping
	CMP #PKT_PONG
	BNE _consume
	INC pongs_rcvd
	BNE +
	INC pongs_rcvd+1
+	JSR get_time
	; round trip = now - time stamp in the packet
	SEC
	LDA now
	SBC stream+5
	STA delta
	LDA now+1
	SBC stream+6
	STA delta+1
	LDA now+2
	SBC stream+7
	STA delta+2
	LDA now+3
	SBC stream+8
	STA delta+3
	LDX #stat_rtt
	JSR stat_add
	; remember the last one
	LDX #3
-	LDA delta,X
	STA rtt_last,X
	DEX
	BPL -

_consume
	; drop PKT_SIZE bytes from the stream buffer
	LDX #$00
	LDY #PKT_SIZE
-	CPY stream_len
	BCS +
	LDA stream,Y
	STA stream,X
	INX
	INY
	BNE -
+	STX stream_len
	JMP _parse

_skip1
	; drop one byte
	LDX #$00
-	LDA stream+1,X
	STA stream,X
	INX
	CPX stream_len
	BCC -
	DEC stream_len
	JMP _parse
.pend

;============================================================
;
; time measurement
;
;============================================================

init_timer .proc
	LDA #$7F ; no CIA2 interrupts (NMI)
	STA CIA2_ICR
	LDA #$FF
	STA CIA2_TA_LO
	STA CIA2_TA_HI
	STA CIA2_TB_LO
	STA CIA2_TB_HI
	LDA #%01010001 ; timer B: count underflows of timer A, force load, start
	STA CIA2_CRB
	LDA #%00010001 ; timer A: count cycles, continuous, force load, start
	STA CIA2_CRA
	RTS
.pend

get_time .proc
	; now = 32 bit cycle counter (counting up)
	; timer B is read before and after timer A, a carry from A into B in between is retried
-	LDA CIA2_TB_LO
	STA now+2
	LDA CIA2_TB_HI
	STA now+3
	LDA CIA2_TA_HI
	STA now+1
	LDA CIA2_TA_LO
	STA now
	LDA CIA2_TB_LO
	CMP now+2
	BNE -
	; the timers count down: invert
	LDX #3
-	LDA now,X
	EOR #$FF
	STA now,X
	DEX
	BPL -
	RTS
.pend

time_since .proc
	; delta = now - (4 bytes at X, X is the low byte of an address in page time_vars)
	SEC
	LDA now
	SBC time_vars_page,X
	STA delta
	LDA now+1
	SBC time_vars_page+1,X
	STA delta+1
	LDA now+2
	SBC time_vars_page+2,X
	STA delta+2
	LDA now+3
	SBC time_vars_page+3,X
	STA delta+3
	RTS
.pend

; -----------------------------------------
;
; statistics: per statistic count (2), sum (4), min (4), max (4) = 14 bytes, X = offset
;

	STAT_LEN = 14
	stat_rtt = 0
	stat_read_data = STAT_LEN
	stat_read_empty = STAT_LEN * 2
	stat_write = STAT_LEN * 3
	stat_send_wait = STAT_LEN * 4
	STAT_COUNT = 5

stat_add .proc
	; adds delta to the statistic at offset X
	INC stats,X
	BNE +
	INC stats+1,X
+
	CLC
	LDA stats+2,X
	ADC delta
	STA stats+2,X
	LDA stats+3,X
	ADC delta+1
	STA stats+3,X
	LDA stats+4,X
	ADC delta+2
	STA stats+4,X
	LDA stats+5,X
	ADC delta+3
	STA stats+5,X
	; min: delta < min ?
	LDA delta
	CMP stats+6,X
	LDA delta+1
	SBC stats+7,X
	LDA delta+2
	SBC stats+8,X
	LDA delta+3
	SBC stats+9,X
	BCS +
	LDA delta
	STA stats+6,X
	LDA delta+1
	STA stats+7,X
	LDA delta+2
	STA stats+8,X
	LDA delta+3
	STA stats+9,X
+
	; max: delta >= max ?
	LDA delta
	CMP stats+10,X
	LDA delta+1
	SBC stats+11,X
	LDA delta+2
	SBC stats+12,X
	LDA delta+3
	SBC stats+13,X
	BCC +
	LDA delta
	STA stats+10,X
	LDA delta+1
	STA stats+11,X
	LDA delta+2
	STA stats+12,X
	LDA delta+3
	STA stats+13,X
+	RTS
.pend

reset_stats .proc
	LDX #STAT_LEN * STAT_COUNT - 1
-	LDA #$00
	STA stats,X
	DEX
	BPL -
	; min = $FFFFFFFF
	LDX #STAT_LEN * (STAT_COUNT - 1)
-	LDA #$FF
	STA stats+6,X
	STA stats+7,X
	STA stats+8,X
	STA stats+9,X
	TXA
	SEC
	SBC #STAT_LEN
	TAX
	BCS -
	LDA #$00
	LDX #rtt_last - counters + 3
-	STA counters,X
	DEX
	BPL -
	RTS
.pend

;============================================================
;
; display
;
;============================================================

	ROW_INFO = 2
	ROW_VALUES = 6

draw_labels .proc
	JSR print_inline
	.null 147, 5, "WOW-LAN NETTEST  Q=QUIT R=RESET +/-", 13, 13
	JSR print_inline
	.null "PEER "
	LDA mode
	CMP #MODE_LISTEN
	BNE +
	JSR print_inline
	.null "(LISTENING)"
	JMP ++
+	JSR print_host
+	JSR print_inline
	.null "  SOCKET "
	LDA net_socket
	JSR print_u8
	JSR print_inline
	.null 13, 13, 13, "             COUNT   MIN   AVG   MAX", 13, "                       (MS)", 13
	JSR print_inline
	.null 13, "RTT", 13, "READ DATA", 13, "READ EMPTY", 13, "WRITE", 13, "SEND WAIT", 13, 13
	JSR print_inline
	.null "PINGS SENT", 13, "PONGS RCVD", 13, "PINGS RCVD", 13, "LAST RTT", 13, "ERRORS", 13, "LAST STATUS", 13
	RTS
.pend

draw_values .proc
	; interval line
	LDX #ROW_INFO+1
	LDY #0
	JSR goto
	JSR print_inline
	.null "SEND EVERY "
	LDA interval
	JSR print_u8
	JSR print_inline
	.null " FRAMES  "
	; statistic table, rows 8-12
	LDA #8
	STA row
	LDA #stat_rtt
	STA stat_ofs
-	LDX row
	LDY #11
	JSR goto
	JSR print_stat
	INC row
	LDA stat_ofs
	CLC
	ADC #STAT_LEN
	STA stat_ofs
	CMP #STAT_LEN * STAT_COUNT
	BCC -
	; counters
	LDX #14
	LDY #12
	JSR goto
	LDA pings_sent
	LDX pings_sent+1
	JSR print_u16_pad
	LDX #15
	LDY #12
	JSR goto
	LDA pongs_rcvd
	LDX pongs_rcvd+1
	JSR print_u16_pad
	LDX #16
	LDY #12
	JSR goto
	LDA pings_rcvd
	LDX pings_rcvd+1
	JSR print_u16_pad
	LDX #17
	LDY #12
	JSR goto
	LDX #3
-	LDA rtt_last,X
	STA delta,X
	DEX
	BPL -
	JSR print_ms
	LDX #18
	LDY #12
	JSR goto
	LDA errors
	LDX errors+1
	JSR print_u16_pad
	LDX #19
	LDY #12
	JSR goto
	JSR print_status
	JSR print_inline
	.null "          "
	RTS
.pend

print_stat .proc
	; one table row: count, min, avg, max of the statistic at stat_ofs
	LDX stat_ofs
	LDA stats,X
	PHA
	LDA stats+1,X
	TAX
	PLA
	JSR print_u16_pad
	LDX stat_ofs
	LDA stats,X
	ORA stats+1,X
	BNE +
	JSR print_inline
	.null "     -     -     -"
	RTS
+
	; min
	LDY #6
	JSR copy_stat_to_delta
	JSR print_ms
	; avg = sum / count
	LDY #2
	JSR copy_stat_to_delta
	LDX stat_ofs
	LDA stats,X
	STA divisor
	LDA stats+1,X
	STA divisor+1
	JSR div32
	JSR print_ms
	; max
	LDY #10
	JSR copy_stat_to_delta
	JMP print_ms
.pend

copy_stat_to_delta .proc
	; delta = 4 bytes at stats + stat_ofs + Y
	TYA
	CLC
	ADC stat_ofs
	TAX
	LDY #$00
-	LDA stats,X
	STA delta,Y
	INX
	INY
	CPY #4
	BCC -
	RTS
.pend

print_ms .proc
	; prints delta (cycles) as milliseconds with one decimal, right aligned in 6 columns
	LDA cyc_per_tenth
	STA divisor
	LDA #$00
	STA divisor+1
	JSR div32
	; delta = tenths of ms; clamp to 9999.9
	LDA delta+2
	ORA delta+3
	BEQ +
	LDA #$FF
	STA delta
	STA delta+1
+	LDA delta
	LDX delta+1
	JSR u16_to_digits
	; digits[0..4], print as "dddd.d" with leading blanks, at least "0.d"
	LDX #$00
-	LDA digits,X
	CPX #3
	BCS + ; from the units digit on always print
	CMP #'0'
	BNE + ; first significant digit
	LDA #' '
	STA digits,X
	INX
	BNE - ; always branches
+	LDA #' '
	JSR CHROUT
	LDX #$00
-	LDA digits,X
	JSR CHROUT
	INX
	CPX #4
	BCC -
	LDA #'.'
	JSR CHROUT
	LDA digits+4
	JMP CHROUT
.pend

;============================================================
;
; helpers
;
;============================================================

init_irq .proc
	; raster IRQ at line 250 counts frames, then continues into the KERNAL handler (keyboard)
	SEI
	LDA #$7F
	STA $DC0D ; no CIA1 timer IRQ
	LDA $DC0D
	LDA #<irq
	STA $0314
	LDA #>irq
	STA $0315
	LDA #250
	STA $D012
	LDA $D011
	AND #$7F
	STA $D011
	LDA #$01
	STA $D01A
	STA $D019
	CLI
	RTS
irq
	LDA $D019
	STA $D019
	INC frame_count
	JMP $EA31
.pend

goto .proc
	; cursor to row X, column Y
	CLC
	JMP PLOT
.pend

print_inline .proc
	; prints the zero terminated string that follows the JSR
	PLA
	STA str_ptr
	PLA
	STA str_ptr+1
-	INC str_ptr
	BNE +
	INC str_ptr+1
+	LDY #$00
	LDA (str_ptr),Y
	BEQ +
	JSR CHROUT
	JMP -
+	LDA str_ptr+1
	PHA
	LDA str_ptr
	PHA
	RTS
.pend

print_host .proc
	LDX #$00
-	LDA net_host,X
	BEQ +
	JSR CHROUT
	INX
	BNE -
+	RTS
.pend

print_status .proc
	.if NET_RRNET
	JSR print_inline
	.null "IP65 ERROR "
	LDA ip65.ip65_error
	JMP print_u8
	.else
	LDX #$00
-	LDA uci_stat,X
	BEQ +
	JSR CHROUT
	INX
	CPX #24
	BCC -
+	RTS
	.fi
.pend

print_ip .proc
	; prints 4 bytes at net_ipcfg+X as a dotted ip
	LDY #4
-	LDA net_ipcfg,X
	STX ip_idx ; not tmp: u16_to_digits uses tmp
	STY ip_cnt
	JSR print_u8
	LDX ip_idx
	LDY ip_cnt
	INX
	DEY
	BEQ +
	LDA #'.'
	JSR CHROUT
	JMP -
+	RTS
.pend

print_u8 .proc
	LDX #$00
	; fall through
.pend

print_u16 .proc
	; prints A (lo) / X (hi) without leading zeros
	JSR u16_to_digits
	LDX #$00
-	LDA digits,X
	CMP #'0'
	BNE +
	INX
	CPX #4
	BCC -
+
-	LDA digits,X
	JSR CHROUT
	INX
	CPX #5
	BCC -
	RTS
.pend

print_u16_pad .proc
	; prints A (lo) / X (hi) right aligned in 6 columns
	JSR u16_to_digits
	LDA #' '
	JSR CHROUT
	LDX #$00
-	LDA digits,X
	CPX #4
	BCS +
	CMP #'0'
	BNE +
	LDA #' '
	STA digits,X
	INX
	BNE - ; always branches
+
	LDX #$00
-	LDA digits,X
	JSR CHROUT
	INX
	CPX #5
	BCC -
	RTS
.pend

u16_to_digits .proc
	; A (lo) / X (hi) -> 5 ascii digits in digits[]
	STA num
	STX num+1
	LDY #$00
_digit
	LDX #'0'
-	LDA num
	SEC
	SBC pow10_lo,Y
	STA tmp
	LDA num+1
	SBC pow10_hi,Y
	BCC +
	STA num+1
	LDA tmp
	STA num
	INX
	BNE - ; always branches
+	TXA
	STA digits,Y
	INY
	CPY #5
	BCC _digit
	RTS
pow10_lo .byte <10000, <1000, <100, <10, <1
pow10_hi .byte >10000, >1000, >100, >10, >1
.pend

div32 .proc
	; delta (32 bit) = delta / divisor (16 bit), remainder in rem
	LDA #$00
	STA rem
	STA rem+1
	LDX #32
-	ASL delta
	ROL delta+1
	ROL delta+2
	ROL delta+3
	ROL rem
	ROL rem+1
	LDA rem
	SEC
	SBC divisor
	TAY
	LDA rem+1
	SBC divisor+1
	BCC +
	STA rem+1
	STY rem
	INC delta
+	DEX
	BNE -
	RTS
.pend

	.if NET_RRNET
	.include "net_rrnet.asm"
	.cerror * > IP65_BLOB_START, "nettest code overlaps the ip65 blob"
	* = IP65_BLOB_START
	.binary "../../build/ip65_nettest.bin"
	.else
	.include "uci.asm"
	.fi

;============================================================
;
; variables (not part of the PRG)
;
;============================================================

	net_host_size = 32
	stream_size = 64

	.if NET_RRNET
	.include "../../build/ip65_nettest.inc"
	.cerror IP65_BSS_END > $C000, "ip65 buffers overlap the variables"
	.else
	.cerror * > $BF00, "program too long"
	.fi

	.virtual $C000
time_vars_page
read_start	.fill 4 ; these four must stay in this page (time_since)
write_start	.fill 4
due_time	.fill 4
	.cerror (<time_vars_page) != 0, "time_vars_page must be page aligned (time_since indexes it with the low byte)"
	.cerror (>*) != (>time_vars_page), "time variables cross a page"

now		.fill 4
delta		.fill 4
divisor		.fill 2
rem		.fill 2
num		.fill 2
tmp		.fill 2
digits		.fill 5
frame_count	.fill 1
last_frame	.fill 1
interval	.fill 1
interval_cnt	.fill 1
display_cnt	.fill 1
cyc_per_tenth	.fill 1
mode		.fill 1
row		.fill 1
stat_ofs	.fill 1
seq		.fill 2
read_pending	.fill 1
read_result	.fill 1
send_due	.fill 1
stream_len	.fill 1
stream		.fill stream_size

counters
pings_sent	.fill 2
pongs_rcvd	.fill 2
pings_rcvd	.fill 2
errors		.fill 2
rtt_last	.fill 4

stats		.fill STAT_LEN * STAT_COUNT

host_input	.fill net_host_size
host_len	.fill 1
ip_idx		.fill 1
ip_cnt		.fill 1
net_ipcfg	.fill 12 ; ip, netmask, gateway

	; used by net_rrnet.asm
net_peer_ip	.fill 4
parsed_ip	.fill 4
net_retries	.fill 1
net_rx_held	.fill 1
net_rx_copy_len	.fill 1
net_rx_copy	.fill 128
net_digits	.fill 1
net_tmp		.fill 1

	; used by both backends
net_port	.fill 2
net_host	.fill net_host_size
net_socket	.fill 1
net_tx_len	.fill 1
net_tx_buf	.fill PKT_SIZE
net_read_max	.fill 1
net_rx_len	.fill 1

	.if !NET_RRNET
	; used by uci.asm
uci_pending	.fill 1
uci_resp_len	.fill 2
uci_stat_len	.fill 1
uci_code	.fill 1
uci_tmo		.fill 3
uci_timeout_secs .fill 1
uci_stat	.fill UCI_STAT_MAX
uci_resp	.fill UCI_RESP_MAX
	.fi
	.endv
