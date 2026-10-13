; =============================================================================
; Archon OME: settings for framework/c64/net/net.s
; =============================================================================

.define NET_LOBBY "ARCHON"              ; the lobby's file name on the disk
NET_WIC_SEND_EVERY = 2
NET_BOT_PERSON = 1                      ; the test bot moves icons (a direction, the button)
NET_TAIL = $C000                        ; net_end's last part: the copy of low
                                        ; memory, not needed after the start

; The state checksum (every 64 ticks): the zero page and the game's variables
; $BCC0-$BFFF (the board, the icons, the battle). tools/dettest.py showed that
; all of it is identical on PAL, NTSC and with whole frames of jitter.
.define NET_CK_START $0002, $00FF, $BCC0, $BDC0, $BEC0, $BFC0
.define NET_CK_LEN   $FD,   1,     0,     0,     0,     $40
