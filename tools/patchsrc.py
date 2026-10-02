"""Helper for same-size NET patches in src/wizard_of_wor.asm.

patch_line(src, context_before, line, replacement): the original `line` that directly follows the unique
text `context_before` becomes
    .if TARGET_PRG / replacement ; NET: was ... / .else / line / .fi
"""
def patch_line(s: str, context_before: str, line: str, replacement: str, comment: str = "") -> str:
    old = context_before + line + "\n"
    assert s.count(old) == 1, f"context not unique ({s.count(old)}): {context_before!r} {line!r}"
    note = comment or f"NET: was {line.strip()}"
    new = (context_before + "\t.if TARGET_PRG\n" + replacement + " ; " + note + "\n"
           "\t.else\n" + line + "\n\t.fi\n")
    return s.replace(old, new)
