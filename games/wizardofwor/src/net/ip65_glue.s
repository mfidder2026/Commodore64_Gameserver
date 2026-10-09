;============================================================
;
; NET: ip65 GLUE (ca65 syntax - this file is assembled with cc65's ca65, not 64tass)
;
; Builds a self contained "blob" of the ip65 UDP stack with the
; RR-Net (CS8900a) driver, for VICE (and real RR-Net hardware).
; The 64tass code calls it through the jump table below; the
; addresses of the variables come from a generated include file
; (tools/build.py turns the ld65 label file into 64tass labels).
;
; Replaces two ip65 platform modules:
; - timer: ip65's C64 timer reprograms CIA2 timer A/B; here we
;   share the free running 32 bit cycle counter on CIA2 (timer A
;   counts cycles from $FFFF, timer B counts its underflows)
; - abort key: ip65 reads the KERNAL keyboard variables, which
;   the game uses for its own data; never abort here
;
; Zero page: ptr1-4, tmp1-4 and sreg are placed by the linker
; config (ZP memory area), so the blob can be linked for the game
; ($EA-$FF, unused by the game) or for a KERNAL/BASIC program.
;
;============================================================

        .exportzp ptr1, ptr2, ptr3, ptr4, tmp1, tmp2, tmp3, tmp4, sreg
        .export timer_init, timer_read, timer_seconds
        .export check_for_abort_key
        .exportzp abort_key_disable

        .import ip65_init, ip65_process
        .import dhcp_init
        .import udp_add_listener, udp_remove_listener, udp_send, udp_callback
        .import udp_inp, ip_inp
        .importzp udp_data, udp_len, udp_src_port, ip_src
        .import _cs8900a

        .export glue_rx_buf, glue_rx_len, glue_rx_ready, glue_rx_ip, glue_rx_port

GLUE_RX_MAX = 128

;------------------------------------------------------------
        .segment "JUMPTABLE"
;------------------------------------------------------------
        jmp glue_init           ; +0  A = last byte of the MAC address; C=1: no RR-Net found
        jmp dhcp_init           ; +3  C=1: no DHCP answer (blocks for a few seconds)
        jmp ip65_process        ; +6  call often; handles one inbound frame if there is one
        jmp glue_listen         ; +9  A/X = UDP port to receive on (into glue_rx_buf)
        jmp glue_send           ; +12 A/X = data; udp_send_dest/_dest_port/_src_port/_len must be set; C=1: failed (ARP still pending)
        jmp glue_unlisten       ; +15 A/X = UDP port

;------------------------------------------------------------
        .zeropage
;------------------------------------------------------------
ptr1:   .res 2
ptr2:   .res 2
ptr3:   .res 2
ptr4:   .res 2
tmp1:   .res 1
tmp2:   .res 1
tmp3:   .res 1
tmp4:   .res 1
sreg:   .res 2
abort_key_disable: .res 1

;------------------------------------------------------------
        .bss
;------------------------------------------------------------
glue_rx_ready:  .res 1          ; set to 1 when a datagram arrived, the 64tass side clears it
glue_rx_len:    .res 1          ; payload length (clipped to GLUE_RX_MAX)
glue_rx_ip:     .res 4          ; sender
glue_rx_port:   .res 2          ; sender's source port (little endian)
glue_rx_buf:    .res GLUE_RX_MAX

;------------------------------------------------------------
        .code
;------------------------------------------------------------

glue_init:
        ; byte 4+5 of the driver module is the last MAC byte (signature 3, version 1, then 6 MAC bytes)
        sta _cs8900a + 4 + 5
        lda #0
        sta glue_rx_ready
        sta abort_key_disable
        lda #0                  ; eth_init_default on the C64 (from ip65's c64init.s)
        jmp ip65_init

glue_listen:
        pha
        lda #<udp_rx
        sta udp_callback
        lda #>udp_rx
        sta udp_callback + 1
        pla
        jmp udp_add_listener

glue_unlisten:
        jmp udp_remove_listener

glue_send:
        jmp udp_send

; udp callback: copy the datagram (a newer one overwrites an unread older one)
udp_rx:
        ; length in the UDP header is big endian and includes the 8 byte header
        lda udp_inp + udp_len + 1
        sec
        sbc #8
        tay
        lda udp_inp + udp_len
        sbc #0
        beq :+
        ldy #GLUE_RX_MAX        ; longer than 255: clip
:       cpy #GLUE_RX_MAX
        bcc :+
        ldy #GLUE_RX_MAX
:       sty glue_rx_len
        ldx #0
:       cpx glue_rx_len
        beq :+
        lda udp_inp + udp_data,x
        sta glue_rx_buf,x
        inx
        bne :-
:       ldx #3
:       lda ip_inp + ip_src,x
        sta glue_rx_ip,x
        dex
        bpl :-
        lda udp_inp + udp_src_port + 1
        sta glue_rx_port
        lda udp_inp + udp_src_port
        sta glue_rx_port + 1
        lda #1
        sta glue_rx_ready
        rts

;------------------------------------------------------------
; platform: timer
;------------------------------------------------------------

timer_init:
        ; make sure the shared 32 bit cycle counter on CIA2 is running (same setup as the 64tass side)
        lda $dd0e
        and #$01
        bne :+
        lda #$7f                ; no CIA2 interrupts
        sta $dd0d
        lda #$ff
        sta $dd04
        sta $dd05
        sta $dd06
        sta $dd07
        lda #%01010001          ; timer B counts underflows of timer A, force load, start
        sta $dd0f
        lda #%00010001          ; timer A counts cycles, force load, start
        sta $dd0e
:       lda #0                  ; start the TOD clock of CIA1 (timer_seconds)
        sta $dc08
        sta $dc09
        rts

; AX = milliseconds (approximately: cycles / 1024)
timer_read:
:       lda $dd06               ; timer B low
        sta tmp1
        lda $dd05               ; timer A high
        sta tmp2
        lda $dd07               ; timer B high
        sta tmp3
        lda $dd06
        cmp tmp1
        bne :-                  ; timer A wrapped in between: read again
        ; counting up = inverted; ms = bits 10..25 of the counter
        lda tmp2
        eor #$ff
        lsr a
        lsr a                   ; bits 10-15 -> 0-5
        sta tmp2
        lda tmp1
        eor #$ff
        sta tmp1                ; timer B low = bits 16-23
        asl a
        asl a
        asl a
        asl a
        asl a
        asl a                   ; bits 16-17 -> 6-7
        ora tmp2
        pha
        lda tmp1
        lsr a
        lsr a                   ; bits 18-23 -> 0-5
        sta tmp1
        lda tmp3
        eor #$ff
        asl a
        asl a
        asl a
        asl a
        asl a
        asl a                   ; bits 24-25 -> 6-7
        ora tmp1
        tax
        pla
        rts

timer_seconds:
        lda $dc09
        rts

;------------------------------------------------------------
; platform: abort key
;------------------------------------------------------------

check_for_abort_key:
        clc                     ; never abort (blocking calls have their own timeouts)
        rts
