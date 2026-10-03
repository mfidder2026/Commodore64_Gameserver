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

	BACKEND_NONE = 0
	BACKEND_UCI = 1
	BACKEND_RRNET = 2

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

	; KERNAL (setup menu only)
	CHROUT = $FFD2
	CHRIN = $FFCF
	GETIN = $FFE4

	; text is printed with CHROUT: PETSCII, upper case letters $41-$5A
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
	LDA #BACKEND_NONE
	BCS +
	LDA #BACKEND_RRNET
+	STA net_backend
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
	SEC
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
	LDA net_rx_len
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

rx_input .proc
	; the peer's inputs: [3] game id, [4/5] newest tick, [6/7] checksum tick, [8/9] checksum, [10..25] inputs
	LDA net_rx_len
	CMP #10 + INPUT_WINDOW
	BCC _ignore
	LDA session_active
	BEQ _ignore
	LDY #3
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
	; store all inputs
	LDY #10
-	LDX rx_tick
	LDA (net_rx_ptr),Y
	STA remote_in,X
	INC rx_tick
	INY
	CPY #10 + INPUT_WINDOW
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
	LDY #6
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
	; our inputs of ticks local_newest-15 .. local_newest
	LDA #PT_INPUT
	LDX #10 + INPUT_WINDOW
	JSR packet_header
	LDA game_id
	STA net_tx_buf+3
	LDA local_newest
	STA net_tx_buf+4
	LDA local_newest+1
	STA net_tx_buf+5
	LDA my_chk_tick
	STA net_tx_buf+6
	LDA my_chk_tick+1
	STA net_tx_buf+7
	LDA my_chk
	STA net_tx_buf+8
	LDA my_chk+1
	STA net_tx_buf+9
	SEC
	LDA local_newest
	SBC #INPUT_WINDOW-1
	TAX
	LDY #10
-	LDA local_in,X
	STA net_tx_buf,Y
	INX
	INY
	CPY #10 + INPUT_WINDOW
	BNE -
	JMP netio_send
.pend

;============================================================
;
; title screen (called by irq_hook every frame, outside a session)
;
;============================================================

proto_title_frame .proc
	JSR netio_poll
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
	LDA #INPUT_DELAY-1
	STA local_newest
	STA remote_newest
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
	LDX #1 ; host: player 1 = actor 1
	LDA net_role
	CMP #ROLE_HOST
	BEQ +
	LDX #0 ; join: player 2 = actor 0
+	STX local_actor
	TXA
	EOR #$01
	STA remote_actor
	RTS
.pend

proto_session_end .proc
	#log_event EV_SESSION_END, game_id
	LDA #0
	STA start_state
	STA start_received
	STA start_acked
	RTS
.pend

; -----------------------------------------

proto_tick .proc
	; called by tick (game_net.asm) after the pacing wait: inputs for tick_count
	; 1. state checksum every CHECK_EVERY ticks (the state before this tick's logic is the same on both machines)
	LDA tick_count
	AND #CHECK_EVERY-1
	BNE +
	JSR make_checksum
+
	; 2. our input for tick + INPUT_DELAY (joystick port 2)
	CLC
	LDA tick_count
	ADC #INPUT_DELAY
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
	JSR send_input

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
	BPL _ready
	JSR netio_poll
	BCS +
	JSR proto_rx
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
	CPX #WAIT_RESEND
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
	BCC _wait
	; flash the border while waiting (restored afterwards: the border color belongs to the game)
	LDA wait_shown
	BNE +
	LDA VIC_D020
	STA wait_border
	INC wait_shown
+	LDA wait_elapsed+1
	STA VIC_D020
	JMP _wait

_ready
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
	RTS
.pend

net_abort .proc
	; A = reason (1: the peer is gone, 2: the host started another game)
	; back to the title screen (like RESTORE does), the connection stays
	STA abort_reason
	#log_event EV_ABORT, abort_reason
	LDA #$00
	STA session_active
	JSR proto_session_end
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
	LDY #8
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
	LDA #$80
	STA netio_kernal
	.if (PROFILE || DETTEST) && !NETBOT
	JMP start_the_game ; test builds play locally
	.fi
	LDA $D012
	ORA #$01
	STA mac_last
	LDA #6 ; blue background, light blue text: like the C64 screen
	STA $D021
	LDA #14
	STA $D020

net_menu
	JSR print_inline
	.null 147, 154, "WIZARD OF WOR - LAN", 13, 13
	JSR netio_detect
	LDA net_backend
	CMP #BACKEND_UCI
	BNE +
	JSR print_inline
	.null "NETWORK: C64 ULTIMATE", 13, "MY IP:   "
	JSR uci.net_get_ip
	JSR print_ip
	JMP _items
+	CMP #BACKEND_RRNET
	BNE +
	JSR print_inline
	.null "NETWORK: RR-NET", 13
	JMP _items
+	JSR print_inline
	.null "NO NETWORK HARDWARE FOUND", 13, "(ULTIMATE: ENABLE THE COMMAND INTERFACE)", 13
_items
	JSR print_inline
	.null 13, "CONTROLS: JOYSTICK PORT 2 OR W A S D + SPACE", 13, "(LOCAL GAME: KEYS / PORT 1 = PLAYER 1)", 13, 13, "1  LOCAL GAME", 13
	LDA net_backend
	CMP #BACKEND_RRNET
	BNE +
	JSR print_inline
	.null "2  HOST A NETWORK GAME", 13
+	LDA net_backend
	BEQ +
	JSR print_inline
	.null "3  JOIN A NETWORK GAME", 13
+	JSR print_inline
	.null 13, "CHOICE? "
-	JSR GETIN
	CMP #'1'
	BEQ _local
	LDX net_backend
	BEQ -
	CMP #'3'
	BEQ _join
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
.pend

; -----------------------------------------

setup_my_ip_rrnet .proc
	; RR-Net: own address by DHCP or typed in; C=1: failed
	JSR print_inline
	.null 13, 13, "MY IP (RETURN = DHCP): "
	JSR read_line
	LDA host_len
	BNE _static
	JSR print_inline
	.null "DHCP... "
	#rr_call rr.net_dhcp
	BCC _ok
	JSR print_inline
	.null "FAILED", 13
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
	.null 13, "MY IP: "
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
	.null 13, 13, "WAITING FOR PLAYER 2 ON PORT 6464", 13, "(ANY KEY = BACK)", 13
-	JSR GETIN
	BEQ +
	JMP net_setup.net_menu
+	JSR netio_poll
	BCS -
	JSR proto_rx
	LDA net_connected
	BEQ -
	JSR print_inline
	.null 13, "PLAYER 2 IS HERE.", 13, "YOU ARE PLAYER 1 (YELLOW).", 13, "PRESS FIRE ON THE TITLE SCREEN TO START.", 13
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
	.null 13, 13, "IP OF THE HOST: "
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
	.null "CANNOT OPEN THE CONNECTION", 13
	JMP wait_key_menu
+	JSR print_inline
	.null "CALLING THE HOST", 13, "(ANY KEY = BACK)", 13
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
	.null 13, "CONNECTED.", 13, "YOU ARE PLAYER 2 (BLUE).", 13, "THE HOST STARTS THE GAME.", 13
	JMP start_after_key
.pend

; -----------------------------------------

start_after_key .proc
	JSR print_inline
	.null 13, "PRESS A KEY"
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
	.null 13, "PRESS A KEY"
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
