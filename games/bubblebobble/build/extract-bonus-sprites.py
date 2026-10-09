#!/usr/bin/env python3
"""
Extract bonus sprites from TGA files.

Input files:
  - bonus-cake.tga (24x42): Giant cupcake (4 sprites)
  - bonus-melon.tga (24x24): Giant watermelon (2 sprites + melon tops)
  - bonus-diamond.tga (24x21): Giant diamond (2 sprites)

Output file:
  - bonus-sprites.bin (530 bytes)

Binary layout:
  Bytes 0-255:   Cake sprites (4 x 64 bytes)
  Bytes 256-263: Melon top left (8 bytes)
  Bytes 264-273: Melon top right (9 bytes + 1 padding byte)
  Bytes 274-401: Melon sprites (2 x 64 bytes)
  Bytes 402-529: Diamond sprites (2 x 64 bytes)

Sprite padding bytes (byte 64 of each sprite) and the melon top padding byte
are read from dead-bytes.txt for byte-compatibility with the original ROM.
"""

import sys
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(SCRIPT_DIR, "..", "data")


def load_dead_bytes(filepath):
    """Load dead bytes registry from file."""
    registry = {}
    with open(filepath, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if ":" not in line:
                continue
            key, values = line.split(":", 1)
            registry[key.strip()] = bytes(int(v, 16) for v in values.split())
    return registry


def get_dead_bytes(registry, key, expected_count):
    """Get dead bytes with validation."""
    if key not in registry:
        raise ValueError(f"Missing '{key}' in dead-bytes.txt")
    data = registry[key]
    if len(data) != expected_count:
        raise ValueError(f"'{key}' must have {expected_count} bytes, got {len(data)}")
    return data


def parse_tga(filepath):
    """Parse TGA file and return width, height, and pixel data."""
    with open(filepath, "rb") as f:
        tga = f.read()

    id_length = tga[0]
    color_map_length = tga[5] | (tga[6] << 8)
    color_map_depth = tga[7]
    width = tga[12] | (tga[13] << 8)
    height = tga[14] | (tga[15] << 8)
    image_descriptor = tga[17]

    palette_size = color_map_length * (color_map_depth // 8)
    pixel_offset = 18 + id_length + palette_size
    pixels_raw = list(tga[pixel_offset : pixel_offset + width * height])

    # Convert to top-left origin if needed
    if image_descriptor & 0x20:
        return width, height, pixels_raw

    # Flip vertically for bottom-left origin
    pixels = []
    for y in range(height - 1, -1, -1):
        pixels.extend(pixels_raw[y * width : (y + 1) * width])
    return width, height, pixels


def encode_row(pixels):
    """Encode 12 pixels to 3 bytes (multicolor format)."""
    return bytes(
        [
            (pixels[0] << 6) | (pixels[1] << 4) | (pixels[2] << 2) | pixels[3],
            (pixels[4] << 6) | (pixels[5] << 4) | (pixels[6] << 2) | pixels[7],
            (pixels[8] << 6) | (pixels[9] << 4) | (pixels[10] << 2) | pixels[11],
        ]
    )


def extract_sprite(pixels, width, col, row, padding_byte):
    """Extract one 64-byte sprite (21 rows + padding byte)."""
    output = bytearray()
    for y in range(21):
        idx = (row + y) * width + col
        output.extend(encode_row(pixels[idx : idx + 12]))
    output.append(padding_byte)
    return output


def extract_melon_tops(pixels, width, padding_byte):
    """Extract melon top data (18 bytes total).

    The TGA shows tops visually correct, but the binary format has them
    swapped (left/right) and the right side is horizontally flipped.
    """
    output = bytearray()

    # Melon top left (8 bytes) - from TGA right side (cols 12-23)
    for row in range(2):
        idx = row * width + 12
        output.extend(encode_row(pixels[idx : idx + 12]))
    # Row 2: only 8 pixels (2 bytes)
    idx = 2 * width + 12
    output.append(
        (pixels[idx] << 6)
        | (pixels[idx + 1] << 4)
        | (pixels[idx + 2] << 2)
        | pixels[idx + 3]
    )
    output.append(
        (pixels[idx + 4] << 6)
        | (pixels[idx + 5] << 4)
        | (pixels[idx + 6] << 2)
        | pixels[idx + 7]
    )

    # Melon top right (10 bytes) - from TGA left side (cols 0-11), horizontally flipped
    for row in range(3):
        idx = row * width
        output.extend(encode_row(pixels[idx : idx + 12][::-1]))
    output.append(padding_byte)

    return output


def main():
    # Load dead bytes
    dead_bytes = load_dead_bytes(os.path.join(DATA_DIR, "dead-bytes.txt"))

    cake_padding = get_dead_bytes(dead_bytes, "bonus-cake.padding", 4)
    melon_padding = get_dead_bytes(dead_bytes, "bonus-melon.padding", 2)
    melon_top_padding = get_dead_bytes(dead_bytes, "bonus-melon-top.padding", 1)
    diamond_padding = get_dead_bytes(dead_bytes, "bonus-diamond.padding", 2)

    # Load TGA files
    cake_w, cake_h, cake_px = parse_tga(os.path.join(DATA_DIR, "bonus-cake.tga"))
    melon_w, melon_h, melon_px = parse_tga(os.path.join(DATA_DIR, "bonus-melon.tga"))
    diamond_w, diamond_h, diamond_px = parse_tga(
        os.path.join(DATA_DIR, "bonus-diamond.tga")
    )

    # Validate dimensions
    if (cake_w, cake_h) != (24, 42):
        print(
            f"Error: bonus-cake.tga must be 24x42, got {cake_w}x{cake_h}",
            file=sys.stderr,
        )
        sys.exit(1)
    if (melon_w, melon_h) != (24, 24):
        print(
            f"Error: bonus-melon.tga must be 24x24, got {melon_w}x{melon_h}",
            file=sys.stderr,
        )
        sys.exit(1)
    if (diamond_w, diamond_h) != (24, 21):
        print(
            f"Error: bonus-diamond.tga must be 24x21, got {diamond_w}x{diamond_h}",
            file=sys.stderr,
        )
        sys.exit(1)

    # Extract sprites
    output = bytearray()

    # Cake: 4 sprites (top-left, top-right, bottom-left, bottom-right)
    for i, (col, row) in enumerate([(0, 0), (12, 0), (0, 21), (12, 21)]):
        output.extend(extract_sprite(cake_px, cake_w, col, row, cake_padding[i]))

    # Melon tops
    output.extend(extract_melon_tops(melon_px, melon_w, melon_top_padding[0]))

    # Melon: 2 sprites (rows 3-23)
    for i, col in enumerate([0, 12]):
        output.extend(extract_sprite(melon_px, melon_w, col, 3, melon_padding[i]))

    # Diamond: 2 sprites
    for i, col in enumerate([0, 12]):
        output.extend(extract_sprite(diamond_px, diamond_w, col, 0, diamond_padding[i]))

    # Write output
    output_path = os.path.join(SCRIPT_DIR, "bonus-sprites.bin")
    with open(output_path, "wb") as f:
        f.write(output)
    print(f"Extracted {len(output)} bytes to bonus-sprites.bin")


if __name__ == "__main__":
    main()
