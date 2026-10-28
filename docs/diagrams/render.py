#!/usr/bin/env python3
"""Render the architecture sources as portable SVGs using the pinned Mermaid CLI."""
from pathlib import Path
import os
import re
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
IMAGE = 'ghcr.io/mermaid-js/mermaid-cli/mermaid-cli:11.12.0@sha256:bad64c9d9ad917c8dfbe9d9e9c162b96f6615ff019b37058638d16eb27ce7783'


def portable_svg(path: Path) -> None:
    """Preserve whitespace and a visible page in SVG viewers and image exporters."""
    svg = path.read_text()
    root = ET.fromstring(svg)
    if root.findall('.//{http://www.w3.org/2000/svg}foreignObject'):
        raise ValueError(f'{path.name}: export must use SVG text rather than HTML labels')
    left, top, width, height = root.attrib['viewBox'].split()
    svg = svg.replace('<svg ', '<svg xml:space="preserve" ', 1)
    background = f'<rect x="{left}" y="{top}" width="{width}" height="{height}" fill="#ffffff"/>'
    svg = re.sub(r'(<svg\b[^>]*>)', lambda match: match[1] + background, svg, count=1)
    ET.fromstring(svg)
    path.write_text(svg)


def main() -> None:
    for name in ('overview', 'runtime', 'authentication', 'delivery'):
        subprocess.run([
            'docker', 'run', '--rm', '--network', 'none', '-u', f'{os.getuid()}:{os.getgid()}',
            '-v', f'{ROOT}:/data', IMAGE,
            '-c', '/data/mermaid-config.json', '-i', f'/data/{name}.mmd',
            '-o', f'/data/{name}.svg', '-b', 'white',
        ], check=True)
        portable_svg(ROOT / f'{name}.svg')
        print(f'Rendered and validated {name}.svg', flush=True)


if __name__ == '__main__':
    main()
