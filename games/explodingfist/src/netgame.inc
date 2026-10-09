; =============================================================================
; The Way of the Exploding Fist OME: settings for framework/c64/net/net.s
; =============================================================================

.define NET_LOBBY "FIST"                ; the lobby's file name on the disk
NET_WIC_SEND_EVERY = 4                  ; short ticks (~22 ms): a WiC64 sends every 4th
                                        ; (the server's inputDelayWiC64 is 4)
NET_TAIL = $C000                        ; net_end's last part (the fighter buffers;
                                        ; our code lies under the KERNAL)

; The state checksum (every 64 ticks): the zero page $34-$F8 (both fighters,
; the judge, the bout, the random generator $8E) and the score and time line
; at the top of the screen (the score only exists as screen digits). Not the
; IRQ's display and speech variables ($14-$33, with $24: which fighter is
; drawn in front, from the sprite collision), not the music driver's pointers
; ($F9-$FE, the music runs per frame). tools/dettest.py showed that everything
; else is identical on PAL, NTSC and with whole frames of jitter.
.define NET_CK_START $0034, $CC00
.define NET_CK_LEN   $C5,   $50
