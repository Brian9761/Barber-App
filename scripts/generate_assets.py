#!/usr/bin/env python3
"""Generates the app's asset catalog.

Draws the app icon and launch logo (a barber pole in the shop's red, white and
navy), writes the brand colors, and optionally converts source photos into
image sets.

    python3 scripts/generate_assets.py                    # icon, logo, colors
    python3 scripts/generate_assets.py --photos DIR       # ...and photos

DIR should contain gallery_1 ... gallery_6 and storefront images in any format
Pillow can read (webp, jpg, png). Requires Pillow (`pip install Pillow`).
"""

import argparse
import json
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "IzzyClipz" / "Resources" / "Assets.xcassets"

RED = (204, 18, 41)
WHITE = (246, 246, 248)
BLUE = (28, 66, 176)
NAVY_TOP = (14, 38, 108)
NAVY_BOTTOM = (4, 8, 24)
BACKGROUND = (10, 13, 22)

SS = 4  # supersampling factor for smooth edges
INFO = {"author": "xcode", "version": 1}


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n")


def cylinder_shade(width: int, height: int, highlight_at: float = 0.3) -> Image.Image:
    """A horizontal light profile that makes a flat shape read as a cylinder."""
    row = []
    for x in range(width):
        t = (x + 0.5) / width
        light = 0.5 + 0.5 * math.sin(math.pi * t)
        row.append(int(255 * min(1.0, light)))
    shade = Image.new("L", (width, 1))
    shade.putdata(row)
    return shade.resize((width, height))


def highlight(width: int, height: int, center: float = 0.3, spread: float = 0.09, strength: float = 0.55) -> Image.Image:
    row = []
    for x in range(width):
        t = (x + 0.5) / width
        row.append(int(255 * strength * math.exp(-((t - center) ** 2) / (2 * spread**2))))
    mask = Image.new("L", (width, 1))
    mask.putdata(row)
    return mask.resize((width, height))


def rounded_mask(size: tuple, box: tuple, radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    return mask


def shaded_layer(size: tuple, box: tuple, base: Image.Image, radius: int) -> Image.Image:
    """Applies cylinder shading and a specular streak to `base` inside `box`."""
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    region = base.crop(box).convert("RGB")
    dark = Image.new("RGB", (w, h), (0, 0, 0))
    region = Image.composite(region, dark, cylinder_shade(w, h))
    region = Image.composite(Image.new("RGB", (w, h), (255, 255, 255)), region, highlight(w, h))
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    layer.paste(region, (x0, y0))
    alpha = rounded_mask(size, box, radius)
    layer.putalpha(alpha)
    return layer


def stripes(size: tuple, box: tuple) -> Image.Image:
    """Diagonal red / white / blue / white bands."""
    image = Image.new("RGB", size, WHITE)
    draw = ImageDraw.Draw(image)
    x0, y0, x1, y1 = box
    height = y1 - y0
    slant = 1.35 * height  # horizontal run of one band over the full height
    band = 82 * SS
    colors = [RED, WHITE, BLUE, WHITE]
    start = x0 - slant - band * 4
    index = 0
    x = start
    while x < x1 + band:
        draw.polygon(
            [(x, y1), (x + slant, y0), (x + slant + band, y0), (x + band, y1)],
            fill=colors[index % len(colors)],
        )
        x += band
        index += 1
    return image


def metal(size: tuple) -> Image.Image:
    return Image.new("RGB", size, (206, 211, 222))


def draw_pole(size: int, offset_y: int = 0) -> Image.Image:
    """The barber pole on a transparent canvas, `size` x `size` (already supersampled)."""
    canvas = (size, size)
    s = size / (1024 * SS)  # lets the same coordinates work at any canvas size

    def box(x0, y0, x1, y1):
        return tuple(int(v * SS * s) for v in (x0, y0 + offset_y, x1, y1 + offset_y))

    pole = Image.new("RGBA", canvas, (0, 0, 0, 0))

    glass = box(394, 262, 630, 800)
    pole.alpha_composite(shaded_layer(canvas, glass, stripes(canvas, glass), int(26 * SS * s)))

    for cap in (box(366, 214, 658, 272), box(366, 790, 658, 848)):
        pole.alpha_composite(shaded_layer(canvas, cap, metal(canvas), int(20 * SS * s)))

    neck = box(490, 186, 534, 222)
    pole.alpha_composite(shaded_layer(canvas, neck, metal(canvas), int(8 * SS * s)))
    foot = box(436, 846, 588, 884)
    pole.alpha_composite(shaded_layer(canvas, foot, metal(canvas), int(14 * SS * s)))

    # The ball on top.
    cx, cy, r = 512 * SS * s, (148 + offset_y) * SS * s, 46 * SS * s
    ball_box = tuple(int(v) for v in (cx - r, cy - r, cx + r, cy + r))
    ball = shaded_layer(canvas, ball_box, metal(canvas), int(r))
    pole.alpha_composite(ball)
    shine = Image.new("RGBA", canvas, (0, 0, 0, 0))
    sr = r * 0.32
    sx, sy = cx - r * 0.35, cy - r * 0.35
    ImageDraw.Draw(shine).ellipse((sx - sr, sy - sr, sx + sr, sy + sr), fill=(255, 255, 255, 170))
    pole.alpha_composite(shine.filter(ImageFilter.GaussianBlur(sr * 0.5)))
    return pole


def gradient_background(size: int) -> Image.Image:
    top = Image.new("RGB", (size, size), NAVY_TOP)
    bottom = Image.new("RGB", (size, size), NAVY_BOTTOM)
    mask = Image.linear_gradient("L").resize((size, size))
    background = Image.composite(bottom, top, mask)
    glow = Image.new("L", (size, size), 0)
    r = size * 0.42
    c = size / 2
    ImageDraw.Draw(glow).ellipse((c - r, c - r * 1.05, c + r, c + r * 0.95), fill=110)
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.12))
    return Image.composite(Image.new("RGB", (size, size), (44, 86, 210)), background, glow)


def make_icon() -> None:
    size = 1024 * SS
    icon = gradient_background(size).convert("RGBA")
    pole = draw_pole(size, offset_y=0)
    shadow_alpha = pole.getchannel("A").filter(ImageFilter.GaussianBlur(28 * SS))
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow.putalpha(ImageChops.multiply(shadow_alpha, Image.new("L", (size, size), 190)))
    icon.alpha_composite(shadow, (0, 18 * SS))
    icon.alpha_composite(pole)
    final = icon.convert("RGB").resize((1024, 1024), Image.Resampling.LANCZOS)  # App Store icons can't have alpha

    folder = CATALOG / "AppIcon.appiconset"
    folder.mkdir(parents=True, exist_ok=True)
    final.save(folder / "AppIcon.png", optimize=True)
    write_json(folder / "Contents.json", {
        "images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": INFO,
    })


def make_launch_logo() -> None:
    size = 1024 * SS
    pole = draw_pole(size)
    bbox = pole.getbbox()
    pole = pole.crop(bbox)
    points_height = 220
    folder = CATALOG / "LaunchLogo.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    images = []
    for scale in (1, 2, 3):
        height = points_height * scale
        width = round(pole.width * height / pole.height)
        name = f"LaunchLogo@{scale}x.png" if scale > 1 else "LaunchLogo.png"
        pole.resize((width, height), Image.Resampling.LANCZOS).save(folder / name, optimize=True)
        images.append({"filename": name, "idiom": "universal", "scale": f"{scale}x"})
    write_json(folder / "Contents.json", {"images": images, "info": INFO})


def color_set(name: str, rgb: tuple) -> None:
    r, g, b = (f"{c / 255:.3f}" for c in rgb)
    write_json(CATALOG / f"{name}.colorset" / "Contents.json", {
        "colors": [{
            "color": {"color-space": "srgb", "components": {"alpha": "1.000", "red": r, "green": g, "blue": b}},
            "idiom": "universal",
        }],
        "info": INFO,
    })


def photo_set(name: str, source: Path, max_width: int) -> None:
    image = Image.open(source).convert("RGB")  # dropping EXIF also drops any location data
    if image.width > max_width:
        image = image.resize((max_width, round(image.height * max_width / image.width)), Image.Resampling.LANCZOS)
    folder = CATALOG / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    image.save(folder / f"{name}.jpg", quality=85, optimize=True, progressive=False)
    write_json(folder / "Contents.json", {
        "images": [{"filename": f"{name}.jpg", "idiom": "universal"}],
        "info": INFO,
    })


def find(directory: Path, stem: str) -> Path:
    matches = sorted(p for p in directory.iterdir() if p.stem == stem)
    if not matches:
        raise SystemExit(f"Missing {stem}.* in {directory}")
    return matches[0]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--photos", type=Path, help="folder with gallery_1..6 and storefront images")
    args = parser.parse_args()

    write_json(CATALOG / "Contents.json", {"info": INFO})
    color_set("AccentColor", RED)
    color_set("LaunchBackground", BACKGROUND)
    make_icon()
    make_launch_logo()

    if args.photos:
        for index in range(1, 7):
            photo_set(f"Gallery{index}", find(args.photos, f"gallery_{index}"), max_width=750)
        photo_set("Storefront", find(args.photos, "storefront"), max_width=1000)

    print(f"Wrote {CATALOG.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
