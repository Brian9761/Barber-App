#!/usr/bin/env python3
"""Generates the photos and colors of the app's asset catalog (IzzyClipz/Resources/Assets.xcassets).

They come from the shop's own photos and the app's palette, so re-running the script
reproduces them:

  AccentColor, BrandRed, BrandBlue, LaunchBackground      Street Drip colors (drip red,
                    royal blue, ink)
  Gallery1...6, Storefront   shop photos                       (needs --photos)

    python3 scripts/generate_assets.py
    python3 scripts/generate_assets.py --photos DIR

DIR holds gallery_1 ... gallery_6 and storefront in any format Pillow reads.
The script never uses the network.

The logo images aren't made here. Logo and LaunchLogo (and the owner app's Logo) are the
shop's official logo, the white art on a transparent background at 1x, 2x and 3x, and both
apps' AppIcon is that logo on black; all of them are rendered from a vector tracing of the
artwork the shop sent, so replace them as files when the logo changes.

Requires Pillow (`pip install Pillow`).
"""

import argparse
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "IzzyClipz" / "Resources" / "Assets.xcassets"
INFO = {"author": "xcode", "version": 1}

# Street Drip colors for the color sets (the same values as Theme.swift).
DRIP_RED = (215, 20, 28)   # #D7141C, the primary-action red
BLUE = (0, 48, 154)        # #00309A, Street Drip's `royal`
INK = (11, 11, 12)         # #0B0B0C, the canvas and the launch screen


# Catalog files ---------------------------------------------------------------------------------

def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n")


def color_set(name: str, rgb: tuple) -> None:
    r, g, b = (f"{c / 255:.3f}" for c in rgb)
    write_json(CATALOG / f"{name}.colorset" / "Contents.json", {
        "colors": [{
            "color": {"color-space": "srgb", "components": {"alpha": "1.000", "red": r, "green": g, "blue": b}},
            "idiom": "universal",
        }],
        "info": INFO,
    })


# Photos ----------------------------------------------------------------------------------------

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


# Main ------------------------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--photos", type=Path, help="folder with gallery_1..6 and storefront images")
    args = parser.parse_args()

    write_json(CATALOG / "Contents.json", {"info": INFO})
    color_set("AccentColor", DRIP_RED)
    color_set("BrandRed", DRIP_RED)
    color_set("BrandBlue", BLUE)
    color_set("LaunchBackground", INK)

    if args.photos:
        for index in range(1, 7):
            photo_set(f"Gallery{index}", find(args.photos, f"gallery_{index}"), max_width=750)
        photo_set("Storefront", find(args.photos, "storefront"), max_width=1000)
    else:
        print("No --photos: wrote the color sets only")

    print(f"Wrote {CATALOG.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
