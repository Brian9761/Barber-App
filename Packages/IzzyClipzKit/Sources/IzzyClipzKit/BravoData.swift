import Foundation

// Bravo Hair Gel, the shop's product sponsor. Products, prices and descriptions
// come from Bravo's own store (bravohairgel.com and its /products.json feed),
// checked October 28, 2026. Summaries and highlights condense Bravo's
// descriptions; they make no claims Bravo doesn't.
//
// Each product's `id` is its Shopify handle, so it doubles as the store link
// (bravohairgel.com/products/<id>) and the key for live prices.

extension ProductCatalog {
    public static let bravo = ProductCatalog(
        sponsor: Sponsor(
            name: "Bravo",
            fullName: "Bravo Hair Gel",
            tagline: "Designed by professionals, for professionals.",
            about: [
                "Bravo's mission is to empower barbers through quality products, tools, education and opportunities for growth. The brand is led by its founder, Joana Davila, who brings industry expertise from her roles as a stylist, salon owner and distributor for leading hair care brands.",
                "Skilled barbers and stylists test Bravo's products and formulas during development, and their feedback shapes each one before it's released.",
            ],
            storeURL: URL(string: "https://bravohairgel.com/")!,
            shippingNote: "Free shipping on U.S. orders $64+",
            phone: nil
        ),
        products: [
            Product(
                id: "blue-bravo-hair-gel-16oz",
                name: "Blue Hair Gel",
                size: "16 oz",
                category: .gels,
                price: Price(cents: 1799),
                summary: BravoCopy.gelSummary,
                highlights: BravoCopy.gelHighlights,
                isFeatured: true
            ),
            Product(
                id: "white-bravo-hair-gel-16oz",
                name: "White Hair Gel",
                size: "16 oz",
                category: .gels,
                price: Price(cents: 1799),
                summary: BravoCopy.gelSummary,
                highlights: BravoCopy.gelHighlights,
                isFeatured: true
            ),
            Product(
                id: "bravo-onyx-hair-gel",
                name: "Onyx Hair Gel",
                size: "16 oz",
                category: .gels,
                price: Price(cents: 1999),
                summary: "A firm-hold gel for strong, all-day control with a clean, professional finish. Its subtle black tint enhances darker hair and helps temporarily blend grey or white hairs.",
                highlights: [
                    "Firm, all-day hold for structured or relaxed styles",
                    "No alcohol flaking or sticky residue",
                    "Subtle black tint enhances dark hair tones",
                    "Helps temporarily blend grey and white hairs",
                    "Adds definition with a clean, professional finish",
                ],
                isFeatured: true
            ),
            Product(
                id: "blue-bravo-hair-gel-4oz",
                name: "Blue Hair Gel",
                size: "4 oz",
                category: .gels,
                price: Price(cents: 1199),
                summary: BravoCopy.gelSummary,
                highlights: BravoCopy.gelHighlights
            ),
            Product(
                id: "white-bravo-hair-gel-4oz",
                name: "White Hair Gel",
                size: "4 oz",
                category: .gels,
                price: Price(cents: 1199),
                summary: BravoCopy.gelSummary,
                highlights: BravoCopy.gelHighlights
            ),
            Product(
                id: "bravo-matte-clay",
                name: "Matte Clay",
                category: .styling,
                price: Price(cents: 1799),
                summary: "Serious hold without unwanted shine. This styling clay gives all-day control and a natural, textured look, and it shapes and defines without stiffness or flaking.",
                highlights: [
                    "Strong, long-lasting hold for structured styles",
                    "Low-shine matte finish for a natural look",
                    "No flaking or stiff, crunchy feel",
                    "Easy to restyle throughout the day",
                    "Paraben-free, and works on wet or dry hair",
                ],
                isFeatured: true
            ),
            Product(
                id: "bravo-texture-powder",
                name: "Texture Powder",
                category: .styling,
                price: Price(cents: 1899),
                summary: "A lightweight powder that instantly adds volume, grip and definition, so flat or fine hair looks fuller in seconds. It leaves a natural finish with no sticky residue.",
                highlights: [
                    "Instantly adds volume and thickness",
                    "Lightweight, with no sticky or greasy feel",
                    "Boosts root lift for fuller-looking hair",
                    "Ideal for fine, thin or flat hair",
                    "Great for messy, textured or matte styles",
                ]
            ),
            Product(
                id: "bravo-blue-pomade",
                name: "Blue Pomade",
                category: .styling,
                price: Price(cents: 1799),
                summary: "A pomade for clean, controlled styles with a polished, medium-to-high shine. It applies smoothly and is made with nourishing oils and natural extracts.",
                highlights: [
                    "Strong, reliable hold for structured styles",
                    "Sleek, medium-to-high shine finish",
                    "Smooth application with easy distribution",
                    "Made for slick-backs, pompadours, side parts and classic cuts",
                    "Flexible control without heavy buildup",
                ]
            ),
            Product(
                id: "bravo-after-shave",
                name: "After-Shave Spray",
                category: .grooming,
                price: Price(cents: 1299),
                summary: "A finishing spray that instantly cools and soothes skin after a shave. Its crisp, masculine scent wears like a subtle cologne, and it dries fast without heavy residue.",
                highlights: [
                    "Instantly cools and refreshes post-shave skin",
                    "Clean scent with a cologne-like finish",
                    "Lightweight, fast-drying formula",
                    "No heavy residue or greasy feel",
                    "Leaves skin feeling smooth and revitalized",
                ]
            ),
            Product(
                id: "bravo-chapstick-3-pack",
                name: "Mint Lip Balm",
                size: "3 pack",
                category: .grooming,
                price: Price(cents: 299),
                summary: "A mint-infused lip balm that keeps lips smooth and hydrated. The lightweight formula glides on easily and helps prevent dryness and chapping.",
                highlights: [
                    "Long-lasting hydration",
                    "Smooth, non-greasy application",
                    "Refreshing mint feel",
                    "Helps prevent dryness and chapping",
                    "Compact and easy to carry",
                ]
            ),
        ]
    )
}

/// Copy shared by products Bravo describes the same way.
enum BravoCopy {
    // Bravo uses one description for its blue and white gels in both sizes.
    static let gelSummary = "A professional-grade gel with dependable hold and natural-looking shine, without the heavy, greasy feel. It keeps sharp fades, slick backs and textured styles in place while staying flexible."

    static let gelHighlights = [
        "Strong, long-lasting hold for all hair types",
        "Adds shine without buildup",
        "Non-greasy formula for a clean finish",
        "Enriched with panthenol for healthy-looking hair",
        "UV filters help protect hair from environmental stress",
    ]
}
