#!/usr/bin/env python3
"""Generates the owner app's colors (IzzyClipzBusiness/Resources/Assets.xcassets).

  AccentColor   the shop's red, #D7141C (the customer app's `dripRed`)
  LaunchBackground  the launch screen's ink, #0B0B0C

    python3 scripts/generate_business_assets.py

The logo images aren't made here. Logo (the sign-in screen's, at 1x, 2x and 3x) is the
shop's official logo, the white art on a transparent background, and AppIcon is that logo
on black above a red "Business" mark, so the owner can tell it apart from the customer app
on the home screen. design/render-logo.js renders both from design/izzy-logo-white.svg, a
vector tracing of the artwork the shop sent.

Requires Python 3 only.
"""

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "IzzyClipzBusiness" / "Resources" / "Assets.xcassets"
INFO = {"author": "xcode", "version": 1}

# The customer app's Street Drip colors (IzzyClipz/Theme/Theme.swift).
INK = (11, 11, 12)          # #0B0B0C
RED = (215, 20, 28)         # #D7141C, dripRed


def write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n")


def color_set(name, rgb):
    components = {
        "alpha": "1.000",
        "red": f"{rgb[0] / 255:.3f}",
        "green": f"{rgb[1] / 255:.3f}",
        "blue": f"{rgb[2] / 255:.3f}",
    }
    write_json(
        CATALOG / f"{name}.colorset" / "Contents.json",
        {"colors": [{"color": {"color-space": "srgb", "components": components}, "idiom": "universal"}], "info": INFO},
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.parse_args()

    write_json(CATALOG / "Contents.json", {"info": INFO})
    color_set("AccentColor", RED)
    color_set("LaunchBackground", INK)
    print(f"Wrote {CATALOG.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
