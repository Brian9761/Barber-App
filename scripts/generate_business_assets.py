#!/usr/bin/env python3
"""Generates the owner app's asset catalog (IzzyClipzBusiness/Resources/Assets.xcassets).

Everything comes from the customer app's own logo, so re-running the script
reproduces the catalog:

  AppIcon       1024 x 1024, no alpha: the shop's logo on a white rounded card
                (its blue letters vanish on black otherwise) over the dark
                background, with a red "Business" mark underneath, so the owner
                can tell it apart from the customer app on the home screen
  AccentColor   the shop's red, #D7141C (the customer app's `dripRed`)
  LaunchBackground  the launch screen's ink, #0B0B0C
  Logo          the logo on its white card, for the sign-in screen (@2x, @3x)

    python3 scripts/generate_business_assets.py
    python3 scripts/generate_business_assets.py --preview /tmp/icon-preview.png

The logo is read from IzzyClipz/Resources/Assets.xcassets/Logo.imageset/Logo.png
(PNG with alpha). The "Business" mark is set in Inter Bold (SIL Open Font
License); pass --font to use another bold sans serif.

Requires Pillow (`pip install Pillow`).
"""

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
LOGO = ROOT / "IzzyClipz" / "Resources" / "Assets.xcassets" / "Logo.imageset" / "Logo.png"
CATALOG = ROOT / "IzzyClipzBusiness" / "Resources" / "Assets.xcassets"
INFO = {"author": "xcode", "version": 1}

# The customer app's Street Drip colors (IzzyClipz/Theme/Theme.swift).
INK = (11, 11, 12)          # #0B0B0C
INK3 = (29, 29, 32)         # #1D1D20
RED = (215, 20, 28)         # #D7141C, dripRed
WHITE = (255, 255, 255)

FONT_CANDIDATES = [
    "/usr/share/fonts/opentype/inter/Inter-Bold.otf",
    "/Library/Fonts/Inter-Bold.otf",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]


def find_font(explicit):
    for candidate in ([explicit] if explicit else []) + FONT_CANDIDATES:
        if candidate and Path(candidate).exists():
            return candidate
    raise SystemExit("No bold font found; pass --font /path/to/Bold.ttf")


def write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n")


def logo_card(width, logo, radius_ratio=0.12, padding_ratio=0.07):
    """The logo on a white rounded card `width` wide, with alpha outside the corners."""
    trimmed = logo.crop(logo.getbbox())
    padding = int(width * padding_ratio)
    inner = width - 2 * padding
    scale = inner / trimmed.width
    scaled = trimmed.resize((inner, round(trimmed.height * scale)), Image.LANCZOS)
    height = scaled.height + 2 * padding
    card = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    mask = Image.new("L", (width, height), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, width - 1, height - 1), radius=int(width * radius_ratio), fill=255)
    white = Image.new("RGBA", (width, height), WHITE + (255,))
    card.paste(white, (0, 0), mask)
    card.alpha_composite(scaled, (padding, padding))
    return card


def app_icon(logo, font_path):
    size = 1024
    # A soft vertical gradient from ink3 to ink, so the icon isn't a flat black square.
    icon = Image.new("RGB", (size, size), INK)
    gradient = ImageDraw.Draw(icon)
    for y in range(size):
        t = y / (size - 1)
        color = tuple(round(INK3[i] * (1 - t) + INK[i] * t) for i in range(3))
        gradient.line([(0, y), (size, y)], fill=color)
    icon = icon.convert("RGBA")

    card = logo_card(760, logo)
    card_x = (size - card.width) // 2
    card_y = 112
    # A soft shadow under the card.
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow_mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(shadow_mask).rounded_rectangle(
        (card_x, card_y + 18, card_x + card.width, card_y + card.height + 18), radius=int(760 * 0.12), fill=150
    )
    shadow.putalpha(shadow_mask.filter(ImageFilter.GaussianBlur(24)))
    icon.alpha_composite(shadow)
    icon.alpha_composite(card, (card_x, card_y))

    # The "Business" mark: white text on a red pill under the card.
    font = ImageFont.truetype(font_path, 92)
    text = "Business"
    draw = ImageDraw.Draw(icon)
    left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
    text_w, text_h = right - left, bottom - top
    pill_w, pill_h = text_w + 120, text_h + 64
    pill_x = (size - pill_w) // 2
    pill_y = card_y + card.height + 52
    draw.rounded_rectangle((pill_x, pill_y, pill_x + pill_w, pill_y + pill_h), radius=pill_h // 2, fill=RED)
    draw.text((pill_x + (pill_w - text_w) // 2 - left, pill_y + (pill_h - text_h) // 2 - top), text, font=font, fill=WHITE)
    return icon.convert("RGB")


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
    parser.add_argument("--font", help="a bold sans serif for the Business mark (default: Inter Bold)")
    parser.add_argument("--preview", help="also write the icon at 180 and 60 px side by side to this PNG")
    args = parser.parse_args()

    logo = Image.open(LOGO).convert("RGBA")
    font_path = find_font(args.font)

    write_json(CATALOG / "Contents.json", {"info": INFO})

    icon = app_icon(logo, font_path)
    icon_dir = CATALOG / "AppIcon.appiconset"
    icon_dir.mkdir(parents=True, exist_ok=True)
    icon.save(icon_dir / "AppIcon.png", optimize=True)
    write_json(
        icon_dir / "Contents.json",
        {"images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}], "info": INFO},
    )

    color_set("AccentColor", RED)
    color_set("LaunchBackground", INK)

    # The sign-in screen's logo: 220 pt wide.
    logo_dir = CATALOG / "Logo.imageset"
    logo_dir.mkdir(parents=True, exist_ok=True)
    for scale in (2, 3):
        logo_card(220 * scale, logo).save(logo_dir / f"Logo@{scale}x.png", optimize=True)
    write_json(
        logo_dir / "Contents.json",
        {
            "images": [
                {"idiom": "universal", "scale": "1x"},
                {"filename": "Logo@2x.png", "idiom": "universal", "scale": "2x"},
                {"filename": "Logo@3x.png", "idiom": "universal", "scale": "3x"},
            ],
            "info": INFO,
        },
    )

    if args.preview:
        sheet = Image.new("RGB", (180 + 60 + 60, 200), (40, 40, 40))
        sheet.paste(icon.resize((180, 180), Image.LANCZOS), (10, 10))
        sheet.paste(icon.resize((60, 60), Image.LANCZOS), (220, 70))
        sheet.save(args.preview)
    print(f"Wrote {CATALOG.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
