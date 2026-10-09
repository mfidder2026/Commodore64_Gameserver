#!/usr/bin/env python3
"""
Convert TGA images to C64 binary formats.

Usage:
    python3 convert-tga.py <input.tga> <output.bin> --format <type>

Formats:
    hires-chars    - 1-bit 8x8 characters (e.g., HUD font, charset)

To add a new format:
    1. Create a converter function: convert_<name>(pixels, width, height) -> bytes
    2. Add entry to FORMATS dict with grid dimensions and converter function
"""

import sys
import os
import argparse


# =============================================================================
# Dead Bytes Registry
# =============================================================================


def load_dead_bytes(filepath):
    """
    Load dead bytes registry from a text file.

    Format:
        # comment
        key: XX XX XX ...

    Returns:
        dict mapping key -> bytes
    """
    registry = {}

    if not os.path.exists(filepath):
        return registry

    with open(filepath, "r") as f:
        for line in f:
            line = line.strip()
            # Skip comments and blank lines
            if not line or line.startswith("#"):
                continue
            # Parse "key: XX XX XX ..."
            if ":" not in line:
                continue
            key, values = line.split(":", 1)
            key = key.strip()
            hex_bytes = values.strip().split()
            registry[key] = bytes(int(b, 16) for b in hex_bytes)

    return registry


def get_dead_bytes(registry, key, expected_count):
    """
    Get dead bytes for a key, with strict validation.

    Raises:
        ValueError if key not found or wrong count
    """
    if key not in registry:
        raise ValueError(f"Dead bytes key '{key}' not found in registry")
    data = registry[key]
    if len(data) != expected_count:
        raise ValueError(
            f"Dead bytes '{key}': expected {expected_count} bytes, got {len(data)}"
        )
    return data


# =============================================================================
# TGA Parser
# =============================================================================


def parse_tga(filepath):
    """
    Parse a TGA file and return image metadata and pixel data.

    Returns:
        dict with keys:
            - width: image width in pixels
            - height: image height in pixels
            - pixels: list of palette indices (row-major, top-left origin)
            - palette: list of (r, g, b) tuples
    """
    with open(filepath, "rb") as f:
        tga = f.read()

    # Parse header
    id_length = tga[0]
    color_map_type = tga[1]
    image_type = tga[2]
    color_map_start = tga[3] | (tga[4] << 8)
    color_map_length = tga[5] | (tga[6] << 8)
    color_map_depth = tga[7]
    width = tga[12] | (tga[13] << 8)
    height = tga[14] | (tga[15] << 8)
    bits_per_pixel = tga[16]
    image_descriptor = tga[17]

    # Validate format
    if image_type != 1:
        raise ValueError(f"Expected indexed color TGA (type 1), got type {image_type}")
    if bits_per_pixel != 8:
        raise ValueError(f"Expected 8-bit indexed image, got {bits_per_pixel}-bit")

    # Parse palette
    header_size = 18
    id_size = id_length
    palette_offset = header_size + id_size
    bytes_per_color = color_map_depth // 8

    palette = []
    for i in range(color_map_length):
        offset = palette_offset + i * bytes_per_color
        if bytes_per_color == 3:
            b, g, r = tga[offset], tga[offset + 1], tga[offset + 2]
        elif bytes_per_color == 4:
            b, g, r = tga[offset], tga[offset + 1], tga[offset + 2]
            # alpha = tga[offset + 3]  # ignored
        else:
            raise ValueError(f"Unsupported palette depth: {color_map_depth} bits")
        palette.append((r, g, b))

    # Read pixel data
    pixel_data_offset = palette_offset + color_map_length * bytes_per_color
    pixels_raw = tga[pixel_data_offset : pixel_data_offset + width * height]

    if len(pixels_raw) != width * height:
        raise ValueError(f"Expected {width * height} pixels, got {len(pixels_raw)}")

    # Convert to top-left origin if needed
    top_left_origin = (image_descriptor & 0x20) != 0

    if top_left_origin:
        pixels = list(pixels_raw)
    else:
        # Flip vertically
        pixels = []
        for y in range(height - 1, -1, -1):
            row_start = y * width
            pixels.extend(pixels_raw[row_start : row_start + width])

    return {
        "width": width,
        "height": height,
        "pixels": pixels,
        "palette": palette,
    }


def get_pixel(image, x, y):
    """Get palette index at (x, y) from parsed image."""
    return image["pixels"][y * image["width"] + x]


# =============================================================================
# Format Converters
# =============================================================================


def convert_hires_chars(image, cell_width, cell_height, cells_per_row):
    """
    Convert image to 1-bit character data.

    Each character is 8 bytes (one byte per row).
    Palette index 0 = background (bit 0), any other index = foreground (bit 1).
    """
    width = image["width"]
    height = image["height"]

    cols = width // cell_width
    rows = height // cell_height

    output = bytearray()

    for char_idx in range(cols * rows):
        col = char_idx % cols
        row = char_idx // cols
        base_x = col * cell_width
        base_y = row * cell_height

        for y in range(cell_height):
            byte = 0
            for x in range(cell_width):
                color_idx = get_pixel(image, base_x + x, base_y + y)
                if color_idx != 0:
                    byte |= 1 << (7 - x)
            output.append(byte)

    return bytes(output)


def convert_multicolor_chars(image, cell_width, cell_height, cells_per_row):
    """
    Convert image to multi-color character data.

    Each character is 8 bytes (one byte per row).
    Each byte encodes 4 pixels using 2-bit pairs.

    Input image should have:
      - Each character cell = 4 pixels wide × 8 pixels tall
      - Palette indices 0-3 only
      - 1 TGA pixel = 1 C64 logical pixel (double-width happens on C64 hardware)

    Output format:
      - 8 bytes per character
      - Each byte = 4 pixels packed as 2-bit pairs (MSB first)
    """
    width = image["width"]
    height = image["height"]

    cols = width // cell_width
    rows = height // cell_height

    output = bytearray()

    for char_idx in range(cols * rows):
        col = char_idx % cols
        row = char_idx // cols
        base_x = col * cell_width
        base_y = row * cell_height

        # Each character is 8 rows × 4 pixels
        for y in range(cell_height):
            byte = 0
            # Each row has 4 pixels
            for x in range(4):
                pixel_idx = get_pixel(image, base_x + x, base_y + y)

                # Validate palette index
                if pixel_idx > 3:
                    raise ValueError(
                        f"Invalid pixel value {pixel_idx} at char {char_idx}, "
                        f"row {y}, pixel {x}. Must be 0-3."
                    )

                # Pack into byte (MSB first: shift by 6, 4, 2, 0)
                shift = 6 - (x * 2)
                byte |= pixel_idx << shift

            output.append(byte)

    return bytes(output)


def convert_multicolor_sprites(image, cell_width, cell_height, cells_per_row, **kwargs):
    """
    Convert image to C64 multicolor sprite data.

    Each sprite is 64 bytes:
        - 21 rows x 3 bytes = 63 bytes of pixel data
        - 1 padding byte (from dead-bytes registry)

    Multicolor format: 2 bits per pixel, 4 pixels per byte, 12 pixels per row.

    Input format:
        - All sprites in a single row (width = num_sprites * 12)
        - Height = 21 (visible sprite data only)

    Padding bytes are read from the dead-bytes registry (strict mode).

    Args:
        image: Parsed TGA image
        cell_width: Sprite width (12 pixels)
        cell_height: Sprite height (21 pixels)
        cells_per_row: Sprites per row in input image
        **kwargs: Must include 'padding_bytes' from dead-bytes registry

    Returns:
        bytes: Sprite data (num_sprites * 64 bytes)
    """
    width = image["width"]
    height = image["height"]

    num_sprites = width // cell_width

    # Get padding bytes (strict - must be provided)
    if "padding_bytes" not in kwargs:
        raise ValueError(
            "multicolor-sprites format requires padding_bytes from dead-bytes registry"
        )
    padding_bytes = kwargs["padding_bytes"]
    if len(padding_bytes) != num_sprites:
        raise ValueError(
            f"padding_bytes count mismatch: got {len(padding_bytes)}, need {num_sprites}"
        )

    output = bytearray()

    for sprite_idx in range(num_sprites):
        base_x = sprite_idx * cell_width

        # 21 rows of pixel data
        for y in range(21):
            for byte_idx in range(3):
                byte = 0
                for pixel in range(4):
                    pixel_x = base_x + byte_idx * 4 + pixel
                    pixel_y = y
                    if pixel_y < height and pixel_x < width:
                        color_idx = get_pixel(image, pixel_x, pixel_y)
                        color_idx = color_idx & 0b11
                        shift = 6 - (pixel * 2)
                        byte |= color_idx << shift
                output.append(byte)

        # Padding byte from dead-bytes registry
        output.append(padding_bytes[sprite_idx])

    return bytes(output)


# =============================================================================
# Additional Format Converters
# =============================================================================


def convert_bubble_masks(image, cell_width, cell_height, cells_per_row):
    """
    Convert image to bubble mask data.

    Each mask is 16 bytes (8 pixels wide x 16 rows, 1 bit per pixel).
    Masks are arranged in a grid in the TGA.
    """
    width = image["width"]
    height = image["height"]

    cols = width // cell_width
    rows = height // cell_height

    output = bytearray()

    for mask_idx in range(cols * rows):
        col = mask_idx % cols
        row = mask_idx // cols
        base_x = col * cell_width
        base_y = row * cell_height

        # Each mask is 8 pixels wide x 16 rows = 16 bytes
        for y in range(cell_height):
            byte = 0
            for x in range(cell_width):
                color_idx = get_pixel(image, base_x + x, base_y + y)
                if color_idx != 0:
                    byte |= 1 << (7 - x)
            output.append(byte)

    return bytes(output)


def convert_software_sprites(image, cell_width, cell_height, cells_per_row):
    """
    Convert image to software sprite data.

    Data is stored in COLUMN-MAJOR order: the image is divided into
    horizontal strips of 16 rows (cell_height). Within each strip,
    4-pixel-wide columns are output left to right, with each column
    producing 16 bytes.

    The TGA dimensions determine the output size:
    - Width must be divisible by 4 (4 multicolor pixels per byte)
    - Height must be divisible by 16 (16 rows per sprite strip)
    - Output bytes = (width / 4) * height
    """
    width = image["width"]
    height = image["height"]

    byte_cols = width // 4  # Number of 4-pixel byte-columns
    strips = height // cell_height  # Number of 16-row strips

    output = bytearray()

    for strip in range(strips):
        base_y = strip * cell_height
        for byte_col in range(byte_cols):
            base_x = byte_col * 4
            for y in range(cell_height):  # 16 rows
                byte = 0
                for pixel in range(4):
                    px = base_x + pixel
                    color_idx = get_pixel(image, px, base_y + y)
                    color_idx = color_idx & 0x03  # Clamp to 2 bits
                    byte |= color_idx << (6 - pixel * 2)
                output.append(byte)

    return bytes(output)


def convert_sprite_patterns(image, cell_width, cell_height, cells_per_row):
    """
    Convert image to sprite pattern data.

    This is a simple strip format: 12 multicolor pixels wide, variable height.
    3 bytes per row (12 pixels / 4 pixels per byte).

    The original file is 290 bytes (96 rows + 2 trailing zeros).
    """
    width = image["width"]
    height = image["height"]

    output = bytearray()

    for y in range(height):
        # 3 bytes per row
        for byte_idx in range(3):
            byte = 0
            for pixel in range(4):
                px = byte_idx * 4 + pixel
                if px < width:
                    color_idx = get_pixel(image, px, y)
                    color_idx = color_idx & 0x03
                    byte |= color_idx << (6 - pixel * 2)
            output.append(byte)

    # Original file is 290 bytes - trim to match if we generated more
    # (97 rows * 3 = 291, but original is 290)
    target_size = 290
    if len(output) > target_size:
        output = output[:target_size]

    return bytes(output)


def convert_diamond_sprite(image, cell_width, cell_height, cells_per_row):
    """
    Convert image to diamond sprite data.

    12x12 multicolor sprite = 36 bytes (3 bytes per row, 12 rows).
    Row-major format.
    """
    width = image["width"]
    height = image["height"]

    output = bytearray()

    for y in range(height):
        # 3 bytes per row (12 pixels / 4 pixels per byte)
        for byte_idx in range(3):
            byte = 0
            for pixel in range(4):
                px = byte_idx * 4 + pixel
                if px < width:
                    color_idx = get_pixel(image, px, y)
                    color_idx = color_idx & 0x03
                    byte |= color_idx << (6 - pixel * 2)
            output.append(byte)

    return bytes(output)


def convert_digit_font(image, cell_width, cell_height, cells_per_row):
    """
    Convert image to digit font data.

    5x8 column-major format: 5 bytes per character, each byte is one column.
    Total 12 characters (0-9, -, blank) = 60 bytes.
    """
    width = image["width"]
    height = image["height"]

    char_width = 5
    char_height = 8
    num_chars = width // char_width

    output = bytearray()

    for char_idx in range(num_chars):
        base_x = char_idx * char_width

        # Column-major: 5 columns, each 8 pixels tall
        for col in range(char_width):
            byte = 0
            for row in range(char_height):
                px = base_x + col
                py = row
                if px < width and py < height:
                    color_idx = get_pixel(image, px, py)
                    # 1-bit: any non-zero is set
                    if color_idx != 0:
                        byte |= 1 << (7 - row)
            output.append(byte)

    return bytes(output)


def convert_level_sprites(image, cell_width, cell_height, cells_per_row, **kwargs):
    """
    Convert image to C64 multicolor sprite data.

    Each sprite is 64 bytes:
        - 21 rows x 3 bytes = 63 bytes of pixel data
        - 1 padding byte (from dead-bytes registry)

    Multicolor format: 2 bits per pixel, 4 pixels per byte, 12 pixels per row.

    Input format (default, stacked_groups=1):
        - All sprites in a single row (width = num_sprites * 12, height = 21)

    Input format (stacked, stacked_groups > 1):
        - Image contains N groups arranged horizontally
        - Each group has M rows of sprites stacked vertically
        - Sprites per group = (width / stacked_groups / 12) * (height / 21)
        - Output order: for each group, top-to-bottom, left-to-right

    Args:
        image: Parsed TGA image
        cell_width: Sprite width (12 pixels)
        cell_height: Sprite height (21 pixels)
        cells_per_row: Sprites per row in input image
        **kwargs: 'padding_bytes' from dead-bytes registry
                  'stacked_groups' number of horizontal groups (default 1)

    Returns:
        bytes: Sprite data
    """
    width = image["width"]
    height = image["height"]

    stacked_groups = kwargs.get("stacked_groups", 1)
    sprite_rows = height // cell_height
    group_width_px = width // stacked_groups
    sprites_per_group_row = group_width_px // cell_width
    sprites_per_group = sprites_per_group_row * sprite_rows
    total_sprites = sprites_per_group * stacked_groups

    # Get padding bytes (strict - must be provided)
    if "padding_bytes" not in kwargs:
        raise ValueError(
            "level-sprites format requires padding_bytes from dead-bytes registry"
        )
    padding_bytes = kwargs["padding_bytes"]

    output = bytearray()
    sprite_idx = 0

    for group in range(stacked_groups):
        group_base_x = group * group_width_px
        for row in range(sprite_rows):
            row_base_y = row * cell_height
            for col in range(sprites_per_group_row):
                base_x = group_base_x + col * cell_width
                base_y = row_base_y

                # 21 rows of pixel data
                for y in range(21):
                    for byte_idx in range(3):
                        byte = 0
                        for pixel in range(4):
                            pixel_x = base_x + byte_idx * 4 + pixel
                            pixel_y = base_y + y
                            if pixel_y < height and pixel_x < width:
                                color_idx = get_pixel(image, pixel_x, pixel_y)
                                color_idx = color_idx & 0b11
                                shift = 6 - (pixel * 2)
                                byte |= color_idx << shift
                        output.append(byte)

                # Padding byte from dead-bytes registry
                output.append(padding_bytes[sprite_idx])
                sprite_idx += 1

    return bytes(output)


def convert_sprites_rom_remaining(image, cell_width, cell_height, cells_per_row):
    """
    Convert image to sprites ROM remaining data.

    This is partial sprite data (cake/watermelon/diamond fragments) at $A340-$A427.
    Format: 12 multicolor pixels wide, variable height, 3 bytes per row.
    Total output: 232 bytes exactly.

    The image should be 12 pixels wide. Each row produces 3 bytes.
    If the image has 78 rows, the last row may be partial (only first 4 pixels used).
    """
    width = image["width"]
    height = image["height"]

    target_size = 232
    output = bytearray()

    for y in range(height):
        # 3 bytes per row (12 pixels / 4 pixels per byte)
        for byte_idx in range(3):
            if len(output) >= target_size:
                break
            byte = 0
            for pixel in range(4):
                px = byte_idx * 4 + pixel
                if px < width:
                    color_idx = get_pixel(image, px, y)
                    color_idx = color_idx & 0x03  # Clamp to 2 bits
                    byte |= color_idx << (6 - pixel * 2)
            output.append(byte)
        if len(output) >= target_size:
            break

    # Truncate or pad to exactly 232 bytes
    if len(output) > target_size:
        output = output[:target_size]
    while len(output) < target_size:
        output.append(0)

    return bytes(output)


# =============================================================================
# Format Registry
# =============================================================================

FORMATS = {
    "hires-chars": {
        "description": "1-bit 8x8 characters (e.g., HUD font, charset)",
        "cell_width": 8,
        "cell_height": 8,
        "converter": convert_hires_chars,
    },
    "multicolor-chars": {
        "description": "Multi-color 4x8 characters (4 pixels wide, sidebars)",
        "cell_width": 4,
        "cell_height": 8,
        "converter": convert_multicolor_chars,
    },
    "multicolor-sprites": {
        "description": "2-bit 12x21 multicolor sprites (padding from dead-bytes)",
        "cell_width": 12,
        "cell_height": 21,
        "converter": convert_multicolor_sprites,
        "dead_bytes_key_template": "{basename}.padding",
    },
    "bubble-masks": {
        "description": "1-bit 8x16 bubble mask patterns",
        "cell_width": 8,
        "cell_height": 16,
        "converter": convert_bubble_masks,
    },
    "software-sprites": {
        "description": "2-bit variable-width software sprites (16 rows, column-major)",
        "cell_width": 4,
        "cell_height": 16,
        "converter": convert_software_sprites,
    },
    "sprite-patterns": {
        "description": "2-bit 12-pixel wide sprite pattern strip",
        "cell_width": 12,
        "cell_height": 1,  # Process row by row
        "converter": convert_sprite_patterns,
    },
    "diamond-sprite": {
        "description": "2-bit 12x12 multicolor diamond sprite (36 bytes)",
        "cell_width": 12,
        "cell_height": 12,
        "converter": convert_diamond_sprite,
    },
    "digit-font": {
        "description": "1-bit 5x8 column-major digit font",
        "cell_width": 5,
        "cell_height": 8,
        "converter": convert_digit_font,
    },
    "sprites-rom-remaining": {
        "description": "2-bit 12-pixel wide ROM sprite data (232 bytes)",
        "cell_width": 12,
        "cell_height": 1,  # Process row by row
        "converter": convert_sprites_rom_remaining,
    },
    "level-sprites": {
        "description": "2-bit 12x21 multicolor sprites (padding from dead-bytes)",
        "cell_width": 12,
        "cell_height": 21,
        "converter": convert_level_sprites,
        "dead_bytes_key_template": "{basename}.padding",
    },
    "level-sprites-stacked": {
        "description": "2-bit 12x21 sprites, stacked groups (use --stacked-groups N)",
        "cell_width": 12,
        "cell_height": 21,
        "converter": convert_level_sprites,
        "dead_bytes_key_template": "{basename}.padding",
    },
}


# =============================================================================
# Main
# =============================================================================


def main():
    parser = argparse.ArgumentParser(
        description="Convert TGA images to C64 binary formats.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Formats:\n"
        + "\n".join(
            f"  {name:20} {info['description']}" for name, info in FORMATS.items()
        ),
    )
    parser.add_argument("input", help="Input TGA file")
    parser.add_argument("output", help="Output binary file")
    parser.add_argument(
        "--format", "-f", required=True, choices=FORMATS.keys(), help="Output format"
    )
    parser.add_argument(
        "--dead-bytes",
        "-d",
        default=None,
        help="Path to dead-bytes.txt (default: ../data/dead-bytes.txt relative to input)",
    )
    parser.add_argument(
        "--stacked-groups",
        "-g",
        type=int,
        default=1,
        help="Number of horizontal sprite groups (for level-sprites-stacked format)",
    )

    args = parser.parse_args()

    # Parse TGA
    try:
        image = parse_tga(args.input)
    except Exception as e:
        print(f"Error reading {args.input}: {e}", file=sys.stderr)
        sys.exit(1)

    # Get format info
    fmt = FORMATS[args.format]
    cell_width = fmt["cell_width"]
    cell_height = fmt["cell_height"]

    # Validate dimensions
    if image["width"] % cell_width != 0:
        print(
            f"Error: Image width {image['width']} not divisible by {cell_width}",
            file=sys.stderr,
        )
        sys.exit(1)
    if image["height"] % cell_height != 0:
        print(
            f"Error: Image height {image['height']} not divisible by {cell_height}",
            file=sys.stderr,
        )
        sys.exit(1)

    # Prepare converter kwargs
    converter_kwargs = {}

    # Load dead bytes if format requires them
    if "dead_bytes_key_template" in fmt:
        # Determine dead-bytes.txt path
        if args.dead_bytes:
            dead_bytes_path = args.dead_bytes
        else:
            # Default: ../data/dead-bytes.txt relative to input file
            input_dir = os.path.dirname(os.path.abspath(args.input))
            dead_bytes_path = os.path.join(input_dir, "dead-bytes.txt")

        # Load registry
        dead_bytes_registry = load_dead_bytes(dead_bytes_path)
        if not dead_bytes_registry:
            print(
                f"Error: Could not load dead-bytes registry from {dead_bytes_path}",
                file=sys.stderr,
            )
            sys.exit(1)

        # Get the key for this file
        basename = os.path.splitext(os.path.basename(args.input))[0]
        key = fmt["dead_bytes_key_template"].format(basename=basename)

        # Calculate expected count (use fixed count if specified, else derive from dimensions)
        if "fixed_sprite_count" in fmt:
            num_sprites = fmt["fixed_sprite_count"]
        elif args.stacked_groups > 1:
            # Stacked layout: sprites = (width/groups/12) * (height/21) * groups
            sprite_rows = image["height"] // cell_height
            sprites_per_row = image["width"] // cell_width // args.stacked_groups
            num_sprites = sprites_per_row * sprite_rows * args.stacked_groups
        else:
            num_sprites = image["width"] // cell_width

        try:
            padding_bytes = get_dead_bytes(dead_bytes_registry, key, num_sprites)
            converter_kwargs["padding_bytes"] = padding_bytes
        except ValueError as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)

    # Pass stacked_groups to converter
    if args.stacked_groups > 1:
        converter_kwargs["stacked_groups"] = args.stacked_groups

    # Convert
    cols = image["width"] // cell_width
    converter = fmt["converter"]
    output = converter(image, cell_width, cell_height, cols, **converter_kwargs)

    # Write output
    with open(args.output, "wb") as f:
        f.write(output)

    print(f"Converted {args.input} -> {args.output} ({len(output)} bytes)")


if __name__ == "__main__":
    main()
