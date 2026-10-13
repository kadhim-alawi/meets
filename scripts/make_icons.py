"""Generates the Meets app icons (two overlapping rings on the dark screen)."""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

PAPER = (12, 12, 14, 255)
LIME = (210, 255, 61, 255)
INK = (243, 239, 230, 255)


def icon(size: int, maskable: bool = False) -> Image.Image:
    scale = 4
    s = size * scale
    img = Image.new("RGBA", (s, s), PAPER)
    d = ImageDraw.Draw(img)
    inset = 0.24 if maskable else 0.14
    w = s * (1 - 2 * inset)
    r = w * 0.31
    stroke = max(2, int(w * 0.085))
    cy = s / 2
    cx1 = s * inset + r + stroke / 2
    cx2 = s - s * inset - r - stroke / 2
    for cx, color in ((cx1, LIME), (cx2, INK)):
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=color, width=stroke)
    return img.resize((size, size), Image.LANCZOS)


def main(root: Path) -> None:
    web = root / "app" / "web"
    icon(32).save(web / "favicon.png")
    for n in (192, 512):
        icon(n).save(web / "icons" / f"Icon-{n}.png")
        icon(n, maskable=True).save(web / "icons" / f"Icon-maskable-{n}.png")
    icon(1024).save(root / "app" / "assets" / "icon-1024.png")


if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else "."))
