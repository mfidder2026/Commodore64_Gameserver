; =============================================================================
; Spy vs Spy OME: settings for framework/c64/net/net.s
; =============================================================================

.define NET_LOBBY "SPYVSSPY"            ; the lobby's file name on the disk
NET_WIC_SEND_EVERY = 2
NET_BOT_PERSON = 1                      ; the test bot moves like a person
NET_TAIL = $C984                        ; net_end's last part: the copy of
                                        ; $0200-$03FF, not needed after the start

; The state checksum (every 64 ticks): the game's variables in the zero page
; and at $0200-$02FF, and the rooms' objects ($EA00), without what the IRQ
; owns (its work bytes $29-$40, the sound $67/$68, the flash $8B/$8C, a blink
; $0258/$0259, the music $0263-$0281). tools/dettest.py showed that the rest
; is identical on PAL, NTSC and with whole frames of jitter.
.define NET_CK_START $0002, $0041, $0069, $008D, $0200, $025A, $0282, $EA00
.define NET_CK_LEN   $27,   $26,   $22,   $73,   $58,   $09,   $7E,   $42
