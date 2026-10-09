# rebb64

**Reverse Engineered Bubble Bobble for Commodore 64**

A complete reverse-engineering of **Bubble Bobble** on the Commodore 64, producing fully documented, reassembleable source code.

## Status

All executable code has been reverse engineered and converted to documented 6502 assembly. The source assembles to a binary **100% identical** to the original game.

**Remaining work:** Convert hardcoded addresses to labels so the assembler can recalculate addresses when code is added or removed.

## Building

### Requirements

- **cc65** - 6502 cross-compiler suite
  - Fedora/RHEL: `sudo dnf install cc65`
  - Debian/Ubuntu: `sudo apt install cc65`
  - macOS: `brew install cc65`

### Build Commands

```bash
cd build
make              # Build the game
make verify       # Build and verify against original
make clean        # Clean build artifacts
```

### Running the Game

The default build produces a raw memory image (`rebb64-raw.prg`) that loads at $0400. This is the decompressed game data without a startup stub, so it won't auto-run directly. The entry point is at $4830.

To create a runnable PRG, use [TSCrunch](https://github.com/tonysavon/TSCrunch) (prebuilt binaries available):

```bash
make release    # requires tscrunch in PATH, outputs rebb64.prg
```

Or manually:
```bash
tscrunch -p -x '$4830' rebb64-raw.prg rebb64.prg
```

## Making Modifications

### Simple Value Changes

Edit `src/master.s` and change values:

```asm
; Change starting lives from 4 to 9:
starting_lives:
        lda     #$09                ; was #$04
```

### Replacing Instructions

Replace instructions with same byte count:

```asm
; Infinite lives - replace 3-byte DEC with 3 NOPs:
lives_decrement:
        nop                         ; ea (was: dec D_045A,x)
        nop                         ; ea
        nop                         ; ea
```

### Adding New Code

**Note:** There is currently no free space in the game binary. The memory region $8B00-$8EFF (previously documented as free) is actively used as a screen buffer and is overwritten every time a level starts.

For larger modifications, you have two options:

1. **Replace existing code** with your custom routine (maintaining exact byte count)
2. **Use the cassette buffer** at $033C-$03FB (192 bytes) which is unused during gameplay:

```asm
; Replace original instruction with JSR to your code:
lives_decrement:
        jsr     custom_lives_handler

; Add your code in cassette buffer (unused during gameplay):
.org $033C
custom_lives_handler:
        lda     cheat_flag
        bne     @skip
        dec     D_045A,x
@skip:  rts
```

**Warning:** The cassette buffer ($033C) may be used during disk/tape operations. Test thoroughly.

### Modifying Graphics and Audio

Graphics and audio are in separate binary files for easy editing:

| File | Address | Size | Description |
|------|---------|------|-------------|
| `data/charset.bin` | $4000-$47FF | 2KB | Character set (256 chars) |
| `data/sprites1.bin` | $5800-$5FFF | 2KB | Player/enemy sprites |
| `data/sprites2.bin` | $8000-$9FFF | 8KB | Animation frames |
| `data/level-data.bin` | $6000-$7FFF | 8KB | Level layouts |
| `data/music-tables.bin` | $F240-$F2C3 | 132B | Music data tables |
| `data/music-freqs.bin` | $F39C-$F4BB | 288B | Note frequency tables |
| `data/sfx-music.bin` | $F900-$FDFF | 1.2KB | Sound effects & music |

Edit with: SpritePad, CharPad, or hex editor. Rebuild to see changes.

### Current Constraints

Modified code must produce **exactly the same byte count** until full label conversion is complete. Adding/removing bytes will break absolute addresses. Graphics files can be freely modified (fixed-size).

## Patch Points

These locations are labeled for easy modification:

| Label | Address | Description |
|-------|---------|-------------|
| `lives_p1` | $045A | Player 1 lives counter |
| `lives_p2` | $045B | Player 2 lives counter |
| `lives_decrement` | $04D8 | Where lives are decremented (NOP for infinite) |
| `starting_lives` | $0537 | Initial lives value (default: 4) |

## Directory Structure

```
rebb64/
├── README.md
├── docs/
│   └── TECHNICAL.md         # Detailed technical documentation
├── src/
│   ├── master.s             # Main source file
│   ├── loadaddr.s           # PRG load address header
│   └── *.s                  # Game modules (25 files)
├── data/
│   └── *.bin                # Graphics, music, level data
└── build/
    ├── Makefile
    └── c64-prg.cfg
```

## Verification

Build is verified against SHA256 of the original decompressed PRG:
```
fdba2390782653ba2533b2d87c44c8f0480ab18968a2c0ccc0cef8300fcee7b6
```

## Documentation

See [docs/TECHNICAL.md](docs/TECHNICAL.md) for:
- Complete memory map
- Key game routines reference
- Detailed module documentation
- Algorithm explanations

## License

This is a reverse-engineering project for educational purposes. Bubble Bobble is Copyright (c) 1986 Taito Corporation. C64 version by Firebird Software.

## Credits

- Original game: Taito Corporation
- C64 conversion: Software Creations (Stephen Ruddy), published by Firebird Software
- Reverse engineering: This project
