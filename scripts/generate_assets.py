#!/usr/bin/env python3
"""Generates the app's asset catalog (IzzyClipz/Resources/Assets.xcassets).

Everything comes from the shop's own artwork, so re-running the script
reproduces the catalog:

  Logo              the official logo with its white background removed (PNG with alpha)
  LogoMascot        just the barber-pole mascot, cut out of the logo (PNG with alpha)
  LaunchLogo        the logo on a white rounded sticker, 260 pt wide, tilted a few degrees,
                    with a soft shadow (@1x, @2x, @3x): the launch screen is ink, and the
                    logo's blue letters vanish on black
  AppIcon           1024 x 1024, no alpha: the logo on white over a barber-stripe band
  AccentColor, BrandRed, BrandBlue, LaunchBackground      Street Drip colors (drip red,
                    royal blue, ink)
  Bravo-<handle>    Bravo product photos, square on white      (needs --bravo-json)
  BravoLogo         Bravo's wordmark as a template image       (needs --bravo-json)
  Gallery1...6, Storefront   shop photos                       (needs --photos)

    python3 scripts/generate_assets.py --logo LOGO.jpg
    python3 scripts/generate_assets.py --logo LOGO.jpg --bravo-json products.json --photos DIR
    python3 scripts/generate_assets.py --launch-only

LOGO is the logo from izzyclipzbarbershop.net (the 1500 x 1150 JPEG on white).
products.json is https://bravohairgel.com/products.json; given it, the script
downloads each product's photo and Bravo's logo from Shopify's CDN. That is the
only time it uses the network. DIR holds gallery_1 ... gallery_6 and storefront
in any format Pillow reads.

    --icon A|B|C            which app icon design goes in the catalog (default A)
    --icon-candidates DIR   also writes all three designs and a comparison of them at 60 and 120 px
    --preview PNG           writes a contact sheet of everything generated
    --launch-only           rebuilds only LaunchLogo (and the color sets) from the catalog's own
                            Logo.png, leaving the logo, the mascot and the app icon untouched;
                            needs no source artwork
    --launch-tilt DEGREES   the launch sticker's tilt, counterclockwise when negative (default -5)
    --launch-preview PNG    writes LaunchLogo@3x on the ink launch background, to check it by eye

Requires Pillow and NumPy (`pip install Pillow numpy`).
"""

import argparse
import json
import tempfile
import time
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "IzzyClipz" / "Resources" / "Assets.xcassets"
INFO = {"author": "xcode", "version": 1}

# Brand colors, sampled from the logo. RED, NAVY and WHITE draw the app icon, which stays as it is.
RED = (200, 16, 46)        # #C8102E
BLUE = (0, 48, 154)        # #00309A, the wordmark's royal blue (Street Drip's `royal`)
NAVY = (6, 26, 77)         # #061A4D
WHITE = (255, 255, 255)
# Street Drip colors for the color sets (the same values as Theme.swift).
DRIP_RED = (215, 20, 28)   # #D7141C, the primary-action red
INK = (11, 11, 12)         # #0B0B0C, the canvas and the launch screen

# Cutting the logo out of its white background (values are 0-255 on the source JPEG).
WHITE_MIN = 220            # min(R, G, B) at or above this counts as white
PAPER = 252                # this light or lighter is fully transparent
SOLID_MARGIN = 20          # within this of the darkest nearby value counts as fully opaque
EDGE = 2                   # px: width of the anti-aliased edge measured from the background
INK_MAX = 100              # max(R, G, B) below this is the mascot's dark outline ink
LIGHT_MIN = 120            # pixels at least this light can be anti-aliasing (or white detail)
DETAIL_MAX = 0.0013        # enclosed white areas in the wordmark smaller than this share of the
                           # image are drawn details (razor rivets, handle slashes) and stay white;
                           # bigger ones are background (letter counters)

LAUNCH_WIDTH_PT = 260      # the sticker's width, white border included
LAUNCH_TILT = -5           # degrees; negative tilts it counterclockwise, like a sticker slapped on

# Bravo products shown in the app (Shopify handle -> which product photo is the cleanest packshot).
BRAVO_PRODUCTS = {
    "blue-bravo-hair-gel-16oz": 0,
    "white-bravo-hair-gel-16oz": 0,
    "bravo-onyx-hair-gel": 0,
    "blue-bravo-hair-gel-4oz": 0,
    "white-bravo-hair-gel-4oz": 0,
    "bravo-matte-clay": 0,
    "bravo-texture-powder": 0,
    "bravo-blue-pomade": 0,
    "bravo-after-shave": 0,
    "bravo-chapstick-3-pack": 0,
}
BRAVO_LOGO_URL = "https://cdn.shopify.com/s/files/1/0645/6380/6385/files/A_New_Design_3_2.png"  # site header
PRODUCT_SIZE = 900         # px, square
PRODUCT_FILL = 0.80        # the product's longer side as a share of the square


# Catalog files ---------------------------------------------------------------------------------

def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n")


def image_set(name: str, files: dict, properties: dict = None) -> None:
    """Writes `<name>.imageset`. `files` maps a scale ("1x"...) or None (single scale) to an image.
    RGB images are saved as JPEG, images with alpha as PNG."""
    folder = CATALOG / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    for old in folder.iterdir():
        if old.name != "Contents.json":
            old.unlink()
    entries = []
    for scale, image in files.items():
        suffix = "" if scale in (None, "1x") else f"@{scale}"
        if image.mode == "RGB":
            filename = f"{name}{suffix}.jpg"
            image.save(folder / filename, quality=85, optimize=True)
        else:
            filename = f"{name}{suffix}.png"
            image.save(folder / filename, optimize=True)
        entry = {"filename": filename, "idiom": "universal"}
        if scale:
            entry["scale"] = scale
        entries.append(entry)
    payload = {"images": entries, "info": INFO}
    if properties:
        payload["properties"] = properties
    write_json(folder / "Contents.json", payload)


def color_set(name: str, rgb: tuple) -> None:
    r, g, b = (f"{c / 255:.3f}" for c in rgb)
    write_json(CATALOG / f"{name}.colorset" / "Contents.json", {
        "colors": [{
            "color": {"color-space": "srgb", "components": {"alpha": "1.000", "red": r, "green": g, "blue": b}},
            "idiom": "universal",
        }],
        "info": INFO,
    })


# Mask helpers (boolean NumPy arrays) -----------------------------------------------------------

def mask_image(mask: np.ndarray) -> Image.Image:
    return Image.fromarray(mask.astype(np.uint8) * 255)


def dilate(mask: np.ndarray, radius: int) -> np.ndarray:
    return np.asarray(mask_image(mask).filter(ImageFilter.MaxFilter(2 * radius + 1))) > 127


def erode(mask: np.ndarray, radius: int) -> np.ndarray:
    return np.asarray(mask_image(mask).filter(ImageFilter.MinFilter(2 * radius + 1))) > 127


def label_components(mask: np.ndarray) -> tuple:
    """Labels the 4-connected regions of `mask` 1...n (0 = not in the mask). Returns (labels, n)."""
    parent = []

    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    runs, previous = [], []
    for y, row in enumerate(mask):
        edges = np.diff(np.concatenate(([0], row.astype(np.int8), [0])))
        current, j = [], 0
        for x0, x1 in zip(np.flatnonzero(edges == 1).tolist(), np.flatnonzero(edges == -1).tolist()):
            run = len(parent)
            parent.append(run)
            while j < len(previous) and previous[j][1] <= x0:
                j += 1
            k = j
            while k < len(previous) and previous[k][0] < x1:  # runs in the row above that overlap this one
                a, b = root(run), root(previous[k][2])
                parent[max(a, b)] = min(a, b)
                k += 1
            current.append((x0, x1, run))
            runs.append((y, x0, x1, run))
        previous = current
    labels = np.zeros(mask.shape, np.int32)
    ids = {}
    for y, x0, x1, run in runs:
        labels[y, x0:x1] = ids.setdefault(root(run), len(ids) + 1)
    return labels, len(ids)


def border_labels(labels: np.ndarray) -> np.ndarray:
    found = np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))
    return found[found > 0]


def fill_holes(mask: np.ndarray) -> np.ndarray:
    """`mask` plus every region it fully encloses."""
    labels, _ = label_components(~mask)
    return ~np.isin(labels, border_labels(labels))


# The logo ---------------------------------------------------------------------------------------

def cut_out_logo(source: Image.Image) -> tuple:
    """Removes the logo's white background. Returns (logo, mascot), RGBA, the size of `source`.

    1. The mascot is everything its dark ink outline encloses. The wordmark has no
       outline, so this separates the two even where the sneaker and the clippers
       overlap the letters.
    2. The background is the white connected to the image border, plus enclosed white
       that is really background: letter counters, and gaps closed off where the mascot
       touches the letters. White inside the mascot (pole stripes, eyes, cap, gloves,
       sneakers) and the small white details of the razor stay opaque.
    3. Along the background's edge, alpha comes from how close each pixel is to white
       relative to the solid color next to it, and the white is un-mixed from the color,
       so the edge stays anti-aliased without a white halo.
    """
    rgb = np.asarray(source.convert("RGB"), dtype=np.float32)
    lo, hi = rgb.min(axis=2), rgb.max(axis=2)
    height, width = lo.shape

    # The outline is one connected drawing (closed first, so hairline gaps don't leak);
    # the wordmark only has specks of dark blue shading, which this ignores.
    ink_labels, _ = label_components(erode(dilate(hi < INK_MAX, 2), 2))
    ink_sizes = np.bincount(ink_labels.ravel())
    ink_sizes[0] = 0
    mascot = fill_holes(ink_labels == ink_sizes.argmax())

    white = lo >= WHITE_MIN
    labels, count = label_components(white)
    sizes = np.bincount(labels.ravel(), minlength=count + 1)
    is_background = np.zeros(count + 1, bool)
    is_background[border_labels(labels)] = True
    near_mascot = dilate(mascot, 2)
    for i in range(1, count + 1):
        if is_background[i]:
            continue
        region = labels == i
        if mascot[region].mean() > 0.5:
            continue  # white inside the mascot
        if near_mascot[region].any() or sizes[i] > DETAIL_MAX * width * height:
            is_background[i] = True
    background = is_background[labels] & white
    art = ~background

    # Light areas that the art separates from the background (white details, light greys) stay opaque.
    light = art & (lo >= LIGHT_MIN)
    light_labels, _ = label_components(light)
    touching = np.unique(light_labels[dilate(background, 1) & light])
    protected = light & ~np.isin(light_labels, touching[touching > 0])

    darkest_nearby = np.asarray(Image.fromarray(lo.astype(np.uint8)).filter(ImageFilter.MinFilter(7)), np.float32)
    coverage = np.clip((PAPER - lo) / np.maximum(PAPER - (darkest_nearby + SOLID_MARGIN), 1), 0, 1)
    edge = (dilate(art, 1) & background) | (dilate(background, EDGE) & art & ~protected)
    alpha = art.astype(np.float32)
    alpha[edge] = coverage[edge]
    alpha[alpha < 2 / 255] = 0

    # Partly transparent pixels take the color of the darkest pixel near them (the solid
    # letter or outline color). That drops the white they were mixed with, and the
    # source's slightly dark sharpening rim along the letters.
    color = rgb.copy()
    ys, xs = np.nonzero((alpha > 0) & (alpha < 1))
    reach = 3
    windows = np.lib.stride_tricks.sliding_window_view(np.pad(lo, reach, mode="edge"), (2 * reach + 1,) * 2)
    darkest = windows[ys, xs].reshape(len(ys), -1).argmin(axis=1)
    dy, dx = np.divmod(darkest, 2 * reach + 1)
    color[ys, xs] = rgb[np.clip(ys + dy - reach, 0, height - 1), np.clip(xs + dx - reach, 0, width - 1)]

    def rgba(alpha_channel):
        return Image.fromarray(np.dstack([color, alpha_channel * 255]).round().astype(np.uint8), "RGBA")

    # The mascot keeps its anti-aliased edge against the background; where it touched
    # the letters, the cut is softened by a fraction of a pixel.
    keep = mascot | (dilate(mascot, EDGE + 1) & dilate(background, EDGE))
    soft = np.asarray(mask_image(keep).filter(ImageFilter.GaussianBlur(0.6)), np.float32) / 255
    soft[erode(keep, 1)] = 1
    return rgba(alpha), rgba(alpha * soft)


def trim(image: Image.Image, margin: float = 0.015) -> Image.Image:
    """Crops to the visible pixels plus a margin (a share of the content's longer side)."""
    x0, y0, x1, y1 = image.getchannel("A").point(lambda v: 255 if v >= 8 else 0).getbbox()
    pad = round(max(x1 - x0, y1 - y0) * margin)
    return image.crop((x0 - pad, y0 - pad, x1 + pad, y1 + pad))


def fit(image: Image.Image, width: int = None, height: int = None) -> Image.Image:
    """Scales to the given width or height (Pillow resamples RGBA premultiplied: no fringes)."""
    scale = width / image.width if width else height / image.height
    size = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
    return image.resize(size, Image.Resampling.LANCZOS)


# Launch logo ------------------------------------------------------------------------------------

def rounded_rect_mask(size: tuple, radius: float, ss: int = 4) -> Image.Image:
    """An anti-aliased rounded-rectangle mask (drawn `ss` times larger, then scaled down)."""
    big = Image.new("L", (size[0] * ss, size[1] * ss), 0)
    ImageDraw.Draw(big).rounded_rectangle((0, 0, size[0] * ss - 1, size[1] * ss - 1), radius=radius * ss, fill=255)
    return big.resize(size, Image.Resampling.LANCZOS)


def launch_sticker(logo: Image.Image, scale: int, tilt: float = LAUNCH_TILT) -> Image.Image:
    """The logo on a white rounded sticker, `LAUNCH_WIDTH_PT` wide at `scale`, tilted by `tilt` degrees,
    with the sticker shadow (0, 8, 18 pt, black 55%) below it.

    The border and corner radius follow the app's `LogoSticker`: 4.5% of the width, and 14 pt of
    radius per 120 pt of width. The canvas keeps the sticker centred (the shadow's room is equal on
    every side), so the launch screen centres the sticker, not the sticker plus its shadow.
    """
    width = LAUNCH_WIDTH_PT * scale
    border = round(LAUNCH_WIDTH_PT * 0.045 * scale)
    radius = 14 * LAUNCH_WIDTH_PT / 120 * scale
    art = fit(logo, width=width - 2 * border)
    sticker = Image.new("RGBA", (width, art.height + 2 * border), WHITE + (0,))
    sticker.putalpha(rounded_rect_mask(sticker.size, radius))
    sticker.alpha_composite(art, (border, border))

    # Rotated premultiplied, so the white edge doesn't pick up a dark fringe from the transparent pixels.
    turned = sticker.convert("RGBa").rotate(-tilt, resample=Image.Resampling.BICUBIC, expand=True).convert("RGBA")
    blur, drop = 9 * scale, 8 * scale
    margin = 3 * blur + drop
    canvas = Image.new("RGBA", (turned.width + 2 * margin, turned.height + 2 * margin), INK + (0,))
    shadow = Image.new("RGBA", turned.size, (0, 0, 0, 0))
    shadow.putalpha(turned.getchannel("A").point(lambda v: round(v * 0.55)))
    canvas.alpha_composite(shadow, (margin, margin + drop))
    canvas = Image.merge("RGBA", (*canvas.split()[:3], canvas.getchannel("A").filter(ImageFilter.GaussianBlur(blur))))
    canvas.alpha_composite(turned, (margin, margin))
    return canvas


def make_launch_logo(logo: Image.Image, tilt: float) -> dict:
    launch = {f"{s}x": launch_sticker(logo, s, tilt) for s in (1, 2, 3)}
    image_set("LaunchLogo", launch)
    return launch


# App icon designs -------------------------------------------------------------------------------

def stripe_band(width: int, height: int) -> Image.Image:
    """Diagonal red / white / blue / white barber stripes under a thin blue rule."""
    ss = 4  # drawn 4x larger, then scaled down for smooth edges
    band = Image.new("RGB", (width * ss, height * ss), WHITE)
    draw = ImageDraw.Draw(band)
    stripe, h = 34 * ss, height * ss
    colors = [RED, WHITE, BLUE, WHITE]
    x, i = -h - stripe * 4, 0
    while x < width * ss + stripe:
        draw.polygon([(x, h), (x + h, 0), (x + h + stripe, 0), (x + stripe, h)], fill=colors[i % 4])
        x, i = x + stripe, i + 1
    draw.rectangle((0, 0, width * ss, 7 * ss), fill=BLUE)
    return band.resize((width, height), Image.Resampling.LANCZOS)


def radial_gradient(size: int, inner: tuple, outer: tuple, center=(0.5, 0.42), radius=0.75) -> Image.Image:
    y, x = np.mgrid[0:size, 0:size] / size
    t = np.clip(np.hypot(x - center[0], y - center[1]) / radius, 0, 1)[..., None]
    pixels = np.array(inner) * (1 - t) + np.array(outer) * t
    return Image.fromarray(pixels.round().astype(np.uint8), "RGB")


def soft_glow(size: int, box: tuple, opacity: int, blur: float, color=WHITE) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse(box, fill=opacity)
    layer = Image.new("RGBA", (size, size), color + (0,))
    layer.putalpha(mask.filter(ImageFilter.GaussianBlur(blur)))
    return layer


def paste_center(canvas: Image.Image, art: Image.Image, center: tuple) -> None:
    canvas.alpha_composite(art, (round(center[0] - art.width / 2), round(center[1] - art.height / 2)))


def icon_a(logo: Image.Image, mascot: Image.Image) -> Image.Image:
    """The full logo on white, as large as fits, over a slim barber-stripe band."""
    size, pad, band_height = 1024, 72, 84
    canvas = Image.new("RGBA", (size, size), WHITE + (255,))
    available = size - band_height - 2 * pad
    art = fit(logo, width=size - 2 * pad)
    if art.height > available:
        art = fit(logo, height=available)
    paste_center(canvas, art, (size / 2, pad + available / 2))
    canvas.paste(stripe_band(size, band_height), (0, size - band_height))
    return canvas.convert("RGB")


def icon_b(logo: Image.Image, mascot: Image.Image) -> Image.Image:
    """The mascot on royal blue with a soft white glow behind it."""
    size = 1024
    canvas = radial_gradient(size, BLUE, NAVY).convert("RGBA")
    canvas.alpha_composite(soft_glow(size, (282, 230, 742, 850), 150, 90))
    art = fit(mascot, height=830)
    shadow = Image.new("RGBA", art.size, NAVY + (0,))
    shadow.putalpha(art.getchannel("A").point(lambda v: v * 0.45).filter(ImageFilter.GaussianBlur(14)))
    paste_center(canvas, shadow, (size / 2 + 6, size / 2 + 22))
    paste_center(canvas, art, (size / 2, size / 2 + 8))
    return canvas.convert("RGB")


def icon_c(logo: Image.Image, mascot: Image.Image) -> Image.Image:
    """The mascot on white inside a thin royal-blue ring."""
    size, ss = 1024, 4
    ring = Image.new("L", (size * ss, size * ss), 0)
    r, w, c = 430 * ss, 20 * ss, size * ss / 2
    ImageDraw.Draw(ring).ellipse((c - r, c - r, c + r, c + r), outline=255, width=w)
    canvas = Image.new("RGBA", (size, size), WHITE + (255,))
    canvas.paste(Image.new("RGBA", (size, size), BLUE + (255,)), (0, 0), ring.resize((size, size), Image.Resampling.LANCZOS))
    paste_center(canvas, fit(mascot, height=720), (size / 2, size / 2 + 4))
    return canvas.convert("RGB")


ICON_DESIGNS = {"A": icon_a, "B": icon_b, "C": icon_c}


def home_screen_mask(size: int) -> Image.Image:
    """Approximates the iOS icon shape (a squircle) so previews look like the home screen."""
    ss = 4
    y, x = (np.mgrid[0:size * ss, 0:size * ss] + 0.5) / (size * ss) * 2 - 1
    return mask_image(np.abs(x) ** 5 + np.abs(y) ** 5 <= 1).resize((size, size), Image.Resampling.LANCZOS)


def icon_comparison(icons: dict) -> Image.Image:
    """Each design at 180, 120 and 60 px, on a light and on a dark wallpaper."""
    font = label_font(20)
    cell, height = 214, 400
    sheet = Image.new("RGB", (len(icons) * cell * 2, height), WHITE)
    draw = ImageDraw.Draw(sheet)
    for column, (name, icon) in enumerate(icons.items()):
        for dark, wallpaper in enumerate([(236, 238, 243), (28, 32, 44)]):
            x = (column * 2 + dark) * cell
            draw.rectangle((x, 0, x + cell - 1, height), fill=wallpaper)
            draw.text((x + 14, 10), f"{name}{' on dark' if dark else ''}", fill=(128, 128, 140), font=font)
            for px, (dx, dy) in {180: (14, 44), 120: (14, 250), 60: (148, 280)}.items():
                small = icon.resize((px, px), Image.Resampling.LANCZOS)
                sheet.paste(small, (x + dx, dy), home_screen_mask(px))
    return sheet


# Bravo -----------------------------------------------------------------------------------------

def download(url: str, destination: Path) -> Path:
    request = urllib.request.Request(url, headers={"User-Agent": "IzzyClipz-assets/2"})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                destination.write_bytes(response.read())
            return destination
        except OSError as error:
            if attempt == 3:
                raise SystemExit(f"Couldn't download {url}: {error}")
            time.sleep(1 + attempt * 2)
    return destination


def sized(url: str, width: int) -> str:
    """A Shopify CDN image URL that serves the image at most `width` px wide."""
    return f"{url}{'&' if '?' in url else '?'}width={width}"


def product_square(photo: Image.Image) -> Image.Image:
    """Fits a product photo inside a white square without cropping the product or its shadow.

    The product itself (not its soft shadow) is sized and centered, so products shot
    with bigger shadows don't come out smaller; the shadow is then kept inside the square.
    """
    flat = Image.new("RGBA", photo.size, WHITE + (255,))
    flat.alpha_composite(photo.convert("RGBA"))
    pixels = np.asarray(flat.convert("RGB"), np.float32)
    border = np.concatenate([pixels[:4].reshape(-1, 3), pixels[-4:].reshape(-1, 3),
                             pixels[:, :4].reshape(-1, 3), pixels[:, -4:].reshape(-1, 3)])
    paper = np.median(border, axis=0)
    pixels = np.clip(pixels * (255 / np.maximum(paper, 1)), 0, 255)  # the studio white becomes pure white
    image = Image.fromarray(pixels.round().astype(np.uint8), "RGB")
    ink = Image.fromarray((255 - pixels.min(axis=2)).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2))
    whole = ink.point(lambda v: 255 if v > 4 else 0).getbbox() or (0, 0, *image.size)  # with the shadow
    body = ink.point(lambda v: 255 if v > 24 else 0).getbbox() or whole                 # just the product

    margin = round(PRODUCT_SIZE * 0.02)
    scale = min(PRODUCT_SIZE * PRODUCT_FILL / max(body[2] - body[0], body[3] - body[1]),
                (PRODUCT_SIZE - 2 * margin) / max(whole[2] - whole[0], whole[3] - whole[1]))
    piece = image.crop(whole)
    piece = piece.resize((round(piece.width * scale), round(piece.height * scale)), Image.Resampling.LANCZOS)

    def offset(body_start, body_end, whole_start, length):
        start = round(PRODUCT_SIZE / 2 - ((body_start + body_end) / 2 - whole_start) * scale)
        return min(max(start, margin), PRODUCT_SIZE - margin - length)

    square = Image.new("RGB", (PRODUCT_SIZE, PRODUCT_SIZE), WHITE)
    square.paste(piece, (offset(body[0], body[2], whole[0], piece.width), offset(body[1], body[3], whole[1], piece.height)))
    return square


def make_bravo(products_json: Path) -> dict:
    products = {p["handle"]: p for p in json.loads(products_json.read_text())["products"]}
    made = {}
    with tempfile.TemporaryDirectory() as folder:
        for handle, index in BRAVO_PRODUCTS.items():
            if handle not in products:
                raise SystemExit(f"{handle} isn't in {products_json}")
            src = products[handle]["images"][index]["src"]
            photo = Image.open(download(sized(src, 1200), Path(folder) / f"{handle}.img"))
            made[f"Bravo-{handle}"] = product_square(photo)
            image_set(f"Bravo-{handle}", {None: made[f"Bravo-{handle}"]})
        logo = Image.open(download(sized(BRAVO_LOGO_URL, 1080), Path(folder) / "bravo-logo.png")).convert("RGBA")
    made["BravoLogo"] = trim(logo, margin=0.02)
    # A one-color black wordmark: as a template image, SwiftUI tints it with the foreground style.
    image_set("BravoLogo", {None: made["BravoLogo"]}, {"template-rendering-intent": "template"})
    return made


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


# Preview ---------------------------------------------------------------------------------------

def label_font(size: int):
    try:
        return ImageFont.load_default(size=size)
    except TypeError:  # older Pillow
        return ImageFont.load_default()


def tile(background, art: Image.Image, size: tuple) -> Image.Image:
    """`art` centered on a color, or on a checkerboard when `background` is None."""
    if background is None:
        y, x = np.mgrid[0:size[1], 0:size[0]]
        light = ((x // 16 + y // 16) % 2).astype(bool)[..., None]
        canvas = Image.fromarray(np.where(light, 255, 210).repeat(3, axis=2).astype(np.uint8)).convert("RGBA")
    else:
        canvas = Image.new("RGBA", size, background + (255,))
    art = art.convert("RGBA")
    art.thumbnail((size[0] - 24, size[1] - 24), Image.Resampling.LANCZOS)
    paste_center(canvas, art, (size[0] / 2, size[1] / 2))
    return canvas


def tinted(image: Image.Image, color: tuple) -> Image.Image:
    solid = Image.new("RGBA", image.size, color + (255,))
    solid.putalpha(image.getchannel("A"))
    return solid


def write_preview(path: Path, logo, mascot, launch, icon, bravo: dict) -> None:
    wallpaper = (236, 238, 243)
    icon_shape = Image.composite(icon, Image.new("RGB", icon.size, wallpaper), home_screen_mask(icon.width))
    tiles = [
        ("Logo", tile(None, logo, (560, 450))),
        ("Logo on BrandBlue", tile(BLUE, logo, (560, 450))),
        ("LogoMascot", tile(None, mascot, (300, 450))),
        ("LogoMascot on BrandBlue", tile(BLUE, mascot, (300, 450))),
        ("LogoMascot on navy", tile(NAVY, mascot, (300, 450))),
        ("LaunchLogo@3x on ink", tile(INK, launch, (560, 450))),
        ("AppIcon", tile(wallpaper, icon_shape, (450, 450))),
    ]
    tiles += [(name, tile(WHITE, image, (300, 300))) for name, image in bravo.items() if name != "BravoLogo"]
    if "BravoLogo" in bravo:
        tiles += [("BravoLogo", tile(None, bravo["BravoLogo"], (420, 200))),
                  ("BravoLogo tinted white on navy", tile(NAVY, tinted(bravo["BravoLogo"], WHITE), (420, 200)))]

    font, width = label_font(20), 1880
    x, y, row_height, placed = 20, 20, 0, []
    for name, image in tiles:
        advance = max(image.width, round(font.getlength(name))) + 24
        if x + advance > width:
            x, y, row_height = 20, y + row_height + 50, 0
        placed.append((name, image, x, y))
        x, row_height = x + advance, max(row_height, image.height)
    sheet = Image.new("RGB", (width, y + row_height + 60), (246, 247, 250))
    draw = ImageDraw.Draw(sheet)
    for name, image, x, y in placed:
        sheet.paste(image.convert("RGB"), (x, y))
        draw.text((x, y + image.height + 8), name, fill=(11, 18, 41), font=font)
    sheet.save(path)


# Main ------------------------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--logo", type=Path, help="the official logo (JPEG or PNG on white)")
    parser.add_argument("--bravo-json", type=Path, help="Bravo's Shopify products.json (downloads the photos)")
    parser.add_argument("--photos", type=Path, help="folder with gallery_1..6 and storefront images")
    parser.add_argument("--icon", choices=sorted(ICON_DESIGNS), default="A", help="app icon design (default A)")
    parser.add_argument("--icon-candidates", type=Path, help="folder for all icon designs and compare.png")
    parser.add_argument("--preview", type=Path, help="contact sheet PNG of everything generated")
    parser.add_argument("--launch-only", action="store_true",
                        help="rebuild only LaunchLogo (and the color sets) from the catalog's Logo.png")
    parser.add_argument("--launch-tilt", type=float, default=LAUNCH_TILT,
                        help=f"the launch sticker's tilt in degrees (default {LAUNCH_TILT})")
    parser.add_argument("--launch-preview", type=Path, help="LaunchLogo@3x on the ink launch background, as a PNG")
    args = parser.parse_args()
    if args.preview and not args.logo:
        parser.error("--preview needs --logo")
    if args.launch_only and (args.logo or args.bravo_json or args.photos):
        parser.error("--launch-only rebuilds LaunchLogo alone; leave out --logo, --bravo-json and --photos")

    write_json(CATALOG / "Contents.json", {"info": INFO})
    color_set("AccentColor", DRIP_RED)
    color_set("BrandRed", DRIP_RED)
    color_set("BrandBlue", BLUE)
    color_set("LaunchBackground", INK)

    launch = None
    if args.launch_only:
        launch = make_launch_logo(Image.open(CATALOG / "Logo.imageset" / "Logo.png").convert("RGBA"), args.launch_tilt)
    elif args.logo:
        full, figure = cut_out_logo(Image.open(args.logo))
        logo, mascot = trim(full), trim(figure)
        image_set("Logo", {None: logo})
        image_set("LogoMascot", {None: mascot})
        launch = make_launch_logo(logo, args.launch_tilt)

        icons = {name: design(logo, mascot) for name, design in ICON_DESIGNS.items()}
        folder = CATALOG / "AppIcon.appiconset"
        folder.mkdir(parents=True, exist_ok=True)
        icons[args.icon].save(folder / "AppIcon.png", optimize=True)  # RGB: App Store icons can't have alpha
        write_json(folder / "Contents.json", {
            "images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
            "info": INFO,
        })
        if args.icon_candidates:
            args.icon_candidates.mkdir(parents=True, exist_ok=True)
            for name, image in icons.items():
                image.save(args.icon_candidates / f"icon_{name}.png")
            icon_comparison(icons).save(args.icon_candidates / "compare.png")
    else:
        print("No --logo: skipped Logo, LogoMascot, LaunchLogo and AppIcon")

    bravo = make_bravo(args.bravo_json) if args.bravo_json else {}

    if args.photos:
        for index in range(1, 7):
            photo_set(f"Gallery{index}", find(args.photos, f"gallery_{index}"), max_width=750)
        photo_set("Storefront", find(args.photos, "storefront"), max_width=1000)

    if args.preview:
        write_preview(args.preview, logo, mascot, launch["3x"], icons[args.icon], bravo)
    if args.launch_preview and launch:
        backdrop = Image.new("RGBA", (launch["3x"].width + 240, launch["3x"].height + 240), INK + (255,))
        paste_center(backdrop, launch["3x"], (backdrop.width / 2, backdrop.height / 2))
        backdrop.convert("RGB").save(args.launch_preview)

    print(f"Wrote {CATALOG.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
