#!/usr/bin/env python3
"""Builds the app's fonts (IzzyClipz/Resources/Fonts) for the Street Drip design.

Archivo comes from Google as one variable font; iOS registers static files, so this cuts the
eight static instances the app uses out of it (each with its own PostScript name, which is what
the app looks fonts up by), and copies Space Mono and Rubik Wet Paint as they are:

  ArchivoExtraCondensed-Black   width 62,  weight 900   display type, 24 pt and up
  ArchivoCondensed-ExtraBold    width 75,  weight 800   small display type, prices, the Instagram handle
  ArchivoExpanded-Black         width 125, weight 900   the wordmark
  ArchivoExpanded-ExtraBold     width 125, weight 800   button labels
  Archivo-Regular/Medium/SemiBold/Bold                  body, captions, names, tab labels
  SpaceMono-Regular, SpaceMono-Bold                     tags and numbers
  RubikWetPaint-Regular                                 the one dripping word

All three families are under the SIL Open Font License with no Reserved Font Names, so renamed
static instances are allowed; their license files sit next to the fonts.

    python3 -I scripts/build_fonts.py SRCDIR IzzyClipz/Resources/Fonts

SRCDIR holds the files from github.com/google/fonts, renamed with their folder as a prefix:

  archivo__Archivo[wdth,wght].ttf          ofl/archivo/Archivo[wdth,wght].ttf
  spacemono__SpaceMono-Regular.ttf         ofl/spacemono/SpaceMono-Regular.ttf
  spacemono__SpaceMono-Bold.ttf            ofl/spacemono/SpaceMono-Bold.ttf
  rubikwetpaint__RubikWetPaint-Regular.ttf ofl/rubikwetpaint/RubikWetPaint-Regular.ttf

Every file must also be listed under UIAppFonts in project.yml and IzzyClipz/Info.plist, and
in `BrandFont` (IzzyClipz/Theme/Typography.swift). Requires fontTools (`pip install fonttools`).
"""
import sys, shutil
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

src, out = sys.argv[1], sys.argv[2]
INSTANCES = [  # (wdth, wght, family, style)
    (62, 900, 'Archivo ExtraCondensed', 'Black'),
    (75, 800, 'Archivo Condensed', 'ExtraBold'),
    (125, 900, 'Archivo Expanded', 'Black'),
    (125, 800, 'Archivo Expanded', 'ExtraBold'),
    (100, 400, 'Archivo', 'Regular'),
    (100, 500, 'Archivo', 'Medium'),
    (100, 600, 'Archivo', 'SemiBold'),
    (100, 700, 'Archivo', 'Bold'),
]
for wdth, wght, family, style in INSTANCES:
    font = TTFont(f'{src}/archivo__Archivo[wdth,wght].ttf')
    inst = instancer.instantiateVariableFont(font, {'wdth': wdth, 'wght': wght}, updateFontNames=False)
    ps = family.replace(' ', '') + '-' + style
    full = f'{family} {style}'
    name = inst['name']
    # Static naming: each file is its own family on iOS, looked up by PostScript name.
    legacy_family = family if style in ('Regular', 'Bold') else full
    legacy_style = style if style in ('Regular', 'Bold') else 'Regular'
    for rec in list(name.names):
        if rec.nameID in (1, 2, 3, 4, 6, 16, 17, 25):
            name.removeNames(nameID=rec.nameID)
    name.setName(legacy_family, 1, 3, 1, 0x409)
    name.setName(legacy_style, 2, 3, 1, 0x409)
    name.setName(f'{ps};static', 3, 3, 1, 0x409)
    name.setName(full, 4, 3, 1, 0x409)
    name.setName(ps, 6, 3, 1, 0x409)
    name.setName(family, 16, 3, 1, 0x409)
    name.setName(style, 17, 3, 1, 0x409)
    for t in ('STAT',):
        if t in inst:
            del inst[t]
    inst['OS/2'].usWeightClass = wght
    inst['OS/2'].usWidthClass = {62: 2, 75: 3, 100: 5, 125: 7}[wdth]
    inst.save(f'{out}/{ps}.ttf')
    check = TTFont(f'{out}/{ps}.ttf')
    print(ps, check['name'].getDebugName(6), check['name'].getDebugName(4), check['OS/2'].usWeightClass, 'fvar' in check)
shutil.copy(f'{src}/spacemono__SpaceMono-Regular.ttf', f'{out}/SpaceMono-Regular.ttf')
shutil.copy(f'{src}/spacemono__SpaceMono-Bold.ttf', f'{out}/SpaceMono-Bold.ttf')
shutil.copy(f'{src}/rubikwetpaint__RubikWetPaint-Regular.ttf', f'{out}/RubikWetPaint-Regular.ttf')
for f in ('SpaceMono-Regular', 'SpaceMono-Bold', 'RubikWetPaint-Regular'):
    print(f, TTFont(f'{out}/{f}.ttf')['name'].getDebugName(6))
