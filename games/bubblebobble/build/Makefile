# rebb64 - Build System
# ========================================
#
# Usage:
#   make                                  - Build the game (original, verifiable)
#   make clean                            - Remove build artifacts
#   make verify                           - Build and verify against original
#   make release                          - Build runnable PRG (requires tscrunch)
#   make sid                              - Build standalone SID file
#   make SOUND_SRC=my-sound.s             - Build with a different sound source
#   make COMPRESS_LEVELS=1                - Build with per-level bitmap compression

# Tools
CA65 = ca65
LD65 = ld65
TSCRUNCH = tscrunch
PYTHON = python3

# Directories
SRC_DIR = ../src
DATA_DIR = ../data

# Config
CONFIG = c64-prg.cfg

# Sound source selection
# Change this to use a different conforming sound source.
# The source must conform to the API contract documented in sid-wrapper.s.
# Note: make verify only passes with the original sound.s.
SOUND_SRC = sound.s

# Level bitmap compression (optional)
# Set COMPRESS_LEVELS=1 to enable per-level bitmap compression.
# When enabled, level bitmaps are compressed with dictionary + zero-run
# encoding, freeing ~1244 bytes in the I/O shadow region.
# Default (unset): original uncompressed bitmaps, binary-identical output.
#COMPRESS_LEVELS ?= 1

# Output
OUTPUT = rebb64-raw.prg
RELEASE = rebb64.prg
LBLFILE = rebb64.lbl

# SHA256 hash of original Bubble Bobble C64 PRG (decompressed)
REFERENCE_SHA256 = fdba2390782653ba2533b2d87c44c8f0480ab18968a2c0ccc0cef8300fcee7b6

# Generated level data files (base set, always needed)
LEVEL_BINS_BASE = level-bitmaps.bin level-colors.bin level-flags.bin \
                  enemy-spawns.bin item-positions.bin physics-flags.bin

# Compressed level data files (only needed when COMPRESS_LEVELS is set)
LEVEL_BINS_COMPRESSED = level-bitmaps-compressed.bin level-bitmap-offsets.bin \
                        bitmap-decode-table.bin bitmap-dict-pairs.bin

ifdef COMPRESS_LEVELS
LEVEL_BINS = $(LEVEL_BINS_BASE) $(LEVEL_BINS_COMPRESSED)
else
LEVEL_BINS = $(LEVEL_BINS_BASE)
endif

# Assembler flags: pass -D COMPRESS_LEVELS=1 when compression is enabled
ifdef COMPRESS_LEVELS
CA65_DEFS = -D COMPRESS_LEVELS=1
else
CA65_DEFS =
endif

# Generated include file that selects the active sound source.
# Used by both master.s (game build) and sid-wrapper.s (SID build).
SOUND_INC = sound-select.inc

all: $(OUTPUT)

$(SOUND_INC):
	@echo '.include "$(SOUND_SRC)"' > $@

# Level data conversion (levels.txt -> binary files)
$(LEVEL_BINS): $(DATA_DIR)/levels.txt convert-levels.py
	$(PYTHON) convert-levels.py $< $(LEVEL_BINS)

# Zone data conversion (zone-data.txt -> zone-data.bin)
zone-data.bin: $(DATA_DIR)/zone-data.txt convert-zone-data.py
	$(PYTHON) convert-zone-data.py $< $@

# TGA to binary conversion
hud-font.bin: $(DATA_DIR)/hud-font.tga convert-tga.py
	$(PYTHON) convert-tga.py $< $@ --format multicolor-chars

sidebars.bin: $(DATA_DIR)/sidebars.tga convert-tga.py
	$(PYTHON) convert-tga.py $< $@ --format multicolor-chars

level-tiles.bin: $(DATA_DIR)/level-tiles.tga convert-tga.py
	$(PYTHON) convert-tga.py $< $@ --format multicolor-chars

# Character set ($4000-$445F, 140 characters = 1120 bytes)
charset.bin: $(DATA_DIR)/charset.tga convert-tga.py
	$(PYTHON) convert-tga.py $< $@ --format hires-chars

# Bonus sprites (cake, melon, diamond) - sprite sheet (8 sprites + melon tops = 530 bytes)
# Layout: [cake][melon_tops][melon][diamond]
# Slicing is done in binaries.s using .incbin offset/size parameters:
#   bytes 0-255:   cake (4 sprites)       -> BONUS_CAKE segment ($A320)
#   bytes 256-273: melon tops (18 bytes)  -> referenced via offset in binaries.s
#   bytes 274-401: melon (2 sprites)      -> BONUS_MELON segment ($A4A0)
#   bytes 402-529: diamond (2 sprites)    -> BONUS_DIAMOND segment ($A520)
# Source TGAs: bonus-cake.tga (24x42), bonus-melon.tga (24x24), bonus-diamond.tga (24x21)
# Padding bytes (byte 64 of each sprite) come from dead-bytes.txt.
bonus-sprites.bin: $(DATA_DIR)/bonus-cake.tga $(DATA_DIR)/bonus-melon.tga $(DATA_DIR)/bonus-diamond.tga $(DATA_DIR)/dead-bytes.txt extract-bonus-sprites.py
	$(PYTHON) extract-bonus-sprites.py

# Game sprites ($5800-$703F, 6208 bytes = 97 sprites)
# Combined from old sprites1.bin + sprite portion of level-data-part1.bin
# Padding bytes come from dead-bytes.txt (byte 64 of each sprite, unused by VIC-II)
sprites-game.bin: $(DATA_DIR)/sprites-game.tga $(DATA_DIR)/dead-bytes.txt convert-tga.py
	$(PYTHON) convert-tga.py $< $@ --format multicolor-sprites

# Bubble masks from sprites2-static region ($8000-$847F, 1152 bytes)
bubble-masks.bin: $(DATA_DIR)/bubble-masks.tga convert-tga.py
	$(PYTHON) convert-tga.py $< $@ --format bubble-masks

# Software sprites ($8F00-$A31F, 5152 bytes)
# 107+ column-major 12x16 multicolor sprites (last sprite partial)
# The remaining 32 bytes ($A320-$A33F) come from bonus-cake-head.bin
software-sprites.bin: $(DATA_DIR)/software-sprites.tga convert-tga.py
	$(PYTHON) convert-tga.py $< $@ --format software-sprites

# Diamond sprite ($A854, 36 bytes - embedded in game-tables-static.bin)
diamond-sprite.bin: $(DATA_DIR)/diamond-sprite.tga convert-tga.py
	$(PYTHON) convert-tga.py $< $@ --format diamond-sprite

# Digit font ($AD75, 60 bytes - embedded in game-tables-static.bin)
digit-font.bin: $(DATA_DIR)/digit-font.tga convert-tga.py
	$(PYTHON) convert-tga.py $< $@ --format digit-font

# Level sprites ($7440-$75FF, 512 bytes = 8 sprites)
# Bubble dragon in bubble sprites (2 groups of 4 sprites each)
# Padding bytes come from dead-bytes.txt (byte 64 of each sprite, unused by VIC-II)
bubble-dragon-in-bubble.bin: $(DATA_DIR)/bubble-dragon-in-bubble.tga $(DATA_DIR)/dead-bytes.txt convert-tga.py
	$(PYTHON) convert-tga.py $< $@ --format level-sprites-stacked --stacked-groups 2

# Level sprites: Grumple Gromit (1728 bytes = 27 sprites)
# Left (9) + bubble (9) at $7600-$7ABF, right (9) at $7C40-$7E7F
# Sliced in binaries.s using .incbin offset/size parameters
# Padding bytes come from dead-bytes.txt (byte 64 of each sprite, unused by VIC-II)
grumple-gromit.bin: $(DATA_DIR)/grumple-gromit.tga $(DATA_DIR)/dead-bytes.txt convert-tga.py
	$(PYTHON) convert-tga.py $< $@ --format level-sprites-stacked --stacked-groups 3

# Assemble load address
loadaddr.o: $(SRC_DIR)/loadaddr.s
	$(CA65) --cpu 6502 -o $@ $<

# Assemble main source (depends on sound-select.inc and the selected sound source)
master.o: $(SRC_DIR)/master.s $(SOUND_INC) $(SRC_DIR)/$(SOUND_SRC) hud-font.bin sidebars.bin level-tiles.bin sprites-game.bin zone-data.bin charset.bin bubble-masks.bin software-sprites.bin bonus-sprites.bin diamond-sprite.bin digit-font.bin bubble-dragon-in-bubble.bin grumple-gromit.bin $(LEVEL_BINS)
	$(CA65) --cpu 6502 $(CA65_DEFS) -I $(SRC_DIR) -I . -o $@ $<

# Link (generates label file and debug info for release target)
DBGFILE = rebb64.dbg

$(OUTPUT): loadaddr.o master.o $(CONFIG)
	$(LD65) -C $(CONFIG) -Ln $(LBLFILE) --dbgfile $(DBGFILE) -o $@ loadaddr.o master.o
	@$(PYTHON) check-gaps.py $(DBGFILE)

# Verify against original hash
verify: $(OUTPUT)
	@echo "Verifying SHA256 hash..."
	@echo "$(REFERENCE_SHA256)  $(OUTPUT)" | sha256sum -c - && echo "SUCCESS: Hash matches original!"

# Build standalone SID file from the selected sound source
sid: $(SRC_DIR)/sid-wrapper.s $(SRC_DIR)/$(SOUND_SRC) sid.cfg build-sid.py
	$(PYTHON) build-sid.py --sound-src $(SOUND_SRC) rebb64.sid

# Create runnable PRG with TSCrunch
# Entry address (game_entry) is read directly from the VICE label file.
release: $(OUTPUT)
	$(TSCRUNCH) -p -x '$$$(shell awk '/\.game_entry$$/ { print toupper($$2) }' $(LBLFILE))' $(OUTPUT) $(RELEASE)

# Clean build artifacts
clean:
	rm -f loadaddr.o master.o $(OUTPUT) $(RELEASE) $(LBLFILE) $(DBGFILE) rebb64.sid $(SOUND_INC) *.bin

.PHONY: all clean verify release sid
