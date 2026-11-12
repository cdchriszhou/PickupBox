#!/usr/bin/env python3
"""Build multi-size Windows ICO + PNG from master art."""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent
SRC_CANDIDATES = [
    Path(r"C:\Users\zhouyl01\.cursor\projects\d-Works-CursorSpace-KaLaOK\assets\fh-kaok-icon-master.jpg"),
    ROOT / "fh-kaok-icon-master.png",
    ROOT / "fh-kaok-icon.jpg",
]
INST = ROOT.parent / "installer" / "assets"


def load_master() -> Image.Image:
    for p in SRC_CANDIDATES:
        if p.exists():
            print("source:", p)
            return Image.open(p).convert("RGBA")
    raise FileNotFoundError("master icon not found")


def main() -> None:
    img = load_master()
    w, h = img.size
    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    img = img.crop((left, top, left + side, top + side)).resize(
        (1024, 1024), Image.Resampling.LANCZOS
    )

    # Transparent outside rounded tile so Explorer doesn't show a black box
    mask = Image.new("L", (1024, 1024), 0)
    draw = ImageDraw.Draw(mask)
    pad, radius = 28, 196
    draw.rounded_rectangle((pad, pad, 1024 - pad, 1024 - pad), radius=radius, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(1.1))
    r, g, b, a = img.split()
    img.putalpha(Image.composite(a, mask, mask))

    png256 = ROOT / "fh-kaok-icon.png"
    img.resize((256, 256), Image.Resampling.LANCZOS).save(png256, optimize=True)
    print("wrote", png256)

    img.save(ROOT / "fh-kaok-icon-master.png", optimize=True)

    sizes = [16, 24, 32, 48, 64, 128, 256]
    icons = []
    for s in sizes:
        im = img.resize((s, s), Image.Resampling.LANCZOS)
        if s <= 32:
            im = im.filter(ImageFilter.UnsharpMask(radius=1.1, percent=150, threshold=2))
        icons.append(im)

    ico_path = ROOT / "fh-kaok.ico"
    icons[-1].save(
        ico_path,
        format="ICO",
        sizes=[(s, s) for s in sizes],
        append_images=icons[:-1],
    )
    print("wrote", ico_path, ico_path.stat().st_size, "bytes")

    INST.mkdir(parents=True, exist_ok=True)
    setup_ico = INST / "setup.ico"
    icons[-1].save(
        setup_ico,
        format="ICO",
        sizes=[(s, s) for s in sizes],
        append_images=icons[:-1],
    )
    print("wrote", setup_ico)


if __name__ == "__main__":
    main()
