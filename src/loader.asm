;============================================================
;
; NET: PRG LOADER
;
; Packs the RAM based build of the game (TARGET_PRG=1, an
; image starting at $8000) into a single PRG with a BASIC line,
; so it can be started with RUN, from the Ultimate menu or
; with VICE autostart.
;
; The loader copies the image to $8000, switches the BASIC ROM
; off and starts the game through the cartridge style boot
; vector at the beginning of the image.
;
; build: see tools/build.py
;
;============================================================


	GAME_BASE = $8000
	GAME_END = $D000 ; the image may use the RAM up to the I/O area
	MEMCFG_NORMAL = $36 ; RAM / RAM / RAM / IO / KERNAL - must match wizard_of_wor.asm

	src_ptr = $fb
	dst_ptr = $fd

	* = $0801

	; BASIC line: 10 SYS start
	.word +, 10
	.null $9e, format("%d", start)
+	.word 0

start
	SEI
	LDA #<payload
	STA src_ptr
	LDA #>payload
	STA src_ptr+1
	LDA #<GAME_BASE
	STA dst_ptr
	LDA #>GAME_BASE
	STA dst_ptr+1

	; the payload is below $8000, so source and destination never overlap
	; writes to $A000-$BFFF always reach the RAM, even with the BASIC ROM visible
	LDX #(payload_end - payload + 255) / 256
	LDY #$00
-	LDA (src_ptr),Y
	STA (dst_ptr),Y
	INY
	BNE -
	INC src_ptr+1
	INC dst_ptr+1
	DEX
	BNE -

	LDA #MEMCFG_NORMAL
	STA $01
	; the game starts with a cartridge header: boot vector, NMI vector, "CBM80"
	JMP (GAME_BASE)

payload
	.binary "../build/wow_payload.bin" ; relative to this file
payload_end
	.cerror payload_end - payload > GAME_END - GAME_BASE, "payload does not fit below $D000"
	.cerror payload_end + 255 > GAME_BASE, "payload overlaps its own destination"
