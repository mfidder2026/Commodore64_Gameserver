; =============================================================================
; Pitstop II OME: settings for framework/c64/net/net.s
; =============================================================================

.define NET_LOBBY "PITSTOP"             ; the lobby's file name on the disk
NET_WIC_SEND_EVERY = 2                  ; a tick is a drawing pass (~2 frames)
NET_TAIL = $C000                        ; net_end's last part (a screen of the race,
                                        ; not needed after it)

; The state checksum (every 64 ticks): the race state the logic and the main
; loop write (zero page $24-$EC, the tables $0380-$039F and $61D0-$6226).
; Not what the display IRQ writes ($27, $6200-$6204, $6207: sprite drawing;
; $E4: our frame counter): tools/dettest.py showed that the rest is identical
; on PAL, NTSC and with whole frames of jitter. The checksum is taken at the
; start of car 0's logic slot.
.define NET_CK_START $0024, $0028, $00E6, $0380, $61D0, $6205, $6208
.define NET_CK_LEN   3,     188,   7,     $20,   $30,   2,     $1F
