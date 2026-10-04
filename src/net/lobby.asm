;============================================================
;
; NET: LOBBY SCREEN (role ROLE_SERVER)
;
; Replaces the title screens while the C64 is connected to the
; C64 Game Server: the other players of the game with their kind
; (person or bot) and state (free, busy, playing). The player
; picks an opponent with the joystick and challenges him with
; FIRE (INVITE, server/docs/protocol.md).
;
; Split like the title screen of the original:
; - the raster IRQ (srv_title_frame in netgame.asm) does the
;   network, the joystick and the status line (bottom row);
; - the main program (lobby_screen) only draws, in the game's
;   own 2x1 character set and colors.
;
; Included by wizard_of_wor.asm after game_net.asm ($C000+).
;
;============================================================

	.enc "none" ; ASCII ('A' = $41) for the code below

	LOBBY_MAX = 16 ; players in the list (the server sends at most 16)
	LB_ROWS = 7 ; visible lines
	LB_ROW0 = 7 ; screen row of the first line (each line is 2 rows high)
	LB_ROW_YOU = 5
	LB_COL = 2 ; column of the nickname
	LB_COL_KIND = 12
	LB_COL_STATE = 19

	; PLAYERS flags
	PF_BOT = $01
	PF_STATE = $06 ; 0 free, 2 busy, 4 playing

	; colors (VIC)
	COL_WHITE = 1
	COL_RED = 2
	COL_CYAN = 3
	COL_GREEN = 5
	COL_YELLOW = 7
	COL_ORANGE = 8
	COL_LIGHT_RED = 10
	COL_LIGHT_BLUE = 14
	COL_LIGHT_GREY = 15

	CHAR2_SPACE = $25 ; encoding "2x1"
	SM_BYE = $0E

; -----------------------------------------
; main program

lobby_screen .proc
	; called by session_end (title screen) in the server role; returns when the server started a game
	LDA #$01
	STA is_title_screen ; the original IRQ: title mode
	; like display_copyright_and_high_scores: hires, no sprites, no music
	; (but no fine scroll: the game's 7 pixels would hide most of column 39)
	LDA #$08
	STA VIC_D016
	LDA #$00
	STA VIC_D015
	STA snd_ingame_status
	STA SID_WV1
	STA snd_pattern_pos
	STA lobby_joy_prev ; "all held": a button held from the game does nothing until released
	JSR clear_screen

	LDA #COL_YELLOW
	LDX #0
	LDY #9
	JSR lb_at
	LDA #<lb_txt_title
	LDY #>lb_txt_title
	JSR lb_print
	LDA #COL_LIGHT_BLUE
	LDX #2
	LDY #7
	JSR lb_at
	LDA #<lb_txt_title2
	LDY #>lb_txt_title2
	JSR lb_print

	LDA #COL_CYAN
	LDX #LB_ROW_YOU
	LDY #LB_COL
	JSR lb_at
	LDA #<lb_txt_you
	LDY #>lb_txt_you
	JSR lb_print
	LDA my_nick_len
	STA lb_len
	LDX #0
-	LDA #CHAR2_SPACE
	CPX lb_len
	BCS +
	LDA my_nick,X
	JSR ascii_to_2x1
+	JSR print_2x1_letter
	INX
	CPX #NICK_MAX
	BNE -

	; the help line in the 1x1 character set
	LDX #39
-	LDA lb_help,X
	STA $0400 + 22 * 40,X
	LDA #COL_LIGHT_BLUE
	STA $D800 + 22 * 40,X
	DEX
	BPL -

	LDA #$01
	STA lobby_dirty
	LDA #$00
	STA lobby_setup
_loop
	LDA lobby_setup
	CMP #1
	BNE +
	JMP cfg_reenter_setup ; F1: the BYE is out, back to the setup menu (config.asm)
+	LDA start_received
	BNE _start
	LDA lobby_frame
	CMP lb_last_frame
	BEQ _loop
	STA lb_last_frame
	AND #$03
	BEQ _draw ; every 4 frames: the selected line flashes
	LDA lobby_dirty
	BEQ _loop
_draw
	LDA #$00
	STA lobby_dirty
	JSR lb_draw_list
	JMP _loop
_start
	RTS ; the title screen sees FIRE (net_joy) and starts a 2 player game
.pend

lb_draw_list .proc
	; the flash phase of the selected line, the same for the whole line
	LDA lobby_frame
	AND #$10
	STA lb_flash
	; keep the selected line visible
	LDA lobby_cursor
	CMP lobby_top
	BCS +
	STA lobby_top
+	LDA lobby_cursor
	SEC
	SBC #LB_ROWS-1
	BCC +
	CMP lobby_top
	BCC +
	STA lobby_top
+
	; "n online" (the others and me)
	LDA #COL_CYAN
	LDX #LB_ROW_YOU
	LDY #28
	JSR lb_at
	LDA lobby_total
	CLC
	ADC #1
	JSR lb_number
	LDA #<lb_txt_online
	LDY #>lb_txt_online
	JSR lb_print

	LDA #0
	STA lb_line
_line
	LDA lb_line
	ASL A
	ADC #LB_ROW0
	STA lb_row
	LDA lb_line
	CLC
	ADC lobby_top
	STA lb_idx
	CMP lobby_total
	BCC _entry
	; no player here
	LDA #COL_WHITE
	LDX lb_row
	LDY #LB_COL
	JSR lb_at
	LDA #<lb_txt_blank
	LDY #>lb_txt_blank
	JSR lb_print
	JMP _next

_entry
	; the nickname
	LDA #COL_LIGHT_GREY
	JSR lb_color
	LDX lb_row
	LDY #LB_COL
	JSR lb_at_col
	LDX lb_idx
	LDA lobby_len,X
	STA lb_len
	TXA
	ASL A
	ASL A
	ASL A
	TAX
	LDY #0
-	LDA #CHAR2_SPACE
	CPY lb_len
	BCS +
	LDA lobby_nick,X
	JSR ascii_to_2x1
+	JSR print_2x1_letter
	INX
	INY
	CPY #NICK_MAX
	BNE -

	; person or bot
	LDX lb_idx
	LDA lobby_flags,X
	AND #PF_BOT
	BEQ +
	LDA #COL_LIGHT_BLUE
	JSR lb_color
	LDX lb_row
	LDY #LB_COL_KIND
	JSR lb_at_col
	LDA #<lb_txt_bot
	LDY #>lb_txt_bot
	JMP ++
+	LDA #COL_YELLOW
	JSR lb_color
	LDX lb_row
	LDY #LB_COL_KIND
	JSR lb_at_col
	LDA #<lb_txt_human
	LDY #>lb_txt_human
+	JSR lb_print

	; free, busy or playing
	LDX lb_idx
	LDA lobby_flags,X
	AND #PF_STATE
	LSR A
	TAX
	LDA lb_state_color,X
	JSR lb_color
	LDX lb_idx
	LDA lobby_flags,X
	AND #PF_STATE
	LSR A
	PHA
	LDX lb_row
	LDY #LB_COL_STATE
	JSR lb_at_col
	PLA
	TAX
	LDA lb_state_lo,X
	LDY lb_state_hi,X
	JSR lb_print

_next
	INC lb_line
	LDA lb_line
	CMP #LB_ROWS
	BEQ +
	JMP _line
+	RTS
.pend

lb_color .proc
	; A = color of the next text; the selected line flashes white / cyan instead
	LDX lb_idx
	CPX lobby_cursor
	BNE +
	LDA lb_flash
	BEQ _white
	LDA #COL_CYAN
	BNE + ; always branches
_white
	LDA #COL_WHITE
+	STA lb_color_now
	RTS
.pend

lb_at .proc
	; text position: X = screen row, Y = column; color: A (lb_at) or lb_color_now (lb_at_col)
	STA lb_color_now
	; fall through
.pend

lb_at_col .proc
	LDA lb_color_now
	STA tmp_00e9 ; print_2x1_letter: color
	TYA
	CLC
	ADC screen_line_ptr.lo,X
	STA tmp_0014_ptr
	STA tmp_000b
	LDA screen_line_ptr.hi,X
	ADC #0
	STA tmp_0014_ptr+1
	CLC
	ADC #>($D800 - $0400)
	STA tmp_000b+1
	RTS
.pend

lb_print .proc
	; prints the 2x1 text at A (lo) / Y (hi), terminated by $FF
	; (no zero page pointer: the IRQ uses str_ptr2 for the status line)
	STA _src+1
	STY _src+2
	LDX #0
_src	LDA $FFFF,X
	CMP #$FF
	BEQ +
	JSR print_2x1_letter
	INX
	BNE _src
+	RTS
.pend

lb_number .proc
	; A (0-99) as two 2x1 digits, a leading zero as a space
	LDY #0
-	CMP #10
	BCC +
	SBC #10
	INY
	BNE - ; always branches
+	PHA
	TYA
	BNE +
	LDA #CHAR2_SPACE
+	JSR print_2x1_letter
	PLA
	JMP print_2x1_letter
.pend

ascii_to_2x1 .proc
	; ASCII 'A'-'Z' / '0'-'9' -> code in the 2x1 character set
	CMP #$41 ; 'A' (numbers: 64tass -a would translate character constants to PETSCII)
	BCC +
	SEC
	SBC #$41 - $0A
	RTS
+	SEC
	SBC #$30 ; '0'
	RTS
.pend

; -----------------------------------------
; raster IRQ (called by srv_title_frame)

lobby_read_joy .proc
	; joystick port 2 and W A S D + SPACE; A = the directions / fire pressed since the last frame (1 = new)
	JSR read_keyboard
	AND CIA1_JOY_KEY1
	ORA #$E0
	TAX
	EOR #$FF ; 1 = held
	AND lobby_joy_prev ; 1 = was released
	STX lobby_joy_prev
	RTS
.pend

lobby_check_setup .proc
	; F1 in the lobby (or while the server does not answer): say BYE, the main program goes to the setup menu
	LDA lobby_setup
	BEQ +
	CMP #1
	BEQ _out
	DEC lobby_setup ; a few frames for the BYE to go out
_out
	RTS
+	LDA srv_state
	CMP #SRV_LOBBY
	BEQ +
	CMP #SRV_CONNECTING
	BNE _out
+	LDA #$FF ; F1: keyboard column 0, row 4 (rows held low by joystick port 1 are ignored)
	STA CIA1_JOY_KEY1
	LDA CIA1_JOY_KEY2
	EOR #$FF
	STA kb_mask
	LDA #%11111110
	STA CIA1_JOY_KEY1
	LDA CIA1_JOY_KEY2
	ORA kb_mask
	LDX #$FF
	STX CIA1_JOY_KEY1
	AND #$10
	BNE _out
	LDA #SM_BYE
	STA net_tx_buf
	LDA #1
	STA net_tx_len
	JSR netio_send
	LDA #12
	STA lobby_setup
	RTS
.pend

lobby_input .proc
	; in the lobby: up / down choose a player, FIRE challenges him
	LDA lobby_new
	AND #$01 ; up
	BEQ +
	LDA lobby_cursor
	BEQ +
	DEC lobby_cursor
	INC lobby_dirty
+	LDA lobby_new
	AND #$02 ; down
	BEQ +
	LDX lobby_cursor
	INX
	CPX lobby_total
	BCS +
	STX lobby_cursor
	INC lobby_dirty
+	LDA lobby_new
	AND #$10 ; fire
	BEQ _out
	LDX lobby_cursor
	CPX lobby_total
	BCS _out ; nobody there
	LDA lobby_flags,X
	AND #PF_STATE
	BEQ _invite
	LDA #MSG_NOT_FREE
	JMP srv_message
_invite
	LDA lobby_id,X
	STA invite_id
	LDA lobby_len,X ; the name for the status line ("waiting for ...")
	STA opp_len
	TXA
	ASL A
	ASL A
	ASL A
	TAX
	LDY #0
-	LDA lobby_nick,X
	STA opp_nick,Y
	INX
	INY
	CPY #NICK_MAX
	BNE -
	INC invite_seq ; a new invitation (the server ignores repeats of the same number)
	LDA #$00
	STA invite_timer
	STA srv_msg_timer
	LDA #SRV_INVITING
	STA srv_state
_out
	RTS
.pend

lobby_inviting .proc
	; waiting for the answer: INVITE again every half second (UDP) until START or CHALLENGE_CANCELLED; N withdraws
	DEC invite_timer
	BPL +
	LDA #30
	STA invite_timer
	JSR srv_send_invite
+	JSR key_n_pressed
	BCC +
	LDA #SRV_LOBBY
	STA srv_state
	JMP srv_send_withdraw
+	RTS
.pend

lobby_rx_players .proc
	; PLAYERS: [1] total, [2] index of the first entry, [3] count, then per entry [id] [flags] [length] [nickname]
	LDY #1
	LDA (net_rx_ptr),Y
	CMP #LOBBY_MAX+1
	BCC +
	LDA #LOBBY_MAX
+	STA lobby_total
	INY
	LDA (net_rx_ptr),Y
	STA lp_index
	ASL A
	ASL A
	ASL A
	STA lp_nick_base
	INY
	LDA (net_rx_ptr),Y
	STA lp_count
	INY
_entry
	LDA lp_count
	BEQ _done
	DEC lp_count
	LDX lp_index
	CPX #LOBBY_MAX
	BCS _done
	LDA (net_rx_ptr),Y
	STA lobby_id,X
	INY
	LDA (net_rx_ptr),Y
	STA lobby_flags,X
	INY
	LDA (net_rx_ptr),Y
	STA lp_len
	INY
	CMP #NICK_MAX+1
	BCC +
	LDA #NICK_MAX
+	STA lobby_len,X
	LDA #0
	STA lp_i
-	LDA lp_i
	CMP lp_len
	BEQ _next
	LDA (net_rx_ptr),Y
	INY
	LDX lp_i
	CPX #NICK_MAX
	BCS +
	PHA
	TXA
	CLC
	ADC lp_nick_base
	TAX
	PLA
	STA lobby_nick,X
+	INC lp_i
	BNE - ; always branches
_next
	INC lp_index
	LDA lp_index
	ASL A
	ASL A
	ASL A
	STA lp_nick_base
	JMP _entry
_done
	; keep the cursor inside the list
	LDA lobby_cursor
	CMP lobby_total
	BCC +
	LDA lobby_total
	BEQ ++
	SEC
	SBC #1
+	STA lobby_cursor
	JMP _dirty
+	LDA #0
	STA lobby_cursor
_dirty
	INC lobby_dirty
	RTS
.pend

; -----------------------------------------
; texts and variables

	.enc "2x1"
lb_txt_title	.text "welcome dungeon master", $FF
lb_txt_title2	.text "at the wizard of wor lobby", $FF
lb_txt_you	.text "you  ", $FF
lb_txt_online	.text " online", $FF
lb_txt_human	.text "person", $FF
lb_txt_bot	.text "bot   ", $FF
lb_txt_free	.text "free   ", $FF
lb_txt_busy	.text "busy   ", $FF
lb_txt_playing	.text "playing", $FF
lb_txt_blank	.text "                        ", $FF
	.enc "charrom"
lb_help		.text "up down choose  fire challenge  f1 setup"
	.fill 40 - (* - lb_help), 0
	.enc "none"

lb_state_lo	.byte <lb_txt_free, <lb_txt_busy, <lb_txt_playing, <lb_txt_playing
lb_state_hi	.byte >lb_txt_free, >lb_txt_busy, >lb_txt_playing, >lb_txt_playing
lb_state_color	.byte COL_GREEN, COL_ORANGE, COL_LIGHT_RED, COL_LIGHT_RED

lobby_total	.byte 0
lobby_cursor	.byte 0
lobby_top	.byte 0
lobby_dirty	.byte 0
lobby_frame	.byte 0
lobby_joy_prev	.byte 0
lobby_new	.byte 0
lobby_setup	.byte 0 ; F1: >1 frames until the setup menu, 1 = now
lobby_id	.fill LOBBY_MAX
lobby_flags	.fill LOBBY_MAX
lobby_len	.fill LOBBY_MAX
lobby_nick	.fill LOBBY_MAX * NICK_MAX
invite_id	.byte 0
invite_seq	.byte 0
invite_timer	.byte 0
lb_last_frame	.byte 0
lb_line		.byte 0
lb_row		.byte 0
lb_idx		.byte 0
lb_len		.byte 0
lb_color_now		.byte 0
lb_flash	.byte 0
lp_index	.byte 0
lp_count	.byte 0
lp_len		.byte 0
lp_i		.byte 0
lp_nick_base	.byte 0
