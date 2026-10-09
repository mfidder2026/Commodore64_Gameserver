;============================================================
;
; NET: PRG LOADER
;
; Packs the RAM based build of the game (TARGET_PRG=1) into a
; single PRG with a BASIC line, so it can be started with RUN,
; from the Ultimate menu or with VICE autostart.
;
; The image starts at $4000 (network code and ip65), contains
; the original game at $8000-$BFFF and the tick / hook code
; from $C000. The loader copies it into place, switches the
; BASIC ROM off and jumps to NET_ENTRY (network setup menu,
; which starts the game).
;
; The image is loaded at $0801+ and copied to $4000+: the
; areas overlap and the destination is higher, so the copy
; runs backwards, from the last byte to the first.
;
; build: see tools/build.py
;
;============================================================

	IMAGE_BASE = $4000
	IMAGE_END = $D000 ; the image may use the RAM up to the I/O area
	NET_ENTRY = $5D00 ; must match src/net/netgame.asm
	MEMCFG_NORMAL = $36 ; RAM / RAM / RAM / IO / KERNAL - must match wizard_of_wor.asm

	src_ptr = $fb
	dst_ptr = $fd

	* = $0801

	; BASIC line: 10 SYS start
	.word +, 10
	.null $9e, format("%d", start)
+	.word 0

	PAGES = (payload_end - payload + 255) / 256

start
	SEI
	; start with the last page of source and destination
	LDA #<(payload + (PAGES - 1) * 256)
	STA src_ptr
	LDA #>(payload + (PAGES - 1) * 256)
	STA src_ptr+1
	LDA #<(IMAGE_BASE + (PAGES - 1) * 256)
	STA dst_ptr
	LDA #>(IMAGE_BASE + (PAGES - 1) * 256)
	STA dst_ptr+1

	; writes to $A000-$BFFF always reach the RAM, even with the BASIC ROM visible
	LDX #PAGES
_page	LDY #$FF
-	LDA (src_ptr),Y
	STA (dst_ptr),Y
	DEY
	CPY #$FF
	BNE -
	DEC src_ptr+1
	DEC dst_ptr+1
	DEX
	BNE _page

	LDA #MEMCFG_NORMAL
	STA $01
	JMP NET_ENTRY

payload
	.binary "../build/wow_payload.bin" ; relative to this file
payload_end
	.cerror IMAGE_BASE + PAGES * 256 > IMAGE_END, "the image does not fit below $D000"
	.cerror payload_end > $A000, "the loaded PRG must end below the BASIC ROM"
	.cerror IMAGE_BASE < payload, "the copy runs backwards, so the destination must be above the source"
