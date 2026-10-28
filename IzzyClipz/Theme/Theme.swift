import SwiftUI

/// Brand colors, sampled from the shop's logo: barber-pole red, royal blue and white.
///
/// The app uses a light appearance so the logo sits on white, the way the shop
/// shows it everywhere else.
enum Theme {
    // Brand
    static let red = Color(red: 0.784, green: 0.063, blue: 0.180)
    static let redDeep = Color(red: 0.588, green: 0.039, blue: 0.118)
    static let blue = Color(red: 0.0, green: 0.188, blue: 0.604)
    static let blueBright = Color(red: 0.118, green: 0.329, blue: 0.839)
    static let blueDeep = Color(red: 0.024, green: 0.102, blue: 0.302)

    // Surfaces
    static let background = Color(red: 0.957, green: 0.965, blue: 0.984)
    static let surface = Color.white
    /// Light blue for chips, callouts and selected rows.
    static let tint = Color(red: 0.918, green: 0.941, blue: 0.984)

    // Text and lines
    static let ink = Color(red: 0.043, green: 0.071, blue: 0.161)
    static let secondaryText = ink.opacity(0.64)
    static let tertiaryText = ink.opacity(0.42)
    static let stroke = ink.opacity(0.08)
    static let shadow = blueDeep.opacity(0.10)

    // Status
    static let star = Color(red: 0.97, green: 0.68, blue: 0.0)
    static let open = Color(red: 0.10, green: 0.60, blue: 0.32)
    static let soon = Color(red: 0.89, green: 0.52, blue: 0.0)

    static let cornerRadius: CGFloat = 20
    static let gutter: CGFloat = 20

    /// Royal blue fading into navy, for heroes and featured cards.
    static let heroGradient = LinearGradient(
        colors: [blueBright, blue, blueDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Red for the main call to action.
    static let redGradient = LinearGradient(
        colors: [red, redDeep],
        startPoint: .top,
        endPoint: .bottom
    )

    static func color(for tone: StatusSummary.Tone) -> Color {
        switch tone {
        case .open: return open
        case .changingSoon: return soon
        case .closed: return red
        }
    }
}

extension Font {
    /// Heavy condensed type for titles, in the spirit of the shop's signage.
    /// Built on text styles, so it scales with Dynamic Type.
    static func display(_ style: Font.TextStyle) -> Font {
        .system(style).weight(.black).width(.condensed)
    }
}

/// Every SF Symbol the app uses, in one place so a test can check they exist.
/// All of them are in SF Symbols 5 (iOS 17).
enum Symbol {
    // Tabs
    static let home = "house"
    static let services = "scissors"
    static let book = "calendar.badge.plus"
    static let shop = "bag"
    static let visit = "mappin.and.ellipse"

    // Actions
    static let reminders = "bell"
    static let remindersOn = "bell.fill"
    static let call = "phone.fill"
    static let directions = "arrow.triangle.turn.up.right.diamond.fill"
    static let instagram = "camera"
    static let website = "safari"
    static let share = "square.and.arrow.up"
    static let copy = "doc.on.doc"
    static let external = "arrow.up.right"
    static let close = "xmark"
    static let chevron = "chevron.right"
    static let back = "chevron.left"
    static let more = "ellipsis.circle"
    static let remove = "trash"
    static let edit = "pencil"
    static let writeReview = "square.and.pencil"
    static let cart = "cart"
    static let buy = "bag.fill"

    // Content
    static let team = "person.3"
    static let starFilled = "star.fill"
    static let starHalf = "star.leadinghalf.filled"
    static let starEmpty = "star"
    static let favorite = "heart"
    static let favoriteFilled = "heart.fill"
    static let included = "checkmark.circle.fill"
    static let clock = "clock"
    static let calendar = "calendar"
    static let calendarAdd = "calendar.badge.plus"
    static let calendarClock = "calendar.badge.clock"
    static let payment = "creditcard"
    static let accessibility = "figure.roll"
    static let walkIn = "figure.walk"
    static let firstAvailable = "person.2.fill"
    static let gallery = "photo.on.rectangle"
    static let quote = "quote.opening"
    static let info = "info.circle"
    static let map = "map"
    static let location = "location.fill"
    static let checkmark = "checkmark"
    static let success = "checkmark.circle.fill"
    static let partner = "checkmark.seal.fill"
    static let shipping = "shippingbox"
    static let reviews = "text.bubble"
    static let morning = "sunrise"
    static let afternoon = "sun.max"
    static let evening = "sunset"
    static let sparkles = "sparkles"

    /// Includes the symbols the shop data refers to.
    static var all: [String] {
        let own = [
            home, services, book, shop, visit,
            reminders, remindersOn, call, directions, instagram, website, share, copy, external, close, chevron,
            back, more, remove, edit, writeReview, cart, buy,
            team, starFilled, starHalf, starEmpty, favorite, favoriteFilled, included, clock, calendar, calendarAdd,
            calendarClock, payment, accessibility, walkIn, firstAvailable, gallery, quote, info, map, location,
            checkmark, success, partner, shipping, reviews, morning, afternoon, evening, sparkles,
        ]
        let data = Catalog.izzyClipz.services.map(\.symbol) + ServiceCategory.allCases.map(\.symbol)
        return Array(Set(own + data)).sorted()
    }

    /// The icon for a part of the day on the booking calendar.
    static func symbol(for part: DayPart) -> String {
        switch part {
        case .morning: return morning
        case .afternoon: return afternoon
        case .evening: return evening
        }
    }
}
