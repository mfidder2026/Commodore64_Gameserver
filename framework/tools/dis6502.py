#!/usr/bin/env python3
"""
A small 6502 disassembler for exploring C64 binaries (documented opcodes; others are shown as .byte).

    python dis6502.py file.prg [start [end]]      a PRG (load address from its first two bytes)
    python dis6502.py --raw file.bin base [start [end]]
Addresses are hex ($ optional). Used while porting games to the framework (finding loaders,
input routines, free memory); the games themselves are built from source or patched images.
"""
from __future__ import annotations

import sys

# mnemonic, addressing mode per opcode
MODES = {
    "imp": 1, "acc": 1, "imm": 2, "zp": 2, "zpx": 2, "zpy": 2, "izx": 2, "izy": 2, "rel": 2,
    "abs": 3, "abx": 3, "aby": 3, "ind": 3,
}
OPS: dict[int, tuple[str, str]] = {}


def _op(code: int, mn: str, mode: str) -> None:
    OPS[code] = (mn, mode)


for mn, codes in {
    "ADC": [(0x69, "imm"), (0x65, "zp"), (0x75, "zpx"), (0x6D, "abs"), (0x7D, "abx"), (0x79, "aby"), (0x61, "izx"), (0x71, "izy")],
    "AND": [(0x29, "imm"), (0x25, "zp"), (0x35, "zpx"), (0x2D, "abs"), (0x3D, "abx"), (0x39, "aby"), (0x21, "izx"), (0x31, "izy")],
    "ASL": [(0x0A, "acc"), (0x06, "zp"), (0x16, "zpx"), (0x0E, "abs"), (0x1E, "abx")],
    "BIT": [(0x24, "zp"), (0x2C, "abs")],
    "CMP": [(0xC9, "imm"), (0xC5, "zp"), (0xD5, "zpx"), (0xCD, "abs"), (0xDD, "abx"), (0xD9, "aby"), (0xC1, "izx"), (0xD1, "izy")],
    "CPX": [(0xE0, "imm"), (0xE4, "zp"), (0xEC, "abs")],
    "CPY": [(0xC0, "imm"), (0xC4, "zp"), (0xCC, "abs")],
    "DEC": [(0xC6, "zp"), (0xD6, "zpx"), (0xCE, "abs"), (0xDE, "abx")],
    "EOR": [(0x49, "imm"), (0x45, "zp"), (0x55, "zpx"), (0x4D, "abs"), (0x5D, "abx"), (0x59, "aby"), (0x41, "izx"), (0x51, "izy")],
    "INC": [(0xE6, "zp"), (0xF6, "zpx"), (0xEE, "abs"), (0xFE, "abx")],
    "JMP": [(0x4C, "abs"), (0x6C, "ind")],
    "JSR": [(0x20, "abs")],
    "LDA": [(0xA9, "imm"), (0xA5, "zp"), (0xB5, "zpx"), (0xAD, "abs"), (0xBD, "abx"), (0xB9, "aby"), (0xA1, "izx"), (0xB1, "izy")],
    "LDX": [(0xA2, "imm"), (0xA6, "zp"), (0xB6, "zpy"), (0xAE, "abs"), (0xBE, "aby")],
    "LDY": [(0xA0, "imm"), (0xA4, "zp"), (0xB4, "zpx"), (0xAC, "abs"), (0xBC, "abx")],
    "LSR": [(0x4A, "acc"), (0x46, "zp"), (0x56, "zpx"), (0x4E, "abs"), (0x5E, "abx")],
    "ORA": [(0x09, "imm"), (0x05, "zp"), (0x15, "zpx"), (0x0D, "abs"), (0x1D, "abx"), (0x19, "aby"), (0x01, "izx"), (0x11, "izy")],
    "ROL": [(0x2A, "acc"), (0x26, "zp"), (0x36, "zpx"), (0x2E, "abs"), (0x3E, "abx")],
    "ROR": [(0x6A, "acc"), (0x66, "zp"), (0x76, "zpx"), (0x6E, "abs"), (0x7E, "abx")],
    "SBC": [(0xE9, "imm"), (0xE5, "zp"), (0xF5, "zpx"), (0xED, "abs"), (0xFD, "abx"), (0xF9, "aby"), (0xE1, "izx"), (0xF1, "izy")],
    "STA": [(0x85, "zp"), (0x95, "zpx"), (0x8D, "abs"), (0x9D, "abx"), (0x99, "aby"), (0x81, "izx"), (0x91, "izy")],
    "STX": [(0x86, "zp"), (0x96, "zpy"), (0x8E, "abs")],
    "STY": [(0x84, "zp"), (0x94, "zpx"), (0x8C, "abs")],
}.items():
    for code, mode in codes:
        _op(code, mn, mode)
for code, mn in {0x10: "BPL", 0x30: "BMI", 0x50: "BVC", 0x70: "BVS", 0x90: "BCC", 0xB0: "BCS", 0xD0: "BNE",
                 0xF0: "BEQ"}.items():
    _op(code, mn, "rel")
for code, mn in {0x00: "BRK", 0x18: "CLC", 0x38: "SEC", 0x58: "CLI", 0x78: "SEI", 0xB8: "CLV", 0xD8: "CLD",
                 0xF8: "SED", 0xCA: "DEX", 0x88: "DEY", 0xE8: "INX", 0xC8: "INY", 0xEA: "NOP", 0x48: "PHA",
                 0x08: "PHP", 0x68: "PLA", 0x28: "PLP", 0x40: "RTI", 0x60: "RTS", 0xAA: "TAX", 0xA8: "TAY",
                 0xBA: "TSX", 0x8A: "TXA", 0x9A: "TXS", 0x98: "TYA"}.items():
    _op(code, mn, "imp")


def fmt(mn: str, mode: str, ops: bytes, pc: int) -> str:
    v = ops[0] if len(ops) == 1 else (ops[0] | ops[1] << 8 if len(ops) == 2 else 0)
    return mn + {
        "imp": "", "acc": "", "imm": f" #${v:02X}", "zp": f" ${v:02X}", "zpx": f" ${v:02X},X",
        "zpy": f" ${v:02X},Y", "izx": f" (${v:02X},X)", "izy": f" (${v:02X}),Y",
        "rel": f" ${(pc + 2 + (v - 256 if v > 127 else v)) & 0xFFFF:04X}",
        "abs": f" ${v:04X}", "abx": f" ${v:04X},X", "aby": f" ${v:04X},Y", "ind": f" (${v:04X})",
    }[mode]


def disasm(mem: bytes, base: int, start: int, end: int):
    """yields (address, bytes, text)"""
    pc = start
    while pc < end:
        i = pc - base
        op = mem[i]
        if op in OPS:
            mn, mode = OPS[op]
            n = MODES[mode]
            if i + n <= len(mem):
                yield pc, mem[i:i + n], fmt(mn, mode, mem[i + 1:i + n], pc)
                pc += n
                continue
        yield pc, mem[i:i + 1], f".byte ${op:02X}"
        pc += 1


def main() -> None:
    args = sys.argv[1:]
    num = lambda s: int(s.lstrip("$"), 16)  # noqa: E731
    if args and args[0] == "--raw":
        data = open(args[1], "rb").read()
        base = num(args[2])
        rest = args[3:]
    else:
        raw = open(args[0], "rb").read()
        base, data = raw[0] | raw[1] << 8, raw[2:]
        rest = args[1:]
    start = num(rest[0]) if rest else base
    end = num(rest[1]) if len(rest) > 1 else base + len(data)
    for pc, b, text in disasm(data, base, start, end):
        print(f"{pc:04X}  {' '.join(f'{x:02X}' for x in b):9} {text}")


if __name__ == "__main__":
    main()
