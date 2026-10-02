"""Read the BRFSS 2023 fixed-width column layout from the official CDC layout page.

The ASCII data file has no header row: every variable lives at a fixed
(start column, field length) position. Those positions are taken from the
downloaded layout HTML (data/raw/llcp_varlayout_23_onecolumn.html) instead of
being typed in by hand, so a typo cannot silently shift a column.
"""
import html
import pathlib
import re

RAW = pathlib.Path(__file__).resolve().parent.parent / "data" / "raw"
LAYOUT_HTML = RAW / "llcp_varlayout_23_onecolumn.html"

ROW_RE = re.compile(
    r'<tr>\s*<td class="c data">(\d+)</td>\s*'
    r'<td class="c data">([^<]+)</td>\s*'
    r'<td class="c data">(\d+)</td>\s*</tr>'
)


def load_layout(path=LAYOUT_HTML):
    """Return {variable name: (zero-based start, length)}."""
    text = path.read_text(encoding="utf-8", errors="replace")
    layout = {}
    for start, name, length in ROW_RE.findall(text):
        layout[html.unescape(name).strip()] = (int(start) - 1, int(length))
    if not layout:
        raise ValueError(f"No layout rows found in {path}")
    return layout


def field(record, layout, name):
    """Extract one variable from a fixed-width record as a stripped string ('' = blank)."""
    start, length = layout[name]
    return record[start:start + length].strip()


if __name__ == "__main__":
    lay = load_layout()
    print(f"{len(lay)} variables in layout")
    for v in ("_STATE", "SEQNO", "IDATE", "SEXVAR", "GENHLTH", "_BMI5", "_URBSTAT"):
        print(v, lay.get(v))
