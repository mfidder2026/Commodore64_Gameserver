;============================================================
;
; NET: GAME SIDE OF THE NETWORK VERSION
;
; Included by wizard_of_wor.asm (TARGET_PRG=1) after the end of
; the original 16K image, so it lives at $C000+.
;
; The original game is not deterministic: part of the game logic
; runs in the raster IRQ (timers, player movement timing, bullets,
; invisibility, launch, warp doors, the frame counter that doubles
; as random number) and the monsters move as fast as the CPU runs
; the main loop. Two machines would drift apart within seconds.
;
; This file makes a game session deterministic and tick based:
; - during a session the raster IRQ only plays sound and music
; - all game logic of the IRQ runs in tick_frame_logic, at a
;   deterministic point between two actor passes
; - the number of actor passes per tick follows a cost model:
;   every pass costs what that kind of pass cost on an NTSC C64
;   in the original (measured with PROFILE=1), a tick has the
;   budget of one NTSC frame. So the game keeps its original
;   pace, including monsters getting faster when fewer are left
; - ticks are paced to 60 per second with the CIA2 cycle counter,
;   on PAL and NTSC machines alike
; - raster line reads used as random numbers are replaced by an
;   LFSR (rnd_d012)
;
; Hooks into the original code (all same-size patches, marked
; with "NET:" in wizard_of_wor.asm):
; - joystick reads use net_joy instead of the CIA registers
;   net_joy+0: actor 0 (player 2, joystick port 2 in the original)
;   net_joy+1: actor 1 (player 1, joystick port 1 in the original)
; - irq_vector: the IRQ handler; outside a session the original
; - irq_hook: called by the original IRQ instead of sfx.play
; - pass_hook_*: once per actor pass in the three gameplay loops
;   (instead of move_bullets)
; - session_start / session_end: start of a game / title screen
; - rnd_d012: instead of LDA VIC_D012 in the game logic
;
; Build options:
;   PROFILE=1  original timing; measures the cycles per actor pass
;              per category, players driven by a bot
;   DETTEST=1  determinism test: deterministic bot, state checksum
;              every 32 ticks into det_log (tools/dettest.py)
;   DETTEST_FAST=1 (with DETTEST) the first kill in a dungeon brings
;              the Worluk, so the Worluk and Wizard loops get tested
;
; Zero page: the game uses $02-$E9. $EA-$F8 is reserved for the
; ip65 blob, $F9-$FF for this file.
;
;============================================================

	.weak
PROFILE = 0
DETTEST = 0
DETTEST_FAST = 0 ; with DETTEST: the first monster killed in a dungeon brings the Worluk (covers the other loops)
SPEEDTEST = 0 ; with DETTEST: keep the real time pacing and count idle time / resyncs (can the machine keep up?)
NETBOT = 0 ; with DETTEST: network game test - setup menu as normal, the local player is a bot, the host starts by itself
	.endweak

	; CIA2 timers: timer A counts cycles from $FFFF, timer B counts its underflows -> 32 bit cycle counter
	CIA2_TA_LO = $DD04
	CIA2_TA_HI = $DD05
	CIA2_TB_LO = $DD06
	CIA2_TB_HI = $DD07
	CIA2_ICR = $DD0D
	CIA2_CRA = $DD0E
	CIA2_CRB = $DD0F

	TICK_CYCLES = 17045 ; cycles of one NTSC frame (1022727 / 60): the budget of actor passes per tick
	TICK_PERIOD_PAL = 16421 ; 985248 / 60: real time of one tick on a PAL machine
	TICK_PERIOD_NTSC = 17045
	MAX_TICKS_BEHIND = 3 ; when the machine falls further behind, the pacing resyncs instead of catching up

	; cost of an actor pass by category (NTSC cycles incl. the IRQ share, measured with PROFILE=1)
	COST_DEAD = 953
	COST_DYING = 782
	COST_MONSTER_IDLE = 1725
	COST_MONSTER_ACTS = 4562
	COST_PLAYER_IDLE = 1699
	COST_PLAYER_MOVES = 3544

	SEED_RANDOM = $5A ; random_number at the start of a session (DETTEST; later from the network host)
	SEED_RND = $A7 ; LFSR of rnd_d012 (must not be 0)

	DET_LOG_EVERY = 32 ; ticks
	DET_LOG_SIZE = 1024 ; entries of 2 bytes

; -----------------------------------------

net_game_init .proc
	; called once at startup (from kernal_ioinit_prg)
	LDA #$7F ; no CIA2 interrupts
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
	LDA #$FF
	STA net_joy
	STA net_joy+1
	LDA #$00
	STA session_active
	LDA #SEED_RND
	STA rnd_state
	JSR detect_pal
	.if PROFILE
	JSR prof_init
	.fi
	.if DETTEST
	LDA #$00
	STA det_log_count
	STA det_log_count+1
	STA det_sessions
	STA det_frame
	LDX #2
-	STA det_loop_passes_lo,X
	STA det_loop_passes_hi,X
	DEX
	BPL -
	.if SPEEDTEST
	LDX #7
-	STA speed_ticks,X
	DEX
	BPL -
	.fi
	.fi
	RTS
.pend

detect_pal .proc
	; tick_period = real time of one tick: the highest raster line is 311 on PAL, 262/261 on NTSC
-	LDA $D012
-	CMP $D012
	BEQ -
	BMI --
	AND #$03
	CMP #$03
	BEQ _pal
	LDA #<TICK_PERIOD_NTSC
	STA tick_period
	LDA #>TICK_PERIOD_NTSC
	STA tick_period+1
	RTS
_pal
	LDA #<TICK_PERIOD_PAL
	STA tick_period
	LDA #>TICK_PERIOD_PAL
	STA tick_period+1
	RTS
.pend

; -----------------------------------------

get_cycles .proc
	; cycles = 32 bit cycle counter (counting up); changes A and X
-	LDA CIA2_TB_LO
	STA cycles+2
	LDA CIA2_TB_HI
	STA cycles+3
	LDA CIA2_TA_HI
	STA cycles+1
	LDA CIA2_TA_LO
	STA cycles
	LDA CIA2_TB_LO
	CMP cycles+2
	BNE -
	LDX #3
-	LDA cycles,X
	EOR #$FF
	STA cycles,X
	DEX
	BPL -
	RTS
.pend

; -----------------------------------------

rnd_d012 .proc
	; replaces LDA VIC_D012 where the raster line served as a random number
	; returns the next value of an 8 bit LFSR in A (period 255), flags as after LDA; X and Y are kept
	LDA rnd_state
	ASL A
	BCC +
	EOR #$1D
+	STA rnd_state
	RTS
.pend

;============================================================
;
; session start and end
;
;============================================================

session_start .proc
	; start_game, before reset_scores
	.if !PROFILE
	LDA #$01 ; PROFILE keeps the original timing: no session mode
	STA session_active
	.fi
	LDA #$00
	STA tick_count
	STA tick_count+1
	STA tick_count+2
	STA pass_valid
	LDA #<TICK_CYCLES
	STA tick_budget
	LDA #>TICK_CYCLES
	STA tick_budget+1
	; seeds: fixed for the determinism test (later: chosen by the network host), otherwise as random as the
	; original (which used the frame counter at the moment fire was pressed)
	.if DETTEST
	LDA #SEED_RND
	STA rnd_state
	LDA #SEED_RANDOM
	STA random_number
	.else
	JSR get_cycles
	LDA cycles
	EOR VIC_D012
	ORA #$01 ; an LFSR state of 0 would stay 0
	STA rnd_state
	LDA cycles+1
	EOR random_number
	STA random_number
	.fi
	; everything else the original IRQ changes on the title screen gets a fixed value, so a session does not
	; depend on how long the title screen was shown (start_dungeon sets most of these again anyway)
	LDA #$41
	STA irq_timer_frame
	LDA #$00
	STA bullet_move_counter
	STA unused_01
	STA animation_timer_tbl
	STA animation_timer_tbl+1
	LDX #MAX_ACTORS-1
-	STA one_second_wait_tbl,X
	STA time_to_invis_counter,X
	DEX
	BPL -
	LDA #$FF
	STA launch_counters
	STA launch_counters+1
	.if DETTEST
	INC det_sessions
	.fi
	LDA net_role
	BEQ +
	JSR proto_session_start ; network game: seeds from the host, input buffers (netgame.asm)
+
	; pacing starts now
	JSR get_cycles
	LDX #3
-	LDA cycles,X
	STA next_tick_time,X
	DEX
	BPL -
	JMP reset_scores
.pend

session_end .proc
	; title screen (display_high_scores_and_enemies), before vic_init
	; the title screen passes here every 10 seconds, so the network state is only reset when a session really ended
	LDA session_active
	BEQ +
	LDA #$00
	STA session_active
	LDA net_role
	BEQ +
	JSR proto_session_end
+	JMP vic_init
.pend

;============================================================
;
; IRQ
;
;============================================================

irq_vector .proc
	; the raster IRQ: outside a session the original handler, during a session only sound and music
	LDA session_active
	BNE _session
	JMP irq_handler

_session
	LDA VIC_D019
	STA VIC_D019
	AND #$01
	BEQ _end ; not a raster IRQ
	; save pointer (the sound routines use it)
	LDA tmp_0014_ptr
	STA tmp_irq_ptr_save
	LDA tmp_0014_ptr+1
	STA tmp_irq_ptr_save+1
	; stop / start sound effects if necessary (copied from irq_handler, including its bug)
	LDX next_sfx_idx
	BMI _leave_alone_sfx ; $80 means no new sfx
	CPX curr_sfx_idx
	BCC _leave_alone_sfx ; the current one has greater priority
	JSR sfx.end_of_sfx
	LDX next_sfx_idx
	STX curr_sfx_idx
	LDA sfx_by_priority,X
	STA snd_sfx_to_start
	LDA #SFX_NO_SFX
	STA next_sfx_idx
_leave_alone_sfx
	JSR sfx.play
	JSR jingles.play
	LDA #$C8
	STA VIC_D012
	LDA tmp_irq_ptr_save
	STA tmp_0014_ptr
	LDA tmp_irq_ptr_save+1
	STA tmp_0014_ptr+1
_end
	PLA
	TAY
	PLA
	TAX
	PLA
	RTI
.pend

irq_hook .proc
	; called by the original IRQ handler (outside a session) instead of sfx.play
	LDA net_role
	BEQ _local
	JSR proto_title_frame ; network game: the host's fire starts a game for both (netgame.asm)
	JMP sfx.play
_local
	.if PROFILE
	JSR prof_bot
	.elsif DETTEST
	JSR det_title_bot
	.else
	JSR read_joysticks
	.fi
	JMP sfx.play
.pend

read_joysticks .proc
	; local play: both joysticks (port 2 -> actor 0, port 1 -> actor 1, as in the original)
	LDA CIA1_JOY_KEY1
	STA net_joy
	LDA CIA1_JOY_KEY2
	STA net_joy+1
	RTS
.pend

;============================================================
;
; actor passes and ticks
;
;============================================================

	; pass hooks: X is not used by the callers before move_bullets, A and Y are free
pass_hook_normal .proc
	LDA #0
	BEQ pass_hook ; always branches
.pend

pass_hook_worluk .proc
	LDA #1
	BNE pass_hook ; always branches
.pend

pass_hook_wizard .proc
	LDA #2
	; fall through
.pend

pass_hook .proc
	; A = loop (0 normal, 1 worluk, 2 wizard); the actor of this pass is actual_actor (normal loop: not masked yet)
	.if PROFILE
	JSR prof_pass
	JMP move_bullets
	.else
	STA pass_loop
	.if DETTEST
	TAX
	INC det_loop_passes_lo,X
	BNE +
	INC det_loop_passes_hi,X
+
	.if DETTEST_FAST
	LDA #$00
	STA normal_monsters_on_screen
	STA burwors_alive
	.fi
	.fi
	LDA pass_valid
	BEQ _save
	; charge the cost of the previous pass
	JSR pass_cost ; -> X = category
	SEC
	LDA tick_budget
	SBC cost_lo,X
	STA tick_budget
	LDA tick_budget+1
	SBC cost_hi,X
	STA tick_budget+1
	; budget used up: next tick (normally once, more if a pass was very expensive)
-	LDA tick_budget+1
	BPL _save
	CLC
	LDA tick_budget
	ADC #<TICK_CYCLES
	STA tick_budget
	LDA tick_budget+1
	ADC #>TICK_CYCLES
	STA tick_budget+1
	JSR tick
	JMP -
_save
	; remember the state of the actor of this pass (the cost is decided at the start of the next pass)
	LDA actual_actor
	AND #$07
	TAX
	STX pass_actor
	LDA actor_type_tbl,X
	STA pass_type
	LDA animation_timer_tbl,X
	STA pass_timer
	LDA pass_loop
	STA pass_prev_loop
	LDA #$01
	STA pass_valid
	JMP move_bullets
	.fi
.pend

pass_cost .proc
	; X = cost category of the previous pass, by the state at its start
	LDA pass_type
	BMI _dead
	BEQ _dying
	LDA pass_actor
	CMP #MAX_PLAYERS
	BCC _player
	; monster: did its animation timer run out in this pass?
	LDA pass_timer
	LDX pass_prev_loop
	BNE _special
	CMP #$01 ; normal loop: the timer is decreased first, it acts when it reaches 0
	BEQ _acts
	BNE _idle ; always branches
_special
	CMP #$00 ; worluk / wizard: it acts when the timer underflows
	BEQ _acts
_idle
	LDX #2
	RTS
_acts
	LDX #3
	RTS
_player
	LDA pass_timer
	BMI _moves
	LDX #4
	RTS
_moves
	LDX #5
	RTS
_dead
	LDX #0
	RTS
_dying
	LDX #1
	RTS
.pend

cost_lo	.byte <COST_DEAD, <COST_DYING, <COST_MONSTER_IDLE, <COST_MONSTER_ACTS, <COST_PLAYER_IDLE, <COST_PLAYER_MOVES
cost_hi	.byte >COST_DEAD, >COST_DYING, >COST_MONSTER_IDLE, >COST_MONSTER_ACTS, >COST_PLAYER_IDLE, >COST_PLAYER_MOVES

; -----------------------------------------

tick .proc
	; one tick: wait for its time, get the inputs, run the game logic of one frame
	JSR tick_wait
	LDA net_role
	BEQ _local
	JSR proto_tick ; network game: lockstep inputs (netgame.asm)
	JMP _inputs_done
_local
	.if DETTEST
	JSR det_tick_bot
	.else
	JSR read_joysticks
	.fi
_inputs_done
	JSR tick_frame_logic
	INC tick_count
	BNE +
	INC tick_count+1
	BNE +
	INC tick_count+2
+
	.if DETTEST && !SPEEDTEST
	JSR det_log_tick ; (the checksum takes about 3 ticks of CPU time - not in the speed test)
	.fi
	RTS
.pend

tick_wait .proc
	; waits until next_tick_time, then next_tick_time += tick_period
	; a machine that is more than MAX_TICKS_BEHIND ticks late resyncs to now instead of catching up
	.if DETTEST && !SPEEDTEST
	; the determinism test runs as fast as possible (warp in VICE) - pacing must not influence the result anyway
	RTS
	.else
	.if SPEEDTEST
	INC speed_ticks
	BNE +
	INC speed_ticks+1
	BNE +
	INC speed_ticks+2
+
	.fi
-	JSR get_cycles
	; diff = cycles - next_tick_time (signed 32 bit)
	SEC
	LDA cycles
	SBC next_tick_time
	STA tick_diff
	LDA cycles+1
	SBC next_tick_time+1
	STA tick_diff+1
	LDA cycles+2
	SBC next_tick_time+2
	STA tick_diff+2
	LDA cycles+3
	SBC next_tick_time+3
	.if SPEEDTEST
	BPL +
	INC speed_idle_loops ; one wait loop is about 90 cycles
	BNE -
	INC speed_idle_loops+1
	BNE -
	INC speed_idle_loops+2
	JMP -
+
	.else
	BMI - ; not yet
	.fi
	; late: more than MAX_TICKS_BEHIND periods?
	ORA tick_diff+2
	BNE _resync
	LDA tick_diff+1
	CMP #>(TICK_PERIOD_NTSC * MAX_TICKS_BEHIND)
	BCS _resync
	; next_tick_time += tick_period
	CLC
	LDA next_tick_time
	ADC tick_period
	STA next_tick_time
	LDA next_tick_time+1
	ADC tick_period+1
	STA next_tick_time+1
	BCC +
	INC next_tick_time+2
	BNE +
	INC next_tick_time+3
+	RTS
_resync
	.if SPEEDTEST
	INC speed_resyncs
	BNE +
	INC speed_resyncs+1
+
	.fi
	LDX #3
-	LDA cycles,X
	STA next_tick_time,X
	DEX
	BPL -
	RTS
	.fi
.pend

; -----------------------------------------

tick_frame_logic .proc
	; the game logic of the original raster IRQ (irq_handler), for one frame
	; sound effect handling stays in the IRQ (irq_vector)

	; the pointer is saved like in the IRQ: start_launch and open_warp_door use it
	LDA tmp_0014_ptr
	PHA
	LDA tmp_0014_ptr+1
	PHA

	; the value of this counter is basically used as a random number
	DEC random_number
	; decrease animation timer for players and the bullets
	DEC animation_timer_tbl
	DEC animation_timer_tbl+1
	DEC bullet_move_counter

	LDA is_title_screen
	BNE _run_timer

	; make garwors and thorwors invisible after a certain time
	LDX #MAX_PLAYERS
_check_invisibility_timers
	DEC one_second_wait_tbl,X
	BPL _not_invisible
	LDA #$3C
	STA one_second_wait_tbl,X
	DEC time_to_invis_counter,X
	BPL _not_invisible
	LDA #$0A ; will be invisible again after 10 seconds
	STA time_to_invis_counter,X
	DEC actor_speed_tbl,X
	; skip burwors (light blue sprites)
	LDA VIC_D027,X
	AND #$0F
	CMP #$0E
	BEQ _not_invisible
	; switch off sprite visibility
	LDA power_of_2_tbl,X
	EOR #$FF
	AND VIC_D015
	STA VIC_D015
_not_invisible
	INX
	CPX #$08
	BNE _check_invisibility_timers

_run_timer
	; timer for player launch and warp door opening
	DEC irq_timer_frame
	BNE _end_of_timer_section
	LDA #$41
	STA irq_timer_frame
	; check launch status for player2
	LDA launch_counters+1
	BMI _check_p1 ; no launch process ATM
	DEC launch_counters+1
	BNE _check_p1 ; countdown in process
	LDA lives_player1
	BMI _check_p1 ; no more lives for player1
	LDX #$01
	JSR move_actor.start_launch
_check_p1
	; check launch status for player1
	LDA launch_counters
	BMI _dont_launch_p1 ; no launch process ATM
	DEC launch_counters
	BNE _dont_launch_p1 ; countdown in process
	LDA lives_player2
	BMI _dont_launch_p1 ; no more lives for player1
	LDX #$00
	JSR move_actor.start_launch
_dont_launch_p1
	DEC unused_01 ; this seems to be unused
	; check warp door opening timer
	DEC irq_timer_sec
	BNE _end_of_timer_section
	; timer expired: open warp door, speed up music
	JSR open_warp_door
	DEC music_speed
	; keep music_speed above zero
	BNE _end_of_timer_section
	INC music_speed
_end_of_timer_section
	PLA
	STA tmp_0014_ptr+1
	PLA
	STA tmp_0014_ptr
	RTS
.pend

;============================================================
;
; deterministic replacements of original routines
;
;============================================================

select_dungeon_layout_det .proc
	; select_dungeon_layout (called by start_dungeon) loops until random_number gives a usable layout,
	; relying on the IRQ to change random_number meanwhile. During a session the IRQ does not touch it, so
	; this copy lets random_number run down one step for every read instead - deterministic, and like time
	; passing in the original. Otherwise the same code.
	LDA session_active
	BNE +
	JMP select_dungeon_layout
+
	LDA #$00
	STA dungeon_layout_ptr+1
	INC current_dungeon
_get_dungeon_layout
	LDX current_dungeon
	; after dungeon 98 loop back to dungeon 97 so after reaching this loop every other dungeon is a Pit
	CPX #$62
	BNE +
	LDX #$60
	STX current_dungeon
+
	TXA
	CMP #$03
	BNE _not_arena
	; dungeon 4 - the Arena: layout 24, magic voice 6
	LDY #$06
	JSR magic_voice.say
	LDA #$18 ; always use layout 24
	BNE _layout_selected ; always branch
_not_arena
	CMP #$07
	BCS _dungeon_over_8
	; first 8 dungeons, not Arena: a random layout in the 0-14 range
-	JSR _random
	AND #$0F
	CMP #$0F
	BEQ -
	BNE _layout_selected ; always branch
_dungeon_over_8
	; the "worlord" dungeons: current_dungeon mod 6
	SBC #$06
	BCS _dungeon_over_8
	ADC #$06
	BNE _not_pit
	; dungeons 13, 19, etc: the Pit, layout 23, magic voice 7
	LDY #$07
	JSR magic_voice.say
	LDA #$17 ; always use layout 23
	BNE _layout_selected ; always branch
_not_pit
	; rest of the dungeons: a random layout in the 15-22 range
	JSR _random
	AND #$07
	TAX
	LDY select_dungeon_layout.worlord_dungeons_MV_tbl,X
	JSR magic_voice.say
	JSR _random
	AND #$07
	CLC
	ADC #$0F
_layout_selected
	; check if this layout was used in the previous dungeon
	CMP prev_dungeon_layout
	BEQ _get_dungeon_layout
	STA prev_dungeon_layout
	; pointer = dungeon_layouts + layout * 18
	LDX #$10
	STA dungeon_layout_ptr
_mul
	CLC
	ADC dungeon_layout_ptr
	BCC +
	INC dungeon_layout_ptr+1
+	DEX
	BPL _mul
	CLC
	ADC #<dungeon_layouts
	STA dungeon_layout_ptr
	LDA dungeon_layout_ptr+1
	ADC #>dungeon_layouts
	STA dungeon_layout_ptr+1
	RTS
_random
	DEC random_number
	LDA random_number
	RTS
.pend

;============================================================
;
; DETTEST: determinism test
;
;============================================================

	.if DETTEST

det_title_bot .proc
	; outside a session: press fire on port 2 now and then (starts a 2 player game), nothing else
	INC det_frame
	LDA det_frame
	AND #$3F
	CMP #$30
	LDA #$FF
	BCC +
	LDA #$EF
+	STA net_joy
	LDA #$FF
	STA net_joy+1
	RTS
.pend

det_tick_bot .proc
	; during a session the inputs are a function of the tick number only:
	; every 16 ticks a new direction and fire state for each player
	LDA tick_count
	AND #$0F
	BNE _keep
	LDX #1
-	TXA
	ASL A
	ASL A
	ASL A
	EOR tick_count
	EOR tick_count+1
	STA det_tmp
	; mix: rotate the tick bits so both players differ
	LDA tick_count
	LSR A
	LSR A
	LSR A
	LSR A
	EOR det_tmp
	ASL A
	ADC #$3B
	EOR tick_count+1
	STA det_tmp
	AND #$03
	TAY
	LDA det_dirs,Y
	BIT det_tmp
	BPL + ; bit 7 clear: fire pressed
	ORA #$10 ; release fire
+	STA net_joy,X
	DEX
	BPL -
_keep
	RTS
det_dirs .byte $EE,$ED,$EB,$E7 ; up, down, left, right with fire pressed
.pend

det_bot_value .proc
	; network test: the bot input of actor det_ba for tick det_bt (16 bit) -> A
	; a new direction / fire state every 16 ticks, different for both actors
	LDA det_bt
	LSR A
	LSR A
	LSR A
	LSR A
	STA det_tmp
	LDA det_bt+1
	ASL A
	ASL A
	ASL A
	ASL A
	ORA det_tmp ; bits 4-11 of the tick
	STA det_tmp
	LDA det_ba
	ASL A
	ASL A
	ASL A
	EOR det_tmp
	ASL A
	ADC #$3B
	EOR det_tmp
	STA det_tmp
	AND #$03
	TAY
	LDA det_tick_bot.det_dirs,Y
	BIT det_tmp
	BPL + ; bit 7 clear: fire pressed
	ORA #$10 ; release fire
+	RTS
.pend

det_log_tick .proc
	; every DET_LOG_EVERY ticks: append a checksum of the game state to det_log
	LDA tick_count
	AND #DET_LOG_EVERY-1
	BEQ +
	RTS
+	LDA det_log_count+1
	CMP #>DET_LOG_SIZE
	BCC +
	RTS ; full
+
	; the very first one: keep a snapshot of the state for tools/dettest.py (finding what differs)
	LDA det_log_count
	ORA det_log_count+1
	BNE +
	LDX #0
-	LDA $00,X
	STA det_snap,X
	LDA $0200,X
	STA det_snap+$100,X
	LDA $0400,X
	STA det_snap+$300,X
	LDA $0500,X
	STA det_snap+$400,X
	LDA $0600,X
	STA det_snap+$500,X
	LDA $0700,X
	STA det_snap+$600,X
	INX
	BNE -
	LDX #$2F
-	LDA $D000,X
	STA det_snap+$200,X
	DEX
	BPL -
+
	JSR det_checksum ; -> det_sum (2 bytes)
	; det_log + count * 2
	LDA det_log_count
	ASL A
	STA det_ptr
	LDA det_log_count+1
	ROL A
	STA det_ptr+1
	CLC
	LDA det_ptr
	ADC #<det_log
	STA det_ptr
	LDA det_ptr+1
	ADC #>det_log
	STA det_ptr+1
	LDY #0
	LDA det_sum
	STA (det_ptr),Y
	INY
	LDA det_sum+1
	STA (det_ptr),Y
	INC det_log_count
	BNE +
	INC det_log_count+1
+	RTS
.pend

det_checksum .proc
	; 16 bit checksum (add with rotate) over: screen RAM, sprite registers and pointers,
	; the zero page variables of the game, page 2 variables
	LDA #0
	STA det_sum
	STA det_sum+1
	; screen $0400-$07FF (includes the sprite pointers)
	LDA #<$0400
	STA det_ptr
	LDA #>$0400
	STA det_ptr+1
	LDX #4
_page
	LDY #0
-	CPX #1 ; last page: $07E8-$07F7 lie between the screen and the sprite pointers, never cleared or read
	BNE +
	CPY #$E8
	BCC +
	CPY #$F8
	BCC _skip_scr
+	LDA (det_ptr),Y
	JSR _add
_skip_scr
	INY
	BNE -
	INC det_ptr+1
	DEX
	BNE _page
	; VIC: sprite positions, enable, multicolor/priority/expansion, colors - not the raster and collision registers
	LDX #0
-	LDA $D000,X
	JSR _add
	INX
	CPX #$11
	BNE -
	LDA $D015
	JSR _add
	LDX #$1B
-	LDA $D000,X
	JSR _add
	INX
	CPX #$1E
	BNE -
	LDX #$20
-	LDA $D000,X
	JSR _add
	INX
	CPX #$2F
	BNE -
	; zero page $02-$E9 without the variables of the sound routines (the IRQ changes them at any time)
	; and without the pointer the IRQ saves and restores
	LDX #$02
-	CPX #<tmp_0014_ptr
	BEQ _skip_zp
	CPX #<tmp_0014_ptr+1
	BEQ _skip_zp
	CPX #<snd_ingame_dur
	BCC +
	CPX #<MV_sentence_ptr+2
	BCC _skip_zp
+	LDA $00,X
	JSR _add
_skip_zp
	INX
	CPX #$EA
	BNE -
	; page 2 variables $0200-$0271 without the ones of the IRQ / sound effects
	LDX #0
-	CPX #<tmp_irq_ptr_save
	BEQ _skip_p2
	CPX #<tmp_irq_ptr_save+1
	BEQ _skip_p2
	CPX #<curr_sfx_idx
	BEQ _skip_p2
	CPX #<next_sfx_idx
	BEQ _skip_p2
	LDA $0200,X
	JSR _add
_skip_p2
	INX
	CPX #$72
	BNE -
	RTS
_add
	; det_sum = rol(det_sum) + A
	ASL det_sum
	ROL det_sum+1
	BCC +
	INC det_sum
+	CLC
	ADC det_sum
	STA det_sum
	BCC +
	INC det_sum+1
+	RTS
.pend

	.fi ; DETTEST

;============================================================
;
; PROFILE: measurement of the original timing
;
;============================================================

	.if PROFILE

	PROF_CATS = 6 ; dead, dying, monster idle, monster acts, player idle, player moves
	PROF_LOOPS = 3
	PROF_ENTRY = 8 ; count (2) + cycle sum (4) + max (2)

prof_init .proc
	LDX #$00
	LDA #$00
-	STA prof_stats,X
	INX
	CPX #PROF_CATS * PROF_LOOPS * PROF_ENTRY
	BNE -
	STA prof_frames
	STA prof_frames+1
	STA prof_bot_frame
	STA prof_bot_frame+1
	STA pass_valid
	LDA #$A5
	STA prof_lfsr
	RTS
.pend

prof_pass .proc
	STA pass_loop
	JSR get_cycles
	; delta = cycles - prof_last
	SEC
	LDA cycles
	SBC prof_last
	STA prof_delta
	LDA cycles+1
	SBC prof_last+1
	STA prof_delta+1
	LDA cycles+2
	SBC prof_last+2
	STA prof_delta+2
	LDA cycles+3
	SBC prof_last+3
	ORA prof_delta+2
	BEQ +
	JMP _skip ; longer than 65535 cycles: a transition, not a pass
+
	LDX #3
-	LDA cycles,X
	STA prof_last,X
	DEX
	BPL -
	LDA pass_valid
	BNE +
	JMP _save
+
	JSR pass_cost ; X = category
	TXA
	; entry = (loop * PROF_CATS + cat) * PROF_ENTRY
	STA prof_tmp
	LDA pass_prev_loop
	ASL A
	ADC pass_prev_loop ; *3
	ASL A ; *6 = PROF_CATS
	ADC prof_tmp
	ASL A
	ASL A
	ASL A ; *8 = PROF_ENTRY
	TAX
	; max
	LDA prof_delta
	CMP prof_stats+6,X
	LDA prof_delta+1
	SBC prof_stats+7,X
	BCC +
	LDA prof_delta
	STA prof_stats+6,X
	LDA prof_delta+1
	STA prof_stats+7,X
+	INC prof_stats,X
	BNE +
	INC prof_stats+1,X
+	CLC
	LDA prof_stats+2,X
	ADC prof_delta
	STA prof_stats+2,X
	LDA prof_stats+3,X
	ADC prof_delta+1
	STA prof_stats+3,X
	BCC _save
	INC prof_stats+4,X
	BNE _save
	INC prof_stats+5,X
	JMP _save

_skip
	LDX #3
-	LDA cycles,X
	STA prof_last,X
	DEX
	BPL -
_save
	; remember the state of the actor of this pass
	LDA actual_actor
	AND #$07
	TAX
	STX pass_actor
	LDA actor_type_tbl,X
	STA pass_type
	LDA animation_timer_tbl,X
	STA pass_timer
	LDA pass_loop
	STA pass_prev_loop
	LDA #1
	STA pass_valid
	RTS
.pend

prof_bot .proc
	; drives both players: start a 2 player game, then wander and shoot
	INC prof_frames
	BNE +
	INC prof_frames+1
+	INC prof_bot_frame
	LDA prof_bot_frame
	AND #$7F
	CMP #$70
	BCC _play
	; for 16 out of 128 frames press fire (starts a 2 player game on the title screen)
	LDA #$EF
	STA net_joy
	STA net_joy+1
	RTS
_play
	AND #$0F
	BNE _keep
	; every 16 frames a new direction and fire state for both players
	LDX #1
-	JSR prof_rnd
	AND #$03
	TAY
	LDA prof_dirs,Y
	STA prof_tmp
	JSR prof_rnd
	AND #$10 ; fire pressed half of the time (active low)
	ORA prof_tmp
	STA net_joy,X
	DEX
	BPL -
_keep
	RTS
prof_dirs .byte $EE,$ED,$EB,$E7 ; up, down, left, right with fire pressed (bit 4 low); the ORA may release fire
.pend

prof_rnd .proc
	LDA prof_lfsr
	ASL A
	BCC +
	EOR #$1D
+	STA prof_lfsr
	RTS
.pend

	.fi ; PROFILE

;============================================================
;
; variables
;
;============================================================

net_joy		.fill 2
cycles		.fill 4
session_active	.fill 1
rnd_state	.fill 1
tick_count	.fill 3
tick_budget	.fill 2
tick_period	.fill 2
tick_diff	.fill 3
next_tick_time	.fill 4
pass_loop	.fill 1
pass_valid	.fill 1
pass_actor	.fill 1
pass_type	.fill 1
pass_timer	.fill 1
pass_prev_loop	.fill 1

	.if DETTEST
det_ptr = $FD ; 2 bytes zero page (shared with net_parse_ptr, which is only used in the setup menu)
det_frame	.fill 1
det_tmp		.fill 1
det_sum		.fill 2
det_sessions	.fill 1
det_log_count	.fill 2
det_bt		.fill 2
det_ba		.fill 1
det_loop_passes_lo .fill 3 ; passes per loop: normal, worluk, wizard
det_loop_passes_hi .fill 3
	.virtual $E000 ; RAM under the KERNAL ROM: written by the C64 (writes always reach the RAM), read by tools/dettest.py
det_log		.fill DET_LOG_SIZE * 2
det_snap	.fill $700 ; zero page, page 2, VIC ($200), screen ($300-$6FF)
	.endv
	.fi

	.if SPEEDTEST
speed_ticks	.fill 3
speed_idle_loops .fill 3
speed_resyncs	.fill 2
	.fi

	.if PROFILE
prof_stats	.fill PROF_CATS * PROF_LOOPS * PROF_ENTRY
prof_frames	.fill 2
prof_last	.fill 4
prof_delta	.fill 3
prof_tmp	.fill 1
prof_bot_frame	.fill 2
prof_lfsr	.fill 1
	.fi
