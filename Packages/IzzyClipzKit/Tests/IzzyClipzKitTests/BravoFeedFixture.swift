import Foundation

/// Bravo's real `/products.json` feed from October 28, 2026, trimmed to the
/// fields the app reads (plus a few neighbors, so parsing ignores extras).
let bravoFeedFixture = #"""
{"products": [
    {"id": 8238742929585, "title": "Bravo Cutting Cape", "handle": "bravo-cutting-cape", "vendor": "BRAVO", "product_type": "", "variants": [
        {"id": 45165054099633, "title": "Default Title", "price": "20.99", "available": true, "compare_at_price": null}
    ]},
    {"id": 8447057133745, "title": "Bravo After-Shave", "handle": "bravo-after-shave", "vendor": "BRAVO", "product_type": "", "variants": [
        {"id": 45716306395313, "title": "Default Title", "price": "12.99", "available": true, "compare_at_price": null}
    ]},
    {"id": 8447057330353, "title": "Bravo Onyx Hair Gel", "handle": "bravo-onyx-hair-gel", "vendor": "BRAVO", "product_type": "", "variants": [
        {"id": 45716306821297, "title": "Default Title", "price": "19.99", "available": true, "compare_at_price": null}
    ]},
    {"id": 8216686723249, "title": "Bravo Backpack", "handle": "bravo-backpack", "vendor": "BRAVO", "product_type": "", "variants": [
        {"id": 45080967545009, "title": "Default Title", "price": "75.99", "available": true, "compare_at_price": null}
    ]},
    {"id": 8216275255473, "title": "Black Bravo Cutting Shears", "handle": "black-bravo-cutting-shears", "vendor": "BRAVO", "product_type": "", "variants": [
        {"id": 46057881731249, "title": "Cutting", "price": "199.99", "available": true, "compare_at_price": null},
        {"id": 46057881764017, "title": "6", "price": "199.99", "available": true, "compare_at_price": null},
        {"id": 46057881796785, "title": "6.5", "price": "199.99", "available": true, "compare_at_price": null},
        {"id": 46057881829553, "title": "7", "price": "199.99", "available": true, "compare_at_price": null}
    ]},
    {"id": 8216271913137, "title": "Silver Bravo Cutting Shears", "handle": "silver-bravo-cutting-shears", "vendor": "BRAVO", "product_type": "", "variants": [
        {"id": 45078200025265, "title": "Default Title", "price": "149.99", "available": true, "compare_at_price": "199.99"}
    ]},
    {"id": 8216114135217, "title": "Bravo Texture Powder", "handle": "bravo-texture-powder", "vendor": "BRAVO", "product_type": "", "variants": [
        {"id": 46751008653489, "title": "SINGLE", "price": "18.99", "available": true, "compare_at_price": null},
        {"id": 46751008686257, "title": "12 CT DISPLAY BOX", "price": "227.88", "available": true, "compare_at_price": null}
    ]},
    {"id": 8198406406321, "title": "Gold Bravo Cutting Shears", "handle": "gold-cutting-shears", "vendor": "BRAVO", "product_type": "", "variants": [
        {"id": 46056065958065, "title": "Straight", "price": "199.99", "available": true, "compare_at_price": null},
        {"id": 46056066875569, "title": "Texturizing", "price": "199.99", "available": true, "compare_at_price": null}
    ]},
    {"id": 8170824695985, "title": "Bravo Chapstick (3 count)", "handle": "bravo-chapstick-3-pack", "vendor": "BRAVO", "product_type": "", "variants": [
        {"id": 46396389916849, "title": "Default Title", "price": "2.99", "available": true, "compare_at_price": null}
    ]},
    {"id": 8003600449713, "title": "White Bravo Hair Gel 16oz.", "handle": "white-bravo-hair-gel-16oz", "vendor": "BRAVO", "product_type": "", "variants": [
        {"id": 44210087166129, "title": "medium / white / gel", "price": "17.99", "available": true, "compare_at_price": null}
    ]},
    {"id": 8003599171761, "title": "White Bravo Hair Gel 4oz.", "handle": "white-bravo-hair-gel-4oz", "vendor": "BRAVO", "product_type": "", "variants": [
        {"id": 44210085462193, "title": "small / white / gel", "price": "11.99", "available": true, "compare_at_price": null}
    ]},
    {"id": 8003597435057, "title": "Blue Bravo Hair Gel 16oz.", "handle": "blue-bravo-hair-gel-16oz", "vendor": "BRAVO", "product_type": "", "variants": [
        {"id": 44210083561649, "title": "medium / blue / gel", "price": "17.99", "available": true, "compare_at_price": null}
    ]},
    {"id": 8003591209137, "title": "Blue Bravo Hair Gel 4oz.", "handle": "blue-bravo-hair-gel-4oz", "vendor": "BRAVO", "product_type": "", "variants": [
        {"id": 44210076909745, "title": "small / blue / gel", "price": "11.99", "available": true, "compare_at_price": null}
    ]},
    {"id": 8003392176305, "title": "Bravo Blue Pomade", "handle": "bravo-blue-pomade", "vendor": "BRAVO", "product_type": "", "variants": [
        {"id": 44209408409777, "title": "$16.00", "price": "17.99", "available": true, "compare_at_price": null}
    ]},
    {"id": 7727024406705, "title": "Bravo Matte Clay", "handle": "bravo-matte-clay", "vendor": "BRAVO", "product_type": "Hair clay", "variants": [
        {"id": 43628496945329, "title": "Default Title", "price": "17.99", "available": true, "compare_at_price": null}
    ]}
]}
"""#
