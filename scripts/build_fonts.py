# Builds the static Archivo instances the Street Drip design uses from Google's variable Archivo[wdth,wght].ttf,
# and copies Space Mono and Rubik Wet Paint as they are. usage: python3 -I make-fonts-street-drip.py <srcdir> <outdir>
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
