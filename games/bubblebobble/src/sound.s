; ============================================================================
; sound.s - Unified Sound & Music System for Bubble Bobble C64
; ============================================================================
;
; This file contains the COMPLETE sound engine, all music data, and all
; sound effect data for Bubble Bobble C64. It is the single source of truth
; for all audio in the game.
;
; SEGMENTS (in memory order):
;   SOUND_LO       $7040-$743F  Music sequences, command handlers, lookup tables
;   SCREEN_BUFFER  $8B00-$8DDF  Title screen music (3 voices + inline instruments)
;   SOUND_HI       $F240-$FE8F  Sound engine code, data tables, SFX & music data
;
; TOTAL: ~4,912 bytes across 3 segments
;
; PUBLIC API:
;   sound_init  (sound_init)   - Initialize SID chip and clear sound state
;   sound_update  (sound_update) - Called every frame to update all 3 voices
;   sfx_start                 - Music/mode initialization
;
; TO REPLACE THE SOUND SYSTEM:
;   Provide your own file that defines the same segments and exports the same
;   public labels. The game calls sound_init, sound_update, sfx_start, and
;   music_start. Also export 2 capability flags (0 or 1) so game code adapts:
;     SOUND_SONGS_LOOP        - 1 if songs loop forever (skip wait-for-end)
;
; ============================================================================

.setcpu "6502"

; ============================================================================
; Public API exports
; ============================================================================
;
; Any replacement sound engine must export these same labels.
;

; --- Entry points ---
.export sound_init                          ; sound_init: init SID, clear state
.export sound_update                          ; sound_update: call every frame
.export music_start                 ; Start a song (Y = song offset)
.export sfx_start                          ; Music/mode init (used by credits)

; --- Song table base (for computing Y offsets) ---
.export music_song_table            ; Base for song Y-value calculation

; --- Song labels (use as: ldy #(song_xxx - music_song_table)) ---
.export song_level_theme                ; Main level gameplay
.export song_level_resume               ; After death / level init (no intro)
.export song_level_final                ; Level 99 variant
.export song_bonus_round                ; Bonus round
.export song_game_over                  ; Game over
.export song_level_complete             ; Level transition
.export song_extend                     ; EXTEND letters collected
.export song_title_screen               ; Title screen
.export song_hurry_up                   ; Hurry-up percussion during scroll
.export song_round_start                ; Round/game start fanfare
.export song_super_bonus                ; Extended bonus stage
.export song_ending                     ; Ending / story sequence

; --- SFX voice configurations (referenced by credits-handler-partial.s) ---
.export sfx_preset_0
.export sfx_preset_1
.export sfx_preset_2
.export sfx_preset_3
.export sfx_preset_4
.export sfx_preset_5

; --- Sound engine capability flags ---
; These flags describe engine behavior so game code can adapt generically
; without needing to know which specific sound engine is active.
SOUND_SONGS_LOOP       = 0  ; Songs end naturally (SYESSION reaches 0)
.export SOUND_SONGS_LOOP

; --- Segment boundaries (for standalone SID build) ---
.export L_7040                          ; Start of SOUND_LO
.export musichandlers_end               ; End of SOUND_LO
.export title_music_voice0              ; Start of SCREEN_BUFFER
.export screen_buffer_end               ; End of SCREEN_BUFFER
.export music_control_data              ; Start of music state to zero
.export music_control_data_end          ; End of music state to zero

; ============================================================================
; SECTION 1: Level Music Sequences ($7040-$7304)
; ============================================================================
; Music sequence data for level music tracks. Music commands embed addresses
; pointing to instrument data in the SFX/music data region, expressed as label
; references to allow relocation.
; ============================================================================

        .segment "SOUND_LO"

L_7040:
        .byte   $86                                    ; $7040: copy instrument
        .byte   <sfx_instr_8, >sfx_instr_8                      ;   -> sfx_instr_8 ($FAC9)
        .byte   $9A                                    ; $7043: copy 16-byte block
        .byte   <sfx_instr_16, >sfx_instr_16                      ;   -> sfx_instr_16 ($FC08)
        .byte   $8E                                    ; $7046: filter from table
        .byte   $98                                    ; $7047: return
L_7048:
        .byte   $86                                    ; $7048: copy instrument
        .byte   <sfx_instr_9, >sfx_instr_9                      ;   -> sfx_instr_9 ($FAE6)
        .byte   $9A                                    ; $704B: copy 16-byte block
        .byte   <sfx_instr_17, >sfx_instr_17                      ;   -> sfx_instr_17 ($FC18)
        .byte   $8E                                    ; $704E: filter from table
        .byte   $98                                    ; $704F: return
L_7050:
        .byte   $80, $04                              ; $7050: set param $04
        .byte   $18, $02                               ; $7052: note + duration
        .byte   $24, $02                               ; $7054: note + duration
        .byte   $82                                    ; $7056: loop decrement
        .byte   $98                                    ; $7057: return
L_7058:
        .byte   $80, $08                              ; $7058: set param $08
        .byte   $16, $02                               ; $705A: note + duration
        .byte   $22, $02                               ; $705C: note + duration
        .byte   $82                                    ; $705E: loop decrement
        .byte   $98                                    ; $705F: return
L_7060:
        .byte   $3A, $02                               ; $7060: note + duration
        .byte   $39, $02                               ; $7062: note + duration
        .byte   $37, $03                               ; $7064: note + duration
        .byte   $35, $01                               ; $7066: note + duration
        .byte   $39, $02                               ; $7068: note + duration
        .byte   $37, $02                               ; $706A: note + duration
        .byte   $98                                    ; $706C: return
L_706D:
        .byte   $60, $01                               ; $706D: end/rest + duration
        .byte   $86                                    ; $706F: copy instrument
        .byte   <sfx_instr_3, >sfx_instr_3                      ;   -> sfx_instr_3 ($FBEB)
        .byte   $88, $F4                              ; $7072: set voice $F4
L_7074:
        .byte   $40, $02                               ; $7074: note + duration
        .byte   $3C, $02                               ; $7076: note + duration
        .byte   $40, $02                               ; $7078: note + duration
        .byte   $3C, $02                               ; $707A: note + duration
        .byte   $40, $02                               ; $707C: note + duration
        .byte   $3C, $02                               ; $707E: note + duration
        .byte   $3E, $02                               ; $7080: note + duration
        .byte   $40, $02                               ; $7082: note + duration
        .byte   $41, $02                               ; $7084: note + duration
        .byte   $3E, $02                               ; $7086: note + duration
        .byte   $41, $02                               ; $7088: note + duration
        .byte   $3E, $02                               ; $708A: note + duration
        .byte   $41, $02                               ; $708C: note + duration
        .byte   $3E, $02                               ; $708E: note + duration
        .byte   $40, $02                               ; $7090: note + duration
        .byte   $41, $02                               ; $7092: note + duration
        .byte   $43, $02                               ; $7094: note + duration
        .byte   $40, $02                               ; $7096: note + duration
        .byte   $43, $02                               ; $7098: note + duration
        .byte   $40, $02                               ; $709A: note + duration
        .byte   $43, $02                               ; $709C: note + duration
        .byte   $40, $02                               ; $709E: note + duration
        .byte   $41, $02                               ; $70A0: note + duration
        .byte   $43, $02                               ; $70A2: note + duration
        .byte   $41, $02                               ; $70A4: note + duration
        .byte   $3E, $02                               ; $70A6: note + duration
        .byte   $41, $02                               ; $70A8: note + duration
        .byte   $3E, $02                               ; $70AA: note + duration
        .byte   $41, $02                               ; $70AC: note + duration
        .byte   $3E, $02                               ; $70AE: note + duration
        .byte   $40, $02                               ; $70B0: note + duration
        .byte   $41, $02                               ; $70B2: note + duration
        .byte   $96                                    ; $70B4: goto/loop
        .byte   <L_7074, >L_7074    ;   -> $7074
L_70B7:
        .byte   $94                                    ; $70B7: call subroutine
        .byte   <L_7048, >L_7048    ;   -> $7048
L_70BA:
        .byte   $92, $00                              ; $70BA: set param + call
        .byte   <L_7050, >L_7050    ;   -> $7050
        .byte   $92, $02                              ; $70BE: set param + call
        .byte   <L_7050, >L_7050    ;   -> $7050
        .byte   $92, $04                              ; $70C2: set param + call
        .byte   <L_7050, >L_7050    ;   -> $7050
        .byte   $92, $02                              ; $70C6: set param + call
        .byte   <L_7050, >L_7050    ;   -> $7050
        .byte   $96                                    ; $70CA: goto/loop
        .byte   <L_70BA, >L_70BA    ;   -> $70BA
L_70CD:
        .byte   $60, $01                               ; $70CD: end/rest + duration
L_70CF:
        .byte   $86                                    ; $70CF: copy instrument
        .byte   <sfx_instr_6, >sfx_instr_6                      ;   -> sfx_instr_6 ($FA72)
        .byte   $88, $0C                              ; $70D2: set voice $0C
        .byte   $28, $02                               ; $70D4: note + duration
        .byte   $21, $02                               ; $70D6: note + duration
        .byte   $27, $02                               ; $70D8: note + duration
        .byte   $20, $02                               ; $70DA: note + duration
        .byte   $1F, $02                               ; $70DC: note + duration
        .byte   $26, $02                               ; $70DE: note + duration
        .byte   $1E, $02                               ; $70E0: note + duration
        .byte   $1D, $02                               ; $70E2: note + duration
        .byte   $24, $02                               ; $70E4: note + duration
        .byte   $1F, $02                               ; $70E6: note + duration
        .byte   $26, $02                               ; $70E8: note + duration
        .byte   $27, $04                               ; $70EA: note + duration
        .byte   $88, $00                              ; $70EC: set voice $00
        .byte   $86                                    ; $70EE: copy instrument
        .byte   <sfx_instr_0, >sfx_instr_0                      ;   -> sfx_instr_0 ($FAAC)
        .byte   $3A, $03                               ; $70F1: note + duration
        .byte   $3A, $04                               ; $70F3: note + duration
        .byte   $86                                    ; $70F5: copy instrument
        .byte   <sfx_instr_13, >sfx_instr_13                      ;   -> sfx_instr_13 ($FB77)
        .byte   $92, $00                              ; $70F8: set param + call
        .byte   <L_710D, >L_710D    ;   -> $710D
        .byte   $92, $05                              ; $70FC: set param + call
        .byte   <L_710D, >L_710D    ;   -> $710D
        .byte   $92, $00                              ; $7100: set param + call
        .byte   <L_710D, >L_710D    ;   -> $710D
        .byte   $92, $07                              ; $7104: set param + call
        .byte   <L_7129, >L_7129    ;   -> $7129
        .byte   $88, $00                              ; $7108: set voice $00
        .byte   $96                                    ; $710A: goto/loop
        .byte   <L_70CF, >L_70CF    ;   -> $70CF
L_710D:
        .byte   $94                                    ; $710D: call subroutine
        .byte   <L_7145, >L_7145    ;   -> $7145
        .byte   $3F, $01                               ; $7110: note + duration
        .byte   $3E, $01                               ; $7112: note + duration
        .byte   $3D, $01                               ; $7114: note + duration
        .byte   $3C, $01                               ; $7116: note + duration
        .byte   $3E, $01                               ; $7118: note + duration
        .byte   $3D, $01                               ; $711A: note + duration
        .byte   $3C, $01                               ; $711C: note + duration
        .byte   $3B, $01                               ; $711E: note + duration
        .byte   $3D, $01                               ; $7120: note + duration
        .byte   $3C, $01                               ; $7122: note + duration
        .byte   $3B, $01                               ; $7124: note + duration
        .byte   $3A, $01                               ; $7126: note + duration
        .byte   $98                                    ; $7128: return
L_7129:
        .byte   $94                                    ; $7129: call subroutine
        .byte   <L_7145, >L_7145    ;   -> $7145
        .byte   $3C, $01                               ; $712C: note + duration
        .byte   $3B, $01                               ; $712E: note + duration
        .byte   $3A, $01                               ; $7130: note + duration
        .byte   $39, $01                               ; $7132: note + duration
        .byte   $38, $01                               ; $7134: note + duration
        .byte   $37, $01                               ; $7136: note + duration
        .byte   $36, $01                               ; $7138: note + duration
        .byte   $35, $01                               ; $713A: note + duration
        .byte   $34, $01                               ; $713C: note + duration
        .byte   $33, $01                               ; $713E: note + duration
        .byte   $32, $01                               ; $7140: note + duration
        .byte   $31, $01                               ; $7142: note + duration
        .byte   $98                                    ; $7144: return
L_7145:
        .byte   $80, $02                              ; $7145: set param $02
        .byte   $40, $01                               ; $7147: note + duration
        .byte   $3F, $01                               ; $7149: note + duration
        .byte   $3E, $01                               ; $714B: note + duration
        .byte   $3D, $01                               ; $714D: note + duration
        .byte   $3C, $01                               ; $714F: note + duration
        .byte   $3D, $01                               ; $7151: note + duration
        .byte   $3E, $01                               ; $7153: note + duration
        .byte   $3F, $01                               ; $7155: note + duration
        .byte   $82                                    ; $7157: loop decrement
        .byte   $40, $01                               ; $7158: note + duration
        .byte   $3F, $01                               ; $715A: note + duration
        .byte   $3E, $01                               ; $715C: note + duration
        .byte   $3D, $01                               ; $715E: note + duration
        .byte   $98                                    ; $7160: return
L_7161:
        .byte   $94                                    ; $7161: call subroutine
        .byte   <L_7040, >L_7040    ;   -> $7040
        .byte   $21, $06                               ; $7164: note + duration
        .byte   $20, $06                               ; $7166: note + duration
        .byte   $1F, $06                               ; $7168: note + duration
        .byte   $1E, $08                               ; $716A: note + duration
        .byte   $86                                    ; $716C: copy instrument
        .byte   <sfx_instr_0, >sfx_instr_0                      ;   -> sfx_instr_0 ($FAAC)
        .byte   $90                                    ; $716F: filter cutoff $78
        .byte   $43, $03                               ; $7170: note + duration
        .byte   $43, $04                               ; $7172: note + duration
        .byte   $86                                    ; $7174: copy instrument
        .byte   <sfx_instr_9, >sfx_instr_9                      ;   -> sfx_instr_9 ($FAE6)
        .byte   $94                                    ; $7177: call subroutine
        .byte   <L_7196, >L_7196    ;   -> $7196
        .byte   $80, $04                              ; $717A: set param $04
        .byte   $1A, $02                               ; $717C: note + duration
        .byte   $21, $02                               ; $717E: note + duration
        .byte   $1D, $02                               ; $7180: note + duration
        .byte   $21, $02                               ; $7182: note + duration
        .byte   $82                                    ; $7184: loop decrement
        .byte   $94                                    ; $7185: call subroutine
        .byte   <L_7196, >L_7196    ;   -> $7196
        .byte   $80, $04                              ; $7188: set param $04
        .byte   $1C, $02                               ; $718A: note + duration
        .byte   $23, $02                               ; $718C: note + duration
        .byte   $20, $02                               ; $718E: note + duration
        .byte   $23, $02                               ; $7190: note + duration
        .byte   $82                                    ; $7192: loop decrement
        .byte   $96                                    ; $7193: goto/loop
        .byte   <L_7161, >L_7161    ;   -> $7161
L_7196:
        .byte   $80, $04                              ; $7196: set param $04
        .byte   $15, $02                               ; $7198: note + duration
        .byte   $1C, $02                               ; $719A: note + duration
        .byte   $18, $02                               ; $719C: note + duration
        .byte   $1C, $02                               ; $719E: note + duration
        .byte   $82                                    ; $71A0: loop decrement
        .byte   $98                                    ; $71A1: return
L_71A2:
        .byte   $86                                    ; $71A2: copy instrument
        .byte   <sfx_instr_1, >sfx_instr_1                      ;   -> sfx_instr_1 ($FB3D)
L_71A5:
        .byte   $32, $01                               ; $71A5: note + duration
        .byte   $36, $03                               ; $71A7: note + duration
        .byte   $36, $01                               ; $71A9: note + duration
        .byte   $32, $03                               ; $71AB: note + duration
        .byte   $32, $01                               ; $71AD: note + duration
        .byte   $34, $01                               ; $71AF: note + duration
        .byte   $36, $01                               ; $71B1: note + duration
        .byte   $37, $02                               ; $71B3: note + duration
        .byte   $2B, $03                               ; $71B5: note + duration
        .byte   $98                                    ; $71B7: return
L_71B8:
        .byte   $86                                    ; $71B8: copy instrument
        .byte   <sfx_instr_3, >sfx_instr_3                      ;   -> sfx_instr_3 ($FBEB)
        .byte   $96                                    ; $71BB: goto/loop
        .byte   <L_71A5, >L_71A5    ;   -> $71A5
L_71BE:
        .byte   $94                                    ; $71BE: call subroutine
        .byte   <L_7040, >L_7040    ;   -> $7040
        .byte   $5F, $01                               ; $71C1: note + duration
        .byte   $1A, $04                               ; $71C3: note + duration
        .byte   $26, $04                               ; $71C5: note + duration
        .byte   $21, $02                               ; $71C7: note + duration
        .byte   $1F, $02                               ; $71C9: note + duration
        .byte   $13, $03                               ; $71CB: note + duration
        .byte   $98                                    ; $71CD: return
L_71CE:
        .byte   $86                                    ; $71CE: copy instrument
        .byte   <sfx_instr_7, >sfx_instr_7                      ;   -> sfx_instr_7 ($FA8F)
        .byte   $37, $04                               ; $71D1: note + duration
        .byte   $86                                    ; $71D3: copy instrument
        .byte   <sfx_instr_12, >sfx_instr_12                      ;   -> sfx_instr_12 ($FB5A)
        .byte   $80, $08                              ; $71D6: set param $08
        .byte   $4F, $04                               ; $71D8: note + duration
        .byte   $4A, $04                               ; $71DA: note + duration
        .byte   $82                                    ; $71DC: loop decrement
        .byte   $4F, $02                               ; $71DD: note + duration
L_71DF:
        .byte   $84                                    ; $71DF: copy 14-byte block
        .byte   <sfx_instr_20, >sfx_instr_20                      ;   -> sfx_instr_20 ($FC48)
        .byte   $1F, $03                               ; $71E2: note + duration
        .byte   $24, $03                               ; $71E4: note + duration
        .byte   $29, $03                               ; $71E6: note + duration
        .byte   $2F, $03                               ; $71E8: note + duration
        .byte   $34, $03                               ; $71EA: note + duration
        .byte   $39, $03                               ; $71EC: note + duration
        .byte   $3E, $03                               ; $71EE: note + duration
        .byte   $43, $03                               ; $71F0: note + duration
        .byte   $48, $03                               ; $71F2: note + duration
        .byte   $4D, $03                               ; $71F4: note + duration
        .byte   $53, $03                               ; $71F6: note + duration
        .byte   $58, $09                               ; $71F8: note + duration
        .byte   $98                                    ; $71FA: return
L_71FB:
        .byte   $86                                    ; $71FB: copy instrument
        .byte   <sfx_instr_7, >sfx_instr_7                      ;   -> sfx_instr_7 ($FA8F)
        .byte   $2D, $04                               ; $71FE: note + duration
        .byte   $86                                    ; $7200: copy instrument
        .byte   <sfx_instr_12, >sfx_instr_12                      ;   -> sfx_instr_12 ($FB5A)
        .byte   $5F, $02                               ; $7203: note + duration
        .byte   $80, $08                              ; $7205: set param $08
        .byte   $48, $04                               ; $7207: note + duration
        .byte   $4D, $04                               ; $7209: note + duration
        .byte   $82                                    ; $720B: loop decrement
        .byte   $5F, $01                               ; $720C: note + duration
        .byte   $88, $02                              ; $720E: set voice $02
        .byte   $96                                    ; $7210: goto/loop
        .byte   <L_71DF, >L_71DF    ;   -> $71DF
L_7213:
        .byte   $90                                    ; $7213: filter cutoff $78
        .byte   $86                                    ; $7214: copy instrument
        .byte   <sfx_instr_7, >sfx_instr_7                      ;   -> sfx_instr_7 ($FA8F)
        .byte   $25, $04                               ; $7217: note + duration
        .byte   $86                                    ; $7219: copy instrument
        .byte   <sfx_instr_12, >sfx_instr_12                      ;   -> sfx_instr_12 ($FB5A)
        .byte   $80, $08                              ; $721C: set param $08
        .byte   $5B, $02                               ; $721E: note + duration
        .byte   $54, $02                               ; $7220: note + duration
        .byte   $56, $02                               ; $7222: note + duration
        .byte   $59, $02                               ; $7224: note + duration
        .byte   $82                                    ; $7226: loop decrement
        .byte   $5B, $02                               ; $7227: note + duration
        .byte   $5F, $02                               ; $7229: note + duration
        .byte   $88, $04                              ; $722B: set voice $04
        .byte   $96                                    ; $722D: goto/loop
        .byte   <L_71DF, >L_71DF    ;   -> $71DF
L_7230:
        .byte   $86                                    ; $7230: copy instrument
        .byte   <sfx_instr_14, >sfx_instr_14                      ;   -> sfx_instr_14 ($FB94)
        .byte   $9A                                    ; $7233: copy 16-byte block
        .byte   <sfx_instr_19, >sfx_instr_19                      ;   -> sfx_instr_19 ($FC38)
        .byte   $8C                                    ; $7236: filter cutoff $F7
        .byte   $8E                                    ; $7237: filter from table
        .byte   $94                                    ; $7238: call subroutine
        .byte   <L_7242, >L_7242    ;   -> $7242
        .byte   $90                                    ; $723B: filter cutoff $78
        .byte   $98                                    ; $723C: return
L_723D:
        .byte   $88, $F4                              ; $723D: set voice $F4
L_723F:
        .byte   $86                                    ; $723F: copy instrument
        .byte   <sfx_instr_15, >sfx_instr_15                      ;   -> sfx_instr_15 ($FBB1)
L_7242:
        .byte   $80, $04                              ; $7242: set param $04
        .byte   $3B, $05                               ; $7244: note + duration
        .byte   $82                                    ; $7246: loop decrement
        .byte   $5F, $01                               ; $7247: note + duration
        .byte   $98                                    ; $7249: return
L_724A:
        .byte   $86                                    ; $724A: copy instrument
        .byte   <sfx_instr_10, >sfx_instr_10                      ;   -> sfx_instr_10 ($FB03)
        .byte   $9A                                    ; $724D: copy 16-byte block
        .byte   <sfx_instr_18, >sfx_instr_18                      ;   -> sfx_instr_18 ($FC28)
        .byte   $8E                                    ; $7250: filter from table
        .byte   $8C                                    ; $7251: filter cutoff $F7
        .byte   $16, $05                               ; $7252: note + duration
        .byte   $5F, $01                               ; $7254: note + duration
        .byte   $16, $01                               ; $7256: note + duration
        .byte   $15, $01                               ; $7258: note + duration
        .byte   $12, $06                               ; $725A: note + duration
        .byte   $13, $02                               ; $725C: note + duration
        .byte   $5F, $05                               ; $725E: note + duration
        .byte   $90                                    ; $7260: filter cutoff $78
        .byte   $98                                    ; $7261: return
L_7262:
        .byte   $86                                    ; $7262: copy instrument
        .byte   <sfx_instr_10, >sfx_instr_10                      ;   -> sfx_instr_10 ($FB03)
        .byte   $96                                    ; $7265: goto/loop
        .byte   <L_726B, >L_726B    ;   -> $726B
L_7268:
        .byte   $86                                    ; $7268: copy instrument
        .byte   <sfx_instr_11, >sfx_instr_11                      ;   -> sfx_instr_11 ($FB20)
L_726B:
        .byte   $16, $05                               ; $726B: note + duration
        .byte   $5F, $01                               ; $726D: note + duration
        .byte   $16, $01                               ; $726F: note + duration
        .byte   $15, $01                               ; $7271: note + duration
        .byte   $12, $06                               ; $7273: note + duration
        .byte   $13, $05                               ; $7275: note + duration
        .byte   $98                                    ; $7277: return
L_7278:
        .byte   $86                                    ; $7278: copy instrument
        .byte   <sfx_instr_12, >sfx_instr_12                      ;   -> sfx_instr_12 ($FB5A)
        .byte   $84                                    ; $727B: copy 14-byte block
        .byte   <sfx_instr_20, >sfx_instr_20                      ;   -> sfx_instr_20 ($FC48)
        .byte   $88, $F4                              ; $727E: set voice $F4
L_7280:
        .byte   $80, $04                              ; $7280: set param $04
        .byte   $44, $04                               ; $7282: note + duration
        .byte   $45, $04                               ; $7284: note + duration
        .byte   $46, $04                               ; $7286: note + duration
        .byte   $47, $04                               ; $7288: note + duration
        .byte   $46, $04                               ; $728A: note + duration
        .byte   $45, $04                               ; $728C: note + duration
        .byte   $82                                    ; $728E: loop decrement
        .byte   $80, $04                              ; $728F: set param $04
        .byte   $42, $04                               ; $7291: note + duration
        .byte   $43, $04                               ; $7293: note + duration
        .byte   $44, $04                               ; $7295: note + duration
        .byte   $45, $04                               ; $7297: note + duration
        .byte   $44, $04                               ; $7299: note + duration
        .byte   $43, $04                               ; $729B: note + duration
        .byte   $82                                    ; $729D: loop decrement
        .byte   $96                                    ; $729E: goto/loop
        .byte   <L_7280, >L_7280    ;   -> $7280
L_72A1:
        .byte   $86                                    ; $72A1: copy instrument
        .byte   <sfx_instr_7, >sfx_instr_7                      ;   -> sfx_instr_7 ($FA8F)
        .byte   $88, $DB                              ; $72A4: set voice $DB
        .byte   $96                                    ; $72A6: goto/loop
        .byte   <L_7280, >L_7280    ;   -> $7280
L_72A9:
        .byte   $86                                    ; $72A9: copy instrument
        .byte   <sfx_instr_10, >sfx_instr_10                      ;   -> sfx_instr_10 ($FB03)
        .byte   $9C                                    ; $72AC: set end markers
        .byte   $9A                                    ; $72AD: copy 16-byte block
        .byte   <sfx_instr_18, >sfx_instr_18                      ;   -> sfx_instr_18 ($FC28)
        .byte   $8E                                    ; $72B0: filter from table
L_72B1:
        .byte   $14, $18                               ; $72B1: note + duration
        .byte   $80, $03                              ; $72B3: set param $03
        .byte   $5F, $18                               ; $72B5: note + duration
        .byte   $82                                    ; $72B7: loop decrement
        .byte   $12, $18                               ; $72B8: note + duration
        .byte   $80, $03                              ; $72BA: set param $03
        .byte   $5F, $18                               ; $72BC: note + duration
        .byte   $82                                    ; $72BE: loop decrement
        .byte   $96                                    ; $72BF: goto/loop
        .byte   <L_72B1, >L_72B1    ;   -> $72B1
L_72C2:
        .byte   $86                                    ; $72C2: copy instrument
        .byte   <sfx_instr_4, >sfx_instr_4                      ;   -> sfx_instr_4 ($FA38)
        .byte   $84                                    ; $72C5: copy 14-byte block
        .byte   <sfx_instr_3, >sfx_instr_3                      ;   -> sfx_instr_3 ($FBEB)
        .byte   $8A, <D_F276                          ; $72C8: set freq ptr -> D_F276
L_72CA:
        .byte   $26, $04                               ; $72CA: note + duration
        .byte   $29, $04                               ; $72CC: note + duration
        .byte   $2D, $04                               ; $72CE: note + duration
        .byte   $2E, $04                               ; $72D0: note + duration
        .byte   $31, $04                               ; $72D2: note + duration
        .byte   $32, $04                               ; $72D4: note + duration
        .byte   $5F, $08                               ; $72D6: note + duration
        .byte   $21, $04                               ; $72D8: note + duration
        .byte   $25, $04                               ; $72DA: note + duration
        .byte   $28, $04                               ; $72DC: note + duration
        .byte   $2B, $04                               ; $72DE: note + duration
        .byte   $2C, $04                               ; $72E0: note + duration
        .byte   $2D, $04                               ; $72E2: note + duration
        .byte   $5F, $08                               ; $72E4: note + duration
        .byte   $96                                    ; $72E6: goto/loop
        .byte   <L_72CA, >L_72CA    ;   -> $72CA
L_72E9:
        .byte   $86                                    ; $72E9: copy instrument
        .byte   <sfx_instr_5, >sfx_instr_5                      ;   -> sfx_instr_5 ($FA55)
L_72EC:
        .byte   $3A, $10                               ; $72EC: note + duration
        .byte   $5F, $10                               ; $72EE: note + duration
        .byte   $39, $10                               ; $72F0: note + duration
        .byte   $5F, $10                               ; $72F2: note + duration
        .byte   $96                                    ; $72F4: goto/loop
        .byte   <L_72EC, >L_72EC    ;   -> $72EC
L_72F7:
        .byte   $86                                    ; $72F7: copy instrument
        .byte   <sfx_instr_10, >sfx_instr_10                      ;   -> sfx_instr_10 ($FB03)
        .byte   $9A                                    ; $72FA: copy 16-byte block
        .byte   <sfx_instr_18, >sfx_instr_18                      ;   -> sfx_instr_18 ($FC28)
        .byte   $8E                                    ; $72FD: filter from table
L_72FE:
        .byte   $16, $20                               ; $72FE: note + duration
        .byte   $15, $20                               ; $7300: note + duration
        .byte   $96                                    ; $7302: goto/loop
        .byte   <L_72FE, >L_72FE    ;   -> $72FE

; ============================================================================
; SECTION 2: Music Command Handlers ($7305-$743F)
; ============================================================================
; Music command dispatch handlers. The "music_track_pointers" table points
; to these handlers. When the sound engine encounters special music commands,
; it uses jmp (D_F256) to dispatch to the appropriate handler routine.
; ============================================================================

; --- Handler 0 ($7305) - Set music parameter and update ---
music_handler_00:
        lda     ($85),y                 ; b1 85        $7305
        ldy     $82,x                   ; b4 82        $7307
        sta     D_F292,y                ; 99 92 f2     $7309
        lda     #$02                    ; a9 02        $730c
        jsr     music_add_offset        ; 20 20 74     $730e
        jsr     music_save_pointer      ; 20 05 74     $7311
        jmp     D_F56F                  ; 4c 6f f5     $7314

; --- Handler 1 ($7317) - Decrement and loop control ---
music_handler_01:
        dec     $82,x                   ; d6 82        $7317
        ldy     $82,x                   ; b4 82        $7319
        lda     D_F292,y                ; b9 92 f2     $731b
        sec                             ; 38           $731e
        sbc     #$01                    ; e9 01        $731f
        sta     D_F292,y                ; 99 92 f2     $7321
        beq     @continue               ; f0 08        $7324
        jsr     music_restore_pointer   ; 20 d0 73     $7326
        inc     $82,x                   ; f6 82        $7329
        lda     #$00                    ; a9 00        $732b
        .byte   $2C                     ; BIT trick    $732d
@continue:
        lda     #$01                    ; a9 01        $732e
        jmp     D_F56C                  ; 4c 6c f5     $7330

; --- Handler 2 ($7333) - Load timing value (0D) ---
music_handler_02:
        lda     #$0D                    ; a9 0d        $7333
        .byte   $2C                     ; BIT trick    $7335

; --- Handler 3 ($7336) - Load timing value (1C) and copy data ---
music_handler_03:
        lda     #$1C                    ; a9 1c        $7336
        pha                             ; 48           $7338
        lda     ($85),y                 ; b1 85        $7339
        sta     $78                     ; 85 78        $733b
        iny                             ; c8           $733d
        lda     ($85),y                 ; b1 85        $733e
        sta     $79                     ; 85 79        $7340
        lda     D_7357,x                ; bd 57 73     $7342
        sta     @copy_target+1          ; 8d 4d 73     $7345
        pla                             ; 68           $7348
        tay                             ; a8           $7349
@copy_loop:
        lda     ($78),y                 ; b1 78        $734a
@copy_target:
        sta     D_F2AE,y                ; 99 ae f2     $734c (self-modified high byte)
        dey                             ; 88           $734f
        bpl     @copy_loop              ; 10 f8        $7350
        lda     #$03                    ; a9 03        $7352
        jmp     D_F56C                  ; 4c 6c f5     $7354

; --- Voice parameter block low-byte tables ($7357-$735C) ---
D_7357:
        .byte   <D_F2AE, <voice1_src_block, <voice2_src_block
D_735A:
        .byte   <D_F31B, <voice1_dst_block, <voice2_dst_block

; --- Handler 4 ($735D) - Set voice parameter ---
music_handler_04:
        lda     ($85),y                 ; b1 85        $735d
        sta     $87,x                   ; 95 87        $735f
        lda     #$02                    ; a9 02        $7361
        jmp     D_F56C                  ; 4c 6c f5     $7363

; --- Handler 5 ($7366) - Set frequency pointers ---
music_handler_05:
        lda     ($85),y                 ; b1 85        $7366
        ldy     D_742D,x                ; bc 2d 74     $7368
        sta     D_F2B6,y                ; 99 b6 f2     $736b
        lda     #>D_F276                ; a9 f2        $736e (high byte of timing data)
        sta     D_F2B7,y                ; 99 b7 f2     $7370
        lda     #$02                    ; a9 02        $7373
        jmp     D_F56C                  ; 4c 6c f5     $7375

; --- Handler 6 ($7378) - Set filter cutoff (F7) ---
music_handler_06:
        ldy     #$F7                    ; a0 f7        $7378
        bne     filter_set_sid          ; d0 06        $737a

; --- Handler 7 ($737C) - Set filter cutoff (from table) ---
music_handler_07:
        ldy     D_742A,x                ; bc 2a 74     $737c
        txa                             ; 8a           $737f
filter_store_accumulator:
        sta     $91                     ; 85 91        $7380
filter_set_sid:
        sty     $D417                   ; 8c 17 d4     $7382 - SID Filter Cutoff Hi
        jmp     D_F56A                  ; 4c 6a f5     $7385

; --- Handler 8 ($7388) - Set filter cutoff (78) with mode 3 ---
music_handler_08:
        ldy     #$78                    ; a0 78        $7388
        lda     #$03                    ; a9 03        $738a
        bne     filter_store_accumulator ; d0 f2       $738c

; --- Handler 9 ($738E) - Multi-step voice parameter update ---
music_handler_09:
        lda     ($85),y                 ; b1 85        $738e
        sta     $87,x                   ; 95 87        $7390
        iny                             ; c8           $7392
        lda     #$04                    ; a9 04        $7393
        .byte   $2C                     ; BIT trick    $7395

; --- Handler 10 ($7396) - Complex pointer and data update ---
music_handler_10:
        lda     #$03                    ; a9 03        $7396
        sty     @restore_y+1            ; 8c b0 73     $7398
        tay                             ; a8           $739b
        lda     $85                     ; a5 85        $739c
        pha                             ; 48           $739e
        lda     $86                     ; a5 86        $739f
        pha                             ; 48           $73a1
        tya                             ; 98           $73a2
        jsr     music_add_offset        ; 20 20 74     $73a3
        jsr     music_save_pointer      ; 20 05 74     $73a6
        pla                             ; 68           $73a9
        sta     $86                     ; 85 86        $73aa
        pla                             ; 68           $73ac
        sta     $85                     ; 85 85        $73ad
@restore_y:
        ldy     #$01                    ; a0 01        $73af (self-modified)
        jsr     music_load_pointer      ; 20 14 74     $73b1
        jmp     D_F56F                  ; 4c 6f f5     $73b4

; --- Handler 11 ($73B7) - Update pointers and continue ---
music_handler_11:
        jsr     music_load_pointer      ; 20 14 74     $73b7
        jmp     D_F56F                  ; 4c 6f f5     $73ba

; --- Handler 12 ($73BD) - Loop counter check and control ---
music_handler_12:
        lda     $82,x                   ; b5 82        $73bd
        cmp     D_7433,x                ; dd 33 74     $73bf
        bne     @not_done               ; d0 04        $73c2
        dec     D_F308,x                ; de 08 f3     $73c4
        rts                             ; 60           $73c7
@not_done:
        dec     $82,x                   ; d6 82        $73c8
        jsr     music_restore_pointer   ; 20 d0 73     $73ca
        jmp     D_F56F                  ; 4c 6f f5     $73cd

; --- Helper: music_restore_pointer ($73D0) ---
music_restore_pointer:
        ldy     $82,x                   ; b4 82        $73d0
        lda     D_F28A,y                ; b9 8a f2     $73d2
        sta     $85                     ; 85 85        $73d5
        lda     D_F28E,y                ; b9 8e f2     $73d7
        sta     $86                     ; 85 86        $73da
        rts                             ; 60           $73dc

; --- Handler 13 ($73DD) - Copy 16-byte block to sound registers ---
music_handler_13:
        lda     ($85),y                 ; b1 85        $73dd
        sta     $78                     ; 85 78        $73df
        iny                             ; c8           $73e1
        lda     ($85),y                 ; b1 85        $73e2
        sta     $79                     ; 85 79        $73e4
        ldy     #$0F                    ; a0 0f        $73e6
@copy_loop:
        lda     ($78),y                 ; b1 78        $73e8
        sta     D_F30B,y                ; 99 0b f3     $73ea
        dey                             ; 88           $73ed
        bpl     @copy_loop              ; 10 f8        $73ee
        lda     #$03                    ; a9 03        $73f0
        jmp     D_F56C                  ; 4c 6c f5     $73f2

; --- Handler 14 ($73F5) - Set sound effect end markers ---
music_handler_14:
        ldy     D_742D,x                ; bc 2d 74     $73f5
        lda     #$FF                    ; a9 ff        $73f8
        sta     D_F2C8,y                ; 99 c8 f2     $73fa
        lda     #$FE                    ; a9 fe        $73fd
        sta     D_F2CA,y                ; 99 ca f2     $73ff
        jmp     D_F56A                  ; 4c 6a f5     $7402

; --- Helper: music_save_pointer ($7405) ---
music_save_pointer:
        ldy     $82,x                   ; b4 82        $7405
        lda     $85                     ; a5 85        $7407
        sta     D_F28A,y                ; 99 8a f2     $7409
        lda     $86                     ; a5 86        $740c
        sta     D_F28E,y                ; 99 8e f2     $740e
        inc     $82,x                   ; f6 82        $7411
        rts                             ; 60           $7413

; --- Helper: music_load_pointer ($7414) ---
music_load_pointer:
        lda     ($85),y                 ; b1 85        $7414
        pha                             ; 48           $7416
        iny                             ; c8           $7417
        lda     ($85),y                 ; b1 85        $7418
        sta     $86                     ; 85 86        $741a
        pla                             ; 68           $741c
        sta     $85                     ; 85 85        $741d
        rts                             ; 60           $741f

; --- Helper: music_add_offset ($7420) ---
music_add_offset:
        clc                             ; 18           $7420
        adc     $85                     ; 65 85        $7421
        sta     $85                     ; 85 85        $7423
        bcc     @done                   ; 90 02        $7425
        inc     $86                     ; e6 86        $7427
@done:
        rts                             ; 60           $7429

; --- DATA TABLES ($742A-$743F) ---

D_742A:
        .byte   $F1, $F2, $F4           ; f1 f2 f4     $742a
D_742D:
        .byte   $00, $1D, $3A           ; 00 1d 3a     $742d
D_7430:
        .byte   $00, $23, $46           ; 00 23 46     $7430
D_7433:
        .byte   $00, $0C, $18           ; 00 0c 18     $7433
D_7436:
        .byte   $00                     ; 00           $7436
D_7437:
        .byte   $07, $0E, $15           ; 07 0e 15     $7437
        .byte   $00, $00, $00           ; 00 00 00     $743a
        .byte   $00, $00, $08           ; 00 00 08     $743d
musichandlers_end:                      ; End of SOUND_LO ($7440)

; ============================================================================
; SECTION 3: Title Screen Music ($8B00-$8DDF)
; ============================================================================
; Three-voice music data played by the SFX engine during the title screen.
; Voice start addresses (from sfx_index_table group 7 at $F953):
;   Voice 0: $8B00 (title_music_voice0)
;   Voice 1: $8BDC (title_music_voice1)
;   Voice 2: $8CBF (title_music_voice2)
;
; NOTE: All embedded address operands use label references for relocatability.
; $86/$84 instrument loads reference sfx_instr_* (SOUND_HI) or title_sfx_data_*
; (inline SCREEN_BUFFER). $92/$94 calls reference L_7040/L_7048 (SOUND_LO) or
; title_voice2_pattern_* (inline SCREEN_BUFFER).
; ============================================================================

        .segment "TMP_SCREEN_BACKUP"

; --- Voice 0: Title screen music ($8B00) ---
title_music_voice0:
; Voice 0 ($8B00)
        .byte   $86                     ; $8B00: LOAD_INSTR_29B
        .byte   <sfx_instr_12           ; $8B01: -> sfx_instr_12 (lo)
        .byte   >sfx_instr_12           ; $8B02: -> sfx_instr_12 (hi)
        .byte   $60
        .byte   $02, $4e, $04, $49, $04, $44, $04, $49, $04, $44, $04, $3f, $04, $44, $04  ; $8B03
        .byte   $3f, $04, $3a, $04, $3f, $04, $3a, $04, $36, $04, $86  ; $8B13
        .byte   <title_sfx_data_0, >title_sfx_data_0   ; $8B1E: $86 cmd -> title_sfx_data_0
        .byte   $80, $08, $5f  ; $8B21
        .byte   $10, $82, $80, $04, $35, $18, $35, $04, $34, $20, $5f, $04, $82, $86  ; $8B23
        .byte   <sfx_instr_2, >sfx_instr_2
                                        ; $8B31: $86 cmd -> sfx_instr_2
        .byte   $8a, <D_F279, $80, $02, $80, $20, $30, $04, $82, $82, $80, $08, $35, $04, $82, $8a  ; $8B33
        .byte   <D_F27C, $80, $08, $32, $04, $82, $8a, <D_F279, $80, $08, $37, $04, $82, $80, $08, $30  ; $8B43
        .byte   $04, $82, $80, $08, $35, $04, $82, $8a, <D_F27C, $80, $06, $32, $04, $82, $34, $04  ; $8B53
        .byte   $34, $04, $8a, <D_F283, $32, $04, $32, $04, $8a, <D_F27C, $34, $04, $34, $04, $8a, <D_F279  ; $8B63
        .byte   $35, $04, $35, $04, $36, $04, $36, $04, $80, $08, $37, $04, $82, $80, $10, $30  ; $8B73
        .byte   $04, $82, $35, $04, $35, $04, $35, $04, $35, $04, $37, $04, $37, $04, $37, $04  ; $8B83
        .byte   $37, $04, $8a, <D_F27C, $80, $08, $34, $04, $82, $8a, <D_F279, $80, $10, $30, $04, $82  ; $8B93
        .byte   $35, $04, $35, $04, $35, $04, $35, $04, $37, $04, $37, $04, $37, $04, $37, $04  ; $8BA3
        .byte   $8a, <D_F27C, $34, $04, $34, $04, $39, $04, $39, $04, $8a, <D_F279, $37, $04, $37, $04  ; $8BB3
        .byte   $37, $04, $37, $04, $30, $04, $5f, $1c, $5f, $20, $86  ; $8BC3
        .byte   <title_sfx_data_0, >title_sfx_data_0   ; $8BCE: $86 cmd -> title_sfx_data_0
        .byte   $80, $03, $35  ; $8BD1
        .byte   $18, $35, $04, $34, $20, $5f, $04, $82, $98  ; $8BD3

; --- Voice 1: Title screen music ($8BDC) ---
title_music_voice1:
; Voice 1 ($8BDC)
        .byte   $60, $02, $86  ; $8BDC
        .byte   <sfx_instr_12, >sfx_instr_12
                                        ; $8BDF: $86 cmd -> sfx_instr_12
        .byte   $5f, $02, $4b, $04, $46, $04, $42, $04, $46, $04, $42, $04, $3d, $04, $42, $04  ; $8BE1
        .byte   $3d, $04, $38, $04, $3d, $04, $38, $04, $33, $02, $86  ; $8BF1
        .byte   <title_sfx_data_0, >title_sfx_data_0   ; $8BFC: $86 cmd -> title_sfx_data_0
        .byte   $84  ; $8BFF
        .byte   <sfx_instr_21           ; $8BFF: $84 cmd -> sfx_instr_21 (lo)
        .byte   >sfx_instr_21           ; $8C00: -> sfx_instr_21 (hi)
        .byte   $80, $08, $5f, $10, $82, $80, $04, $3c, $18, $3c, $04, $3c, $20, $5f, $04, $82  ; $8C01
        .byte   $84                             ; $8C11
        .byte   <title_sfx_data_0, >title_sfx_data_0   ; $8C12: $84 cmd -> title_sfx_data_0
        .byte   $80, $02, $34, $10, $34, $04, $35, $04, $37, $04, $3c, $0c, $37  ; $8C14
        .byte   $08, $35, $08, $37, $04, $34, $1c, $86  ; $8C21
        .byte   <sfx_instr_1, >sfx_instr_1
                                        ; $8C29: $86 cmd -> sfx_instr_1
        .byte   $84  ; $8C2B
        .byte   <sfx_instr_22, >sfx_instr_22
                                        ; $8C2C: $84 cmd -> sfx_instr_22
        .byte   $3c, $04, $3c, $08, $3c, $04, $8a, <D_F26C, $3c, $08, $8a, <D_F273, $3c, $04, $8a, <D_F26C  ; $8C2E
        .byte   $3c, $0c, $86                   ; $8C3E
        .byte   <title_sfx_data_0, >title_sfx_data_0   ; $8C41: $86 cmd -> title_sfx_data_0
        .byte   $82, $39, $10, $34, $04, $35, $04, $37, $04, $35, $10  ; $8C44
        .byte   $5f, $14, $37, $10, $32, $04, $34, $04, $35, $04, $34, $10, $5f, $14, $39, $10  ; $8C4E
        .byte   $34, $04, $35, $04, $37, $04, $35, $10, $5f, $0c, $34, $08, $32, $08, $34, $08  ; $8C5E
        .byte   $35, $08, $36, $08, $37, $14, $37, $04, $39, $04, $80, $02, $3c, $08, $3c, $04  ; $8C6E
        .byte   $3b, $08, $39, $04, $3b, $08, $82, $5f, $04, $35, $10, $37, $0c, $34, $18, $37  ; $8C7E
        .byte   $04, $39, $04, $80, $02, $3c, $08, $3c, $04, $3b, $08, $39, $04, $3b  ; $8C8E
        .byte   $08, $82                ; $8C9C
        .byte   $5f, $04, $35, $10, $37, $0c, $34, $0c, $39, $08, $3b  ; $8C9E
        .byte   $08, $37, $08, $3c, $20 ; $8CA9
        .byte   $5f, $20, $84  ; $8CAE
        .byte   <sfx_instr_21, >sfx_instr_21
                                        ; $8CB1: $84 cmd -> sfx_instr_21
        .byte   $80, $03, $3c, $18, $3c, $04, $3c, $20, $5f, $04, $82, $98  ; $8CB3

; --- Voice 2: Title screen music ($8CBF) ---
title_music_voice2:
; Voice 2 ($8CBF)
        .byte   $60, $01, $90, $86  ; $8CBF
        .byte   <sfx_instr_12, >sfx_instr_12
                                        ; $8CC3: $86 cmd -> sfx_instr_12
        .byte   $60, $01, $5a, $02, $57, $02, $55, $02, $54, $02, $50, $02, $4e, $02, $55, $02  ; $8CC5
        .byte   $54, $02, $50, $02, $4e, $02, $4b, $02, $49  ; $8CD5

; --- Voice 2 continued: Note sequence ($8CDE) ---
        .byte   $02, $50, $02, $4e, $02, $4b, $02, $49, $02, $46, $02, $44, $02, $4b  ; $8CDE
        .byte   $02, $49                ; $8CEC
        .byte   $02, $46, $02, $44, $02, $42, $02, $3f, $02, $94, <L_7048, >L_7048, $80, $17, $18, $04  ; $8CEE
        .byte   $18, $04                ; $8CFE
        .byte   $18, $04, $18, $04, $82, $18, $04, $18, $04, $94, <L_7040, >L_7040, $1f, $04  ; $8D00
        .byte   $21, $04                        ; $8D0E
        .byte   $80, $08                        ; $8D10: SET_PARAM $08
        .byte   $92, $00                        ; $8D12: CALL_TRANSPOSE $00
        .byte   <title_voice2_pattern_long, >title_voice2_pattern_long  ; -> title_voice2_pattern_long
        .byte   $82                             ; $8D16: DEC_LOOP
        .byte   $92, $05                        ; $8D17: CALL_TRANSPOSE $05
        .byte   <title_voice2_pattern_long, >title_voice2_pattern_long
        .byte   $92, $02                        ; $8D1B: CALL_TRANSPOSE $02
        .byte   <title_voice2_pattern_long, >title_voice2_pattern_long
        .byte   $92, $04                        ; $8D1F: CALL_TRANSPOSE $04
        .byte   <title_voice2_pattern_long, >title_voice2_pattern_long
        .byte   $92, $00                        ; $8D23: CALL_TRANSPOSE $00
        .byte   <title_voice2_pattern_long, >title_voice2_pattern_long
        .byte   $92, $05                        ; $8D27: CALL_TRANSPOSE $05
        .byte   <title_voice2_pattern_long, >title_voice2_pattern_long
        .byte   $92, $02                        ; $8D2B: CALL_TRANSPOSE $02
        .byte   <title_voice2_pattern_long, >title_voice2_pattern_long
        .byte   $88, $00                        ; $8D2F: SET_VOICE_PARAM $00
        .byte   $1a, $04, $26, $04, $1c, $04, $28, $04  ; $8D31: melody
        .byte   $1d, $04, $29, $04, $1e, $04, $2a, $04  ; $8D39
        .byte   $92, $07                        ; $8D41: CALL_TRANSPOSE $07
        .byte   <title_voice2_pattern_long, >title_voice2_pattern_long
        .byte   $80, $02                        ; $8D45: SET_PARAM $02
        .byte   $92, $00                        ; $8D47: CALL_TRANSPOSE $00
        .byte   <title_voice2_pattern_long, >title_voice2_pattern_long
        .byte   $82                             ; $8D4B: DEC_LOOP
        .byte   $92, $05                        ; $8D4C: CALL_TRANSPOSE $05
        .byte   <title_voice2_pattern_short, >title_voice2_pattern_short
        .byte   $92, $07                        ; $8D50: CALL_TRANSPOSE $07
        .byte   <title_voice2_pattern_short, >title_voice2_pattern_short
        .byte   $92, $04                        ; $8D54: CALL_TRANSPOSE $04
        .byte   <title_voice2_pattern_long, >title_voice2_pattern_long
        .byte   $80, $02                        ; $8D58: SET_PARAM $02
        .byte   $92, $00                        ; $8D5A: CALL_TRANSPOSE $00
        .byte   <title_voice2_pattern_long, >title_voice2_pattern_long
        .byte   $82                             ; $8D5E: DEC_LOOP
        .byte   $92, $05                        ; $8D5F: CALL_TRANSPOSE $05
        .byte   <title_voice2_pattern_short, >title_voice2_pattern_short
        .byte   $92, $07                        ; $8D63: CALL_TRANSPOSE $07
        .byte   <title_voice2_pattern_short, >title_voice2_pattern_short
        .byte   $88, $00                        ; $8D67: SET_VOICE_PARAM $00
        .byte   $1c, $08, $21, $08, $23, $08, $1f, $08  ; $8D69: melody
        .byte   $94, <L_7048, >L_7048           ; $8D71: CALL L_7048
        .byte   $80, $0c                        ; $8D74: SET_PARAM $0C
        .byte   $18, $04, $18, $04, $18, $04, $18, $04  ; $8D76: rhythm
        .byte   $82                             ; $8D7E: DEC_LOOP
        .byte   $94, <L_7040, >L_7040           ; $8D7F: CALL L_7040
        .byte   $18, $10, $21, $04, $1f, $04, $21, $04, $18, $0c  ; $8D82: melody
        .byte   $98                             ; $8D8C: RETURN
; --- Voice 2 sub-pattern: long variant ($8D8D) ---
; Called via $92 (CALL_TRANSPOSE) from the main voice 2 sequence.
; Plays a full pattern then falls through into title_voice2_pattern_short.
title_voice2_pattern_long:
        .byte   $18, $08                        ; $8D8D: note $18, dur $08
        .byte   $86                             ; $8D8F: LOAD_INSTR_29B
        .byte   <title_sfx_data_1, >title_sfx_data_1   ; -> title_sfx_data_1
        .byte   $90                             ; $8D92: SET_FILTER
        .byte   $38, $04                        ; $8D93: note $38, dur $04
        .byte   $94, <L_7040, >L_7040           ; $8D95: CALL L_7040
        .byte   $18, $04                        ; $8D98: note $18, dur $04
; --- Voice 2 sub-pattern: short variant ($8D9A) ---
; Entry point for the shorter version (skips the first iteration above).
title_voice2_pattern_short:
        .byte   $18, $08                        ; $8D9A: note $18, dur $08
        .byte   $86                             ; $8D9C: LOAD_INSTR_29B
        .byte   <title_sfx_data_1, >title_sfx_data_1   ; -> title_sfx_data_1
        .byte   $90                             ; $8D9F: SET_FILTER
        .byte   $38, $04                        ; $8DA0: note $38, dur $04
        .byte   $94, <L_7040, >L_7040           ; $8DA2: CALL L_7040
        .byte   $18, $04                        ; $8DA5: note $18, dur $04
        .byte   $98                             ; $8DA7: RETURN

; --- Title screen music: SFX parameter data ($8DA8) ---
; 29-byte instrument block loaded by $86 cmd, 14-byte block loaded by $84 cmd.
title_sfx_data_0:
        .byte   $23, $00, $dd, $ff, $23, $00, $00, $00, $02, $04, $02, $00, $02, $05, $3c, $3c  ; $8DA8
        .byte   $00, $05, $20, $00, $e0, $ff, $00, $01, $41, $07, $cc, $1e, $5a                 ; $8DB8
title_sfx_data_1:
        .byte   $a0, $0f, $c0  ; $8DC5
        .byte   $e0, $40, $1f, $60, $f0, $02, $02, $02, $02, $01, $05, $00, $00, $00, $00, $00  ; $8DCC
        .byte   $00, $00, $00, $00, $00, $81, $06, $f9  ; $8DD8
screen_buffer_end:                      ; End of SCREEN_BUFFER ($8DE0)

; ============================================================================
; SECTION 4: Command Handler Pointer Table ($F240-$F261)
; ============================================================================
; 17 pointers to music command handler routines in the $73xx range.
; Must be aligned so low byte bits 1-3 are zero for EOR dispatch.
; ============================================================================

.segment "SOUND_HI"

music_track_pointers:               ; Historical name - actually command handlers
        .word   music_handler_00    ; $F240: Handler 0 - Set music parameter
        .word   music_handler_01    ; $F242: Handler 1 - Decrement and loop
        .word   music_handler_02    ; $F244: Handler 2 - Load timing (0D)
        .word   music_handler_03    ; $F246: Handler 3 - Load timing (1C)
        .word   music_handler_04    ; $F248: Handler 4 - Set voice parameter
        .word   music_handler_05    ; $F24A: Handler 5 - Set frequency pointers
        .word   music_handler_06    ; $F24C: Handler 6 - Set filter (F7)
        .word   music_handler_07    ; $F24E: Handler 7 - Set filter (table)
        .word   music_handler_08    ; $F250: Handler 8 - Set filter (78)
        .word   music_handler_09    ; $F252: Handler 9 - Multi-step update
        .word   music_handler_10    ; $F254: Handler 10 - Complex pointer update
D_F256:                             ; Used by jmp (D_F256) at $F57B
        .word   music_handler_11    ; $F256: Handler 11 - Update pointers
        .word   music_handler_12    ; $F258: Handler 12 - Loop counter check
        .word   music_handler_13    ; $F25A: Handler 13 - Copy 16-byte block
        .word   music_handler_14    ; $F25C: Handler 14 - Set SFX end markers
D_F25E:                             ; Referenced as embedded pointer in sfx_instr_21
        .word   $0007               ; $F25E: Handler 15 - Invalid/placeholder
        .byte   $07                 ; $F260: Handler 16 low byte
D_F261:                             ; Referenced by $8A cmd in credits music voice 1
        .byte   $00                 ; $F261: Handler 16 high byte

; ============================================================================
; SECTION 5: Music Timing & Control Data ($F262-$F2AD)
; ============================================================================
; Frequency pointer target table and music state storage.
; ============================================================================

; --- Music timing data ($F262-$F289) ---
music_timing_data:
        .byte   $03, $08, $03      ; $F262
D_F265:                             ; Referenced by $8A cmd in credits music
        .byte   $0C, $03, $08      ; $F265
D_F268:                             ; Referenced by $8A cmd in credits music
        .byte   $00, $05           ; $F268
        .byte   $09, $05           ; $F26A
D_F26C:                             ; Referenced by $8A cmd in title music voice 1
        .byte   $0C, $04, $07      ; $F26C
D_F26F:                             ; Referenced by $8A cmd in credits music
        .byte   $00, $08, $03      ; $F26F
        .byte   $06                ; $F272
D_F273:                             ; Referenced by $8A cmd in title music voice 1
        .byte   $0C, $02, $07      ; $F273
D_F276:                             ; Referenced as embedded pointer in voice parameter blocks
        .byte   $00, $0C, $00      ; $F276
D_F279:                             ; Referenced by $8A cmd in title/credits music
        .byte   $0C                ; $F279
        .byte   $04, $07           ; $F27A
D_F27C:                             ; Referenced by $8A cmd in title music voice 0
        .byte   $0C, $03, $07      ; $F27C
D_F27F:                             ; Referenced as embedded pointer in sfx_instr_3
        .byte   $0C, $18, $0C      ; $F27F
        .byte   $18                ; $F282
D_F283:                             ; Referenced by $8A cmd in title music voice 0
        .byte   $0A, $04, $07      ; $F283
D_F286:                             ; Referenced as embedded pointer in sfx_instr_22
        .byte   $0C, $05, $07, $00 ; $F286

; --- Music control parameters ($F28A-$F2AD) ---
music_control_data:
D_F28A:                             ; Music pointer save slots (low bytes)
        .byte   $D8, $39, $00, $00
D_F28E:                             ; Music pointer save slots (high bytes)
        .byte   $71, $8B, $00, $00
D_F292:                             ; Music parameter storage
        .byte   $00, $00, $00, $00, $07, $10, $47, $00  ; $F292
        .byte   $72, $71, $71, $00, $00, $00, $00, $00  ; $F29A
        .byte   $1E, $98, $98, $00, $72, $71, $8D, $00  ; $F2A2
        .byte   $00, $01, $01, $00                      ; $F2AA
music_control_data_end:                 ; End of music control data ($F2AE)

; ============================================================================
; SECTION 6: Voice Parameter Blocks ($F2AE-$F39B)
; ============================================================================
; Voice parameter blocks using Y-indexed addressing with offsets $00/$1D/$3A.
; All data MUST remain contiguous from $F2AE through $F39B.
; ============================================================================

; --- Sound effect index table ($F2AE-$F2C3) ---
D_F2AE:
sound_effect_table:
        .byte   $00, $00, $00, $00, $01, $00, $03, $00  ; $F2AE-$F2B5 (8 bytes)
D_F2B6:                             ; $F2B6 - Frequency pointer low byte (into timing data)
        .byte   <D_F276                                 ; $F2B6
D_F2B7:                             ; $F2B7 - Frequency pointer high byte (into timing data)
        .byte   >D_F276                                 ; $F2B7
        .byte   $00, $03                                ; $F2B8-$F2B9
        .byte   $00                                     ; $F2BA
D_F2BB:                             ; $F2BB
        .byte   $08                                     ; $F2BB
        .byte   $08                                     ; $F2BC
        .byte   $08                                     ; $F2BD
        .byte   $06                                     ; $F2BE
D_F2BF:                             ; $F2BF
        .byte   $05, $80, $FF, $40, $00                 ; $F2BF-$F2C3

D_F2C4:
    .byte $00                   ; $F2C4
D_F2C5:
    .byte $08                   ; $F2C5
D_F2C6:
    .byte $41                   ; $F2C6
D_F2C7:
    .byte $08                   ; $F2C7
D_F2C8:
    .byte $7B                   ; $F2C8
D_F2C9:
    .byte $03                   ; $F2C9
D_F2CA:
    .byte $32                   ; $F2CA
; Voice 1 source block (24 bytes from $F2CB)
voice1_src_block:
    .byte $1E, $00, $E2         ; $F2CB-$F2CD
    .byte $FF, $1E, $00         ; $F2CE-$F2D0
    .byte $00                   ; $F2D1
    .byte $00, $04              ; $F2D2-$F2D3
    .byte $08                   ; $F2D4
    .byte $04, $00              ; $F2D5-$F2D6
    .byte $10, $05              ; $F2D7-$F2D8
    .byte $00                   ; $F2D9
    .byte $00, $00, $00, $00    ; $F2DA-$F2DD

L_F2DE:
    .byte $00, $00, $00, $00, $00           ; $F2DE-$F2E2
    .byte $29, $D7, $8D, $14                ; $F2E3-$F2E6
    .byte $64                               ; $F2E7
; Voice 2 source block (24 bytes from $F2E8)
voice2_src_block:
    .byte $F4, $FF, $0C                     ; $F2E8-$F2EA
    .byte $00, $F4, $FF, $00                ; $F2EB-$F2EE
    .byte $00, $02, $04, $02, $00           ; $F2EF-$F2F3
    .byte $08                               ; $F2F4
    .byte $05, $08                          ; $F2F5-$F2F6
    .byte $08, $00                          ; $F2F7-$F2F8
    .byte $05, $E0, $FF                     ; $F2F9-$F2FB
    .byte $20, $00, $80                     ; $F2FC-$F2FE
    .byte $0C, $49, $09                     ; $F2FF-$F301
    .byte $F7, $03                          ; $F302-$F303
    .byte $5A                               ; $F304

D_F305:
    .byte $01                   ; $F305
D_F306:
    .byte $01                   ; $F306
D_F307:
    .byte $01                   ; $F307
D_F308:
    .byte $01                   ; $F308
D_F309:
    .byte $01                   ; $F309
D_F30A:
    .byte $01                   ; $F30A

D_F30B:
    .byte $D8                   ; $F30B
    .byte $FF, $00, $00         ; $F30C-$F30E
    .byte $00                   ; $F30F
    .byte $00, $00, $00, $08    ; $F310-$F313
    .byte $00, $00, $00, $06    ; $F314-$F317
    .byte $04, $0E, $06         ; $F318-$F31A

D_F31B:
    .byte $00                   ; $F31B
D_F31C:
    .byte $00                   ; $F31C
D_F31D:
    .byte $00                   ; $F31D
D_F31E:
    .byte $00                   ; $F31E
D_F31F:
    .byte $01                   ; $F31F
D_F320:
    .byte $00                   ; $F320
D_F321:
    .byte $03                   ; $F321
D_F322:
    .byte $00                   ; $F322

D_F323:
        .byte   <D_F276               ; $F323
D_F324:
        .byte   >D_F276               ; $F324
D_F325:
    .byte $2D                   ; $F325
D_F326:
    .byte $03                   ; $F326
D_F327:
    .byte $01                   ; $F327
D_F328:
    .byte $08                   ; $F328
D_F329:
    .byte $08                   ; $F329
D_F32A:
    .byte $08                   ; $F32A
D_F32B:
    .byte $00                   ; $F32B
D_F32C:
    .byte $05                   ; $F32C
D_F32D:
    .byte $80                   ; $F32D
D_F32E:
    .byte $FF                   ; $F32E
D_F32F:
    .byte $40                   ; $F32F
D_F330:
    .byte $00                   ; $F330
D_F331:
    .byte $00                   ; $F331
D_F332:
    .byte $08                   ; $F332

D_F333:
    .byte $B0                   ; $F333
D_F334:
    .byte $0E                   ; $F334
D_F335:
    .byte $41                   ; $F335
D_F336:
    .byte $00                   ; $F336
D_F337:
    .byte $20                   ; $F337
D_F338:
    .byte $00                   ; $F338
D_F339:
    .byte $03                   ; $F339
D_F33A:
    .byte $03                   ; $F33A
D_F33B:
    .byte $00                   ; $F33B
D_F33C:
    .byte $00                   ; $F33C
D_F33D:
    .byte $01                   ; $F33D
; Voice 1 destination block (24 bytes from $F33E)
voice1_dst_block:
    .byte $1E, $00, $E2, $FF, $1E ; $F33E-$F342

L_F343:
    .byte $00                   ; $F343
    .byte $00, $00, $04         ; $F344-$F346
    .byte $08                   ; $F347
    .byte $04, $00              ; $F348-$F349
    .byte $00                   ; $F34A
    .byte $05, $00, $00, $00    ; $F34B-$F34E
    .byte $00, $00, $00, $00    ; $F34F-$F352
    .byte $00, $00, $00, $5F    ; $F353-$F356
    .byte $1D, $20, $00         ; $F357-$F359

D_F35A:
    .byte $29, $00, $03, $04    ; $F35A-$F35D
    .byte $00, $00, $00         ; $F35E-$F360
; Voice 2 destination block (24 bytes from $F361)
voice2_dst_block:
    .byte $F4                   ; $F361
    .byte $FF, $0C, $00, $F4    ; $F362-$F365
    .byte $FF, $00, $00, $02    ; $F366-$F369
    .byte $04, $02, $00, $00, $05 ; $F36A-$F36E
    .byte $08                   ; $F36F
    .byte $08                   ; $F370
    .byte $00                   ; $F371
    .byte $05, $E0, $FF         ; $F372-$F374
    .byte $20, $00, $80         ; $F375-$F377
    .byte $0C, $AD, $03         ; $F378-$F37A
    .byte $49, $03              ; $F37B-$F37C

D_F37D:
    .byte $5A                   ; $F37D
    .byte $01, $04              ; $F37E-$F37F
    .byte $02                   ; $F380
    .byte $00, $00, $07         ; $F381-$F383

D_F384:
    .byte $D8, $FF, $00, $00    ; $F384-$F387
    .byte $00, $00, $00, $00    ; $F388-$F38B

D_F38C:
    .byte $08                   ; $F38C
D_F38D:
    .byte $00                   ; $F38D
D_F38E:
    .byte $00                   ; $F38E
D_F38F:
    .byte $00                   ; $F38F
    .byte $06                   ; $F390
D_F391:
    .byte $04                   ; $F391
D_F392:
    .byte $0E                   ; $F392
D_F393:
    .byte $06                   ; $F393
D_F394:
    .byte $0E                   ; $F394
D_F395:
    .byte $06                   ; $F395
D_F396:
    .byte $08                   ; $F396
D_F397:
    .byte $00                   ; $F397
D_F398:
    .byte $00                   ; $F398
D_F399:
    .byte $00                   ; $F399

; ============================================================================
; SECTION 7: Frequency Tables & Init ($F39A-$F4BC)
; ============================================================================
; Note offset table, frequency tables, and music initialization code.
; ============================================================================

; --- Multiplication-by-5 lookup table ($F39A-$F3B8) ---
D_F39A:
        .byte   $05, $0A
note_offset_table:
        .byte   $0F, $14, $19, $1E, $23, $28, $2D, $32
        .byte   $37, $3C, $41, $46, $4B, $50, $55, $5A
        .byte   $5F, $64, $69, $6E, $73, $78, $7D, $82
        .byte   $87, $8C, $91, $96, $9B

; --- Frequency table - Low bytes ($F3B9-$F417) ---
FREQ_TABLE_LO:
        .byte   $A0, $28, $3C, $4B, $60, $74, $8B, $A4
        .byte   $BC, $D4, $F2, $11, $31, $51, $72, $98
        .byte   $BF, $EA, $16, $45, $78, $AD, $E5, $20
        .byte   $5F, $9F, $E6, $32, $80, $D4, $2E, $8A
        .byte   $EF, $5A, $CA, $3E, $BC, $3F, $CD, $64
        .byte   $00, $A9, $5A, $16, $DE, $B0, $8F, $7C
        .byte   $79, $81, $9B, $C6, $02, $53, $B4, $2B
        .byte   $BA, $5F, $1F, $F8, $ED, $05, $35, $8A
        .byte   $01, $A1, $67, $57, $74, $BF, $3F, $F1
        .byte   $DE, $04, $6C, $15, $06, $44, $CF, $AD
        .byte   $E8, $7E, $7E, $E5, $BA, $0A, $D7, $2E
        .byte   $0D, $84, $9D, $5C, $CE, $00, $00

; --- Frequency table - High bytes ($F418-$F476) ---
FREQ_TABLE_HI:
        .byte   $01, $01, $01, $01, $01, $01, $01, $01
        .byte   $01, $01, $01, $02, $02, $02, $02, $02
        .byte   $02, $02, $03, $03, $03, $03, $03, $04
        .byte   $04, $04, $04, $05, $05, $05, $06, $06
        .byte   $06, $07, $07, $08, $08, $09, $09, $0A
        .byte   $0B, $0B, $0C, $0D, $0D, $0E, $0F, $10
        .byte   $11, $12, $13, $14, $16, $17, $18, $1A
        .byte   $1B, $1D, $1F, $20, $22, $25, $27, $29
        .byte   $2C, $2E, $31, $34, $37, $3A, $3E, $41
        .byte   $45, $4A, $4E, $53, $58, $5D, $62, $68
        .byte   $6E, $75, $7C, $83, $8B, $94, $9C, $A6
        .byte   $B0, $BA, $C5, $D1, $DD, $EB, $00

; --- Music initialization code ($F477-$F4BC) ---
music_start:
        lda     music_song_table,y          ; $F477: B9 24 F9
        sta     smc_adc_operand                 ; $F47A: 8D B3 F4 (self-mod)
        ldx     #$02                            ; $F47D: A2 02

@loop1:
        lda     music_song_table_lo,y       ; $F47F: B9 22 F9
        sta     $8A,x                           ; $F482: 95 8A
        lda     music_song_table_hi,y       ; $F484: B9 23 F9
        sta     $8D,x                           ; $F487: 95 8D
        sty     $9E                             ; $F489: 84 9E
        lda     #$00                            ; $F48B: A9 00
        ldy     D_742D,x                        ; $F48D: BC 2D 74
        sta     $87,x                           ; $F490: 95 87
        sta     D_F2BB,y                        ; $F492: 99 BB F2
        sta     D_F2BF,y                        ; $F495: 99 BF F2
        lda     D_7433,x                        ; $F498: BD 33 74
        sta     $82,x                           ; $F49B: 95 82
        lda     #$01                            ; $F49D: A9 01
        sta     $A0,x                           ; $F49F: 95 A0
        sta     D_F308,x                        ; $F4A1: 9D 08 F3
        sta     D_F305,x                        ; $F4A4: 9D 05 F3
        ldy     $9E                             ; $F4A7: A4 9E
        dey                                     ; $F4A9: 88
        dey                                     ; $F4AA: 88
        dex                                     ; $F4AB: CA
        bpl     @loop1                          ; $F4AC: 10 D1

        clc                                     ; $F4AE: 18
        lda     #$00                            ; $F4AF: A9 00
        tax                                     ; $F4B1: AA

loop2:
smc_adc_operand := * + 1                        ; $F4B3: Self-modified by $F47A
        adc     #$05                            ; $F4B2: 69 05
        sta     D_F39A,x                        ; $F4B4: 9D 9A F3
        inx                                     ; $F4B7: E8
        cpx     #$20                            ; $F4B8: E0 20
        bcc     loop2                           ; $F4BA: 90 F6

        rts                                     ; $F4BC: 60

; ============================================================================
; SECTION 8: Sound Engine ($F4BD-$F921)
; ============================================================================
; Complete SID sound and music system.
;   sound_init: Initialize SID chip and clear sound state
;   sound_update: Called every frame to update all 3 voices
;   sfx_start: Music/mode initialization (called from credits handler)
; ============================================================================

sound_init:
    ldx  #$16                   ; a2 16        $f4bd
L_F4BF:
    lda  #$08                   ; a9 08        $f4bf
    sta  SID_V1_FREQ_LO,x       ; 9d 00 d4     $f4c1
    lda  #$00                   ; a9 00        $f4c4
    sta  SID_V1_FREQ_LO,x       ; 9d 00 d4     $f4c6
    dex                         ; ca           $f4c9
    bpl  L_F4BF                 ; 10 f3        $f4ca
    stx  D_F305                 ; 8e 05 f3     $f4cc
    stx  D_F306                 ; 8e 06 f3     $f4cf
    stx  D_F307                 ; 8e 07 f3     $f4d2
    sta  D_F337                 ; 8d 37 f3     $f4d5
    sta  D_F35A                 ; 8d 5a f3     $f4d8
    sta  D_F37D                 ; 8d 7d f3     $f4db
    sta  D_F391                 ; 8d 91 f3     $f4de
    sta  D_F308                 ; 8d 08 f3     $f4e1
    sta  D_F309                 ; 8d 09 f3     $f4e4
    sta  D_F30A                 ; 8d 0a f3     $f4e7
    stx  STKEY                  ; 86 91        $f4ea
    ldx  #$1f                   ; a2 1f        $f4ec
    stx  SID_VOL                ; 8e 18 d4     $f4ee
    rts                         ; 60           $f4f1
D_F4F2:
    stx  $80                    ; 86 80        $f4f2
    ldx  #$0f                   ; a2 0f        $f4f4
L_F4F6:
    lda  D_F30B,x               ; bd 0b f3     $f4f6
    sta  D_F384,x               ; 9d 84 f3     $f4f9
    dex                         ; ca           $f4fc
D_F4FD:
    bpl  L_F4F6                 ; 10 f7        $f4fd
    ldx  D_F392                 ; ae 92 f3     $f4ff
    ldy  D_F393                 ; ac 93 f3     $f502
    stx  D_F394                 ; 8e 94 f3     $f505
    sty  D_F395                 ; 8c 95 f3     $f508
    lda  D_F38C                 ; ad 8c f3     $f50b
    sta  D_F396                 ; 8d 96 f3     $f50e
    lda  D_F38D                 ; ad 8d f3     $f511
    sta  D_F397                 ; 8d 97 f3     $f514
    lda  D_F38E                 ; ad 8e f3     $f517
    sta  D_F398                 ; 8d 98 f3     $f51a
    lda  D_F38F                 ; ad 8f f3     $f51d
    sta  D_F399                 ; 8d 99 f3     $f520
    txa                         ; 8a           $f523
    and  #$07                   ; 29 07        $f524
    sta  SID_FILT_LO            ; 8d 15 d4     $f526
    tya                         ; 98           $f529
    stx  BSOUR                  ; 86 a3        $f52a
    lsr                         ; 4a           $f52c
    ror  BSOUR                  ; 66 a3        $f52d
    lsr                         ; 4a           $f52f
    ror  BSOUR                  ; 66 a3        $f530
    lsr                         ; 4a           $f532
    lda  BSOUR                  ; a5 a3        $f533
    ror                         ; 6a           $f535
    sta  SID_FILT_HI            ; 8d 16 d4     $f536
    ldx  $80                    ; a6 80        $f539
    rts                         ; 60           $f53b
sound_update:
    ldx  #$02                   ; a2 02        $f53c
    lda  #$00                   ; a9 00        $f53e
    sta  SYESSION               ; 85 a4        $f540
L_F542:
    lda  D_F308,x               ; bd 08 f3     $f542
    beq  L_F54C                 ; f0 05        $f545
    inc  SYESSION               ; e6 a4        $f547
    jsr  D_F55B                 ; 20 5b f5     $f549
L_F54C:
    ldy  D_7430,x               ; bc 30 74     $f54c
    lda  D_F337,y               ; b9 37 f3     $f54f
    beq  L_F557                 ; f0 03        $f552
    jsr  D_F6A5                 ; 20 a5 f6     $f554
L_F557:
    dex                         ; ca           $f557
    bpl  L_F542                 ; 10 e8        $f558
L_F55A:
    rts                         ; 60           $f55a
D_F55B:
    dec  $a0,x                  ; d6 a0        $f55b
    bne  L_F55A                 ; d0 fb        $f55d
    lda  $8a,x                  ; b5 8a        $f55f
    sta  $85                    ; 85 85        $f561
    lda  $8d,x                  ; b5 8d        $f563
    sta  $86                    ; 85 86        $f565
    jmp  D_F56F                 ; 4c 6f f5     $f567
D_F56A:
    lda  #$01                   ; a9 01        $f56a
D_F56C:
    jsr  music_add_offset       ; 20 20 74     $f56c
D_F56F:
    ldy  #$00                   ; a0 00        $f56f
    lda  ($85),y                ; b1 85        $f571
    bpl  L_F581                 ; 10 0c        $f573
    iny                         ; c8           $f575
    .assert (<music_track_pointers .bitand $0E) = 0, error, "music_track_pointers low byte bits 1-3 must be zero for EOR dispatch"
    eor  #($80 ^ <music_track_pointers)  ; 49 XX   $f576
    sta  smc_jmp_vec+1           ; 8d 7c f5     $f578
smc_jmp_vec:
    jmp  (D_F256)               ; 6c 56 f2     $f57b
L_F57E:
    jmp  D_F63B                 ; 4c 3b f6     $f57e
L_F581:
    sta  STATUS                 ; 85 90        $f581
    cmp  #$5f                   ; c9 5f        $f583
    bcs  L_F57E                 ; b0 f7        $f585
    adc  $87,x                  ; 75 87        $f587
    sta  $78                    ; 85 78        $f589
    lda  D_F305,x               ; bd 05 f3     $f58b
    beq  L_F57E                 ; f0 ee        $f58e
    lda  #$08                   ; a9 08        $f590
    sta  $7c                    ; 85 7c        $f592
    ldy  D_7436,x               ; bc 36 74     $f594
    sta  SID_V1_CTRL,y          ; 99 04 d4     $f597
    cpx  STKEY                  ; e4 91        $f59a
    bne  L_F5A1                 ; d0 03        $f59c
    jsr  D_F4F2                 ; 20 f2 f4     $f59e
L_F5A1:
    ldy  $78                    ; a4 78        $f5a1
    lda  FREQ_TABLE_HI,y        ; b9 18 f4     $f5a3
    sta  CHRGOT                 ; 85 79        $f5a6
    pha                         ; 48           $f5a8
    lda  FREQ_TABLE_LO,y        ; b9 b9 f3     $f5a9
    sta  $78                    ; 85 78        $f5ac
    ldy  D_7430,x               ; bc 30 74     $f5ae
    sta  D_F333,y               ; 99 33 f3     $f5b1
    pla                         ; 68           $f5b4
    sta  D_F334,y               ; 99 34 f3     $f5b5
    ldy  D_742D,x               ; bc 2d 74     $f5b8
    lda  D_F2C4,y               ; b9 c4 f2     $f5bb
    sta  TXTPTR                 ; 85 7a        $f5be
    lda  D_F2C5,y               ; b9 c5 f2     $f5c0
    sta  $7b                    ; 85 7b        $f5c3
    lda  D_F2C7,y               ; b9 c7 f2     $f5c5
    sta  $7d                    ; 85 7d        $f5c8
    lda  D_F2C8,y               ; b9 c8 f2     $f5ca
    sta  $7e                    ; 85 7e        $f5cd
    lda  D_F2C6,y               ; b9 c6 f2     $f5cf
    ldy  D_7430,x               ; bc 30 74     $f5d2
    sta  D_F335,y               ; 99 35 f3     $f5d5
    and  #$f7                   ; 29 f7        $f5d8
    pha                         ; 48           $f5da
    stx  $7f                    ; 86 7f        $f5db
    ldy  D_7437,x               ; bc 37 74     $f5dd
    dey                         ; 88           $f5e0
    ldx  #$06                   ; a2 06        $f5e1
L_F5E3:
    lda  $78,x                  ; b5 78        $f5e3
    sta  SID_V1_FREQ_LO,y       ; 99 00 d4     $f5e5
    dey                         ; 88           $f5e8
    dex                         ; ca           $f5e9
    bpl  L_F5E3                 ; 10 f7        $f5ea
    iny                         ; c8           $f5ec
    pla                         ; 68           $f5ed
    sta  SID_V1_CTRL,y          ; 99 04 d4     $f5ee
    ldx  $7f                    ; a6 7f        $f5f1
    ldy  D_7430,x               ; bc 30 74     $f5f3
    jsr  D_F68D                 ; 20 8d f6     $f5f6
    lda  D_7357,x               ; bd 57 73     $f5f9
    sta  smc_copy_src+1         ; 8d 08 f6     $f5fc
    lda  D_735A,x               ; bd 5a 73     $f5ff
    sta  smc_copy_dst+1         ; 8d 0b f6     $f602
    ldy  #$17                   ; a0 17        $f605
L_F607:
smc_copy_src:
    lda  D_F2AE,y               ; b9 ae f2     $f607
smc_copy_dst:
    sta  D_F31B,y               ; 99 1b f3     $f60a
    dey                         ; 88           $f60d
    bpl  L_F607                 ; 10 f7        $f60e
    ldy  D_7430,x               ; bc 30 74     $f610
    lda  D_F328,y               ; b9 28 f3     $f613
    and  #$08                   ; 29 08        $f616
    beq  L_F624                 ; f0 0a        $f618
    lda  STATUS                 ; a5 90        $f61a
    clc                         ; 18           $f61c
    adc  $87,x                  ; 75 87        $f61d
    sta  D_F325,y               ; 99 25 f3     $f61f
    bne  L_F627                 ; d0 03        $f622
L_F624:
    jsr  D_F659                 ; 20 59 f6     $f624
L_F627:
    ldy  D_742D,x               ; bc 2d 74     $f627
    lda  D_F2C9,y               ; b9 c9 f2     $f62a
    pha                         ; 48           $f62d
    lda  D_F2CA,y               ; b9 ca f2     $f62e
    ldy  D_7430,x               ; bc 30 74     $f631
    sta  D_F337,y               ; 99 37 f3     $f634
    pla                         ; 68           $f637
    sta  D_F336,y               ; 99 36 f3     $f638
D_F63B:
    ldy  #$01                   ; a0 01        $f63b
    lda  ($85),y                ; b1 85        $f63d
    ldy  STATUS                 ; a4 90        $f63f
    cpy  #$60                   ; c0 60        $f641
    beq  L_F649                 ; f0 04        $f643
    tay                         ; a8           $f645
    lda  D_F399,y               ; b9 99 f3     $f646
L_F649:
    sta  $a0,x                  ; 95 a0        $f649
    lda  #$02                   ; a9 02        $f64b
    jsr  music_add_offset       ; 20 20 74     $f64d
    lda  $85                    ; a5 85        $f650
    sta  $8a,x                  ; 95 8a        $f652
    lda  $86                    ; a5 86        $f654
    sta  $8d,x                  ; 95 8d        $f656
    rts                         ; 60           $f658
D_F659:
    lda  D_F333,y               ; b9 33 f3     $f659
    sta  DFLTN,x                ; 95 98        $f65c
    sta  TXTPTR                 ; 85 7a        $f65e
    lda  D_F334,y               ; b9 34 f3     $f660
    sta  TESSION,x              ; 95 9b        $f663
    sta  $7b                    ; 85 7b        $f665
D_F667:
    lda  D_F326,y               ; b9 26 f3     $f667
    sta  D_F33B,y               ; 99 3b f3     $f66a
    lda  D_F325,y               ; b9 25 f3     $f66d
    sta  D_F33A,y               ; 99 3a f3     $f670
    lda  D_F324,y               ; b9 24 f3     $f673
    sta  D_F339,y               ; 99 39 f3     $f676
    lda  D_F323,y               ; b9 23 f3     $f679
    sta  D_F338,y               ; 99 38 f3     $f67c
    rts                         ; 60           $f67f
D_F680:
    ldy  D_7430,x               ; bc 30 74     $f680
    lda  D_F331,y               ; b9 31 f3     $f683
    sta  TXTPTR                 ; 85 7a        $f686
    lda  D_F332,y               ; b9 32 f3     $f688
    sta  $7b                    ; 85 7b        $f68b
D_F68D:
    ldy  D_7430,x               ; bc 30 74     $f68d
    lda  TXTPTR                 ; a5 7a        $f690
    sta  SVXT,x                 ; 95 92        $f692
    lda  $7b                    ; a5 7b        $f694
    sta  BESSION,x              ; 95 95        $f696
    lda  D_F329,y               ; b9 29 f3     $f698
    sta  D_F33C,y               ; 99 3c f3     $f69b
    lda  D_F32A,y               ; b9 2a f3     $f69e
    sta  D_F33D,y               ; 99 3d f3     $f6a1
    rts                         ; 60           $f6a4
D_F6A5:
    lda  D_F335,y               ; b9 35 f3     $f6a5
    and  #$08                   ; 29 08        $f6a8
    beq  L_F6C2                 ; f0 16        $f6aa
    lda  $a0,x                  ; b5 a0        $f6ac
    cmp  D_F336,y               ; d9 36 f3     $f6ae
    bcs  L_F70C                 ; b0 59        $f6b1
    lda  #$00                   ; a9 00        $f6b3
    sta  D_F336,y               ; 99 36 f3     $f6b5
    lda  D_F335,y               ; b9 35 f3     $f6b8
    and  #$f6                   ; 29 f6        $f6bb
    sta  D_F335,y               ; 99 35 f3     $f6bd
    bne  L_F703                 ; d0 41        $f6c0
L_F6C2:
    lda  D_F336,y               ; b9 36 f3     $f6c2
    bne  L_F6EF                 ; d0 28        $f6c5
    lda  D_F337,y               ; b9 37 f3     $f6c7
    clc                         ; 18           $f6ca
    adc  #$01                   ; 69 01        $f6cb
    beq  L_F70C                 ; f0 3d        $f6cd
    sbc  #$01                   ; e9 01        $f6cf
    sta  D_F337,y               ; 99 37 f3     $f6d1
    bne  L_F70C                 ; d0 36        $f6d4
    stx  $7f                    ; 86 7f        $f6d6
    ldy  D_7437,x               ; bc 37 74     $f6d8
    dey                         ; 88           $f6db
    ldx  #$06                   ; a2 06        $f6dc
L_F6DE:
    sta  SID_V1_FREQ_LO,y       ; 99 00 d4     $f6de
    dey                         ; 88           $f6e1
    dex                         ; ca           $f6e2
    bpl  L_F6DE                 ; 10 f9        $f6e3
    ldx  $7f                    ; a6 7f        $f6e5
    cpx  STKEY                  ; e4 91        $f6e7
    bne  L_F6EE                 ; d0 03        $f6e9
    sta  D_F391                 ; 8d 91 f3     $f6eb
L_F6EE:
    rts                         ; 60           $f6ee
L_F6EF:
    lda  D_F336,y               ; b9 36 f3     $f6ef
    clc                         ; 18           $f6f2
    adc  #$01                   ; 69 01        $f6f3
    beq  L_F70C                 ; f0 15        $f6f5
    sbc  #$01                   ; e9 01        $f6f7
    sta  D_F336,y               ; 99 36 f3     $f6f9
    bne  L_F70C                 ; d0 0e        $f6fc
    lda  D_F335,y               ; b9 35 f3     $f6fe
    and  #$f6                   ; 29 f6        $f701
L_F703:
    ldy  D_7436,x               ; bc 36 74     $f703
    sta  SID_V1_CTRL,y          ; 99 04 d4     $f706
    ldy  D_7430,x               ; bc 30 74     $f709
L_F70C:
    lda  D_F32C,y               ; b9 2c f3     $f70c
    beq  L_F78A                 ; f0 79        $f70f
    lda  D_F32B,y               ; b9 2b f3     $f711
    beq  L_F71F                 ; f0 09        $f714
    sec                         ; 38           $f716
    sbc  #$01                   ; e9 01        $f717
    sta  D_F32B,y               ; 99 2b f3     $f719
    jmp  L_F78A                 ; 4c 8a f7     $f71c
L_F71F:
    lda  SVXT,x                 ; b5 92        $f71f
    sta  TXTPTR                 ; 85 7a        $f721
    lda  BESSION,x              ; b5 95        $f723
    sta  $7b                    ; 85 7b        $f725
    lda  D_F33C,y               ; b9 3c f3     $f727
    beq  L_F744                 ; f0 18        $f72a
    sec                         ; 38           $f72c
    sbc  #$01                   ; e9 01        $f72d
    sta  D_F33C,y               ; 99 3c f3     $f72f
    lda  TXTPTR                 ; a5 7a        $f732
    clc                         ; 18           $f734
    adc  D_F32D,y               ; 79 2d f3     $f735
    sta  TXTPTR                 ; 85 7a        $f738
    lda  $7b                    ; a5 7b        $f73a
    adc  D_F32E,y               ; 79 2e f3     $f73c
    sta  $7b                    ; 85 7b        $f73f
    jmp  D_F776                 ; 4c 76 f7     $f741
L_F744:
    lda  D_F33D,y               ; b9 3d f3     $f744
    beq  L_F761                 ; f0 18        $f747
    sec                         ; 38           $f749
    sbc  #$01                   ; e9 01        $f74a
    sta  D_F33D,y               ; 99 3d f3     $f74c
    lda  TXTPTR                 ; a5 7a        $f74f
    clc                         ; 18           $f751
    adc  D_F32F,y               ; 79 2f f3     $f752
    sta  TXTPTR                 ; 85 7a        $f755
    lda  $7b                    ; a5 7b        $f757
    adc  D_F330,y               ; 79 30 f3     $f759
    sta  $7b                    ; 85 7b        $f75c
    jmp  D_F776                 ; 4c 76 f7     $f75e
L_F761:
    lda  D_F32C,y               ; b9 2c f3     $f761
    and  #$81                   ; 29 81        $f764
    beq  D_F776                 ; f0 0e        $f766
    bpl  L_F770                 ; 10 06        $f768
    jsr  D_F680                 ; 20 80 f6     $f76a
    jmp  L_F71F                 ; 4c 1f f7     $f76d
L_F770:
    jsr  D_F68D                 ; 20 8d f6     $f770
    jmp  L_F71F                 ; 4c 1f f7     $f773
D_F776:
    ldy  D_7436,x               ; bc 36 74     $f776
    lda  TXTPTR                 ; a5 7a        $f779
    sta  SID_V1_PW_LO,y         ; 99 02 d4     $f77b
    sta  SVXT,x                 ; 95 92        $f77e
    lda  $7b                    ; a5 7b        $f780
    sta  SID_V1_PW_HI,y         ; 99 03 d4     $f782
    sta  BESSION,x              ; 95 95        $f785
    ldy  D_7430,x               ; bc 30 74     $f787
L_F78A:
    lda  D_F328,y               ; b9 28 f3     $f78a
    beq  L_F7FA                 ; f0 6b        $f78d
    and  #$08                   ; 29 08        $f78f
    beq  L_F7E0                 ; f0 4d        $f791
    cpx  #$02                   ; e0 02        $f793
    beq  L_F7E0                 ; f0 49        $f795
    lda  D_F31F,y               ; b9 1f f3     $f797
    sec                         ; 38           $f79a
    sbc  #$01                   ; e9 01        $f79b
    sta  D_F31F,y               ; 99 1f f3     $f79d
    bne  L_F7FA                 ; d0 58        $f7a0
    lda  D_F321,y               ; b9 21 f3     $f7a2
    sta  D_F31F,y               ; 99 1f f3     $f7a5
    lda  D_F323,y               ; b9 23 f3     $f7a8
    sta  $80                    ; 85 80        $f7ab
    lda  D_F324,y               ; b9 24 f3     $f7ad
    sta  $81                    ; 85 81        $f7b0
    lda  D_F325,y               ; b9 25 f3     $f7b2
    pha                         ; 48           $f7b5
    lda  D_F327,y               ; b9 27 f3     $f7b6
    bpl  L_F7BE                 ; 10 03        $f7b9
    lda  D_F326,y               ; b9 26 f3     $f7bb
L_F7BE:
    tay                         ; a8           $f7be
    pla                         ; 68           $f7bf
    clc                         ; 18           $f7c0
    adc  ($80),y                ; 71 80        $f7c1
    pha                         ; 48           $f7c3
    dey                         ; 88           $f7c4
    tya                         ; 98           $f7c5
    ldy  D_7430,x               ; bc 30 74     $f7c6
    sta  D_F327,y               ; 99 27 f3     $f7c9
    pla                         ; 68           $f7cc
    tay                         ; a8           $f7cd
    lda  FREQ_TABLE_HI,y        ; b9 18 f4     $f7ce
    pha                         ; 48           $f7d1
    lda  FREQ_TABLE_LO,y        ; b9 b9 f3     $f7d2
    ldy  D_7436,x               ; bc 36 74     $f7d5
    sta  SID_V1_FREQ_LO,y       ; 99 00 d4     $f7d8
    pla                         ; 68           $f7db
    sta  SID_V1_FREQ_HI,y       ; 99 01 d4     $f7dc
    rts                         ; 60           $f7df
L_F7E0:
    lda  DFLTN,x                ; b5 98        $f7e0
    sta  TXTPTR                 ; 85 7a        $f7e2
    lda  TESSION,x              ; b5 9b        $f7e4
    sta  $7b                    ; 85 7b        $f7e6
    lda  D_F327,y               ; b9 27 f3     $f7e8
    beq  L_F7FB                 ; f0 0e        $f7eb
    sec                         ; 38           $f7ed
    sbc  #$01                   ; e9 01        $f7ee
    sta  D_F327,y               ; 99 27 f3     $f7f0
    lda  D_F328,y               ; b9 28 f3     $f7f3
    and  #$02                   ; 29 02        $f7f6
    bne  L_F851                 ; d0 57        $f7f8
L_F7FA:
    rts                         ; 60           $f7fa
L_F7FB:
    lda  D_F338,y               ; b9 38 f3     $f7fb
    beq  L_F814                 ; f0 14        $f7fe
    sec                         ; 38           $f800
    sbc  #$01                   ; e9 01        $f801
    sta  D_F338,y               ; 99 38 f3     $f803
    lda  TXTPTR                 ; a5 7a        $f806
    clc                         ; 18           $f808
    adc  D_F31B,y               ; 79 1b f3     $f809
    sta  TXTPTR                 ; 85 7a        $f80c
    lda  D_F31C,y               ; b9 1c f3     $f80e
    jmp  D_F85C                 ; 4c 5c f8     $f811
L_F814:
    lda  D_F339,y               ; b9 39 f3     $f814
    beq  L_F82D                 ; f0 14        $f817
    sec                         ; 38           $f819
    sbc  #$01                   ; e9 01        $f81a
    sta  D_F339,y               ; 99 39 f3     $f81c
D_F81F:
    lda  $7a                    ; a5 7a        $f81f
    clc                         ; 18           $f821
    adc  D_F31D,y               ; 79 1d f3     $f822
    sta  TXTPTR                 ; 85 7a        $f825
    lda  D_F31E,y               ; b9 1e f3     $f827
    jmp  D_F85C                 ; 4c 5c f8     $f82a
L_F82D:
    lda  D_F33A,y               ; b9 3a f3     $f82d
    beq  L_F846                 ; f0 14        $f830
    sec                         ; 38           $f832
    sbc  #$01                   ; e9 01        $f833
    sta  D_F33A,y               ; 99 3a f3     $f835
    lda  TXTPTR                 ; a5 7a        $f838
    clc                         ; 18           $f83a
    adc  D_F31F,y               ; 79 1f f3     $f83b
    sta  TXTPTR                 ; 85 7a        $f83e
    lda  D_F320,y               ; b9 20 f3     $f840
    jmp  D_F85C                 ; 4c 5c f8     $f843
L_F846:
    lda  D_F33B,y               ; b9 3b f3     $f846
    beq  L_F872                 ; f0 27        $f849
    sec                         ; 38           $f84b
    sbc  #$01                   ; e9 01        $f84c
    sta  D_F33B,y               ; 99 3b f3     $f84e
L_F851:
    lda  TXTPTR                 ; a5 7a        $f851
    clc                         ; 18           $f853
    adc  D_F321,y               ; 79 21 f3     $f854
    sta  TXTPTR                 ; 85 7a        $f857
    lda  D_F322,y               ; b9 22 f3     $f859
D_F85C:
    adc  $7b                    ; 65 7b        $f85c
    sta  $7b                    ; 85 7b        $f85e
L_F860:
    ldy  D_7436,x               ; bc 36 74     $f860
    lda  TXTPTR                 ; a5 7a        $f863
    sta  DFLTN,x                ; 95 98        $f865
    sta  SID_V1_FREQ_LO,y       ; 99 00 d4     $f867
    lda  $7b                    ; a5 7b        $f86a
    sta  TESSION,x              ; 95 9b        $f86c
    sta  SID_V1_FREQ_HI,y       ; 99 01 d4     $f86e
L_F871:
    rts                         ; 60           $f871
L_F872:
    lda  D_F328,y               ; b9 28 f3     $f872
    and  #$81                   ; 29 81        $f875
    beq  L_F860                 ; f0 e7        $f877
    bpl  L_F881                 ; 10 06        $f879
    jsr  D_F659                 ; 20 59 f6     $f87b
    jmp  L_F7FB                 ; 4c fb f7     $f87e
L_F881:
    jsr  D_F667                 ; 20 67 f6     $f881
    jmp  L_F7FB                 ; 4c fb f7     $f884

; sfx_start: Music/mode initialization routine
sfx_start:
    sta  TIME                   ; 85 9e        $f887
    sty  $9f                    ; 84 9f        $f889
    lda  #$00                   ; a9 00        $f88b
    sta  D_F305                 ; 8d 05 f3     $f88d
    ldx  #$06                   ; a2 06        $f890
L_F892:
    lda  #$08                   ; a9 08        $f892
    sta  SID_V1_FREQ_LO,x       ; 9d 00 d4     $f894
    lda  #$00                   ; a9 00        $f897
    sta  SID_V1_FREQ_LO,x       ; 9d 00 d4     $f899
    dex                         ; ca           $f89c
    bpl  L_F892                 ; 10 f3        $f89d
    ldy  #$1a                   ; a0 1a        $f89f
    ldx  #$04                   ; a2 04        $f8a1
L_F8A3:
    lda  (TIME),y               ; b1 9e        $f8a3
    sta  SID_V1_PW_LO,x         ; 9d 02 d4     $f8a5
    dey                         ; 88           $f8a8
    dex                         ; ca           $f8a9
    bpl  L_F8A3                 ; 10 f7        $f8aa
    ldy  #$1d                   ; a0 1d        $f8ac
    lda  (TIME),y               ; b1 9e        $f8ae
    tax                         ; aa           $f8b0
    lda  FREQ_TABLE_LO,x        ; bd b9 f3     $f8b1
    sta  SID_V1_FREQ_LO         ; 8d 00 d4     $f8b4
    sta  D_F333                 ; 8d 33 f3     $f8b7
    lda  FREQ_TABLE_HI,x        ; bd 18 f4     $f8ba
    sta  SID_V1_FREQ_HI         ; 8d 01 d4     $f8bd
    sta  D_F334                 ; 8d 34 f3     $f8c0
    dey                         ; 88           $f8c3
    lda  (TIME),y               ; b1 9e        $f8c4
    sta  D_F337                 ; 8d 37 f3     $f8c6
    dey                         ; 88           $f8c9
    lda  (TIME),y               ; b1 9e        $f8ca
    sta  D_F336                 ; 8d 36 f3     $f8cc
    ldy  #$18                   ; a0 18        $f8cf
    lda  (TIME),y               ; b1 9e        $f8d1
    sta  D_F335                 ; 8d 35 f3     $f8d3
    dey                         ; 88           $f8d6
L_F8D7:
    lda  (TIME),y               ; b1 9e        $f8d7
    sta  D_F31B,y               ; 99 1b f3     $f8d9
    dey                         ; 88           $f8dc
    bpl  L_F8D7                 ; 10 f8        $f8dd
    lda  D_F32C                 ; ad 2c f3     $f8df
    beq  L_F8FA                 ; f0 16        $f8e2
    lda  D_F331                 ; ad 31 f3     $f8e4
    sta  SVXT                   ; 85 92        $f8e7
    lda  D_F332,y               ; b9 32 f3     $f8e9
    sta  BESSION                ; 85 95        $f8ec
    lda  D_F329                 ; ad 29 f3     $f8ee
    sta  D_F33C                 ; 8d 3c f3     $f8f1
    lda  D_F32A                 ; ad 2a f3     $f8f4
    sta  D_F33D                 ; 8d 3d f3     $f8f7
L_F8FA:
    lda  D_F328                 ; ad 28 f3     $f8fa
    beq  L_F921                 ; f0 22        $f8fd
    lda  D_F333                 ; ad 33 f3     $f8ff
    sta  DFLTN                  ; 85 98        $f902
    lda  D_F334                 ; ad 34 f3     $f904
    sta  TESSION                ; 85 9b        $f907
    lda  D_F326                 ; ad 26 f3     $f909
    sta  D_F33B                 ; 8d 3b f3     $f90c
    lda  D_F325                 ; ad 25 f3     $f90f
    sta  D_F33A                 ; 8d 3a f3     $f912
    lda  D_F324                 ; ad 24 f3     $f915
    sta  D_F339                 ; 8d 39 f3     $f918
    lda  D_F323                 ; ad 23 f3     $f91b
    sta  D_F338                 ; 8d 38 f3     $f91e
L_F921:
    rts                         ; 60           $f921

; ============================================================================
; SECTION 9: SFX & Music Data ($F922-$FE01)
; ============================================================================
; Sound effect parameter blocks, instrument data, and music sequences.
; ============================================================================

; --- Music track pointers ($F922-$F927) ---
music_song_table_lo:            ; $F922
        .byte   <music_voice0_start ; -> music_voice0_start ($FC72)
music_song_table_hi:            ; $F923
        .byte   >music_voice0_start
music_song_table:               ; $F924
        .byte   <music_voice1_start ; -> music_voice1_start ($FCA3)
        .byte   >music_voice1_start ; $F925
        .byte   <music_voice2_start, >music_voice2_start ; $F926-$F927

; --- Song index table ($F928-$F975) ---
; Each entry: voice0_lo, voice0_hi, voice1_lo, voice1_hi, voice2_lo, voice2_hi, freq_divisor
; The song label marks the freq_divisor byte (the last byte of each entry).
; To start a song: ldy #(song_xxx - music_song_table) / jsr music_start
; Note: song_level_theme's voice pointers are in music_song_table above.
sfx_index_table:

song_level_theme:                                                ; $F928 (Y=$04)
        .byte   $06                                              ;   freq_divisor
        .byte   <music_seq_voice0_alt, >music_seq_voice0_alt    ;   voice 0
        .byte   <music_seq_voice1_alt, >music_seq_voice1_alt    ;   voice 1
        .byte   <D_FDC4, >D_FDC4                                ;   voice 2
song_level_resume:                                               ; $F92F (Y=$0B)
        .byte   $06                                              ;   freq_divisor
        .byte   <music_seq_voice0_alt, >music_seq_voice0_alt    ;   voice 0
        .byte   <L_70CD, >L_70CD                                ;   voice 1
        .byte   <L_7161, >L_7161                                ;   voice 2
song_level_final:                                                ; $F936 (Y=$12)
        .byte   $04                                              ;   freq_divisor
        .byte   <D_FE40, >D_FE40                                ;   voice 0
        .byte   <L_706D, >L_706D                                ;   voice 1
        .byte   <L_70B7, >L_70B7                                ;   voice 2
song_bonus_round:                                                ; $F93D (Y=$19)
        .byte   $05                                              ;   freq_divisor
        .byte   <L_71A2, >L_71A2                                ;   voice 0
        .byte   <L_71B8, >L_71B8                                ;   voice 1
        .byte   <L_71BE, >L_71BE                                ;   voice 2
song_game_over:                                                  ; $F944 (Y=$20)
        .byte   $06                                              ;   freq_divisor
        .byte   <music_seq_voice0_alt, >music_seq_voice0_alt    ;   voice 0
        .byte   <music_seq_voice1_alt, >music_seq_voice1_alt    ;   voice 1
        .byte   <D_FDC4, >D_FDC4                                ;   voice 2
song_level_complete:                                             ; $F94B (Y=$27)
        .byte   $05                                              ;   freq_divisor
        .byte   <L_71CE, >L_71CE                                ;   voice 0
        .byte   <L_71FB, >L_71FB                                ;   voice 1
        .byte   <L_7213, >L_7213                                ;   voice 2
song_extend:                                                     ; $F952 (Y=$2E)
        .byte   $03                                              ;   freq_divisor
        .byte   <title_music_voice0, >title_music_voice0        ;   voice 0
        .byte   <title_music_voice1, >title_music_voice1        ;   voice 1
        .byte   <title_music_voice2, >title_music_voice2        ;   voice 2
song_title_screen:                                               ; $F959 (Y=$35)
        .byte   $03                                              ;   freq_divisor
        .byte   <L_7230, >L_7230                                ;   voice 0
        .byte   <L_723D, >L_723D                                ;   voice 1
        .byte   <L_723F, >L_723F                                ;   voice 2
song_hurry_up:                                                   ; $F960 (Y=$3C)
        .byte   $04                                              ;   freq_divisor
        .byte   <L_724A, >L_724A                                ;   voice 0
        .byte   <L_7262, >L_7262                                ;   voice 1
        .byte   <L_7268, >L_7268                                ;   voice 2
song_round_start:                                                ; $F967 (Y=$43)
        .byte   $05                                              ;   freq_divisor
        .byte   <L_7278, >L_7278                                ;   voice 0
        .byte   <L_72A1, >L_72A1                                ;   voice 1
        .byte   <L_72A9, >L_72A9                                ;   voice 2
song_super_bonus:                                                ; $F96E (Y=$4A)
        .byte   $03                                              ;   freq_divisor
        .byte   <L_72C2, >L_72C2                                ;   voice 0
        .byte   <L_72E9, >L_72E9                                ;   voice 1
        .byte   <L_72F7, >L_72F7                                ;   voice 2
song_ending:                                                     ; $F975 (Y=$51)
        .byte   $05                                              ;   freq_divisor
sfx_preset_0:                 ; $F976
        .byte   $BC, $02                                         ; $F976

; --- Sound effect parameter blocks ($F978-$FC71) ---

sfx_params_00:
        .byte   $70, $FE, $00, $00, $00, $00, $02, $02          ; $F978
        .byte   $00, $00, $00, $05, $00, $00, $00, $04          ; $F980
        .byte   $00, $00, $00, $00, $00, $04, $49, $07          ; $F988

sfx_params_01:
        .byte   $FA, $23, $23, $2B                               ; $F990
sfx_preset_1:                 ; $F994
        .byte   $D5, $FB, $01, $00                               ; $F994
        .byte   $A0, $0F, $00, $00, $06, $03, $03, $00          ; $F998
        .byte   $02, $04, $02, $02, $00, $05, $40, $00          ; $F9A0

sfx_params_02:
        .byte   $C0, $FF, $00, $08, $49, $07, $F9, $17          ; $F9A8
        .byte   $28, $4A                                         ; $F9B0
sfx_preset_2:                 ; $F9B2
        .byte   $30, $F8, $38, $FF, $06, $FF                    ; $F9B2
        .byte   $00, $00, $01, $02, $01, $00, $04, $04          ; $F9B8
        .byte   $00, $00, $00, $00, $00, $00, $00, $00          ; $F9C0

sfx_params_03:
        .byte   $00, $00, $89, $07, $FA, $2D, $1E, $2E          ; $F9C8
sfx_preset_3:                 ; $F9D0
        .byte   $00, $00, $00, $00, $01, $00, $05, $00          ; $F9D0
        .byte   $ED, $F9, $00, $07, $00, $0D, $00, $00          ; $F9D8
        .byte   $00, $00, $00, $00, $00, $00                    ; $F9E0

sfx_params_04:
        .byte   $00, $08, $49, $07, $FB, $23, $29, $3C          ; $F9E6
        .byte   $40, $40, $40, $40, $43, $3E, $41               ; $F9EE
sfx_preset_4:                 ; $F9F5
        .byte   $90                                              ; $F9F5
        .byte   $01, $00, $00, $00, $00, $00, $00, $1E          ; $F9F6
        .byte   $00, $00, $00, $00, $05, $04                    ; $F9FE

sfx_params_05:
        .byte   $04, $00, $05, $F0, $01, $10, $FE, $00          ; $FA04
        .byte   $08, $49, $07, $FB, $32, $32, $14               ; $FA0C
sfx_preset_5:                 ; $FA13
        .byte   $00                                              ; $FA13
        .byte   $00, $00, $00, $01, $00, $05, $00, $30          ; $FA14
        .byte   $FA, $00, $07, $00, $0D, $00                    ; $FA1C

sfx_params_06:
        .byte   $00, $00, $00, $00, $00, $00, $00, $00          ; $FA22
        .byte   $08, $49, $07, $FA, $28, $29, $45, $41          ; $FA2A
        .byte   $41, $41, $41, $41, $45, $41                    ; $FA32
sfx_instr_4:                        ; $FA38
        .byte   $70, $FE                                         ; $FA38
        .byte   $C8, $00, $00, $00, $00, $00, $01, $02          ; $FA3A
        .byte   $00, $00, $00, $04, $08                         ; $FA42

sfx_params_07:
        .byte   $08, $06, $05, $80, $FF, $40, $00, $00          ; $FA47
        .byte   $08, $41, $08, $7B, $03, $32                    ; $FA4F
sfx_instr_5:                        ; $FA55
        .byte   $1E, $00                                         ; $FA55
        .byte   $E2, $FF, $1E, $00, $00, $00, $04, $08          ; $FA57
        .byte   $04, $00, $10, $05, $00, $00, $00, $00          ; $FA5F
        .byte   $00, $00, $00, $00, $00, $00, $29, $D7          ; $FA67

sfx_params_08:
        .byte   $8D, $14, $64                                    ; $FA6F
sfx_instr_6:                        ; $FA72
        .byte   $00, $00, $00, $00, $00                          ; $FA72
        .byte   $00, $00, $00, $00, $00, $00, $00, $00          ; $FA77
        .byte   $00, $00, $00, $00, $00, $00, $00, $00          ; $FA7F

sfx_params_09:
        .byte   $00, $00, $08, $41, $09, $79, $07, $3C          ; $FA87
sfx_instr_7:                        ; $FA8F
        .byte   $0F, $00, $F1, $FF, $0F, $00, $00, $00          ; $FA8F
        .byte   $03, $06, $03, $00, $0A, $05, $00, $00          ; $FA97
        .byte   $00, $00, $00, $00, $00, $00, $00, $00          ; $FA9F
        .byte   $15, $02, $DA, $03                              ; $FAA7

sfx_params_10:
        .byte   $0F                                              ; $FAAB
sfx_instr_0:                        ; $FAAC
        .byte   $55, $00, $AB, $FF, $55, $00, $00               ; $FAAC
        .byte   $00, $02, $04, $02, $00, $10, $05, $00          ; $FAB3
        .byte   $00, $00, $00, $00, $00, $00, $00, $00          ; $FABB
        .byte   $00, $29, $37, $F8                              ; $FAC3

sfx_params_11:
        .byte   $07, $5A                                         ; $FAC7
sfx_instr_8:                        ; $FAC9
        .byte   $F4, $FF, $0C, $00, $F4, $FF                    ; $FAC9
        .byte   $00, $00, $02, $04, $02, $00, $08, $05          ; $FACF
        .byte   $08, $08, $05, $05                              ; $FAD7

sfx_params_12:
        .byte   $C0, $FF, $30, $00, $00, $0C, $41, $09          ; $FADB
        .byte   $FB, $09, $5A                                    ; $FAE3
sfx_instr_9:                        ; $FAE6
        .byte   $00, $00, $00, $00, $00                          ; $FAE6
        .byte   $00, $00, $00, $00, $00, $00, $00, $00          ; $FAEB
        .byte   $00, $04, $04, $02, $05, $C0                    ; $FAF3

sfx_params_13:
        .byte   $FF, $40, $00, $00, $0D, $41, $09, $08          ; $FAF9
        .byte   $08, $28                                         ; $FB01
sfx_instr_10:                       ; $FB03
        .byte   $F4, $FF, $0C, $00, $F4, $FF                    ; $FB03
        .byte   $00, $00, $02, $04, $02, $00, $08, $05          ; $FB09
        .byte   $08, $08, $00, $05, $E0, $FF                    ; $FB11

sfx_params_14:
        .byte   $20, $00, $80, $0C, $49, $09, $F7, $03          ; $FB17
        .byte   $5A                                              ; $FB1F
sfx_instr_11:                       ; $FB20
        .byte   $F4, $FF, $0C, $00, $F4, $FF, $00               ; $FB20
        .byte   $00, $02, $04, $02, $00, $08, $05, $08          ; $FB27
        .byte   $08, $00, $04, $D0, $FF, $30                    ; $FB2F

sfx_params_15:
        .byte   $00, $00, $0D, $49, $09, $F7, $03, $5A          ; $FB35
sfx_instr_1:                        ; $FB3D
        .byte   $23, $00, $DD, $FF, $23, $00, $00, $00          ; $FB3D
        .byte   $02, $04, $02, $00, $00, $05, $10, $10          ; $FB45
        .byte   $02, $05                                        ; $FB4D

sfx_params_16:
        .byte   $80, $FF, $80, $00, $01, $08, $41, $07          ; $FB4F
        .byte   $BA, $07, $32                                    ; $FB57
sfx_instr_12:                       ; $FB5A
        .byte   $38, $FF, $64, $00, $9C                          ; $FB5A
        .byte   $FF, $64, $00, $02, $03, $02, $03, $04          ; $FB5F
        .byte   $05, $00, $00, $00, $04, $00, $00, $00          ; $FB67
        .byte   $00, $00                                        ; $FB6F

sfx_params_17:
        .byte   $08, $41, $07, $8B, $07, $32                    ; $FB71
sfx_instr_13:                       ; $FB77
        .byte   $00, $00                                         ; $FB77
        .byte   $00, $00, $00, $00, $00, $00, $00, $00          ; $FB79
        .byte   $00, $00, $00, $00, $00, $00, $00, $00          ; $FB81
        .byte   $00, $00, $00, $00                              ; $FB89

sfx_params_18:
        .byte   $80, $0C, $49, $06, $98, $03, $0F               ; $FB8D
sfx_instr_14:                       ; $FB94
        .byte   $48                                              ; $FB94
        .byte   $F4, $58, $02, $90, $01, $00, $00, $01          ; $FB95
        .byte   $01, $14, $00, $02, $05, $08, $08, $04          ; $FB9D
        .byte   $04, $90, $00, $90, $00, $00, $03, $49          ; $FBA5
        .byte   $16                                             ; $FBAD

sfx_params_19:
        .byte   $F8, $04, $08                                    ; $FBAE
sfx_instr_15:                       ; $FBB1
        .byte   $48, $F4, $58, $02, $90                          ; $FBB1
        .byte   $01, $00, $00, $01, $01, $14, $00, $02          ; $FBB6
        .byte   $05, $00, $00, $00, $04, $00, $00, $00          ; $FBBE
        .byte   $00, $00, $02, $49                              ; $FBC6

sfx_params_20:
        .byte   $16, $F8, $04, $08                               ; $FBCA
sfx_instr_2:                        ; $FBCE
        .byte   $00, $00, $00, $00                               ; $FBCE
        .byte   $01, $00, $01, $00, $DD, $DD, $00, $03          ; $FBD2
        .byte   $00, $08, $08, $00, $00, $04, $C0, $FF          ; $FBDA
        .byte   $00, $00, $00, $0D, $41, $06, $7A, $09          ; $FBE2

sfx_params_21:
        .byte   $1E                                              ; $FBEA
sfx_instr_3:                        ; $FBEB
        .byte   $00, $00, $00, $00, $01, $00, $03               ; $FBEB
        .byte   $00, <D_F27F, >D_F27F, $00, $03, $00, $08, $00  ; $FBF2
        .byte   $00, $00, $04, $00, $00, $00, $00, $00          ; $FBFA
        .byte   $08, $41, $09, $49                              ; $FC02

sfx_params_22:
        .byte   $09, $1E                                         ; $FC06
sfx_instr_16:                       ; $FC08
        .byte   $3C, $00, $EC, $FF, $FB, $FF                    ; $FC08
        .byte   $00, $00, $06, $12, $64, $00, $01, $04          ; $FC0E
        .byte   $B0, $04                                        ; $FC16

sfx_params_23:
sfx_instr_17:                       ; $FC18
        .byte   $EE, $02, $ED, $FE, $E7, $FF, $00, $00          ; $FC18
        .byte   $01, $03, $04, $00, $02, $04, $E8, $03          ; $FC20
sfx_instr_18:                       ; $FC28
        .byte   $D8, $FF, $00, $00, $00, $00, $00, $00          ; $FC28
        .byte   $08, $00, $00, $00, $06, $04                    ; $FC30

sfx_params_24:
        .byte   $0E, $06                                         ; $FC36
sfx_instr_19:                       ; $FC38
        .byte   $C8, $00, $9C, $FF, $E7, $FF                    ; $FC38
        .byte   $32, $00, $01, $04, $04, $04, $01, $05          ; $FC3E
        .byte   $78, $05                                         ; $FC46
sfx_instr_20:                       ; $FC48
        .byte   $D8, $FF, $28, $00, $D8, $FF                    ; $FC48
        .byte   $00, $00, $03, $06, $03, $00                    ; $FC4E

sfx_params_25:
        .byte   $02, $05                                         ; $FC54
sfx_instr_21:                           ; $FC56
        .byte   $00, $00, $00, $00, $01, $00          ; $FC56
        .byte   $02, $00, <D_F25E, >D_F25E, $00, $03, $00, $0D  ; $FC5C
sfx_instr_22:                           ; $FC64
        .byte   $00, $00, $00, $00, $01, $00, $01, $00          ; $FC64
        .byte   <D_F286, >D_F286, $00, $03, $00, $0D            ; $FC6C
music_voice0_start:                 ; $FC72
        .byte   $60, $02                                         ; $FC72

; --- Music sequence data ($FC74-$FDFF) ---
music_sequence_data:
        .byte   $86                                              ; $FC74: copy instrument
        .byte   <sfx_instr_0, >sfx_instr_0                      ;   -> sfx_instr_0 ($FAAC)
        .byte   $88, $0C, $33, $02, $5F, $04, $33, $04, $32, $02, $30, $04, $32                 ; $FC77
        .byte   $02, $33, $02, $35, $02, $2E, $06, $32, $04, $30, $06, $2B, $04, $2B, $02, $32 ; $FC84
        .byte   $04, $30, $07                                    ; $FC94
        .byte   $86                                              ; $FC97: copy instrument
        .byte   <sfx_instr_1, >sfx_instr_1                      ;   -> sfx_instr_1 ($FB3D)
        .byte   $29, $06, $2B, $06, $2D, $07, $88, $00          ; $FC9A
music_seq_voice0_alt:               ; $FCA2
        .byte   $98                                              ; $FCA2: silence/rest
music_voice1_start:                 ; $FCA3
        .byte   $60                                              ; $FCA3: end/stop
        .byte   $01                                              ; $FCA4
        .byte   $86                                              ; $FCA5: copy instrument
        .byte   <sfx_instr_2, >sfx_instr_2                      ;   -> sfx_instr_2 ($FBCE)
        .byte   $88, $0C, $8A, <D_F261, $80, $08, $2B, $02, $82, $8A, <D_F268, $80              ; $FCA8
        .byte   $08, $29, $02, $82, $8A, <D_F26F, $80, $08, $28, $02, $82, $8A, <D_F279, $29, $07, $29 ; $FCB4
        .byte   $06, $8A, <D_F265, $2B, $06, $2D, $07, $88, $00     ; $FCC4
music_seq_voice1_alt:               ; $FCCD
        .byte   $60, $01                                         ; $FCCD
        .byte   $86                                              ; $FCCF: copy instrument
        .byte   <sfx_instr_3, >sfx_instr_3                      ;   -> sfx_instr_3 ($FBEB)
music_seq_loop_a:                   ; $FCD2
        .byte   $94, <L_7060, >L_7060                            ; $FCD2: call subroutine -> L_7060
        .byte   $35, $02, $33, $02, $37, $02, $35, $02, $33, $01, $32, $03, $35, $06            ; $FCD5
        .byte   $94                                              ; $FCE3: call subroutine
        .byte   <music_seq_pattern_a, >music_seq_pattern_a       ;   -> music_seq_pattern_a ($FD27)
        .byte   $37, $03, $35, $02, $35, $02, $37, $02, $39, $02, $94, <L_7060, >L_7060, $35   ; $FCE6
        .byte   $01, $33, $03, $37, $02, $35, $02, $33, $01, $32, $03, $35, $06                 ; $FCF4
        .byte   $94                                              ; $FD01: call subroutine
        .byte   <music_seq_pattern_a, >music_seq_pattern_a       ;   -> music_seq_pattern_a ($FD27)
        .byte   $35, $03, $3A, $02                               ; $FD04
        .byte   $94                                              ; $FD08: call subroutine
        .byte   <music_seq_pattern_b, >music_seq_pattern_b       ;   -> music_seq_pattern_b ($FD42)
        .byte   $37, $06, $3E, $04, $3C, $0A                    ; $FD0B
        .byte   $94                                              ; $FD11: call subroutine
        .byte   <music_seq_pattern_b, >music_seq_pattern_b       ;   -> music_seq_pattern_b ($FD42)
        .byte   $35, $04, $3E, $02, $35, $02, $3E, $02, $3A, $0A, $35, $02, $37, $02, $39, $02 ; $FD14
        .byte   $96                                              ; $FD24: loop back
        .byte   <music_seq_loop_a, >music_seq_loop_a             ;   -> music_seq_loop_a ($FCD2)
music_seq_pattern_a:                ; $FD27
        .byte   $32, $01, $30, $01, $2E, $02, $30, $02, $32, $02, $33, $02, $30                 ; $FD27
        .byte   $02, $32, $01, $33, $03, $35, $02, $35, $02, $37, $02, $39, $01, $98            ; $FD34
music_seq_pattern_b:                ; $FD42
        .byte   $35, $02                                         ; $FD42
        .byte   $37, $02, $38, $02, $39, $02                    ; $FD44
        .byte   $86                                              ; $FD4A: copy instrument
        .byte   <sfx_instr_1, >sfx_instr_1                      ;   -> sfx_instr_1 ($FB3D)
        .byte   $41, $02, $43, $02, $44, $02, $45               ; $FD4D
        .byte   $02                                              ; $FD54
        .byte   $86                                              ; $FD55: copy instrument
        .byte   <sfx_instr_3, >sfx_instr_3                      ;   -> sfx_instr_3 ($FBEB)
        .byte   $35, $02, $37, $02, $39, $02, $3A, $02          ; $FD58
        .byte   $86                                              ; $FD60: copy instrument
        .byte   <sfx_instr_1, >sfx_instr_1                      ;   -> sfx_instr_1 ($FB3D)
        .byte   $41                                              ; $FD63
        .byte   $02, $43, $02, $45, $02, $46, $02               ; $FD64
        .byte   $86                                              ; $FD6B: copy instrument
        .byte   <sfx_instr_3, >sfx_instr_3                      ;   -> sfx_instr_3 ($FBEB)
        .byte   $35, $02, $37, $02, $39, $02                    ; $FD6E
        .byte   $3C, $02                                         ; $FD74
        .byte   $86                                              ; $FD76: copy instrument
        .byte   <sfx_instr_1, >sfx_instr_1                      ;   -> sfx_instr_1 ($FB3D)
        .byte   $41, $02, $43, $02, $45, $02, $48, $02          ; $FD79
        .byte   $86                                              ; $FD81: copy instrument
        .byte   <sfx_instr_3, >sfx_instr_3                      ;   -> sfx_instr_3 ($FBEB)
        .byte   $35, $02, $37, $02, $39, $02, $3E, $02          ; $FD84
        .byte   $86                                              ; $FD8C: copy instrument
        .byte   <sfx_instr_1, >sfx_instr_1                      ;   -> sfx_instr_1 ($FB3D)
        .byte   $41, $02, $43, $02, $45                          ; $FD8F
        .byte   $02, $4A, $02                                    ; $FD94
        .byte   $86                                              ; $FD97: copy instrument
        .byte   <sfx_instr_3, >sfx_instr_3                      ;   -> sfx_instr_3 ($FBEB)
        .byte   $3A, $02, $3C, $02, $3E, $02, $3F, $02, $3F, $04                                ; $FD9A
        .byte   $3F, $04, $3E, $02, $3C, $04, $3E, $0C, $3E, $04, $3C, $06, $98                 ; $FDA4
music_voice2_start:                 ; $FDB1
        .byte   $94, <L_7040, >L_7040                            ; $FDB1: call subroutine -> L_7040
        .byte   $1F, $10, $1D, $10, $1C, $10, $1D, $07, $1D, $06, $1F, $06, $21, $07, $60, $01 ; $FDB4
D_FDC4:                             ; $FDC4
        .byte   $94, <L_7048, >L_7048                            ; $FDC4: call subroutine -> L_7048
        .byte   $92, $00, <L_7058, >L_7058                      ; $FDC7: set param + call -> L_7058
        .byte   $92, $FD, <L_7058, >L_7058                      ; $FDCB: set param + call -> L_7058
        .byte   $92, $00, <L_7058, >L_7058                      ; $FDCF: set param + call -> L_7058
        .byte   $80                                              ; $FDD3
        .byte   $06, $13, $02, $1F, $02, $82, $16, $02          ; $FDD4
        .byte   $94                                              ; $FDDC: call subroutine
        .word   D_FE02                                           ;   -> D_FE02
        .byte   $13, $02, $1F, $02, $13                          ; $FDDF
        .byte   $02, $1F, $02                                    ; $FDE4
        .byte   $94                                              ; $FDE7: call subroutine
        .word   D_FE37                                           ;   -> D_FE37
        .byte   $18, $02                                         ; $FDE9
        .byte   $94                                              ; $FDEC: call subroutine
        .word   D_FE02                                           ;   -> D_FE02
        .byte   $11, $02, $18, $02, $11                          ; $FDEE
        .byte   $02, $18, $02, $16, $0A, $11, $02, $13, $02, $15, $02 ; $FDF3
        .byte   $96                                              ; $FDFF: loop back
; The $96 loop command at $FDFF reads these 2 bytes as its address operand.
D_FE00:
        .word   D_FDC4                                           ; -> D_FDC4 loop target

; ============================================================================
; SECTION 10: Music Continuation ($FE02-$FE8F)
; ============================================================================
; Continuation of music sequence data.
; ============================================================================

D_FE02:
    .byte $80, $02               ; $FE02
    .byte $11, $02               ; $FE04
    .byte $13, $02               ; $FE06
    .byte $14, $02               ; $FE08
    .byte $80, $02               ; $FE0A
    .byte $15, $02               ; $FE0C
    .byte $21, $02               ; $FE0E
    .byte $82                    ; $FE10
    .byte $15, $02               ; $FE11
    .byte $11, $02               ; $FE13
    .byte $13, $02               ; $FE15
    .byte $15, $02               ; $FE17
    .byte $80, $02               ; $FE19
    .byte $16, $02               ; $FE1B
    .byte $22, $02               ; $FE1D
    .byte $82                    ; $FE1F
    .byte $16, $02               ; $FE20
    .byte $82                    ; $FE22
    .byte $16, $02               ; $FE23
    .byte $18, $02               ; $FE25
    .byte $1A, $02               ; $FE27
    .byte $80, $04               ; $FE29
    .byte $1B, $02               ; $FE2B
    .byte $27, $02               ; $FE2D
    .byte $82                    ; $FE2F
    .byte $80, $04               ; $FE30
    .byte $1A, $02               ; $FE32
    .byte $26, $02               ; $FE34
    .byte $82                    ; $FE36
D_FE37:
    .byte $18, $02               ; $FE37
    .byte $24, $02               ; $FE39
    .byte $18, $02               ; $FE3B
    .byte $24, $02               ; $FE3D
    .byte $98                    ; $FE3F
D_FE40:
    .byte $60, $02               ; $FE40
    .byte $86                    ; $FE42
D_FE43:
    .byte <sfx_instr_1, >sfx_instr_1 ; $FE43: copy instrument -> sfx_instr_1 ($FB3D)
D_FE45:
    .byte $30, $02               ; $FE45
    .byte $34, $02               ; $FE47
    .byte $37, $02               ; $FE49
    .byte $3C, $02               ; $FE4B
    .byte $40, $02               ; $FE4D
    .byte $3C, $02               ; $FE4F
    .byte $37, $02               ; $FE51
    .byte $34, $02               ; $FE53
    .byte $32, $02               ; $FE55
    .byte $35, $02               ; $FE57
    .byte $39, $02               ; $FE59
    .byte $3E, $02               ; $FE5B
    .byte $41, $02               ; $FE5D
    .byte $3E, $02               ; $FE5F
    .byte $39, $02               ; $FE61
    .byte $35, $02               ; $FE63
    .byte $34, $02               ; $FE65
    .byte $37, $02               ; $FE67
    .byte $3B, $02               ; $FE69
    .byte $40, $02               ; $FE6B
    .byte $43, $02               ; $FE6D
    .byte $40, $02               ; $FE6F
    .byte $3B, $02               ; $FE71
    .byte $37, $02               ; $FE73
    .byte $32, $02               ; $FE75
    .byte $35, $02               ; $FE77
    .byte $39, $02               ; $FE79
    .byte $3E, $02               ; $FE7B
    .byte $41, $02               ; $FE7D
    .byte $3E, $02               ; $FE7F
    .byte $39, $02               ; $FE81
    .byte $35, $02               ; $FE83
    .byte $96                    ; $FE85
    .word D_FE45                 ; $FE86: loop target address (relocatable)
    .byte $EF, $FF               ; $FE88
    .byte $A6                    ; $FE8A
    .byte $5D, $FF               ; $FE8B
    .byte $FF, $EF               ; $FE8D
    .byte $FF                    ; $FE8F

; ============================================================================
; End of sound.s
; ============================================================================
