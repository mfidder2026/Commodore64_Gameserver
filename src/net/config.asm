;============================================================
;
; NET: SETTINGS FILE (WOW.CFG) AND BACK TO THE SETUP MENU
;
; The name and the game server (and on RR-Net the own IP) are
; kept in a sequential file WOW.CFG on the disk the game was
; loaded from (KERNAL, the drive in $BA, default 8):
;
;   NAME=ERIK
;   SERVER=192.168.1.17
;   MYIP=
;
; With valid settings the setup menu is skipped: welcome, the
; server, the lobby. F1 in the lobby comes back here
; (cfg_reenter_setup): the KERNAL is set up again and the setup
; menu shows the saved values as defaults.
;
; Included by wizard_of_wor.asm after lobby.asm ($C000+).
; Only used while the KERNAL runs (setup menu).
;
;============================================================

	.enc "cfg" ; PETSCII upper case for KERNAL file names and the file contents
	.cdef " @", $20
	.cdef "AZ", $41
	.cdef "[[", $5B
	.cdef "]]", $5D

	CFG_MAX = 120 ; bytes of the file that are read
	CFG_SERVER_MAX = 31
	CFG_MYIP_MAX = 15

	; KERNAL
	K_SETMSG = $FF90
	K_READST = $FFB7
	K_SETLFS = $FFBA
	K_SETNAM = $FFBD
	K_OPEN = $FFC0
	K_CLOSE = $FFC3
	K_CHKIN = $FFC6
	K_CHKOUT = $FFC9
	K_CLRCHN = $FFCC
	K_CHRIN = $FFCF
	K_CHROUT = $FFD2
	K_CLALL = $FFE7
	K_RESTOR = $FF8A
	K_CINT = $FF81

cfg_first_init .proc
	; once, at the first start: the drive the game was loaded from
	LDA cfg_inited
	BNE +
	INC cfg_inited
	LDA $BA
	CMP #8
	BCC _default
	CMP #31
	BCC _ok
_default
	LDA #8
_ok
	STA cfg_device
+	RTS
.pend

; -----------------------------------------

cfg_load .proc
	; reads WOW.CFG; C=0: valid settings in my_nick, cfg_server, cfg_myip
	LDA #0
	STA cfg_len
	JSR K_SETMSG ; no KERNAL messages ("?FILE NOT FOUND")
	LDA #len(cfg_name)
	LDX #<cfg_name
	LDY #>cfg_name
	JSR K_SETNAM
	LDA #2
	LDX cfg_device
	LDY #2
	JSR K_SETLFS
	JSR K_OPEN
	BCS _close
	LDX #2
	JSR K_CHKIN
	BCS _close
-	JSR K_CHRIN
	LDX cfg_len
	CPX #CFG_MAX
	BCS +
	STA cfg_buf,X
	INC cfg_len
+	JSR K_READST
	BEQ -
	CMP #$40 ; end of file: the last byte was valid; anything else (no file, no drive): nothing
	BEQ _close
	LDA #0
	STA cfg_len
_close
	JSR K_CLRCHN
	LDA #2
	JSR K_CLOSE
	JMP cfg_parse ; (no fall through: 64tass leaves out a .proc that is never referenced)
.pend

cfg_parse .proc
	; lines KEY=VALUE separated by RETURN; C=0 if a valid name and a server were found
	LDA #0
	STA my_nick_len
	STA cfg_server_len
	STA cfg_myip_len
	STA cfg_pos
_line
	LDA cfg_pos
	CMP cfg_len
	BCC +
	JMP _check
+	LDY #2 ; the keys
_key
	LDA key_lo,Y
	STA _cmp+1
	LDA key_hi,Y
	STA _cmp+2
	LDX cfg_pos
	LDA #0
	STA cfg_i
-	LDA cfg_buf,X
	STX cfg_tmp
	LDX cfg_i
_cmp	CMP $FFFF,X
	BNE _no
	INX
	STX cfg_i
	LDX cfg_tmp
	INX
	LDA cfg_i
	CMP key_len,Y
	BNE -
	; key found: copy the value
	STX cfg_pos
	LDA dest_lo,Y
	STA _store+1
	LDA dest_hi,Y
	STA _store+2
	LDA dest_max,Y
	STA cfg_vmax
	LDA #0
	STA cfg_i
-	LDX cfg_pos
	CPX cfg_len
	BCS _value_end
	LDA cfg_buf,X
	CMP #13
	BEQ _value_end
	INC cfg_pos
	LDX cfg_i
	CPX cfg_vmax
	BCS -
_store	STA $FFFF,X
	INC cfg_i
	BNE - ; always branches
_value_end
	LDA len_lo,Y
	STA _len+1
	LDA len_hi,Y
	STA _len+2
	LDA cfg_i
_len	STA $FFFF ; my_nick_len / cfg_server_len / cfg_myip_len
	JMP _skip
_no
	DEY
	BMI _skip
	JMP _key
_skip
	; to the next line
	LDX cfg_pos
-	CPX cfg_len
	BCS +
	LDA cfg_buf,X
	INX
	CMP #13
	BNE -
+	STX cfg_pos
	JMP _line

_check
	; the name: 1-8 characters A-Z / 0-9; the server: at least 1 character
	LDX my_nick_len
	BEQ _bad
	DEX
-	LDA my_nick,X
	CMP #'0'
	BCC _bad
	CMP #'9'+1
	BCC +
	CMP #'A'
	BCC _bad
	CMP #'Z'+1
	BCS _bad
+	DEX
	BPL -
	LDA cfg_server_len
	BEQ _bad
	CLC
	RTS
_bad
	SEC
	RTS

key_lo		.byte <key_name, <key_server, <key_myip
key_hi		.byte >key_name, >key_server, >key_myip
key_len		.byte len(key_name), len(key_server), len(key_myip)
dest_lo		.byte <my_nick, <cfg_server, <cfg_myip
dest_hi		.byte >my_nick, >cfg_server, >cfg_myip
dest_max	.byte NICK_MAX, CFG_SERVER_MAX, CFG_MYIP_MAX
len_lo		.byte <my_nick_len, <cfg_server_len, <cfg_myip_len
len_hi		.byte >my_nick_len, >cfg_server_len, >cfg_myip_len
.pend

; -----------------------------------------

cfg_save .proc
	; writes WOW.CFG (only when something was typed in); prints the result
	LDA cfg_dirty
	BNE +
	RTS
+	LDA #0
	STA cfg_dirty
	JSR K_SETMSG
	; the text
	LDX #0
	LDA #<key_name
	LDY #>key_name
	JSR _add_text
	LDA my_nick_len
	STA cfg_i
	LDA #<my_nick
	LDY #>my_nick
	JSR _add_value
	LDA #<key_server
	LDY #>key_server
	JSR _add_text
	LDA cfg_server_len
	STA cfg_i
	LDA #<cfg_server
	LDY #>cfg_server
	JSR _add_value
	LDA #<key_myip
	LDY #>key_myip
	JSR _add_text
	LDA cfg_myip_len
	STA cfg_i
	LDA #<cfg_myip
	LDY #>cfg_myip
	JSR _add_value
	STX cfg_len

	; delete the old file: OPEN 15,dev,15,"S0:WOW.CFG"
	LDA #len(cfg_scratch)
	LDX #<cfg_scratch
	LDY #>cfg_scratch
	JSR _open15
	LDA #15
	JSR K_CLOSE

	; write the new one
	LDA #len(cfg_write)
	LDX #<cfg_write
	LDY #>cfg_write
	JSR K_SETNAM
	LDA #2
	LDX cfg_device
	LDY #2
	JSR K_SETLFS
	JSR K_OPEN
	BCS _failed
	LDX #2
	JSR K_CHKOUT
	BCS _failed
	LDX #0
-	LDA cfg_buf,X
	JSR K_CHROUT
	INX
	CPX cfg_len
	BNE -
	JSR K_CLRCHN
	LDA #2
	JSR K_CLOSE

	; the drive's answer must be "00, OK"
	LDA #0
	JSR _open15
	BCS _failed
	LDX #15
	JSR K_CHKIN
	BCS _failed
	JSR K_CHRIN
	STA cfg_tmp
	JSR K_CHRIN
	ORA cfg_tmp
	CMP #'0'
	BNE _failed
	JSR K_READST
	AND #$80 ; device not present
	BNE _failed
	JSR _done
	JSR print_inline
	.null C_LBLUE, "SETTINGS SAVED (WOW.CFG)", 13
	JMP _pause
_failed
	JSR _done
	JSR print_inline
	.null C_LRED, "SETTINGS NOT SAVED (NO DISK?)", 13
_pause
	; a second to read it (the jiffy clock of the KERNAL IRQ)
	LDA $A2
	CLC
	ADC #60
	STA cfg_tmp
-	LDA $A2
	CMP cfg_tmp
	BNE -
	RTS

_done
	JSR K_CLRCHN
	LDA #15
	JSR K_CLOSE
	LDA #2
	JMP K_CLOSE

_open15
	; OPEN 15,dev,15 with the command at X/Y, length A
	JSR K_SETNAM
	LDA #15
	LDX cfg_device
	LDY #15
	JSR K_SETLFS
	JMP K_OPEN

_add_text
	; appends the key text at A/Y up to and including its "=" to cfg_buf at X
	STA _src+1
	STY _src+2
	LDY #0
_src	LDA $FFFF,Y
	CMP #'='
	PHP
	STA cfg_buf,X
	INX
	INY
	PLP
	BNE _src
	RTS

_add_value
	; appends cfg_i bytes from A/Y and a RETURN to cfg_buf at X
	STA _val+1
	STY _val+2
	LDY #0
-	CPY cfg_i
	BEQ +
_val	LDA $FFFF,Y
	STA cfg_buf,X
	INX
	INY
	BNE - ; always branches
+	LDA #13
	STA cfg_buf,X
	INX
	RTS
.pend

cfg_name	.text "WOW.CFG"
cfg_write	.text "0:WOW.CFG,S,W"
cfg_scratch	.text "S0:WOW.CFG"
key_name	.text "NAME="
key_server	.text "SERVER="
key_myip	.text "MYIP="

; -----------------------------------------
; setup menu helpers

cfg_show .proc
	; prints " [value]" when there is one, then ": " in white for the input
	; A/Y = value, X = its length
	STA _src+1
	STY _src+2
	STX cfg_i
	TXA
	BEQ +
	LDA #' '
	JSR K_CHROUT
	LDA #'['
	JSR K_CHROUT
	LDX #0
_src	LDA $FFFF,X
	JSR K_CHROUT
	INX
	CPX cfg_i
	BNE _src
	LDA #']'
	JSR K_CHROUT
+	LDA #':'
	JSR K_CHROUT
	LDA #' '
	JSR K_CHROUT
	LDA #C_WHITE
	JMP K_CHROUT
.pend

cfg_myip_line .proc
	; RR-Net own IP: from the settings (automatic start) or typed in (then kept for the settings)
	LDA cfg_auto
	BEQ _ask
	LDX #0
-	CPX cfg_myip_len
	BEQ +
	LDA cfg_myip,X
	STA host_input,X
	JSR K_CHROUT
	INX
	BNE - ; always branches
+	LDA #0
	STA host_input,X
	STX host_len
	LDA #13
	JMP K_CHROUT
_ask
	JSR read_line
	LDX host_len
	CPX #CFG_MYIP_MAX+1
	BCC +
	LDX #CFG_MYIP_MAX
+	STX cfg_myip_len
	DEX
	BMI +
-	LDA host_input,X
	STA cfg_myip,X
	DEX
	BPL -
+	RTS
.pend

netio_close .proc
	; closes the connection to the server / peer, if one is open
	LDA net_is_open
	BEQ _out
	LDA #0
	STA net_is_open
	STA netio_state
	STA netio_tx_pending
	LDA net_backend
	CMP #BACKEND_UCI
	BNE +
	JSR uci.uci_reset ; abort a read that may still run
	JMP uci.net_close
+	CMP #BACKEND_RRNET
	BNE _out
	JSR rr_enter ; (the rr_call macro is defined later, in netgame.asm)
	JSR rr.net_close
	JMP rr_leave
_out
	RTS
.pend

; -----------------------------------------

cfg_reenter_setup .proc
	; F1 in the lobby: from the game back to the setup menu (KERNAL screen, keyboard and interrupts again)
	SEI
	LDX #$FF
	TXS
	LDA #$00
	STA $D01A ; no raster IRQ
	STA VIC_D015 ; no sprites
	STA $D418 ; SID silent
	STA $D404
	STA $D40B
	STA $D412
	LDA #$FF
	STA VIC_D019
	JSR kernal_ioinit_prg ; CIAs ($01 back to RAM / IO / KERNAL), CIA2 cycle counter
	JSR K_RESTOR ; the KERNAL vectors ($0314 ...)
	; the game used page 2: KERNAL variables that CINT does not set itself
	LDA #$04
	STA $0288 ; screen at $0400 (CINT clears the screen there: with garbage it clears page 3 and the vectors)
	LDA #$00
	STA $028A ; key repeat: cursor keys only
	STA $0292 ; screen scrolling on
	JSR K_CINT ; VIC, screen editor, clear screen
	LDA #$00
	STA $C6 ; keyboard buffer empty
	STA $C7 ; no reverse
	STA $D4 ; no quote mode
	STA $D8 ; no inserts
	STA $D0 ; input from the keyboard
	JSR K_CLALL
	LDA #$80
	STA netio_kernal ; ip65 calls save the KERNAL's zero page again
	CLI
	JSR netio_close
	LDA #$01
	STA cfg_force_menu
	JMP net_setup
.pend

; -----------------------------------------
; variables

cfg_inited	.byte 0
cfg_device	.byte 8
cfg_force_menu	.byte 0
cfg_auto	.byte 0 ; 1: automatic start with the saved settings
cfg_dirty	.byte 0 ; 1: typed in, save after connecting
cfg_len		.byte 0
cfg_pos		.byte 0
cfg_i		.byte 0
cfg_tmp		.byte 0
cfg_vmax		.byte 0
cfg_server	.fill CFG_SERVER_MAX+1
cfg_server_len	.byte 0
cfg_myip	.fill CFG_MYIP_MAX+1
cfg_myip_len	.byte 0
net_is_open	.byte 0
cfg_buf		.fill CFG_MAX
