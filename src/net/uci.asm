;============================================================
;
; NET: ULTIMATE COMMAND INTERFACE (UCI) DRIVER
;
; Talks to the network stack of the Commodore 64 Ultimate
; (also Ultimate 64 / 1541 Ultimate-II+) through the registers
; at $DF1C-$DF1F. The Command Interface has to be enabled in
; the Ultimate menu.
;
; Protocol notes (see docs/netcode.md and the ultimate-uci-sdk
; documentation for the measurements behind them):
; - never read-modify-write the control register: reading
;   $DF1C returns the status register
; - one command at a time; a command is: wait for idle, write
;   the bytes to $DF1D, write PUSH_CMD, wait while busy, read
;   data + status, write DATA_ACC (data-more: repeat)
; - the queues saturate on their last byte, so every read loop
;   is bounded
; - a socket read with nothing pending takes ~42 ms on the
;   Ultimate side: reads are started with uci_push and finished
;   later with uci_poll, the C64 keeps running meanwhile
;
; Interface
;   uci_detect          C=0: Command Interface present
;   uci_reset           abort whatever is going on, back to idle
;   uci_begin           wait for idle (C=1: timeout); then write
;                       the command bytes to UCI_CMD yourself
;   uci_push            submit the command
;   uci_poll            C=1: still busy; C=0: finished, reply in
;                       uci_resp/uci_resp_len, status text in
;                       uci_stat, its number in uci_code
;   uci_wait            uci_poll until finished (C=1: timeout)
;
;============================================================

	UCI_CTRL = $DF1C ; write: control
	UCI_STATUS = $DF1C ; read: status
	UCI_CMD = $DF1D ; write: command bytes
	UCI_ID = $DF1D ; read: identification ($C9)
	UCI_RESP = $DF1E ; read: response data
	UCI_STATDATA = $DF1F ; read: status data

	; control register bits
	UCI_PUSH_CMD = $01
	UCI_DATA_ACC = $02
	UCI_ABORT = $04
	UCI_CLR_ERR = $08

	; status register bits
	UCI_ST_BUSY = $01
	UCI_ST_ABORT_P = $04
	UCI_ST_ERROR = $08
	UCI_ST_STATE = $30
	UCI_ST_STAT_AV = $40
	UCI_ST_DATA_AV = $80

	; protocol states (status & UCI_ST_STATE)
	UCI_STATE_IDLE = $00
	UCI_STATE_BUSY = $10
	UCI_STATE_DATA_LAST = $20
	UCI_STATE_DATA_MORE = $30

	; targets and network commands
	UCI_TARGET_NET = $03
	NET_CMD_GET_IPADDR = $05
	NET_CMD_OPEN_TCP = $07
	NET_CMD_OPEN_UDP = $08
	NET_CMD_CLOSE_SOCKET = $09
	NET_CMD_READ_SOCKET = $10
	NET_CMD_WRITE_SOCKET = $11
	NET_CMD_LISTEN_START = $12 ; not in the published spec
	NET_CMD_LISTEN_STOP = $13 ; not in the published spec
	NET_CMD_LISTEN_STATE = $14 ; not in the published spec
	NET_CMD_LISTEN_SOCKET = $15 ; not in the published spec

	; listener states (reply of NET_CMD_LISTEN_STATE)
	LISTEN_NOT_LISTENING = $00
	LISTEN_LISTENING = $01
	LISTEN_CONNECTED = $02
	LISTEN_BIND_ERROR = $03
	LISTEN_PORT_IN_USE = $04

	UCI_RESP_MAX = 600 ; we never ask for more than 512 bytes of socket data (+2 count bytes)
	UCI_STAT_MAX = 40

; -----------------------------------------

uci_detect .proc
	LDA UCI_ID
	CMP #$C9
	BEQ _found
	CMP #$49 ; $C9 with a pending IRQ
	BEQ _found
	SEC
	RTS
_found
	CLC
	RTS
.pend

; -----------------------------------------

uci_reset .proc
	; release any reply block that is still held, then abort and wait until the abort was serviced
	JSR uci_timeout_start
-	LDA UCI_STATUS
	AND #UCI_ST_STATE
	CMP #UCI_STATE_DATA_LAST
	BCC +
	LDA #UCI_DATA_ACC
	STA UCI_CTRL
	JSR uci_timeout_tick
	BCC -
+
	LDA #UCI_ABORT
	STA UCI_CTRL
	JSR uci_timeout_start
-	LDA UCI_STATUS
	AND #UCI_ST_STATE | UCI_ST_ABORT_P
	BEQ +
	JSR uci_timeout_tick
	BCC -
+
	LDA #UCI_CLR_ERR
	STA UCI_CTRL
	LDA #$00
	STA uci_pending
	RTS
.pend

; -----------------------------------------

uci_begin .proc
	; wait for the idle state, C=1 on timeout
	JSR uci_timeout_start
-	LDA UCI_STATUS
	AND #UCI_ST_STATE
	BEQ +
	JSR uci_timeout_tick
	BCC -
	RTS ; C=1
+
	CLC
	RTS
.pend

; -----------------------------------------

uci_push .proc
	LDA #UCI_PUSH_CMD
	STA UCI_CTRL
	LDA #$01
	STA uci_pending
	LDA #$00
	STA uci_resp_len
	STA uci_resp_len+1
	STA uci_stat_len
	RTS
.pend

; -----------------------------------------

uci_poll .proc
	; C=1: still busy; C=0: finished (or nothing pending)
	LDA uci_pending
	BNE +
	CLC
	RTS
+
	LDA UCI_STATUS
	AND #UCI_ST_STATE
	CMP #UCI_STATE_BUSY
	BNE +
	SEC
	RTS
+
	CMP #UCI_STATE_IDLE
	BEQ _finished ; finished without a data phase

	; a data block: read response and status (both bounded), then release it
	; response bytes go to uci_resp + uci_resp_len
	LDA #<uci_resp
	CLC
	ADC uci_resp_len
	STA uci_ptr
	LDA #>uci_resp
	ADC uci_resp_len+1
	STA uci_ptr+1
	LDY #$00
_resp
	BIT UCI_STATUS
	BPL _resp_done ; DATA_AV is bit 7
	; room left?
	LDA uci_resp_len+1
	CMP #>UCI_RESP_MAX
	BCC +
	LDA uci_resp_len
	CMP #<UCI_RESP_MAX
	BCS _resp_done ; full - the rest is dropped by DATA_ACC
+
	LDA UCI_RESP
	STA (uci_ptr),Y
	INC uci_ptr
	BNE +
	INC uci_ptr+1
+
	INC uci_resp_len
	BNE _resp
	INC uci_resp_len+1
	BNE _resp ; always branches
_resp_done

	LDX uci_stat_len
_stat
	BIT UCI_STATUS
	BVC _stat_done ; STAT_AV is bit 6
	CPX #UCI_STAT_MAX-1
	BCS _stat_done
	LDA UCI_STATDATA
	STA uci_stat,X
	INX
	BNE _stat ; always branches
_stat_done
	STX uci_stat_len

	; remember the state before releasing the block
	LDA UCI_STATUS
	AND #UCI_ST_STATE
	PHA
	LDA #UCI_DATA_ACC
	STA UCI_CTRL
	PLA
	CMP #UCI_STATE_DATA_MORE
	BNE _finished
	SEC ; another block follows
	RTS

_finished
	LDA #$00
	STA uci_pending
	; terminate the status text and decode its number ("00,OK" -> 0)
	LDX uci_stat_len
	STA uci_stat,X
	LDA #$FF
	STA uci_code
	CPX #$02
	BCC +
	LDA uci_stat
	SEC
	SBC #'0'
	CMP #10
	BCS +
	STA uci_code
	ASL A
	ASL A
	ADC uci_code ; *5
	ASL A ; *10
	STA uci_code
	LDA uci_stat+1
	SEC
	SBC #'0'
	CMP #10
	BCS +
	ADC uci_code
	STA uci_code
+
	CLC
	RTS
.pend

; -----------------------------------------

uci_wait .proc
	; poll until the command has finished, C=1 on timeout (then the interface is reset)
	JSR uci_timeout_start
-	JSR uci_poll
	BCC +
	JSR uci_timeout_tick
	BCC -
	JSR uci_reset
	SEC
+
	RTS
.pend

; -----------------------------------------

uci_timeout_start .proc
	; about uci_timeout_secs seconds of polling (one tick is roughly 40 cycles, 25000 ticks ~ 1s)
	LDA #<25000
	STA uci_tmo
	LDA #>25000
	STA uci_tmo+1
	LDA uci_timeout_secs
	STA uci_tmo+2
	RTS
.pend

uci_timeout_tick .proc
	; C=1 when the time is up
	LDA uci_tmo
	BNE _lo
	LDA uci_tmo+1
	BNE _hi
	LDA uci_tmo+2
	BEQ _expired
	DEC uci_tmo+2
	LDA #>25000
	STA uci_tmo+1
_hi
	DEC uci_tmo+1
_lo
	DEC uci_tmo
	CLC
	RTS
_expired
	SEC
	RTS
.pend

;============================================================
;
; network commands on top of the core
;
;============================================================

; -----------------------------------------

net_get_ip .proc
	; reply: 4 bytes ip, 4 bytes netmask, 4 bytes gateway in uci_resp; C=1 on error
	JSR uci_begin
	BCS +
	LDA #UCI_TARGET_NET
	STA UCI_CMD
	LDA #NET_CMD_GET_IPADDR
	STA UCI_CMD
	LDA #$00 ; interface 0
	STA UCI_CMD
	JSR uci_push
	JSR uci_wait
	BCS +
	LDA uci_resp_len
	CMP #12
	BCC + ; C=1
	LDA uci_code
	CMP #$01 ; 00 = ok
+	RTS
.pend

; -----------------------------------------

net_open .proc
	; A = NET_CMD_OPEN_TCP or NET_CMD_OPEN_UDP, net_port = remote port, net_host = zero terminated host name / dotted ip
	; returns the socket handle in A and net_socket, C=1 on error
	; a TCP connect to an address where nothing answers can take ~30 seconds (firmware timeout)
	PHA
	JSR uci_begin
	PLA
	BCS _err
	LDX #UCI_TARGET_NET
	STX UCI_CMD
	STA UCI_CMD
	LDA net_port
	STA UCI_CMD
	LDA net_port+1
	STA UCI_CMD
	LDX #$00
-	LDA net_host,X
	BEQ +
	STA UCI_CMD
	INX
	CPX #net_host_size
	BCC -
+
	JSR uci_push
	LDA uci_timeout_secs
	PHA
	LDA #40
	STA uci_timeout_secs
	JSR uci_wait
	PLA
	STA uci_timeout_secs
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

net_close .proc
	; closes net_socket
	JSR uci_begin
	BCS +
	LDA #UCI_TARGET_NET
	STA UCI_CMD
	LDA #NET_CMD_CLOSE_SOCKET
	STA UCI_CMD
	LDA net_socket
	STA UCI_CMD
	JSR uci_push
	JSR uci_wait
+	LDA #$FF
	STA net_socket
	RTS
.pend

; -----------------------------------------

net_listen_cmd .proc
	; A = NET_CMD_LISTEN_START (uses net_port), _STOP, _STATE or _SOCKET
	; reply byte in A (listener state / socket handle), C=1 on error
	PHA
	JSR uci_begin
	PLA
	BCS +
	LDX #UCI_TARGET_NET
	STX UCI_CMD
	STA UCI_CMD
	CMP #NET_CMD_LISTEN_START
	BNE _push
	LDA net_port
	STA UCI_CMD
	LDA net_port+1
	STA UCI_CMD
_push
	JSR uci_push
	JSR uci_wait
	BCS +
	LDA uci_resp
	LDX uci_resp_len
	BNE _ok
	LDA #$00
_ok
	CLC
+	RTS
.pend

; -----------------------------------------

net_write .proc
	; sends net_tx_len bytes from net_tx_buf over net_socket (synchronous, ~3-7 ms), C=1 on error
	JSR uci_begin
	BCS +
	LDA #UCI_TARGET_NET
	STA UCI_CMD
	LDA #NET_CMD_WRITE_SOCKET
	STA UCI_CMD
	LDA net_socket
	STA UCI_CMD
	LDX #$00
-	CPX net_tx_len
	BEQ _push
	LDA net_tx_buf,X
	STA UCI_CMD
	INX
	BNE -
_push
	JSR uci_push
	JSR uci_wait
	BCS +
	LDA uci_code
	CMP #$01 ; 00 = ok
+	RTS
.pend

; -----------------------------------------

net_read_start .proc
	; starts an asynchronous read of up to net_read_max bytes, finish it with net_read_poll; C=1 if the interface is not idle
	LDA UCI_STATUS
	AND #UCI_ST_STATE
	BEQ +
	SEC
	RTS
+
	LDA #UCI_TARGET_NET
	STA UCI_CMD
	LDA #NET_CMD_READ_SOCKET
	STA UCI_CMD
	LDA net_socket
	STA UCI_CMD
	LDA net_read_max
	STA UCI_CMD
	LDA #$00
	STA UCI_CMD
	JSR uci_push
	CLC
	RTS
.pend

; -----------------------------------------

net_read_poll .proc
	; C=1: still busy
	; C=0: finished, A = result: 0 = data (net_rx_ptr/net_rx_len), 1 = connection closed, 2 = no data, $FF = error
	JSR uci_poll
	BCC +
	RTS
+
	LDA uci_code
	BEQ _data
	CMP #$01
	BEQ _done ; closed by host
	CMP #$02
	BEQ _done ; no data
	LDA #$FF
	BNE _done ; always branches
_data
	; reply: count (16 bit LE, $FFFF = nothing) followed by the bytes
	LDA uci_resp_len+1
	BNE +
	LDA uci_resp_len
	CMP #$02
	BCC _nodata
+
	LDA uci_resp+1
	CMP #$FF
	BEQ _nodata
	LDA uci_resp
	STA net_rx_len
	LDA #<(uci_resp+2)
	STA net_rx_ptr
	LDA #>(uci_resp+2)
	STA net_rx_ptr+1
	LDA #$00
	BEQ _done ; always branches
_nodata
	LDA #$02
_done
	CLC
	RTS
.pend
