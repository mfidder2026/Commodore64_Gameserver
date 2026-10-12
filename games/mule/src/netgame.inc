; =============================================================================
; M.U.L.E. OME: settings for framework/c64/net/net.s
; =============================================================================

.define NET_LOBBY "MULE"                ; the lobby's file name on the disk
NET_PLAYERS = 4                         ; up to four players: slots 0-3 are the
                                        ; colonists 0-3 (the rest the computer's)
NET_WIC_SEND_EVERY = 2
NET_SPLIT = 1                           ; the game has no 1.3 KB in one piece
NET_TAIL = $C000                        ; net_end's last part: game code, not
                                        ; needed after the session (not the
                                        ; screen: the KERNAL's CINT clears it)

; The state checksum (every 64 ticks): the zero page without the raster IRQ
; handlers' own bytes ($1C/$1D saved registers, $29 the step of the screen
; split), and the game's tables $E000-$E3FF (players, plots, the store).
; tools/dettest.py showed that the rest is identical on PAL, NTSC and with
; whole frames of jitter.
.define NET_CK_START $0002, $001E, $002A, $E000, $E100, $E200, $E300
.define NET_CK_LEN   $1A,   $0B,   $D6,   0,     0,     0,     0
