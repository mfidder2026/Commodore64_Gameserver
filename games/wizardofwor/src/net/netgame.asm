;============================================================
;
; NET: NETWORK GAME - setup menu, network I/O and lockstep
;
; Included by wizard_of_wor.asm (TARGET_PRG=1).
;
; Memory
;   $4000-$5CFF  ip65 blob (RR-Net), linked for zero page $EA-$F8
;   $5D00-$7FFF  this file: entry (NET_ENTRY), setup menu,
;                network I/O for both backends, protocol
;
; Roles (decided in the setup menu)
;   host  RR-Net only (VICE or hardware): listens on UDP 6464,
;         the first machine that says HELLO becomes the peer.
;         Controls player 1 (actor 1).
;   join  C64 Ultimate or RR-Net: UDP to host:6464. Controls
;         player 2 (actor 0).
;   The Ultimate firmware cannot listen or open a fixed local
;   port (docs/netcode.md), so an Ultimate always joins.
;   server  via the C64 Game Server (server/, UDP 6465; WiC64: TCP 6466):
;         nickname, lobby on the title screen, the server pairs the players.
;         Slot 0 = player 1 (actor 1), slot 1 = player 2 (actor 0).
;         Needed for Ultimate <-> Ultimate. Protocol: docs/protocol.md
;         A WiC64 (TCP only) can only play via the server.
;   Each player uses joystick port 2 or the keyboard (W A S D +
;   SPACE) on his own machine.
;
; Protocol (UDP, every packet starts with 'W' 'L' type)
;   HELLO      join -> host   version
;   WELCOME    host -> join   version, input delay
;   START      host -> join   game id, seed random_number, seed rnd_state
;   START_ACK  join -> host   game id
;   INPUT      both           game id, newest tick (16), checksum tick (16),
;                             checksum (16), the inputs of the last 16 ticks
;
; Lockstep: tick t uses the inputs both players gave for tick t.
; A player's input is sampled INPUT_DELAY ticks ahead (at tick
; t-INPUT_DELAY) and sent at once; every INPUT packet repeats the
; last 16 inputs, so a lost packet is covered by the next one.
; A tick waits until the peer's input for it has arrived.
;
;============================================================

	NET_ENTRY = $5D00 ; must match src/loader.asm
	GAME_PORT = 6464 ; UDP
	PROTO_VERSION = 1
	INPUT_DELAY = 4 ; ticks
	INPUT_WINDOW = 16 ; inputs per packet
	CHECK_EVERY = 64 ; ticks between state checksums (power of 2)

	PT_HELLO = 1
	PT_WELCOME = 2
	PT_START = 3
	PT_START_ACK = 4
	PT_INPUT = 5

	ROLE_LOCAL = 0
	ROLE_HOST = 1
	ROLE_JOIN = 2
	ROLE_SERVER = 3

	SERVER_PORT = 6465
	NICK_MAX = 8

	; game server message types (server/docs/protocol.md)
	SM_HELLO = $01
	SM_WELCOME = $02
	SM_REJECT = $03
	SM_LOBBY = $04
	SM_CHALLENGE = $05
	SM_ACCEPT = $06
	SM_DECLINE = $07
	SM_START = $08
	SM_START_ACK = $09
	SM_OPPONENT_LEFT = $0A
	SM_SESSION_END = $0B
	SM_PING = $0C
	SM_PONG = $0D
	SM_CANCELLED = $0F
	SM_PLAYERS = $10
	SM_INVITE = $11
	SM_INPUT = $80
	SERVER_GAME_ID = 1 ; Wizard of Wor
	SERVER_GAME_VERSION = 1

	; lobby states (server role)
	SRV_CONNECTING = 0
	SRV_LOBBY = 1
	SRV_CHALLENGED = 2
	SRV_ACCEPTED = 3
	SRV_STARTING = 4
	SRV_INVITING = 5 ; we challenged a player from the lobby list (lobby.asm)

	; status line messages shown for a while on the title screen
	MSG_NONE = 0
	MSG_OPPONENT_LEFT = 1
	MSG_DESYNC = 2
	MSG_DECLINED = 3
	MSG_NO_SERVER = 4
	MSG_NOT_FREE = 5
	MSG_NO_ANSWER = 6
	MSG_PLAYER_LEFT = 7

	BACKEND_NONE = 0
	BACKEND_UCI = 1
	BACKEND_RRNET = 2
	BACKEND_WIC64 = 3
	WIC_SEND_EVERY = 4 ; WiC64: send INPUT every 4th tick (power of 2; the window of 16 covers it)
	WIC_RESEND = 250 ; WiC64: resend while waiting every ~64 ms instead of ~20 ms

	NETIO_IDLE = 0
	NETIO_READ = 1
	NETIO_WRITE = 2

	WAIT_RESEND = 78 ; units of 256 cycles (~20 ms): resend while waiting for the peer
	WAIT_SHOW = 3850 ; ~1 s: flash the border
	WAIT_ABORT = 57700 ; ~15 s: give up, back to the title screen

	; zero page: the game uses $02-$E9, the ip65 blob $EA-$F8
	uci_ptr = $F9 ; 2 bytes (uci.asm)
	net_rx_ptr = $FB ; 2 bytes (received packet)
	net_parse_ptr = $FD ; 2 bytes (net_rrnet.asm, setup menu only)
	str_ptr = $02 ; 2 bytes, setup menu only (the game has not started yet)
	str_ptr2 = $FD ; 2 bytes: setup menu and the status line (shares net_parse_ptr / det_ptr, never at the same time)

	; KERNAL (setup menu only)
	CHROUT = $FFD2
	CHRIN = $FFCF
	GETIN = $FFE4

	; text is printed with CHROUT: PETSCII, upper case letters $41-$5A
	; PETSCII color codes for the setup screen: the colors of the game on black
	C_WHITE = 5
	C_LRED = 150
	C_LBLUE = 154
	C_LGREY = 155
	C_YELLOW = 158
	C_CYAN = 159

	.enc "setup"
	.cdef " @", $20
	.cdef "AZ", $41
	.cdef "[[", $5B
	.cdef "]]", $5D

;============================================================
;
; NETBOT: event log for tools/netgame_test.py (RAM under the KERNAL, written only)
;   4 bytes per event: code, tick low, tick high, extra
;
	EV_SESSION_START = 1 ; extra: game id
	EV_SESSION_END = 2
	EV_ABORT = 3 ; extra: 1 = waited too long, 2 = the host started another game
	EV_START_SENT = 4 ; extra: game id
	EV_START_RX = 5 ; extra: game id
	EV_ACK_RX = 6 ; extra: game id
	EV_DESYNC = 7 ; extra: low byte of the tick of the checksum
	EV_FIRST_TICK = 8
	EV_BUF = $E800
	EV_LOG_SIZE = 256 ; events

log_event .macro code, extra
	.if NETBOT
	PHA
	TXA
	PHA
	LDA \extra
	LDX #\code
	JSR ev_log
	PLA
	TAX
	PLA
	.fi
.endm

log_event_a .macro code
	; the extra byte is in A
	.if NETBOT
	PHA
	STA ev_a
	TXA
	PHA
	LDA ev_a
	LDX #\code
	JSR ev_log
	PLA
	TAX
	PLA
	.fi
.endm

;============================================================

	* = $4000
	.binary "../../build/ip65_game.bin"
	.include "../../build/ip65_game.inc"
	.cerror IP65_BLOB_START != $4000, "the ip65 blob must be linked for $4000"
	.cerror IP65_BSS_END > NET_ENTRY, "the ip65 blob and its buffers overlap NET_ENTRY"

	* = NET_ENTRY
	JMP net_setup ; the loader jumps here

; the two network drivers, each in its own namespace (they use the same routine names)
uci	.block
	.include "uci.asm"
	.bend

rr	.block
	.include "net_rrnet.asm"
	.bend

wic	.block
	.include "wic64.asm"
	.bend

;============================================================
;
; network I/O: one interface for both backends
;
;============================================================

; -----------------------------------------
; ip65 calls during the setup menu: the KERNAL screen editor and keyboard use $EA-$F6 too, so the KERNAL's
; zero page is saved around every call and interrupts are off meanwhile. In the game the KERNAL is not used.

rr_enter .proc
	BIT netio_kernal
	BPL +
	SEI
	PHA
	TXA
	PHA
	LDX #$F8-$EA
-	LDA $EA,X
	STA kernal_zp_save,X
	DEX
	BPL -
	PLA
	TAX
	PLA
+	RTS
.pend

rr_leave .proc
	; keeps A, X and the carry
	BIT netio_kernal
	BPL +
	PHP
	PHA
	TXA
	PHA
	LDX #$F8-$EA
-	LDA kernal_zp_save,X
	STA $EA,X
	DEX
	BPL -
	PLA
	TAX
	PLA
	PLP
	CLI
+	RTS
.pend

rr_call .macro
	JSR rr_enter
	JSR \1
	JSR rr_leave
.endm

; -----------------------------------------

netio_detect .proc
	; finds the network hardware: C64 Ultimate (UCI) first, then RR-Net; sets net_backend
	JSR uci.uci_detect
	BCS _no_uci
	JSR uci.uci_reset
	LDA #BACKEND_UCI
	STA net_backend
	RTS
_no_uci
	LDA mac_last
	#rr_call rr.net_detect
	LDA #BACKEND_RRNET
	BCC +
	JSR wic.net_detect
	LDA #BACKEND_NONE
	BCS +
	LDA #BACKEND_WIC64
+	STA net_backend
	LDX #WAIT_RESEND ; a WiC64 resends less often while waiting
	CMP #BACKEND_WIC64
	BNE +
	LDX #WIC_RESEND
+	STX resend_units
	RTS
.pend

; -----------------------------------------

netio_send .proc
	; sends the packet in net_tx_buf / net_tx_len
	LDA net_backend
	CMP #BACKEND_UCI
	BNE _rr
	; Ultimate: one command at a time - if a read is running, the write follows when it is done
	LDA netio_state
	BNE _later
	JSR uci.net_write_start
	BCS _later
	LDA #NETIO_WRITE
	STA netio_state
	RTS
_later
	LDA #$01
	STA netio_tx_pending
	RTS
_rr
	CMP #BACKEND_RRNET
	BNE +
	#rr_call rr.net_write
	RTS
+	CMP #BACKEND_WIC64
	BNE +
	JMP wic.net_write
+	RTS
.pend

; -----------------------------------------

netio_poll .proc
	; C=0: a packet arrived (net_rx_ptr / net_rx_len); C=1: nothing (yet)
	LDA net_backend
	CMP #BACKEND_UCI
	BEQ _uci
	CMP #BACKEND_RRNET
	BEQ _rr
	CMP #BACKEND_WIC64
	BNE +
	JMP wic.net_read_poll
+	SEC
	RTS
_rr
	#rr_call rr.net_read_poll
	RTS

_uci
	LDA netio_state
	BEQ _idle
	CMP #NETIO_READ
	BEQ _reading
	; a write is running
	JSR uci.uci_poll
	BCS _busy
	LDA #NETIO_IDLE
	STA netio_state
	BEQ _idle ; always branches
_reading
	JSR uci.net_read_poll ; C=1: busy, else A = result
	BCS _busy
	LDX #NETIO_IDLE
	STX netio_state
	CMP #$00
	BNE _idle ; no data / closed / error
	CLC ; data: the next call starts the next command, so the reply buffer stays valid until then
	RTS
_idle
	; a pending write first, otherwise the next read (it returns as soon as data arrives, after 40 ms at most)
	LDA netio_tx_pending
	BEQ _read
	LDA #$00
	STA netio_tx_pending
	JSR uci.net_write_start
	BCS _busy
	LDA #NETIO_WRITE
	STA netio_state
	SEC
	RTS
_read
	LDA #128
	STA net_read_max
	JSR uci.net_read_start
	BCS _busy
	LDA #NETIO_READ
	STA netio_state
_busy
	SEC
	RTS
.pend

;============================================================
;
; protocol
;
;============================================================

proto_rx .proc
	; handles the packet at net_rx_ptr / net_rx_len
	LDA net_role
	CMP #ROLE_SERVER
	BNE +
	JMP srv_rx
+	LDA net_rx_len
	CMP #$04
	BCS +
	RTS
+	LDY #$00
	LDA (net_rx_ptr),Y
	CMP #'W'
	BNE _out
	INY
	LDA (net_rx_ptr),Y
	CMP #'L'
	BNE _out
	INY
	LDA (net_rx_ptr),Y
	CMP #PT_INPUT
	BNE +
	JMP rx_input
+	CMP #PT_HELLO
	BEQ rx_hello
	CMP #PT_WELCOME
	BEQ rx_welcome
	CMP #PT_START
	BEQ rx_start
	CMP #PT_START_ACK
	BEQ rx_start_ack
_out
	RTS
.pend

rx_hello .proc
	; host: somebody wants to play
	LDA net_role
	CMP #ROLE_HOST
	BNE +
	LDA #$01
	STA net_connected
	JMP send_welcome
+	RTS
.pend

rx_welcome .proc
	LDA net_role
	CMP #ROLE_JOIN
	BNE +
	LDA #$01
	STA net_connected
+	RTS
.pend

rx_start .proc
	; join: the host starts a game
	LDA net_role
	CMP #ROLE_JOIN
	BNE _out
	LDY #3
	LDA (net_rx_ptr),Y
	#log_event_a EV_START_RX
	CMP game_id
	BEQ _ack ; a repeated START: only answer again
	STA game_id
	; a new game while a session is running: the host has given up the old one
	LDX session_active
	BEQ +
	LDX #$01
	STX abort_requested
+
	INY
	LDA (net_rx_ptr),Y
	STA start_seed_random
	INY
	LDA (net_rx_ptr),Y
	STA start_seed_rnd
	LDA #$01
	STA start_received
_ack
	JMP send_start_ack
_out
	RTS
.pend

rx_start_ack .proc
	LDA net_role
	CMP #ROLE_HOST
	BNE +
	LDY #3
	LDA (net_rx_ptr),Y
	CMP game_id
	BNE +
	#log_event EV_ACK_RX, game_id
	LDA #$01
	STA start_acked
+	RTS
.pend

ldy_ofs .macro
	; Y = \1 + in_ofs (the field offsets of INPUT differ by 2 between the direct and the server format)
	LDA #\1
	CLC
	ADC in_ofs
	TAY
.endm

rx_input .proc
	; the peer's inputs, offsets + in_ofs: [1] game / session id, [2/3] newest tick, [4/5] checksum tick,
	; [6/7] checksum, [8..23] inputs  (direct: in_ofs = 2 after 'W' 'L' type, server: in_ofs = 0 after $80)
	#ldy_ofs 8 + INPUT_WINDOW
	CPY net_rx_len
	BEQ +
	BCS _ignore ; too short
+	LDA session_active
	BEQ _ignore
	#ldy_ofs 1
	LDA (net_rx_ptr),Y
	CMP session_game_id ; inputs of this session only
	BEQ +
_ignore
	RTS
+
	INY
	LDA (net_rx_ptr),Y
	STA rx_newest
	INY
	LDA (net_rx_ptr),Y
	STA rx_newest+1
	; first tick in the packet = newest - 15; it must connect to what we have (first <= remote_newest + 1)
	SEC
	LDA rx_newest
	SBC #INPUT_WINDOW-1
	STA rx_tick
	LDA rx_newest+1
	SBC #0
	STA rx_tick+1
	CLC
	LDA remote_newest
	ADC #1
	STA rx_next
	LDA remote_newest+1
	ADC #0
	STA rx_next+1
	SEC
	LDA rx_next
	SBC rx_tick
	LDA rx_next+1
	SBC rx_tick+1
	BMI _out ; first > remote_newest + 1: a hole (cannot happen with a window of 16)
	LDA #$01
	STA rx_alive ; for proto_tick: the peer is alive
	; store all inputs
	#ldy_ofs 8
	LDX #INPUT_WINDOW
	STX rx_count
-	LDX rx_tick
	LDA (net_rx_ptr),Y
	STA remote_in,X
	INC rx_tick
	INY
	DEC rx_count
	BNE -
	; remote_newest = max(remote_newest, rx_newest)
	SEC
	LDA rx_newest
	SBC remote_newest
	LDA rx_newest+1
	SBC remote_newest+1
	BMI +
	LDA rx_newest
	STA remote_newest
	LDA rx_newest+1
	STA remote_newest+1
+
	; compare the peer's checksum with ours for that tick
	#ldy_ofs 4
	LDA (net_rx_ptr),Y
	STA rx_tick
	INY
	LDA (net_rx_ptr),Y
	STA rx_tick+1
	JSR check_peer_checksum
_out
	RTS
.pend

; -----------------------------------------

packet_header .proc
	; net_tx_buf = 'W' 'L' A, net_tx_len = X
	STA net_tx_buf+2
	STX net_tx_len
	LDA #'W'
	STA net_tx_buf
	LDA #'L'
	STA net_tx_buf+1
	RTS
.pend

send_hello .proc
	LDA #PT_HELLO
	LDX #4
	JSR packet_header
	LDA #PROTO_VERSION
	STA net_tx_buf+3
	JMP netio_send
.pend

send_welcome .proc
	LDA #PT_WELCOME
	LDX #5
	JSR packet_header
	LDA #PROTO_VERSION
	STA net_tx_buf+3
	LDA #INPUT_DELAY
	STA net_tx_buf+4
	JMP netio_send
.pend

send_start .proc
	LDA #PT_START
	LDX #6
	JSR packet_header
	LDA game_id
	STA net_tx_buf+3
	LDA start_seed_random
	STA net_tx_buf+4
	LDA start_seed_rnd
	STA net_tx_buf+5
	JMP netio_send
.pend

send_start_ack .proc
	LDA #PT_START_ACK
	LDX #4
	JSR packet_header
	LDA game_id
	STA net_tx_buf+3
	JMP netio_send
.pend

send_input .proc
	; our inputs of ticks local_newest-15 .. local_newest (field offsets + in_ofs, see rx_input)
	LDA in_ofs
	BEQ _server
	LDA #PT_INPUT
	LDX #10 + INPUT_WINDOW
	JSR packet_header
	JMP _fields
_server
	LDA #SM_INPUT
	STA net_tx_buf
	LDA #8 + INPUT_WINDOW
	STA net_tx_len
_fields
	LDX in_ofs
	LDA session_game_id
	STA net_tx_buf+1,X
	LDA local_newest
	STA net_tx_buf+2,X
	LDA local_newest+1
	STA net_tx_buf+3,X
	LDA my_chk_tick
	STA net_tx_buf+4,X
	LDA my_chk_tick+1
	STA net_tx_buf+5,X
	LDA my_chk
	STA net_tx_buf+6,X
	LDA my_chk+1
	STA net_tx_buf+7,X
	#ldy_ofs 8
	SEC
	LDA local_newest
	SBC #INPUT_WINDOW-1
	TAX
	LDA #INPUT_WINDOW
	STA rx_count
-	LDA local_in,X
	STA net_tx_buf,Y
	INX
	INY
	DEC rx_count
	BNE -
	JMP netio_send
.pend

;============================================================
;
; title screen (called by irq_hook every frame, outside a session)
;
;============================================================

proto_title_frame .proc
	LDA net_role
	CMP #ROLE_SERVER
	BNE +
	JMP srv_title_frame
+	JSR netio_poll
	BCS +
	JSR proto_rx
+
	LDA #$FF
	STA net_joy
	STA net_joy+1
	LDA net_role
	CMP #ROLE_HOST
	BEQ _host
	; join: the game starts when the host says so (fire on port 2 = a 2 player game in the original title loop)
	LDA start_received
	BEQ +
	LDA #$EF
	STA net_joy
+	RTS

_host
	LDA start_acked
	BEQ +
	LDA #$EF ; the peer confirmed: start
	STA net_joy
	RTS
+	LDA start_state
	BNE _starting
	; fire on the local joystick (port 2) or SPACE starts a new game for both
	.if !NETBOT ; (the network test starts by itself)
	JSR read_keyboard
	AND CIA1_JOY_KEY1
	AND #$10
	BNE _out
	.fi
	INC game_id
	JSR get_cycles
	LDA cycles
	EOR VIC_D012
	STA start_seed_random
	LDA cycles+1
	ORA #$01 ; an LFSR state of 0 would stay 0
	STA start_seed_rnd
	LDA #$01
	STA start_state
	LDA #$00
	STA start_resend
_starting
	; (re)send START every 8 frames until the peer confirms
	DEC start_resend
	BPL _out
	LDA #7
	STA start_resend
	#log_event EV_START_SENT, game_id
	JSR send_start
_out
	RTS
.pend

;============================================================
;
; session (called by game_net.asm)
;
;============================================================

proto_session_start .proc
	; seeds from the START packet, input buffers neutral
	LDA #$01
	STA net_busy
	LDA #$00
	STA ka_frames
	STA rx_alive
	LDA game_id
	STA session_game_id
	#log_event EV_SESSION_START, game_id
	LDA #0
	STA abort_requested
	STA first_tick_done
	LDA start_seed_random
	STA random_number
	LDA start_seed_rnd
	STA rnd_state
	LDX #0
	LDA #$FF
-	STA local_in,X
	STA remote_in,X
	INX
	BNE -
	LDX delay_ticks
	DEX
	STX local_newest
	STX remote_newest
	LDA #0
	STA local_newest+1
	STA remote_newest+1
	STA start_state
	STA start_received
	STA start_acked
	STA desync
	LDA #$FF ; no checksum yet
	STA my_chk_tick
	STA my_chk_tick+1
	LDX #3
-	STA chk_hist_tick_lo,X
	STA chk_hist_tick_hi,X
	DEX
	BPL -
	; player of this machine
	LDA net_role
	CMP #ROLE_SERVER
	BNE _direct
	LDX #1 ; server slot 0: player 1 = actor 1
	LDA srv_slot
	BEQ +
	LDX #0 ; slot 1: player 2 = actor 0
	BEQ + ; always branches
_direct
	LDX #1 ; host: player 1 = actor 1
	LDA net_role
	CMP #ROLE_HOST
	BEQ +
	LDX #0 ; join: player 2 = actor 0
+	STX local_actor
	TXA
	EOR #$01
	STA remote_actor
	LDA #$00
	STA net_busy
	RTS
.pend

proto_session_end .proc
	LDA #$01
	STA net_busy
	#log_event EV_SESSION_END, game_id
	LDA #0
	STA start_state
	STA start_received
	STA start_acked
	LDA net_role
	CMP #ROLE_SERVER
	BNE +
	; game over: tell the server (it also notices when the inputs stop)
	LDA #SM_SESSION_END
	STA net_tx_buf
	LDA session_game_id
	STA net_tx_buf+1
	LDA #1 ; reason: the game is over
	STA net_tx_buf+2
	LDA #3
	STA net_tx_len
	JSR netio_send
	LDA #SRV_LOBBY
	STA srv_state
+	LDA #$00
	STA net_busy
	RTS
.pend

; -----------------------------------------

net_session_irq .proc
	; called by the raster IRQ during a session. Between the dungeons the game shows its transition screens
	; (GET READY, DOUBLE SCORE ...) for many seconds without ticks, so nothing would be sent: the server would
	; drop the C64 after 10 s. When no tick ran for ~1/3 s, the IRQ answers pings, handles packets and repeats
	; the last INPUT every 10 frames. Never while the main program is inside the network code itself (net_busy).
	INC ka_frames
	BNE +
	DEC ka_frames ; stays at 255
+	LDA net_busy
	BNE _out
	LDA ka_frames
	CMP #20
	BCC _out ; ticks are running: the main program does the network
	LDA #1
	STA wic_gap ; (a WiC64 reads at most every ~50 ms here)
	JSR netio_poll
	BCS +
	JSR proto_rx
+	DEC ka_timer
	BPL _out
	LDA #10
	STA ka_timer
	JSR send_input
_out
	RTS
.pend

proto_tick .proc
	; called by tick (game_net.asm) after the pacing wait: inputs for tick_count
	LDA #$01
	STA net_busy ; the IRQ keeps its hands off the network meanwhile
	LDA #$00
	STA ka_frames
	; 1. state checksum every CHECK_EVERY ticks (the state before this tick's logic is the same on both machines)
	LDA tick_count
	AND #CHECK_EVERY-1
	BNE +
	JSR make_checksum
+
	; 2. our input for tick + INPUT_DELAY (joystick port 2)
	CLC
	LDA tick_count
	ADC delay_ticks
	STA local_newest
	LDA tick_count+1
	ADC #0
	STA local_newest+1
	.if NETBOT
	LDA local_newest
	STA det_bt
	LDA local_newest+1
	STA det_bt+1
	LDA local_actor
	STA det_ba
	JSR det_bot_value ; network test: a bot plays the local player
	.else
	JSR read_keyboard ; W A S D + SPACE, together with joystick port 2
	AND CIA1_JOY_KEY1
	ORA #$E0 ; only the joystick bits
	.fi
	LDX local_newest
	STA local_in,X
	LDA net_backend
	CMP #BACKEND_WIC64
	BNE _send
	LDA #0
	STA wic_gap ; poll as fast as possible while waiting
	LDA tick_count
	AND #WIC_SEND_EVERY-1
	BNE _sent ; a WiC64 transfer costs time: every 4th tick (each packet carries 16 ticks)
_send
	JSR send_input
_sent

	; 3. wait for the peer's input for this tick
	JSR get_cycles
	LDA cycles+1
	STA wait_start
	STA wait_last_send
	LDA cycles+2
	STA wait_start+1
	STA wait_last_send+1
	LDA #$00
	STA wait_shown
	LDA first_tick_done
	BNE _wait
	INC first_tick_done
	#log_event EV_FIRST_TICK, game_id
_wait
	LDA abort_requested
	BEQ +
	LDA #2
	JMP net_abort
+
	; remote_newest >= tick ?
	SEC
	LDA remote_newest
	SBC tick_count
	LDA remote_newest+1
	SBC tick_count+1
	BMI +
	JMP _ready
+	JSR netio_poll
	BCS +
	JSR proto_rx
	LDA rx_alive
	BEQ _wait
	; the peer sent inputs (perhaps only repeated ones from its transition screen): it is alive, wait on
	LDA #$00
	STA rx_alive
	JSR get_cycles
	LDA cycles+1
	STA wait_start
	LDA cycles+2
	STA wait_start+1
	JMP _wait
+	JSR get_cycles
	; resend every ~20 ms while waiting (the last packet may be lost)
	SEC
	LDA cycles+1
	SBC wait_last_send
	TAX
	LDA cycles+2
	SBC wait_last_send+1
	BNE _resend
	CPX resend_units
	BCC _no_resend
_resend
	LDA cycles+1
	STA wait_last_send
	LDA cycles+2
	STA wait_last_send+1
	JSR send_input
_no_resend
	; how long are we waiting?
	SEC
	LDA cycles+1
	SBC wait_start
	STA wait_elapsed
	LDA cycles+2
	SBC wait_start+1
	STA wait_elapsed+1
	CMP #>WAIT_ABORT
	BCC +
	LDA #1
	JMP net_abort
+	CMP #>WAIT_SHOW
	BCS +
	JMP _wait
+	; flash the border while waiting (restored afterwards: the border color belongs to the game)
	LDA wait_shown
	BNE +
	LDA VIC_D020
	STA wait_border
	INC wait_shown
+	LDA wait_elapsed+1
	STA VIC_D020
	JMP _wait

_ready
	LDA #1
	STA wic_gap
	LDA wait_shown
	BEQ +
	LDA wait_border
	STA VIC_D020
+
	; 4. the inputs of this tick
	LDX tick_count
	LDA local_in,X
	LDY local_actor
	STA net_joy,Y
	LDA remote_in,X
	LDY remote_actor
	STA net_joy,Y
	LDA #$00
	STA net_busy
	STA ka_frames
	RTS
.pend

net_abort .proc
	; A = reason (1: the peer is gone, 2: the host started another game)
	; back to the title screen (like RESTORE does), the connection stays
	STA abort_reason
	LDA #$00
	STA net_busy
	#log_event EV_ABORT, abort_reason
	LDA net_role
	CMP #ROLE_SERVER
	BNE +
	LDA #SRV_LOBBY ; the server put us back into the lobby
	STA srv_state
+	LDA #$00
	STA session_active
	JSR proto_session_end
	; like the NMI: with interrupts off (init_cset banks the char ROM in over the I/O for a moment; a raster IRQ
	; then could not acknowledge $D019 and would repeat forever). init_stuff enables them again.
	SEI
	LDX #$FF
	TXS
	JSR sfx.end_of_sfx
	JMP init_stuff
.pend

; -----------------------------------------

make_checksum .proc
	; a small checksum of the game state at the start of this tick -> my_chk / my_chk_tick and the history
	LDA #0
	STA my_chk
	STA my_chk+1
	LDX #$10 ; sprite positions
-	LDA $D000,X
	JSR _add
	DEX
	BPL -
	LDX #MAX_ACTORS-1
-	LDA actor_type_tbl,X
	JSR _add
	DEX
	BPL -
	LDX #11 ; both scores
-	LDA player1_score_string,X
	JSR _add
	DEX
	BPL -
	LDA lives_player1
	JSR _add
	LDA lives_player2
	JSR _add
	LDA current_dungeon
	JSR _add
	LDA random_number
	JSR _add
	LDA rnd_state
	JSR _add
	LDA tick_count
	STA my_chk_tick
	LDA tick_count+1
	STA my_chk_tick+1
	; history: slot = (tick / CHECK_EVERY) & 3 = bits 6-7 of the low byte
	LDA tick_count
	LSR A
	LSR A
	LSR A
	LSR A
	LSR A
	LSR A
	TAX
	LDA my_chk_tick
	STA chk_hist_tick_lo,X
	LDA my_chk_tick+1
	STA chk_hist_tick_hi,X
	LDA my_chk
	STA chk_hist_lo,X
	LDA my_chk+1
	STA chk_hist_hi,X
	RTS
_add
	ASL my_chk
	ROL my_chk+1
	BCC +
	INC my_chk
+	CLC
	ADC my_chk
	STA my_chk
	BCC +
	INC my_chk+1
+	RTS
.pend

	.cerror CHECK_EVERY != 64, "make_checksum computes the history slot for CHECK_EVERY = 64"

check_peer_checksum .proc
	; rx_tick = tick of the peer's checksum, (net_rx_ptr),8/9 = its value; compare with our history
	LDX #3
-	LDA chk_hist_tick_lo,X
	CMP rx_tick
	BNE +
	LDA chk_hist_tick_hi,X
	CMP rx_tick+1
	BEQ _found
+	DEX
	BPL -
	RTS ; not (or no longer) known
_found
	#ldy_ofs 6
	LDA (net_rx_ptr),Y
	CMP chk_hist_lo,X
	BNE _desync
	INY
	LDA (net_rx_ptr),Y
	CMP chk_hist_hi,X
	BNE _desync
	RTS
_desync
	LDA #$01
	STA desync
	#log_event EV_DESYNC, rx_tick
	RTS
.pend

;============================================================
;
; game server (role ROLE_SERVER), see server/docs/protocol.md
;
;============================================================

srv_rx .proc
	; a packet from the server
	LDY #0
	LDA (net_rx_ptr),Y
	BMI _input ; $80-$FF: game messages
	STA srv_type
	LDA #0
	STA srv_silence ; the server is alive
	STA srv_silence+1
	; dispatch through a table: type -> handler
	LDX #0
-	LDA _types,X
	BEQ _unknown
	CMP srv_type
	BEQ +
	INX
	BNE - ; always branches
+	LDA _handlers_hi,X
	PHA
	LDA _handlers_lo,X
	PHA
	RTS ; jumps to the handler (address - 1 on the stack)
_unknown
	RTS
_types		.byte SM_PING, SM_LOBBY, SM_PLAYERS, SM_CHALLENGE, SM_CANCELLED, SM_START, SM_SESSION_END, SM_OPPONENT_LEFT, SM_WELCOME, SM_REJECT, 0
_handlers_lo	.byte <(_ping-1), <(_lobby-1), <(lobby_rx_players-1), <(_challenge-1), <(_cancelled-1), <(srv_rx_start-1), <(_end-1), <(_left-1), <(_welcome-1), <(_reject-1)
_handlers_hi	.byte >(_ping-1), >(_lobby-1), >(lobby_rx_players-1), >(_challenge-1), >(_cancelled-1), >(srv_rx_start-1), >(_end-1), >(_left-1), >(_welcome-1), >(_reject-1)
_input
	LDA #0
	STA srv_silence
	STA srv_silence+1
	JMP rx_input
_ping
	; answer with PONG and the same token
	LDY #1
	LDA (net_rx_ptr),Y
	STA net_tx_buf+1
	INY
	LDA (net_rx_ptr),Y
	STA net_tx_buf+2
	LDA #SM_PONG
	STA net_tx_buf
	LDA #3
	STA net_tx_len
	JMP netio_send
_lobby
	LDY #1
	LDA (net_rx_ptr),Y
	STA srv_waiting
	LDA srv_state
	CMP #SRV_CONNECTING
	BNE +
	LDA #SRV_LOBBY ; LOBBY also confirms a repeated HELLO
	STA srv_state
+	RTS
_welcome
	LDA #$01
	STA net_connected
	LDA srv_state
	CMP #SRV_CONNECTING
	BNE +
	LDA #SRV_LOBBY
	STA srv_state
+	RTS
_reject
	LDY #1
	LDA (net_rx_ptr),Y
	STA srv_reject
	RTS
_challenge
	; [1] id, [2] length, [3..] nickname of the opponent
	LDA session_active
	BNE _out
	LDY #1
	LDA (net_rx_ptr),Y
	STA srv_challenge
	LDA srv_state
	CMP #SRV_ACCEPTED
	BNE +
	JMP srv_send_accept ; repeated challenge after our ACCEPT: answer again
+	CMP #SRV_STARTING
	BEQ _out
	INY
	LDA (net_rx_ptr),Y
	CMP #NICK_MAX+1
	BCC +
	LDA #NICK_MAX
+	STA opp_len
	LDX #0
-	CPX opp_len
	BEQ +
	INY
	LDA (net_rx_ptr),Y
	STA opp_nick,X
	INX
	BNE - ; always branches
+	LDA #SRV_CHALLENGED
	STA srv_state
_out
	RTS
_cancelled
	; [1] challenge id (0: the answer to our INVITE), [2] reason 1 declined, 2 no answer, 3 a player left, 4 not free
	LDA session_active
	BNE _out
	LDY #1
	LDA (net_rx_ptr),Y
	BNE +
	LDA srv_state
	CMP #SRV_INVITING
	BNE _out
	BEQ _to_lobby ; always branches
+	LDA srv_state
	CMP #SRV_CHALLENGED
	BEQ _to_lobby
	CMP #SRV_ACCEPTED
	BEQ _to_lobby
	CMP #SRV_INVITING
	BNE _out ; in the lobby already (we declined or withdrew ourselves): nothing to say
_to_lobby
	LDA #SRV_LOBBY
	STA srv_state
	INY
	LDA (net_rx_ptr),Y
	AND #$03 ; 1-4 -> 1, 2, 3, 0
	TAX
	LDA _cancel_msg,X
	JMP srv_message
_cancel_msg	.byte MSG_NOT_FREE, MSG_DECLINED, MSG_NO_ANSWER, MSG_PLAYER_LEFT
_end
	; [1] session, [2] reason
	LDA session_active
	BEQ _out
	LDY #1
	LDA (net_rx_ptr),Y
	CMP session_game_id
	BNE _out
	INY
	LDA (net_rx_ptr),Y
	CMP #2 ; desync
	BNE +
	LDA #MSG_DESYNC
	JSR srv_message
+	LDA #3
	STA abort_requested ; proto_tick leaves the session
	RTS
_left
	LDA session_active
	BEQ _out
	LDA #MSG_OPPONENT_LEFT
	JSR srv_message
	LDA #3
	STA abort_requested
	RTS
.pend

srv_rx_start .proc
	; START: [1] session, [2] slot, [3] players, [4] parameter length, [5..8] seed random, seed rnd, input delay, tick rate
	LDY #1
	LDA (net_rx_ptr),Y
	STA srv_start_session
	LDA session_active
	BNE _ack ; already playing: only confirm again
	LDA srv_state
	CMP #SRV_STARTING
	BEQ _ack
	LDA srv_start_session
	STA game_id ; proto_session_start copies it to session_game_id
	INY
	LDA (net_rx_ptr),Y
	STA srv_slot
	LDY #5
	LDA (net_rx_ptr),Y
	STA start_seed_random
	INY
	LDA (net_rx_ptr),Y
	BNE +
	LDA #$01 ; an LFSR state of 0 would stay 0
+	STA start_seed_rnd
	LDY #4 ; parameter 2: the input delay (1-12), if the server sends it
	LDA (net_rx_ptr),Y ; parameter length
	CMP #3
	BCC _default
	LDY #7
	LDA (net_rx_ptr),Y
	BEQ _default
	CMP #13
	BCC +
_default
	LDA #INPUT_DELAY
+	STA delay_ticks
	LDA #SRV_STARTING
	STA srv_state
	LDA #$01
	STA start_received ; the title screen starts the game
_ack
	LDA #SM_START_ACK
	STA net_tx_buf
	LDA srv_start_session
	STA net_tx_buf+1
	LDA #2
	STA net_tx_len
	JMP netio_send
.pend

srv_send_accept .proc
	LDA #SM_ACCEPT
	BNE srv_send_answer ; always branches
.pend

srv_send_decline .proc
	LDA #SM_DECLINE
	; fall through
.pend

srv_send_answer .proc
	STA net_tx_buf
	LDA srv_challenge
	STA net_tx_buf+1
	LDA #2
	STA net_tx_len
	JMP netio_send
.pend

srv_send_invite .proc
	; INVITE: [1] client id of the player, [2] sequence number
	LDA #SM_INVITE
	STA net_tx_buf
	LDA invite_id
	STA net_tx_buf+1
	LDA invite_seq
	STA net_tx_buf+2
	LDA #3
	STA net_tx_len
	JMP netio_send
.pend

srv_send_withdraw .proc
	; DECLINE with challenge id 0: we take our invitation back
	LDA #SM_DECLINE
	STA net_tx_buf
	LDA #0
	STA net_tx_buf+1
	LDA #2
	STA net_tx_len
	JMP netio_send
.pend

srv_send_hello .proc
	LDA #SM_HELLO
	STA net_tx_buf
	LDA #1 ; protocol version
	STA net_tx_buf+1
	LDA #SERVER_GAME_ID
	STA net_tx_buf+2
	LDA #SERVER_GAME_VERSION
	STA net_tx_buf+3
	LDA my_nick_len
	STA net_tx_buf+4
	LDX #0
-	CPX my_nick_len
	BEQ +
	LDA my_nick,X
	STA net_tx_buf+5,X
	INX
	BNE - ; always branches
+	TXA
	CLC
	ADC #5
	STA net_tx_len
	JMP netio_send
.pend

srv_message .proc
	; A = message shown on the status line for about 4 seconds
	STA srv_msg
	LDA #240
	STA srv_msg_timer
	RTS
.pend

; -----------------------------------------

srv_title_frame .proc
	; title screen in the lobby: network, answering a challenge, the status line, starting the game
	JSR netio_poll
	BCS +
	JSR proto_rx
+
	; no answer from the server for ~10 s: say HELLO again (the server may have restarted)
	INC srv_silence
	BNE +
	INC srv_silence+1
+	LDA srv_silence+1
	CMP #3 ; 768 frames
	BCC _alive
	LDA srv_silence
	AND #$1F
	BNE +
	JSR srv_send_hello
	LDA #MSG_NO_SERVER
	JSR srv_message
+	LDA #SRV_CONNECTING
	STA srv_state
_alive
	INC lobby_frame
	LDA #$FF
	STA net_joy
	STA net_joy+1
	JSR lobby_check_setup ; F1 (lobby.asm)
	JSR lobby_read_joy
	STA lobby_new
	LDA srv_state
	CMP #SRV_LOBBY
	BNE +
	JSR lobby_input ; choose a player and challenge him (lobby.asm)
	JMP _draw
+	CMP #SRV_INVITING
	BNE +
	JSR lobby_inviting
	JMP _draw
+	CMP #SRV_CHALLENGED
	BNE _not_challenged
	; FIRE (joystick port 2 or SPACE) accepts, N declines
	LDA test_accept ; set by test tools through the VICE monitor
	BNE _accept
	JSR read_keyboard
	AND CIA1_JOY_KEY1
	AND #$10
	BNE +
_accept
	LDA #SRV_ACCEPTED
	STA srv_state
	JSR srv_send_accept
	JMP _draw
+	JSR key_n_pressed
	BCC _draw
	LDA #SRV_LOBBY
	STA srv_state
	JSR srv_send_decline
	JMP _draw
_not_challenged
	LDA start_received
	BEQ _draw
	LDA #$EF ; START from the server: fire on port 2 = a 2 player game in the original title loop
	STA net_joy
_draw
	LDA srv_msg_timer
	BEQ +
	DEC srv_msg_timer
+	JMP srv_draw_status
.pend

key_n_pressed .proc
	; C=1 if N is pressed (keyboard column 4, row 7); rows held low by joystick port 1 are ignored
	LDA #$FF
	STA CIA1_JOY_KEY1
	LDA CIA1_JOY_KEY2
	EOR #$FF
	STA kb_mask
	LDA #%11101111
	STA CIA1_JOY_KEY1
	LDA CIA1_JOY_KEY2
	ORA kb_mask
	LDX #$FF
	STX CIA1_JOY_KEY1
	ASL A ; row 7 -> C (0 = pressed)
	BCS +
	SEC
	RTS
+	CLC
	RTS
.pend

; -----------------------------------------
; the status line: the bottom row of the title screen, written every frame (the title screens clear the
; screen now and then); characters of the game's own character set (encoding "charrom")

	STATUS_ROW = $0400 + 24 * 40
	STATUS_COLOR = $D800 + 24 * 40

srv_draw_status .proc
	LDX #39
	LDA #$00 ; space
-	STA status_buf,X
	DEX
	BPL -
	LDA #0
	STA status_pos
	LDA srv_msg_timer
	BEQ _state
	LDX srv_msg
	LDA msg_lo-1,X
	LDY msg_hi-1,X
	JSR status_text
	JMP _show
_state
	LDX srv_state
	LDA state_lo,X
	LDY state_hi,X
	JSR status_text
	LDA srv_state
	CMP #SRV_INVITING
	BNE +
	JSR status_nick
	LDA #<txt_cancel
	LDY #>txt_cancel
	JSR status_text
	JMP _show
+	CMP #SRV_CHALLENGED
	BNE +
	JSR status_nick
	LDA #<txt_fire
	LDY #>txt_fire
	JSR status_text
	JMP _show
+	CMP #SRV_ACCEPTED
	BNE _show
	JSR status_nick
_show
	; white; a challenge flashes yellow / white
	LDY #1
	LDA srv_msg_timer
	BNE +
	LDA srv_state
	CMP #SRV_CHALLENGED
	BNE +
	LDA lobby_frame
	AND #$10
	BEQ +
	LDY #7
+	LDX #39
-	LDA status_buf,X
	STA STATUS_ROW,X
	TYA ; hires colors (< 8)
	STA STATUS_COLOR,X
	DEX
	BPL -
	RTS
.pend

status_text .proc
	; appends the text at A (lo) / Y (hi), terminated by $FF (in the game's character set $00 is a space)
	STA str_ptr2
	STY str_ptr2+1
	LDY #0
-	LDA (str_ptr2),Y
	CMP #$FF
	BEQ +
	LDX status_pos
	CPX #40
	BCS +
	STA status_buf,X
	INC status_pos
	INY
	BNE -
+	RTS
.pend

status_nick .proc
	; appends the opponent's nickname (ASCII A-Z 0-9 -> game characters)
	LDX #0
-	CPX opp_len
	BEQ +
	LDA opp_nick,X
	JSR ascii_to_game
	LDY status_pos
	STA status_buf,Y
	INC status_pos
	INX
	BNE - ; always branches
+	RTS
.pend

ascii_to_game .proc
	; ASCII 'A'-'Z' / '0'-'9' -> code in the game's character set
	CMP #'A'
	BCC _digit
	SEC
	SBC #'A'
	CLC
	ADC #CHAR_A
	RTS
_digit
	SEC
	SBC #'0'
	CLC
	ADC #CHAR_0
	RTS
.pend

	CHAR_A = $69 ; encoding "charrom" of the original source: a-z = $69-$82, 0-9 = $83-$8C, space = $00
	CHAR_0 = $83

	.enc "charrom"
txt_connecting	.text "connecting to the server", $FF
txt_waiting	.text "choose your opponent", $FF
txt_cancel	.text "  n cancel", $FF
txt_challenge	.text "challenge from ", $FF
txt_fire	.text "  fire play  n no", $FF
txt_accepted	.text "waiting for ", $FF
txt_starting	.text "starting", $FF
txt_left	.text "your opponent left", $FF
txt_desync	.text "desync  the game was stopped", $FF
txt_declined	.text "no game  back to the lobby", $FF
txt_no_server	.text "no answer from the server", $FF
txt_not_free	.text "that player is not free", $FF
txt_no_answer	.text "no answer  back to the lobby", $FF
txt_player_left	.text "the player has left", $FF
	.enc "setup"

state_lo	.byte <txt_connecting, <txt_waiting, <txt_challenge, <txt_accepted, <txt_starting, <txt_accepted
state_hi	.byte >txt_connecting, >txt_waiting, >txt_challenge, >txt_accepted, >txt_starting, >txt_accepted
msg_lo		.byte <txt_left, <txt_desync, <txt_declined, <txt_no_server, <txt_not_free, <txt_no_answer, <txt_player_left
msg_hi		.byte >txt_left, >txt_desync, >txt_declined, >txt_no_server, >txt_not_free, >txt_no_answer, >txt_player_left

; -----------------------------------------

setup_server .proc
	; play via the C64 Game Server: own ip (RR-Net), nickname, server ip, HELLO
	LDA net_backend
	CMP #BACKEND_RRNET
	BNE +
	JSR setup_my_ip_rrnet
	BCC +
	JMP wait_key_menu
+	LDA cfg_auto
	BEQ _nick
	JMP _connect
_nick
	JSR print_inline
	.null 13, 13, C_CYAN, "YOUR NAME (A-Z, 0-9, MAX 8)"
	LDA #<my_nick
	LDY #>my_nick
	LDX my_nick_len
	JSR cfg_show ; " [ERIK]: "
	JSR read_line
	LDX host_len
	BNE +
	LDA my_nick_len ; RETURN keeps the name
	BEQ _nick
	BNE _server ; always branches
+	CPX #NICK_MAX+1
	BCS _nick
	DEX
-	LDA host_input,X
	CMP #'0'
	BCC _nick
	CMP #'9'+1
	BCC +
	CMP #'A'
	BCC _nick
	CMP #'Z'+1
	BCS _nick
+	STA my_nick,X ; PETSCII upper case letters and digits are ASCII
	DEX
	BPL -
	LDA host_len
	STA my_nick_len
_server
	JSR print_inline
	.null 13, C_CYAN, "IP OF THE GAME SERVER"
	LDA #<cfg_server
	LDY #>cfg_server
	LDX cfg_server_len
	JSR cfg_show
	JSR read_line
	LDX host_len
	BNE +
	LDA cfg_server_len ; RETURN keeps the server
	BNE _typed
	JMP net_setup.net_menu
+	CPX #CFG_SERVER_MAX+1
	BCS _server
	STX cfg_server_len
	DEX
-	LDA host_input,X
	STA cfg_server,X
	DEX
	BPL -
_typed
	LDA #1
	STA cfg_dirty ; save after connecting
_connect
	LDX #0
-	LDA cfg_server,X
	STA net_host,X
	INX
	CPX cfg_server_len
	BNE -
	LDA #0
	STA net_host,X
	JSR netio_close
	LDA #<SERVER_PORT
	STA net_port
	LDA #>SERVER_PORT
	STA net_port+1
	LDA #ROLE_SERVER
	STA net_role
	LDA #0 ; server packets: type, then the fields
	STA in_ofs
	STA srv_reject
	STA srv_msg_timer
	STA srv_silence
	STA srv_silence+1
	LDA #SRV_CONNECTING
	STA srv_state
	LDA net_backend
	CMP #BACKEND_UCI
	BNE _rr
	LDA #uci.NET_CMD_OPEN_UDP
	JSR uci.net_open
	JMP _opened
_rr
	CMP #BACKEND_WIC64
	BNE _rrnet
	JSR wic.net_open
	JMP _opened
_rrnet
	#rr_call rr.net_open
_opened
	BCC +
	JSR print_inline
	.null C_LRED, "CANNOT OPEN THE CONNECTION", 13, C_WHITE
	JMP wait_key_menu
+	INC net_is_open
	JSR print_inline
	.null 13, C_YELLOW, "CALLING THE SERVER", 13, C_LGREY, "(ANY KEY = SETUP)", 13, C_YELLOW
	LDA #0
	STA hello_timer
	STA hello_timer+1
_loop
	JSR GETIN
	BEQ +
	JMP net_setup.net_menu
+	; HELLO about every half second
	JSR get_cycles
	LDA cycles+2
	CMP hello_timer
	BEQ +
	STA hello_timer
	INC hello_timer+1
	LDA hello_timer+1
	AND #$07
	BNE +
	JSR srv_send_hello
	LDA #'.'
	JSR CHROUT
+	JSR netio_poll
	BCS _loop
	JSR proto_rx
	LDA srv_reject
	BNE _rejected
	LDA srv_state
	CMP #SRV_CONNECTING
	BEQ _loop
	JSR cfg_save ; typed in: keep it in WOW.CFG (config.asm)
	JMP start_the_game ; connected: the lobby screen (lobby.asm) replaces the title screens
_rejected
	JSR print_inline
	.null 13, C_LRED, "THE SERVER SAYS NO: "
	LDX srv_reject
	CPX #6
	BCC +
	LDX #0
+	LDA reject_lo,X
	LDY reject_hi,X
	JSR print_string
	JMP wait_key_menu
.pend

print_string .proc
	; prints the zero terminated string at A (lo) / Y (hi)
	STA str_ptr2
	STY str_ptr2+1
	LDY #0
-	LDA (str_ptr2),Y
	BEQ +
	JSR CHROUT
	INY
	BNE -
+	RTS
.pend

rej_0	.null "?"
rej_1	.null "THE NAME IS IN USE"
rej_2	.null "WRONG VERSION"
rej_3	.null "UNKNOWN GAME"
rej_4	.null "THE SERVER IS FULL"
rej_5	.null "INVALID NAME"
reject_lo	.byte <rej_0, <rej_1, <rej_2, <rej_3, <rej_4, <rej_5
reject_hi	.byte >rej_0, >rej_1, >rej_2, >rej_3, >rej_4, >rej_5

;============================================================
;
; setup menu (before the game starts; KERNAL text output)
;
;============================================================

net_setup .proc
	JSR net_game_init ; CIA2 cycle counter (ip65 timer, timeouts)
	LDA #ROLE_LOCAL
	STA net_role
	LDA #BACKEND_NONE
	STA net_backend
	LDA #$00
	STA net_connected
	STA netio_state
	STA netio_tx_pending
	STA game_id
	STA start_state
	STA start_received
	STA start_acked
	LDA #2
	STA uci_timeout_secs
	LDA #<GAME_PORT
	STA net_port
	LDA #>GAME_PORT
	STA net_port+1
	LDA #2 ; direct packets: 'W' 'L' type, then the fields
	STA in_ofs
	LDA #INPUT_DELAY
	STA delay_ticks
	LDA #WAIT_RESEND
	STA resend_units
	LDA #1
	STA wic_gap
	LDA #$80
	STA netio_kernal
	.if (PROFILE || DETTEST) && !NETBOT
	JMP start_the_game ; test builds play locally
	.fi
	LDA $D012
	ORA #$01
	STA mac_last
	LDA #0 ; black, like the game
	STA $D021
	STA $D020
	JSR cfg_first_init
	LDA cfg_force_menu ; F1 in the lobby: the menu
	BNE net_menu
	JSR cfg_load ; WOW.CFG on the disk (config.asm)
	BCS net_menu
	JSR print_inline
	.null 147, C_YELLOW, "WELCOME DUNGEON MASTER", 13, C_LBLUE, "AT THE WIZARD OF WOR LOBBY", 13, 13
	JSR netio_detect
	LDA net_backend
	BEQ net_menu ; no network: the menu says why
	LDA #1
	STA cfg_auto
	JMP setup_server

net_menu
	LDA #0
	STA cfg_auto
	STA cfg_force_menu
	JSR netio_close
	JSR print_inline
	.null 147, C_YELLOW, "WIZARD OF WOR", C_LBLUE, "  NETWORK EDITION", 13, 13
	JSR netio_detect
	LDA net_backend
	CMP #BACKEND_UCI
	BNE +
	JSR print_inline
	.null C_CYAN, "NETWORK: ", C_WHITE, "C64 ULTIMATE", 13, C_CYAN, "MY IP:   ", C_WHITE
	JSR uci.net_get_ip
	JSR print_ip
	JMP _items
+	CMP #BACKEND_RRNET
	BNE +
	JSR print_inline
	.null C_CYAN, "NETWORK: ", C_WHITE, "RR-NET", 13
	JMP _items
+	CMP #BACKEND_WIC64
	BNE +
	JSR print_inline
	.null C_CYAN, "NETWORK: ", C_WHITE, "WIC64", 13, C_CYAN, "MY IP:   ", C_WHITE
	JSR wic.net_print_ip
	JSR print_inline
	.null 13
	JMP _items
+	JSR print_inline
	.null C_LRED, "NO NETWORK HARDWARE FOUND", 13, C_LGREY, "(ULTIMATE: ENABLE THE COMMAND INTERFACE)", 13
_items
	JSR print_inline
	.null 13, C_CYAN, "CONTROLS: ", C_WHITE, "JOYSTICK 2 OR W A S D + SPACE", 13, C_LGREY, "(LOCAL GAME: KEYBOARD OR PORT 1 = PL. 1)", 13, 13, C_YELLOW, "1  ", C_LBLUE, "LOCAL GAME", 13
	LDA net_backend
	CMP #BACKEND_RRNET
	BNE +
	JSR print_inline
	.null C_YELLOW, "2  ", C_LBLUE, "HOST A NETWORK GAME", 13
+	LDA net_backend
	BEQ +
	CMP #BACKEND_WIC64
	BEQ _wic_items ; TCP only: no direct games
	JSR print_inline
	.null C_YELLOW, "3  ", C_LBLUE, "JOIN A NETWORK GAME", 13
_wic_items
	JSR print_inline
	.null C_YELLOW, "4  ", C_LBLUE, "PLAY VIA A GAME SERVER", 13
+	JSR print_inline
	.null 13, C_CYAN, "YOUR CHOICE? ", C_WHITE
-	JSR GETIN
	CMP #'1'
	BEQ _local
	LDX net_backend
	BEQ -
	CPX #BACKEND_WIC64
	BEQ +
	CMP #'3'
	BEQ _join
+
	CMP #'4'
	BEQ _server
	CPX #BACKEND_RRNET
	BNE -
	CMP #'2'
	BNE -
	JMP setup_host
_local
	LDA #ROLE_LOCAL
	STA net_role
	JMP start_the_game
_join
	JMP setup_join
_server
	JMP setup_server
.pend

; -----------------------------------------

setup_my_ip_rrnet .proc
	; RR-Net: own address by DHCP or typed in; C=1: failed
	JSR print_inline
	.null 13, 13, C_CYAN, "MY IP (RETURN = DHCP): ", C_WHITE
	JSR cfg_myip_line ; typed in, or from the settings (config.asm)
	LDA host_len
	BNE _static
	JSR print_inline
	.null "DHCP... "
	#rr_call rr.net_dhcp
	BCC _ok
	JSR print_inline
	.null C_LRED, "FAILED", 13, C_WHITE
	SEC
	RTS
_static
	LDX #<host_input
	LDY #>host_input
	JSR rr.parse_ip
	BCC +
	RTS
+	; MAC: the last byte is the last byte of the ip, so two machines differ; ip65 must be started again for it
	LDA parsed_ip+3
	STA mac_last
	#rr_call rr.net_detect
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
	#rr_call rr.net_set_ip
_ok
	JSR print_inline
	.null 13, C_CYAN, "MY IP: ", C_WHITE
	#rr_call rr.net_get_ip
	JSR print_ip
	CLC
	RTS
.pend

; -----------------------------------------

setup_host .proc
	JSR setup_my_ip_rrnet
	BCC +
	JMP wait_key_menu
+	LDA #ROLE_HOST
	STA net_role
	#rr_call rr.net_listen
	JSR print_inline
	.null 13, 13, C_YELLOW, "WAITING FOR PLAYER 2 ON PORT 6464", 13, C_LGREY, "(ANY KEY = BACK)", 13, C_WHITE
-	JSR GETIN
	BEQ +
	JMP net_setup.net_menu
+	JSR netio_poll
	BCS -
	JSR proto_rx
	LDA net_connected
	BEQ -
	JSR print_inline
	.null 13, C_YELLOW, "PLAYER 2 IS HERE.", 13, C_WHITE, "YOU ARE PLAYER 1 (YELLOW).", 13, "PRESS FIRE ON THE TITLE SCREEN TO START.", 13
	JMP start_after_key
.pend

; -----------------------------------------

setup_join .proc
	LDA net_backend
	CMP #BACKEND_RRNET
	BNE +
	JSR setup_my_ip_rrnet
	BCC +
	JMP wait_key_menu
+	JSR print_inline
	.null 13, 13, C_CYAN, "IP OF THE HOST: ", C_WHITE
	JSR read_line
	LDA host_len
	BNE +
	JMP net_setup.net_menu
+	LDX host_len
-	LDA host_input,X
	STA net_host,X
	DEX
	BPL -
	LDA #ROLE_JOIN
	STA net_role
	LDA net_backend
	CMP #BACKEND_UCI
	BNE _rr
	LDA #uci.NET_CMD_OPEN_UDP
	JSR uci.net_open
	JMP _opened
_rr
	#rr_call rr.net_open
_opened
	BCC +
	JSR print_inline
	.null C_LRED, "CANNOT OPEN THE CONNECTION", 13, C_WHITE
	JMP wait_key_menu
+	INC net_is_open
	JSR print_inline
	.null C_YELLOW, "CALLING THE HOST", 13, C_LGREY, "(ANY KEY = BACK)", 13, C_YELLOW
	LDA #0
	STA hello_timer
	STA hello_timer+1
_loop
	JSR GETIN
	BEQ +
	JMP net_setup.net_menu
+	; HELLO about every half second
	JSR get_cycles
	LDA cycles+2
	CMP hello_timer
	BEQ +
	STA hello_timer
	INC hello_timer+1
	LDA hello_timer+1
	AND #$07
	BNE +
	JSR send_hello
	LDA #'.'
	JSR CHROUT
+	JSR netio_poll
	BCS _loop
	JSR proto_rx
	LDA net_connected
	BEQ _loop
	JSR print_inline
	.null 13, C_YELLOW, "CONNECTED.", 13, C_WHITE, "YOU ARE PLAYER 2 (BLUE).", 13, "THE HOST STARTS THE GAME.", 13
	JMP start_after_key
.pend

; -----------------------------------------

start_after_key .proc
	JSR print_inline
	.null 13, C_CYAN, "PRESS A KEY", C_WHITE
-	JSR netio_poll ; keep answering (the host: repeated HELLOs)
	BCS +
	JSR proto_rx
+	JSR GETIN
	BEQ -
	; fall through
.pend

start_the_game .proc
	LDA #$00
	STA netio_kernal ; from now on the KERNAL does not run: ip65 calls need no zero page saving
	SEI
	JMP ($8000) ; the cartridge style boot vector of the game
.pend

wait_key_menu .proc
	JSR print_inline
	.null 13, C_CYAN, "PRESS A KEY", C_WHITE
-	JSR GETIN
	BEQ -
	JMP net_setup.net_menu
.pend

; -----------------------------------------
; helpers (KERNAL)

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

read_line .proc
	; a line from the screen editor into host_input (zero terminated), length in host_len
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

print_ip .proc
	; the 4 bytes at net_ipcfg as a dotted ip
	LDX #$00
-	STX ip_idx
	LDA net_ipcfg,X
	JSR print_u8
	LDX ip_idx
	INX
	CPX #4
	BEQ +
	LDA #'.'
	JSR CHROUT
	JMP -
+	RTS
.pend

print_u8 .proc
	; A as decimal without leading zeros
	LDY #'0'-1
	SEC
-	INY
	SBC #100
	BCS -
	ADC #100
	CPY #'0'
	BEQ +
	PHA
	TYA
	JSR CHROUT
	PLA
	LDX #1
	BNE _tens ; always branches: after a hundreds digit the tens digit is printed even if 0
+	LDX #0
_tens
	LDY #'0'-1
	SEC
-	INY
	SBC #10
	BCS -
	ADC #10
	CPY #'0'
	BNE +
	CPX #0
	BEQ ++
+	PHA
	TYA
	JSR CHROUT
	PLA
+	ORA #'0'
	JMP CHROUT
.pend

	.if NETBOT
ev_log .proc
	; X = code, A = extra; keeps Y (the callers read packets with it)
	STA ev_extra
	TYA
	PHA
	LDA ev_count+1
	BNE _full
	LDA ev_count
	ASL A
	ASL A
	STA ev_ptr_lo
	LDA ev_count
	LSR A
	LSR A
	LSR A
	LSR A
	LSR A
	LSR A
	CLC
	ADC #>EV_BUF
	STA _store+2
	STA _store2+2
	STA _store3+2
	STA _store4+2
	LDY ev_ptr_lo
	TXA
_store	STA EV_BUF,Y
	LDA tick_count
_store2	STA EV_BUF+1,Y
	LDA tick_count+1
_store3	STA EV_BUF+2,Y
	LDA ev_extra
_store4	STA EV_BUF+3,Y
	INC ev_count
	BNE _full
	INC ev_count+1
_full
	PLA
	TAY
	RTS
.pend
ev_count	.word 0
ev_extra	.byte 0
ev_ptr_lo	.byte 0
ev_a		.byte 0
	.fi

;============================================================
;
; variables
;
;============================================================

	net_host_size = 32

net_role	.byte 0
net_backend	.byte 0
net_connected	.byte 0
netio_kernal	.byte 0 ; $80 during the setup menu
netio_state	.byte 0
netio_tx_pending .byte 0
kernal_zp_save	.fill $F8-$EA+1
mac_last	.byte 0
game_id		.byte 0
start_seed_random	.byte 0
start_seed_rnd	.byte 0
start_state	.byte 0
start_resend	.byte 0
start_received	.byte 0
start_acked	.byte 0
local_actor	.byte 0
remote_actor	.byte 0
local_newest	.word 0
remote_newest	.word 0
rx_newest	.word 0
rx_tick		.word 0
rx_next		.word 0
rx_count	.byte 0
rx_alive	.byte 0
net_busy	.byte 0
ka_frames	.byte 0
ka_timer	.byte 0
in_ofs		.byte 2 ; INPUT field offset: 2 direct ('W' 'L' type), 0 server (type)
srv_state	.byte 0
srv_type	.byte 0
srv_waiting	.byte 0
srv_challenge	.byte 0
srv_slot	.byte 0
srv_start_session .byte 0
srv_reject	.byte 0
srv_msg		.byte 0
srv_msg_timer	.byte 0
srv_silence	.word 0
my_nick		.fill NICK_MAX
my_nick_len	.byte 0
opp_nick	.fill NICK_MAX
opp_len		.byte 0
status_buf	.fill 40
status_pos	.byte 0
wait_start	.word 0
wait_last_send	.word 0
wait_elapsed	.word 0
wait_shown	.byte 0
wait_border	.byte 0
desync		.byte 0
session_game_id	.byte 0
abort_requested	.byte 0
abort_reason	.byte 0
first_tick_done	.byte 0
my_chk		.word 0
my_chk_tick	.word 0
chk_hist_tick_lo .fill 4
chk_hist_tick_hi .fill 4
chk_hist_lo	.fill 4
chk_hist_hi	.fill 4
hello_timer	.word 0
test_accept	.byte 0 ; tests: 1 = accept every challenge (written through the VICE monitor)
delay_ticks	.byte INPUT_DELAY ; from START (server) or INPUT_DELAY (direct)
resend_units	.byte WAIT_RESEND
wic_gap		.byte 1 ; WiC64: 1 = read at most every ~50 ms (title screen, lobby), 0 = as fast as possible
host_input	.fill net_host_size
host_len	.byte 0
ip_idx		.byte 0

	; used by the drivers (uci.asm, net_rrnet.asm)
net_port	.word 0
net_host	.fill net_host_size
net_socket	.byte 0
net_tx_len	.byte 0
net_tx_buf	.fill 32
net_read_max	.byte 0
net_rx_len	.byte 0
net_ipcfg	.fill 12
uci_pending	.byte 0
uci_resp_len	.word 0
uci_stat_len	.byte 0
uci_code	.byte 0
uci_tmo		.fill 3
uci_timeout_secs .byte 0
uci_stat	.fill uci.UCI_STAT_MAX
net_peer_ip	.fill 4
net_peer_known	.byte 0
parsed_ip	.fill 4
net_retries	.byte 0
net_rx_held	.byte 0
net_rx_copy_len	.byte 0
net_rx_copy	.fill 128
net_digits	.byte 0
net_tmp		.byte 0

	.align $100
local_in	.fill 256 ; inputs by tick (low byte)
remote_in	.fill 256
uci_resp	.fill uci.UCI_RESP_MAX

	.cerror * > $8000, "the network code must end below $8000"
