from __future__ import annotations
import sys
from pathlib import Path

def extract_strats(path: Path) -> set[str]:
    out: set[str] = set()
    for line in path.read_text(encoding='utf-8', errors='ignore').splitlines():
        line = line.strip()
        if not line:
            continue
        marker = ' : nfqws2 '
        if marker in line:
            strat = line.split(marker, 1)[1].strip()
            if strat:
                out.add(strat)
    return out


def main() -> int:
    if len(sys.argv) < 4:
        print('Usage: intersect_strats.py <tls12_summary> <tls13_summary> <out_file>')
        return 2

    tls12 = Path(sys.argv[1])
    tls13 = Path(sys.argv[2])
    out = Path(sys.argv[3])

    if not tls12.exists():
        print(f'Input not found: {tls12}')
        return 1
    if not tls13.exists():
        print(f'Input not found: {tls13}')
        return 1

    s12 = extract_strats(tls12)
    s13 = extract_strats(tls13)
    inter = sorted(s12 & s13)

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text('\n'.join(inter) + ('\n' if inter else ''), encoding='utf-8')
    print(f'Found {len(inter)} common strategies. Saved to {out}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())