; -----------------------------------------------------------------------------
; bb-player-movement.s
; Player movement, position updates, and animation handlers
; Address range: $26BF - $284C (398 bytes)
; -----------------------------------------------------------------------------

; Entry point: $26BF - Player horizontal movement handler
.segment "CODE_PHYSICS"

L_26BF:
        lda  D_87F0,x               ; bd f0 87     $26bf
        bne  L_26D9                 ; d0 15        $26c2
        lda  D_87A0,x               ; bd a0 87     $26c4
        clc                         ; 18           $26c7
        adc  FA,x                   ; 75 ba        $26c8
        sta  FA,x                   ; 95 ba        $26ca
        cmp  #$f4                   ; c9 f4        $26cc
        bcc  L_26EC                 ; 90 1c        $26ce
        lda  #$f4                   ; a9 f4        $26d0
        sta  FA,x                   ; 95 ba        $26d2
        inc  D_87F0,x               ; fe f0 87     $26d4
        bne  L_26EC                 ; d0 13        $26d7
L_26D9:
        lda  FA,x                   ; b5 ba        $26d9
        sec                         ; 38           $26db
        sbc  D_87A0,x               ; fd a0 87     $26dc
        sta  FA,x                   ; 95 ba        $26df
        cmp  #$24                   ; c9 24        $26e1
        bcs  L_26EC                 ; b0 07        $26e3
        lda  #$24                   ; a9 24        $26e5
        sta  FA,x                   ; 95 ba        $26e7
        dec  D_87F0,x               ; de f0 87     $26e9
L_26EC:
        lda  D_87C8,x               ; bd c8 87     $26ec
        bmi  L_2703                 ; 30 12        $26ef
        lda  ZP_C2,x                ; b5 c2        $26f1
        sec                         ; 38           $26f3
        sbc  D_8868,x               ; fd 68 88     $26f4
        sta  ZP_C2,x                ; 95 c2        $26f7
        cmp  #$15                   ; c9 15        $26f9
        bcs  L_2713                 ; b0 16        $26fb
        lda  #$f5                   ; a9 f5        $26fd
        sta  ZP_C2,x                ; 95 c2        $26ff
        bne  L_2713                 ; d0 10        $2701
L_2703:
        lda  D_8868,x               ; bd 68 88     $2703
        clc                         ; 18           $2706
        adc  ZP_C2,x                ; 75 c2        $2707
        sta  ZP_C2,x                ; 95 c2        $2709
        cmp  #$f5                   ; c9 f5        $270b
        bcc  L_2713                 ; 90 04        $270d
        lda  #$15                   ; a9 15        $270f
        sta  ZP_C2,x                ; 95 c2        $2711
L_2713:
        inc  D_85E8,x               ; fe e8 85     $2713
        lda  D_85E8,x               ; bd e8 85     $2716
        lsr                         ; 4a           $2719
        lsr                         ; 4a           $271a
        and  #$03                   ; 29 03        $271b
        beq  L_2726                 ; f0 07        $271d
        ldy  D_8840,x               ; bc 40 88     $271f
        clc                         ; 18           $2722
        adc  D_AB89,y               ; 79 89 ab     $2723
L_2726:
        sta  D_8520,x               ; 9d 20 85     $2726
        lda  #$00                   ; a9 00        $2729
        sta  D_8728,x               ; 9d 28 87     $272b
        rts                         ; 60           $272e

; Entry point: $272F - Self-modifying code wrapper for vertical movement
D_272F:
        lda  #$60                   ; a9 60        $272f
        sta  D_2782                 ; 8d 82 27     $2731
        jsr  D_273D                 ; 20 3d 27     $2734
        lda  #$4c                   ; a9 4c        $2737
        sta  D_2782                 ; 8d 82 27     $2739
        rts                         ; 60           $273c

; Entry point: $273D - Vertical position update with collision detection
D_273D:
        lda  ZP_C2,x                ; b5 c2        $273d
        clc                         ; 18           $273f
        adc  #$02                   ; 69 02        $2740
        sta  ZP_C2,x                ; 95 c2        $2742
        cmp  #$f5                   ; c9 f5        $2744
        bne  L_274C                 ; d0 04        $2746
        lda  #$15                   ; a9 15        $2748
        sta  ZP_C2,x                ; 95 c2        $274a
L_274C:
        cmp  #$1f                   ; c9 1f        $274c
        bcc  D_2782                 ; 90 32        $274e
        sbc  #$2d                   ; e9 2d        $2750
        and  #$07                   ; 29 07        $2752
        bne  D_2782                 ; d0 2c        $2754
        ldy  #$51                   ; a0 51        $2756
        lda  (INPFLG),y             ; b1 11        $2758
        bmi  D_2782                 ; 30 26        $275a
        iny                         ; c8           $275c
        lda  (INPFLG),y             ; b1 11        $275d
        bmi  D_2782                 ; 30 21        $275f
        lda  $23                    ; a5 23        $2761
        beq  L_276A                 ; f0 05        $2763
        iny                         ; c8           $2765
        lda  (INPFLG),y             ; b1 11        $2766
        bmi  D_2782                 ; 30 18        $2768
L_276A:
        ldy  #$79                   ; a0 79        $276a
        lda  (INPFLG),y             ; b1 11        $276c
D_276E:
        bmi  L_277E                 ; 30 0e        $276e
        iny                         ; c8           $2770
        lda  (INPFLG),y             ; b1 11        $2771
        bmi  L_277E                 ; 30 09        $2773
        lda  $23                    ; a5 23        $2775
        beq  D_2782                 ; f0 09        $2777
        iny                         ; c8           $2779
        lda  (INPFLG),y             ; b1 11        $277a
        bpl  D_2782                 ; 10 04        $277c
L_277E:
        lda  #$11                   ; a9 11        $277e
D_277F := * - 1                     ; SMC: operand byte
        sta  ENESSION,x             ; 95 b2        $2780
D_2782:
        jmp  L_2713                 ; 4c 13 27     $2782

; Continued movement and collision routines
D_2785:
        lda  #$0e                   ; a9 0e        $2785
        sta  D_8548,x               ; 9d 48 85     $2787
        ldy  #$29                   ; a0 29        $278a
        lda  (INPFLG),y             ; b1 11        $278c
        bmi  L_27B2                 ; 30 22        $278e
        iny                         ; c8           $2790
        lda  (INPFLG),y             ; b1 11        $2791
        bmi  L_27B2                 ; 30 1d        $2793
        lda  $23                    ; a5 23        $2795
        beq  L_279E                 ; f0 05        $2797
        iny                         ; c8           $2799
        lda  (INPFLG),y             ; b1 11        $279a
        bmi  L_27B2                 ; 30 14        $279c
L_279E:
        ldy  #$51                   ; a0 51        $279e
        lda  (INPFLG),y             ; b1 11        $27a0
        bmi  L_27C7                 ; 30 23        $27a2
        iny                         ; c8           $27a4
        lda  (INPFLG),y             ; b1 11        $27a5
        bmi  L_27C7                 ; 30 1e        $27a7
        lda  $23                    ; a5 23        $27a9
        beq  L_27B2                 ; f0 05        $27ab
        iny                         ; c8           $27ad
        lda  (INPFLG),y             ; b1 11        $27ae
        bpl  L_27B2                 ; 10 00        $27b0
L_27B2:
        lda  FA,x                   ; b5 ba        $27b2
        and  #$fe                   ; 29 fe        $27b4
        sta  FA,x                   ; 95 ba        $27b6
        lda  ZP_C2,x                ; b5 c2        $27b8
        ora  #$01                   ; 09 01        $27ba
        sta  ZP_C2,x                ; 95 c2        $27bc
        jsr  D_272F                 ; 20 2f 27     $27be
        lda  ENESSION,x             ; b5 b2        $27c1
        cmp  #$11                   ; c9 11        $27c3
        bne  L_27CB                 ; d0 04        $27c5
L_27C7:
        lda  #$17                   ; a9 17        $27c7
        sta  ENESSION,x             ; 95 b2        $27c9
L_27CB:
        ldy  #$01                   ; a0 01        $27cb
L_27CD:
        lda  a:ESSION,y             ; b9 b2 00     $27cd
        beq  L_2804                 ; f0 32        $27d0
        lda  FA,x                   ; b5 ba        $27d2
        sec                         ; 38           $27d4
        sbc  a:FA,y                 ; f9 ba 00     $27d5
        bcs  L_27DE                 ; b0 04        $27d8
        eor  #$ff                   ; 49 ff        $27da
        adc  #$01                   ; 69 01        $27dc
L_27DE:
        cmp  #$10                   ; c9 10        $27de
        bcs  L_2804                 ; b0 22        $27e0
        lda  ZP_C2,x                ; b5 c2        $27e2
        sec                         ; 38           $27e4
        sbc  a:ZP_C2,y              ; f9 c2 00     $27e5
        bcs  L_27EE                 ; b0 04        $27e8
        eor  #$ff                   ; 49 ff        $27ea
        adc  #$01                   ; 69 01        $27ec
L_27EE:
        cmp  #$10                   ; c9 10        $27ee
        bcs  L_2804                 ; b0 12        $27f0
        lda  D_87A0,x               ; bd a0 87     $27f2
        sta  ENESSION,x             ; 95 b2        $27f5
        dex                         ; ca           $27f7
        dex                         ; ca           $27f8
        jsr  D_1A6F                 ; 20 6f 1a     $27f9
        ldx  INDEX1                 ; a6 22        $27fc
        lda  #$0a                   ; a9 0a        $27fe
D_2800:
        sta  D_8890,x               ; 9d 90 88     $2800
        rts                         ; 60           $2803
L_2804:
        dey                         ; 88           $2804
        bpl  L_27CD                 ; 10 c6        $2805
        rts                         ; 60           $2807

; More movement handlers
D_2808:
        lda  D_87A0,x               ; bd a0 87     $2808
        sta  D_277F                 ; 8d 7f 27     $280b
        jsr  D_1E87                 ; 20 87 1e     $280e
        jsr  D_272F                 ; 20 2f 27     $2811
        lda  #$11                   ; a9 11        $2814
        sta  D_277F                 ; 8d 7f 27     $2816
        lda  ENESSION,x             ; b5 b2        $2819
        cmp  #$0a                   ; c9 0a        $281b
        beq  L_284C                 ; f0 2d        $281d
        cmp  #$09                   ; c9 09        $281f
        bne  L_282E                 ; d0 0b        $2821
        lda  FA,x                   ; b5 ba        $2823
        sec                         ; 38           $2825
        sbc  #$14                   ; e9 14        $2826
        and  #$fc                   ; 29 fc        $2828
        adc  #$13                   ; 69 13        $282a
        sta  FA,x                   ; 95 ba        $282c
L_282E:
        lda  #$24                   ; a9 24        $282e
        cmp  FA,x                   ; d5 ba        $2830
        bcc  L_2836                 ; 90 02        $2832
        sta  FA,x                   ; 95 ba        $2834
L_2836:
        lda  #$f4                   ; a9 f4        $2836
        cmp  FA,x                   ; d5 ba        $2838
        bcs  D_283E                 ; b0 02        $283a
        sta  FA,x                   ; 95 ba        $283c
D_283E:
        lda  #$ff                   ; a9 ff        $283e
        sta  D_87A0,x               ; 9d a0 87     $2840
        sta  D_87C8,x               ; 9d c8 87     $2843
        sta  D_87F0,x               ; 9d f0 87     $2846
        sta  D_8818,x               ; 9d 18 88     $2849
L_284C:
        rts                         ; 60           $284c
