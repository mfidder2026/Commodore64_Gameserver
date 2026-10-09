# Technical Documentation

Detailed technical documentation for the Bubble Bobble C64 reverse engineering project.

## Memory Map

```
$0400-$07FF  Game variables, score data, player state
$0800-$0FFF  Game logic: main loop, collision detection, enemy AI
$1000-$1FFF  Level handling, bubble mechanics
$2000-$3FFF  Graphics routines, screen updates
$4000-$47FF  Character set (fonts, shadows, fire/water animations)
$4800-$57FF  Screen buffers, sprite pointers
$5800-$5FFF  Sprite data block 1 (player, enemies)
$6000-$7FFF  Level data and game code
$7440-$7FFF  Additional sprite data (player in bubble, boss sprites)
$8000-$8FFF  Character data (bubble animations, Baron Von Blubba)
$8F00-$9FFF  Character data continued (special bubbles, items, weapons)
$A000-$AFFF  Sprite data (bonus items), item/monster data tables
$B000-$CFFF  Level/graphics data tables (platforms, bitmaps, metadata)
$D000-$DFFF  (I/O area - banked out when needed)
$E000-$EFFF  Game routines, input handling
$F000-$FFFF  Sound/music routines, IRQ handlers
```

## Source File Organization

| Address Range | File | Description |
|---------------|------|-------------|
| $0400-$078B | master.s | Game variables, player state, IRQ handler |
| $078C-$08E3 | sprites-init.s | Sprite management, game initialization |
| $08E4-$0AAA | game-loop.s | Game start sequence, main loop |
| $0AAB-$0CF1 | collision.s | Collision detection, enemy spawning |
| $0CF2-$10D2 | enemy-ai.s | Enemy AI update and movement |
| $10D3-$12FF | special-enemies.s | Special enemy behaviors |
| $1300-$1577 | player-sprites.s | Player sprite updates |
| $1578-$1804 | bubbles-sprites.s | Bubble physics and capture |
| $1805-$1A6E | render-screen.s | Screen rendering |
| $1A6F-$1CA0 | level-complete.s | Level completion handling |
| $1CA1-$1E2D | joystick-input.s | Input handling |
| $1E2E-$2161 | player-animation.s | Player animation |
| $2162-$272E | entity-interaction.s | Entity interactions |
| $272F-$2899 | player-movement.s | Player movement |
| $289A-$29BB | spawn-handlers.s | Spawn point management |
| $29BC-$2A3E | item-collision.s | Item pickup collision |
| $2A3F-$2B30 | super-bonus.s | Super bonus handling |
| $2B31-$2D64 | level-setup.s | Level initialization |
| $2D65-$2F5E | special-item-effects.s | Special item effects |
| $2F5F-$2FAB | level-transition.s | Level transitions |
| $2FAC-$3168 | level-start.s | Level start sequence |
| $3169-$32C0 | platform-collision.s | Platform collision |
| $32C1-$3489 | extend-bonus.s | EXTEND bonus system |
| $348A-$35AF | bonus-round.s | Bonus round handling |
| $35B0-$37C6 | bonus-stage-extended.s | Extended bonus stages |
| $37C7-$39D1 | level-display.s | Level number display |
| $39D2-$3AB7 | entity-spawn.s | Entity spawning |
| $3AB8-$3C00 | screen-scroll.s | Screen scrolling |
| $3C01-$3CB1 | graphics-copy.s | Graphics copying |
| $3CB2-$3D2C | entity-state-tables.s | Entity state tables |
| $3D2D-$3DB0 | entity-collision.s | Entity collision |
| $3DB0-$3E76 | bubble-handler.s | Bubble state handler |
| $3E77-$3FAF | sprite-init.s | Sprite initialization |
| $3FB0-$3FFF | sprite-helpers.s | Sprite helper routines |
| $4800-$48FF | init-routines.s | System initialization |
| $4900-$4AFF | loader.s | Tape/disk loader |
| $E000-$E3A6 | level-renderer.s | Level rendering |
| $E3A7-$E553 | sprites-display.s | Sprite display |
| $E554-$E751 | line-draw.s | Line drawing |
| $E752-$E9FC | sprite-composer.s | Sprite composition |
| $E9FD-$EC0B | entity-bubble-handler.s | Bubble physics |
| $EC0C-$EDC6 | entity-movement.s | Entity movement |
| $EDC7-$EFBB | entity-ai.s | Entity AI |
| $EFBC-$F0ED | entity-physics-cont.s | Entity physics |
| $F0EE-$F1AB | title-screen-data.s | Title screen text |
| $F1AC-$F23F | credits-handler-partial.s | Credits handler |
| $F2C4-$F39B | music-sound-data.s | Sound data tables |
| $F4BC-$F8FF | sound-engine.s | SID sound engine |
| $FE00-$FFFA | final-data.s | Final data section |

## Key Routines

### Core Game Loop

| Address | Label | Description |
|---------|-------|-------------|
| $045C | `check_player_state` | Handles death, respawn, game over |
| $052A | `check_join_game` | Detects fire button to join game |
| $06AB | `irq_frame_update` | Raster IRQ - timers, frame counter |
| $0A07 | `main_game_loop` | Main game loop entry point |

### Enemy System

| Address | Label | Description |
|---------|-------|-------------|
| $0BED | `enemy_spawn_handler` | Spawns new enemies |
| $0CF2 | `enemy_ai_update` | Enemy AI and movement |
| $EA20 | `check_entity_trapped` | Check if entity trapped between platforms |
| $EA92 | `climb_descend_decision` | Determine vertical movement direction |

### Player & Input

| Address | Label | Description |
|---------|-------|-------------|
| $1319 | `update_player_sprites` | Player sprite animation |
| $1805 | `update_sprite_positions` | Sprite multiplexer |
| $1844 | `update_player_input` | Joystick reading, player control |
| $7EB3 | `read_joystick_keyboard` | Input polling |

### Bubble Physics

| Address | Label | Description |
|---------|-------|-------------|
| $1578 | `update_bubbles` | Bubble physics and capture |
| $E9FD | `entity_bubble_handler` | Main bubble physics dispatcher |
| $EB3F | `setup_bubble_ascent` | Configure bubble upward movement |
| $EBD9 | `platform_climbing_physics` | Platform descent state machine |

### Graphics & Rendering

| Address | Label | Description |
|---------|-------|-------------|
| $E000 | `setup_level_screen` | Level initialization & rendering |
| $E18B | `decompress_level_data` | RLE level data decompression |
| $E3A7 | `update_sprite_animations` | Sprite animations & high score |
| $E42A | `display_text_string` | Text display with control codes |
| $E494 | `wait_one_frame` | Frame sync (critical timing) |
| $E554 | `draw_animated_sprite` | Motion trail effects |
| $E5C4 | `draw_bresenham_line` | Bresenham line algorithm |
| $E752 | `sprite_composition` | Multi-layer sprite composition |
| $E90E | `render_all_entities` | Entity rendering loop (18 entities) |

### Sound System

| Address | Label | Description |
|---------|-------|-------------|
| $F4BC | `sound_init` | Sound initialization |
| $F53C | `update_music` | SID music player |
| $F887 | `music_mode_init` | Music/mode initialization |

### Scoring

| Address | Label | Description |
|---------|-------|-------------|
| $7C26 | `scoring` | BCD score calculation |
| $E97F | `score_update_bcd` | BCD score addition for pickups |

## Entity Data Arrays

The game uses parallel arrays indexed by entity slot (0-17):

| Address | Description |
|---------|-------------|
| $85E8,x | Entity state bit flags |
| $8610,x | Animation frame counter |
| $8520,x | Current sprite frame index |
| $8688,x | Invincibility timer |
| $8700,x | Movement/bubble state |
| $8750,x | Target direction / frame limit |
| $8778,x | Animation mask value |
| $87A0,x | Platform climbing state counter |
| $87C8,x | Secondary collision flags |
| $87F0,x | Vertical collision state |
| $8818,x | Animation frame data (bit 7 = bubble active) |
| $8840,x | Horizontal velocity |
| $8868,x | Secondary velocity |
| $86D8,x | Collision data |
| $B2,x | Entity type/state (ENESSION) |
| $BA,x | Entity X position (FA) |
| $C2,x | Entity Y position |

## Technical Details

### Frame Timing

The game runs at 25fps (PAL), achieved by skipping every other frame:
- IRQ handler at $06AB increments frame counter ($08)
- Sprite updates only run on odd frames (AND #$01 check)
- Sound updates run every frame

### Graphics Data Tables

#### Sprite Data Locations

| Address | Description | Count | Size |
|---------|-------------|-------|------|
| $5800 | Sprite data block 1 (Player, enemies) | Variable | 2KB |
| $7440 | Player in bubble A | 4 sprites | 256 bytes |
| $7540 | Player in bubble B | 4 sprites | 256 bytes |
| $7640 | Boss facing left | 9 sprites | 576 bytes |
| $7880 | Boss in bubble | 9 sprites | 576 bytes |
| $7C40 | Boss facing right | 9 sprites | 576 bytes |
| $8000 | Sprite data block 2 | Variable | 8KB |
| $A320 | Bonus cupcake | 4 sprites | 256 bytes |
| $A420 | Bonus melon (partial) | 3 sprites | 192 bytes |
| $A520 | Bonus diamond | 2 sprites | 128 bytes |

#### Character Set Data Locations

| Address | Description |
|---------|-------------|
| $4000 | Numeric font (charset base) |
| $4050 | Shadows (6 chars × 8 bytes) |
| $4080 | Fatneck font |
| $40E0 | Fire on ground A |
| $40E8 | Life dot lines font |
| $40F8 | Flowing water animation |
| $4108 | Alpha font |
| $41D8 | Punctuation font |
| $4200 | Fire on ground |
| $4210 | Ruddy "HELLO THERE" font |
| $8000 | Bubble blow animation |
| $8980 | Bubble pop animation |
| $8F00 | Baron Von Blubba (main block start) |

### Level Data Format

Level data uses bit-packed compression:
- Each bit determines tile placement (1 = platform, 0 = empty)
- RLE encoding for repeated patterns
- Optional horizontal mirroring (left half copied to right)
- Symmetry flag in $FF94 (bit 7): 0 = symmetric, 1 = asymmetric

### Sprite System

- 8 hardware sprites multiplexed for more on-screen
- Double-buffered screen updates
- Multi-layer sprite composition with AND/OR masking
- Self-modifying code for dynamic sprite pointers

### Sound Engine

- 3-channel SID music using custom player
- Separate sound effect system
- Music data in pattern-based format
- Note frequency lookup tables for pitch

### PRNG (Random Number Generator)

Located at $E9EA:
- 16-bit XOR-shift-rotate pattern
- Incorporates CIA timer ($DC06) for entropy
- State stored in zero-page ($26/$27)

### BCD Score System

Uses 6502 decimal mode (SED) for proper score display:
- Multi-byte addition with carry propagation
- Digits stored as BCD (e.g., $09 + $01 = $10, not $0A)

## Self-Modifying Code Locations

The game uses extensive self-modification for optimization:

| Address | Purpose |
|---------|---------|
| $E849-$E861 | Sprite graphics pointers (6 pairs) |
| $E966 | Sprite frame offset |
| $EB94 | JMP/BIT toggle for control flow |
| $EBB5-$EBB6 | Dynamic jump target |

## Text Control Codes

The text rendering system at $E42A supports:
- `$00` = End of string
- `$01-$0F` = Direct character codes
- `$1F xx yy` = Set cursor position
- `$20+` = Standard characters

## Data Tables in ROM

### Level Data Tables

| Address | Description | Length |
|---------|-------------|--------|
| $AE51 | Monster spawn data | 1,815 bytes (572 monsters × 3 bytes + stop bytes) |
| $B569 | Item spawn positions A | 100 bytes (5-bit packed coords) |
| $B5CD | Item spawn positions B | 100 bytes (5-bit packed coords) |
| $B631 | Item spawn positions C (upper nibble) + bubble spawns (lower nibble) | 100 bytes |
| $B695 | Wind currents / level data | Variable (up to 1,145 bytes) |
| $BB0E | Sidebar chars | 1,888 bytes (32 bytes × 59 sidebars) |
| $C26E | Platform chars | 800 bytes |
| $C58E | Hole metadata (lower nibble: holes, upper nibble: bubble currents) | 100 bytes |
| $C5F2 | Bitmaps | 6,670 bytes (46 bytes × 145 levels) |
| $FF30 | Background colors | 100 bytes |
| $FF94 | Symmetry flag (bit 7) + sidebar chars index (bits 0-6) | 100 bytes |

### Item Data Tables

| Address | Description | Length |
|---------|-------------|--------|
| $A790 | Enemy death bonus item indices | 6 bytes (starting at $A791) |
| $A81F | Large bonus sprite colors (cupcake, melon, diamonds) | 5 bytes |
| $A892 | Points item char block indices | 47 bytes |
| $A8C1 | Powerup item char block indices | 35 bytes |
| $A8E4 | Points item color indices (lower nibble only) | 47 bytes |
| $A913 | Powerup item color indices (lower nibble only) | 35 bytes |
| $AB63 | Monster sprite colors | 8 bytes (one per monster type) |

### Other Lookup Tables

| Address | Description |
|---------|-------------|
| $AB52 | Pickup point values |
| $AC03/$AC04 | Screen address lookup |
| $ACDD | Standard climbing offsets |
| $ACED | Velocity climbing offsets |
| $F305 | Sound channel state (3 channels) |
| $F323 | Sound frequency table |
| $F35A | Sound effect configuration |
