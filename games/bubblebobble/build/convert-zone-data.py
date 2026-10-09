#!/usr/bin/env python3
"""
Convert zone-data.txt to binary format for rebb64.

Binary Format:
- Variable-length records, one per level (100 levels)
- First byte: offset to next level's data, or redirect (bit 7 set = use level N & 0x7F)
- Rectangle commands (3 bytes each):
  - Byte 1: 1TTXXXXX  (T=type 0-3, X=column 0-31)
  - Byte 2: YYYYYHHH  (Y=row 0-23, H=width bits 4-2)
  - Byte 3: HHHHHWWW  (H=width bits 1-0 in high bits, W=height 0-31)
- End marker: 0x00

Usage:
    python3 convert-zone-data.py <input.txt> <output.bin>
"""

import sys


def parse_text(text):
    """Parse zone-data.txt into level definitions."""
    levels = []
    current_level = None

    for line in text.split("\n"):
        line = line.strip()

        # Skip comments and empty lines
        if not line or line.startswith("#"):
            continue

        if line.startswith("level "):
            if current_level is not None:
                levels.append(current_level)

            parts = line.split()
            level_num = int(parts[1])

            if "->" in line:
                # Redirect to another level
                redirect_to = int(parts[3])
                current_level = {
                    "number": level_num,
                    "redirect": redirect_to,
                    "commands": [],
                }
            else:
                current_level = {
                    "number": level_num,
                    "redirect": None,
                    "commands": [],
                }
                # Parse size= and trailing= attributes
                for part in parts[2:]:
                    if part.startswith("size="):
                        current_level["size"] = int(part.split("=")[1])
                    elif part.startswith("trailing="):
                        current_level["trailing"] = part.split("=")[1]

        elif line.startswith("rect "):
            if current_level is None:
                raise ValueError(f"rect command outside of level: {line}")

            parts = line.split()
            x = int(parts[1])
            y = int(parts[2])
            width = int(parts[3])
            height = int(parts[4])

            # Parse type=N
            zone_type = 0
            for part in parts[5:]:
                if part.startswith("type="):
                    zone_type = int(part.split("=")[1])

            current_level["commands"].append(
                {
                    "type": "rect",
                    "x": x,
                    "y": y,
                    "width": width,
                    "height": height,
                    "zone_type": zone_type,
                }
            )

        elif line == "mirror":
            if current_level is None:
                raise ValueError("mirror command outside of level")
            current_level["commands"].append({"type": "mirror"})

    if current_level is not None:
        levels.append(current_level)

    return levels


def encode_level(level):
    """Encode a single level to binary."""
    if level.get("redirect") is not None:
        # Redirect marker: bit 7 set + target level
        return bytes([0x80 | level["redirect"]])

    commands_data = bytearray()

    for cmd in level.get("commands", []):
        if cmd["type"] == "rect":
            x = cmd["x"] & 0x1F
            y = cmd["y"] & 0x1F
            width = (cmd["width"] - 1) & 0x1F
            height = (cmd["height"] - 1) & 0x1F
            zone_type = cmd["zone_type"] & 0x03

            # Encode byte1: 1TTXXXXX
            byte1 = 0x80 | (zone_type << 5) | x

            # Width encoding: split into high (3 bits) and low (2 bits)
            w_high = (width >> 2) & 0x07
            w_low = width & 0x03

            # Encode byte2: YYYYYHHH (Y in bits 7-3, width high in bits 2-0)
            byte2 = (y << 3) | w_high

            # Encode byte3: WWHHHHH (width low in bits 7-6, height in bits 4-0)
            byte3 = (w_low << 6) | height

            commands_data.extend([byte1, byte2, byte3])

        elif cmd["type"] == "mirror":
            # Mirror command (0x00 terminates, so mirror must be non-zero with bit 7 clear)
            commands_data.append(0x01)

    # Calculate total length
    if "size" in level:
        total_length = level["size"]

        if total_length == 0:
            return bytes([0x00])

        # Check if commands exactly fill the block
        if len(commands_data) + 1 == total_length:
            # No room for terminator - commands fill block exactly
            pass
        elif len(commands_data) + 1 < total_length:
            # Add terminator
            commands_data.append(0x00)

            # Add trailing bytes if specified
            if "trailing" in level:
                trailing = bytes.fromhex(level["trailing"])
                commands_data.extend(trailing)

            # Pad remaining space
            padding = total_length - 1 - len(commands_data)
            if padding > 0:
                commands_data.extend(b"\x00" * padding)
        else:
            # Commands overflow - add terminator anyway
            commands_data.append(0x00)
            total_length = 1 + len(commands_data)
    else:
        # No explicit size - add terminator if there are commands
        if commands_data:
            commands_data.append(0x00)
        total_length = 1 + len(commands_data)

    return bytes([total_length]) + bytes(commands_data)


def encode_binary(levels, min_size=1145):
    """Encode all 100 levels to binary."""
    levels_by_num = {l["number"]: l for l in levels}

    result = bytearray()

    for level_num in range(100):
        level = levels_by_num.get(
            level_num,
            {
                "number": level_num,
                "redirect": None,
                "commands": [],
            },
        )
        result.extend(encode_level(level))

    # Pad to minimum size for original binary compatibility
    if len(result) < min_size:
        result.extend(b"\x00" * (min_size - len(result)))

    return bytes(result)


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input.txt> <output.bin>", file=sys.stderr)
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2]

    with open(input_file, "r") as f:
        text = f.read()

    levels = parse_text(text)
    data = encode_binary(levels)

    with open(output_file, "wb") as f:
        f.write(data)

    print(f"Converted {len(levels)} levels ({len(data)} bytes) to {output_file}")


if __name__ == "__main__":
    main()
