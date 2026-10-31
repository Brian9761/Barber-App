import Foundation

// The shop's real data, collected from izzyclipzbarbershop.net, the shop's
// former Squire booking page, its Google Maps listing and its Yelp page.
//
// To update prices, add a barber or change hours, edit this file, then
// regenerate server/data/catalog.json (see CatalogExport). Each offering's
// `squireServiceID` is the menu item's ID from the shop's old Squire menu: it
// stays because offering IDs ("<barber>/<item>") are what the server books.

/// Identifiers the shop's data and links share.
enum IzzyClipzListing {
    static let fullName = "Izzy Clipz Barbershop"
    static let googlePlaceID = "ChIJGz5HChRv3IARYJJy_6jyRm8"
}

extension ShopInfo {
    public static let izzyClipz = ShopInfo(
        name: "Izzy Clipz",
        fullName: IzzyClipzListing.fullName,
        tagline: "Traditional & modern cuts in Oceanside",
        about: [
            "Welcome to Izzy Clipz. We cater to both traditional and modern hairstyles, making us your one-stop destination for exceptional grooming services.",
            "At Izzy Clipz, a haircut is more than just a service. It's an experience. Izzy and his team are dedicated to helping you look and feel your best, whether you're after a fresh cut, a bold new color or a precision shave.",
            "Walk-ins are welcome, and appointments are available for your convenience.",
        ],
        address: PostalAddress(
            street: "1919 Mission Ave",
            unit: "Ste 105",
            city: "Oceanside",
            state: "CA",
            postalCode: "92058"
        ),
        coordinate: Coordinate(latitude: 33.2034409, longitude: -117.364815),
        phone: PhoneNumber(digits: "4423413053"),
        timeZoneIdentifier: "America/Los_Angeles",
        schedule: WeeklySchedule([
            .monday: OpeningHours(opens: TimeOfDay(hour: 10), closes: TimeOfDay(hour: 19)),
            .tuesday: OpeningHours(opens: TimeOfDay(hour: 10), closes: TimeOfDay(hour: 19)),
            .wednesday: OpeningHours(opens: TimeOfDay(hour: 10), closes: TimeOfDay(hour: 19)),
            .thursday: OpeningHours(opens: TimeOfDay(hour: 10), closes: TimeOfDay(hour: 19)),
            .friday: OpeningHours(opens: TimeOfDay(hour: 10), closes: TimeOfDay(hour: 19)),
            .saturday: OpeningHours(opens: TimeOfDay(hour: 10), closes: TimeOfDay(hour: 19)),
            .sunday: OpeningHours(opens: TimeOfDay(hour: 10), closes: TimeOfDay(hour: 18)),
        ]),
        instagramHandle: "izzy_clipz_barbershop_",
        websiteURL: URL(string: "https://www.izzyclipzbarbershop.net")!,
        paymentMethods: ["Credit card", "Gift card"],
        highlights: ["Walk-ins welcome", "Appointments available", "Traditional & modern styles"],
        accessibility: ["Wheelchair accessible", "ADA-compliant entrance", "Accessible parking near the entrance"],
        googlePlaceID: IzzyClipzListing.googlePlaceID
    )
}

extension Catalog {
    public static let izzyClipz = Catalog(
        services: [
            Service(
                id: "haircut",
                name: "Haircut",
                category: .haircuts,
                summary: "A custom cut tailored to you, starting with a consultation and finished with clipper and shear work.",
                includes: ["Consultation", "Clipper & shear work", "Cut customized to you"],
                symbol: "scissors",
                isPopular: true
            ),
            Service(
                id: "military-haircut",
                name: "Military Haircut",
                category: .haircuts,
                summary: "A clean, sharp cut with clipper and shear work and a straight-razor finish.",
                includes: ["Consultation", "Clipper & shear work", "Straight-razor finish"],
                symbol: "shield"
            ),
            Service(
                id: "seniors-haircut",
                name: "Seniors Haircut",
                category: .haircuts,
                summary: "A classic cut for seniors with shear and clipper work and a trimmer finish.",
                includes: ["Consultation", "Shear & clipper work", "Trimmer finish"],
                symbol: "person"
            ),
            Service(
                id: "haircut-and-beard",
                name: "Haircut & Beard",
                category: .packages,
                summary: "The full service: a custom haircut plus beard work with a hot towel and a straight-razor finish.",
                includes: ["Consultation", "Clippers & shears", "Hot towel shave", "Straight-razor finish"],
                symbol: "mustache.fill",
                isPopular: true
            ),
            Service(
                id: "vip",
                name: "VIP",
                category: .packages,
                summary: "The works in one appointment: a haircut, a shave and a facial.",
                includes: ["Haircut", "Shave", "Facial"],
                symbol: "crown",
                isPopular: true
            ),
            Service(
                id: "hot-towel-shave",
                name: "Hot Towel Shave",
                category: .shaves,
                summary: "A classic straight-razor shave, prepped with pre-lather and hot towels.",
                includes: ["Pre-lather", "Hot towel application", "Straight-razor shave"],
                symbol: "flame",
                isPopular: true
            ),
            Service(
                id: "lightener",
                name: "Lightener Process",
                category: .colorAndTexture,
                summary: "Lightening only, no color. The final price depends on the design and your hair length.",
                includes: ["Lightener application", "No color added"],
                symbol: "sparkles"
            ),
            Service(
                id: "perm",
                name: "Perm",
                category: .colorAndTexture,
                summary: "A perm for lasting curl and texture. Plan on about four hours in the chair.",
                includes: ["Perm service"],
                symbol: "water.waves"
            ),
            Service(
                id: "hot-lather-shave",
                name: "Hot Lather Shave",
                category: .addOns,
                summary: "Hot lather and a straight razor on the sides and back of your fade.",
                includes: ["Hot lather", "Straight razor on the sides & back"],
                symbol: "drop"
            ),
            Service(
                id: "eyebrows",
                name: "Eyebrows",
                category: .addOns,
                summary: "A straight-razor eyebrow cleanup.",
                includes: ["Straight-razor detail"],
                symbol: "eye"
            ),
            Service(
                id: "mustache",
                name: "Mustache",
                category: .addOns,
                summary: "Mustache detail with a trimmer or straight razor.",
                includes: ["Trimmer or straight razor"],
                symbol: "mustache"
            ),
            Service(
                id: "enhancements",
                name: "Enhancements",
                category: .addOns,
                summary: "Enhancement spray on your lineup or haircut for extra definition.",
                includes: ["Enhancement spray"],
                symbol: "paintbrush"
            ),
        ],
        barbers: [
            Barber(
                id: "israel-flores",
                name: "Izzy",
                listedName: "Israel F.",
                title: "Owner · Barber",
                bio: "Izzy is a licensed barber and educator who believes a haircut is more than a service. It's an experience. He's the shop's go-to for color, lightener and perms, and a straight-razor shave specialist.",
                specialties: ["Color & lightener", "Perms", "VIP service", "Hot towel shaves"],
                instagramHandle: "izzy_clipz_"
            ),
            Barber(
                id: "carlos-rafael",
                name: "Carlos",
                listedName: "Carlos R.",
                title: "Barber",
                bio: "Every haircut with Carlos comes with mustache and eyebrow detail, straight-razor work and styling.",
                specialties: ["Detail work", "Straight-razor finish", "Styling"]
            ),
            Barber(
                id: "flowxbori",
                name: "Flowxbori",
                listedName: "Flowxbori",
                title: "Barber",
                bio: "Custom cuts, haircut and beard combos, hot towel shaves and seniors' cuts.",
                specialties: ["Custom cuts", "Hot towel shaves", "Seniors"]
            ),
            Barber(
                id: "cristian-ceja",
                name: "Cristian",
                listedName: "Cristian C.",
                title: "Barber",
                bio: "Custom cuts, military cuts, haircut and beard combos and quick hot towel shaves.",
                specialties: ["Custom cuts", "Military cuts", "Beard work"]
            ),
            Barber(
                id: "julian-ramos",
                name: "Julian",
                listedName: "Julian R.",
                title: "Barber",
                bio: "Custom cuts, haircut and beard combos, hot towel shaves and seniors' cuts.",
                specialties: ["Custom cuts", "Hot towel shaves", "Seniors"]
            ),
        ],
        offerings: IzzyClipzMenu.offerings
    )
}

/// Each barber's menu, item by item.
enum IzzyClipzMenu {
    // Menu item IDs, from the shop's old Squire menu. Offering IDs are built from them, so they
    // must not change.
    static let haircut45 = "bbb0c294-87a6-465d-9f55-6f579dcb399a"
    static let haircut60 = "0d069a9e-c5ea-4cca-ae34-3f38bf668940"
    static let haircutCarlos = "9343fc67-b196-4604-987e-a4a9b6b4cc41"
    static let military = "4cee4e88-564d-415e-a095-d47d89d132bc"
    static let militaryCarlos = "ff42ccab-844e-4afd-9ee1-0f6c5e2cf930"
    static let seniors = "90c9bf5d-e012-4164-a906-67638220e262"
    static let haircutAndBeard = "23936782-15f7-4ed5-9cde-ece8cc1d730c"
    static let vip = "9a33be59-43eb-445c-9c18-6435125b1f75"
    static let hotTowelShave30 = "dc8eaeeb-e359-48be-84ca-c877ae337e5d"
    static let hotTowelShave15 = "8a1817c8-0976-40f1-8fb9-924430377d0a"
    static let lightener = "8f795304-bb2d-4f55-bd37-a6fe6cabb43c"
    static let perm = "7e5d9547-5951-475e-87d9-9b915ca5684e"
    static let hotLatherShave = "a2f11804-e406-41f3-b763-6ebb3bddd1b0"
    static let eyebrows = "0b5b851e-ab05-44a1-8d42-dc9dbc5f02eb"
    static let mustache = "0a68da55-05a5-4a45-ac57-e60f5c15547a"
    static let enhancements = "6fe4e1ce-7e98-42dc-a581-d33fdbf57719"

    static let carlosCutNote = "Includes mustache & eyebrows, plus straight-razor detail and styling."

    static let offerings: [Offering] = [
        // Izzy
        Offering(squireServiceID: haircut60, serviceID: "haircut", barberID: "israel-flores", price: .dollars(40), durationMinutes: 60),
        Offering(squireServiceID: military, serviceID: "military-haircut", barberID: "israel-flores", price: .dollars(25), durationMinutes: 45),
        Offering(squireServiceID: haircutAndBeard, serviceID: "haircut-and-beard", barberID: "israel-flores", price: .dollars(55), durationMinutes: 60),
        Offering(squireServiceID: vip, serviceID: "vip", barberID: "israel-flores", price: .dollars(80), durationMinutes: 75),
        Offering(squireServiceID: hotTowelShave30, serviceID: "hot-towel-shave", barberID: "israel-flores", price: .dollars(30), durationMinutes: 30),
        Offering(squireServiceID: lightener, serviceID: "lightener", barberID: "israel-flores", price: .startingAt(dollars: 80), durationMinutes: 120),
        Offering(squireServiceID: perm, serviceID: "perm", barberID: "israel-flores", price: .dollars(150), durationMinutes: 240),

        // Carlos
        Offering(squireServiceID: haircutCarlos, serviceID: "haircut", barberID: "carlos-rafael", price: .dollars(45), durationMinutes: 45, note: carlosCutNote),
        Offering(squireServiceID: militaryCarlos, serviceID: "military-haircut", barberID: "carlos-rafael", price: .dollars(35), durationMinutes: 45, note: carlosCutNote),
        Offering(squireServiceID: haircutAndBeard, serviceID: "haircut-and-beard", barberID: "carlos-rafael", price: .dollars(60), durationMinutes: 60),
        Offering(squireServiceID: hotLatherShave, serviceID: "hot-lather-shave", barberID: "carlos-rafael", price: .dollars(5), durationMinutes: 15),
        Offering(squireServiceID: eyebrows, serviceID: "eyebrows", barberID: "carlos-rafael", price: .includedWithCut, durationMinutes: 15),
        Offering(squireServiceID: mustache, serviceID: "mustache", barberID: "carlos-rafael", price: .includedWithCut, durationMinutes: 15),
        Offering(squireServiceID: enhancements, serviceID: "enhancements", barberID: "carlos-rafael", price: .dollars(5), durationMinutes: 15),

        // Flowxbori
        Offering(squireServiceID: haircut45, serviceID: "haircut", barberID: "flowxbori", price: .dollars(35), durationMinutes: 45),
        Offering(squireServiceID: haircut60, serviceID: "haircut", barberID: "flowxbori", price: .dollars(40), durationMinutes: 60),
        Offering(squireServiceID: military, serviceID: "military-haircut", barberID: "flowxbori", price: .dollars(25), durationMinutes: 45),
        Offering(squireServiceID: seniors, serviceID: "seniors-haircut", barberID: "flowxbori", price: .dollars(16), durationMinutes: 30),
        Offering(squireServiceID: haircutAndBeard, serviceID: "haircut-and-beard", barberID: "flowxbori", price: .dollars(55), durationMinutes: 60),
        Offering(squireServiceID: hotTowelShave30, serviceID: "hot-towel-shave", barberID: "flowxbori", price: .dollars(30), durationMinutes: 30),

        // Cristian
        Offering(squireServiceID: haircut45, serviceID: "haircut", barberID: "cristian-ceja", price: .dollars(35), durationMinutes: 45),
        Offering(squireServiceID: military, serviceID: "military-haircut", barberID: "cristian-ceja", price: .dollars(25), durationMinutes: 45),
        Offering(squireServiceID: haircutAndBeard, serviceID: "haircut-and-beard", barberID: "cristian-ceja", price: .dollars(55), durationMinutes: 60),
        Offering(squireServiceID: hotTowelShave15, serviceID: "hot-towel-shave", barberID: "cristian-ceja", price: .dollars(30), durationMinutes: 15),

        // Julian
        Offering(squireServiceID: haircut45, serviceID: "haircut", barberID: "julian-ramos", price: .dollars(35), durationMinutes: 45),
        Offering(squireServiceID: military, serviceID: "military-haircut", barberID: "julian-ramos", price: .dollars(25), durationMinutes: 45),
        Offering(squireServiceID: seniors, serviceID: "seniors-haircut", barberID: "julian-ramos", price: .dollars(16), durationMinutes: 30),
        Offering(squireServiceID: haircutAndBeard, serviceID: "haircut-and-beard", barberID: "julian-ramos", price: .dollars(55), durationMinutes: 60),
        Offering(squireServiceID: hotTowelShave30, serviceID: "hot-towel-shave", barberID: "julian-ramos", price: .dollars(30), durationMinutes: 30),
    ]
}
