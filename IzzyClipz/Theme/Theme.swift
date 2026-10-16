import SwiftUI

/// Brand colors, taken from the shop's sign: barber-pole red, white and navy.
enum Theme {
    static let red = Color(red: 0.80, green: 0.07, blue: 0.16)
    static let navy = Color(red: 0.06, green: 0.18, blue: 0.52)
    static let background = Color(red: 0.039, green: 0.051, blue: 0.086)
    static let surface = Color(red: 0.078, green: 0.098, blue: 0.157)
    static let surfaceRaised = Color(red: 0.118, green: 0.141, blue: 0.212)
    static let stroke = Color.white.opacity(0.08)
    static let secondaryText = Color.white.opacity(0.68)
    static let open = Color(red: 0.24, green: 0.80, blue: 0.47)
    static let soon = Color(red: 1.0, green: 0.73, blue: 0.24)

    static let cornerRadius: CGFloat = 20
    static let gutter: CGFloat = 20

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
enum Symbol {
    static let home = "house"
    static let services = "scissors"
    static let book = "calendar.badge.plus"
    static let team = "person.3"
    static let visit = "mappin.and.ellipse"
    static let reminders = "bell"
    static let remindersOn = "bell.fill"
    static let call = "phone.fill"
    static let directions = "arrow.triangle.turn.up.right.diamond.fill"
    static let instagram = "camera"
    static let website = "safari"
    static let share = "square.and.arrow.up"
    static let copy = "doc.on.doc"
    static let starFilled = "star.fill"
    static let starHalf = "star.leadinghalf.filled"
    static let starEmpty = "star"
    static let favorite = "heart"
    static let favoriteFilled = "heart.fill"
    static let included = "checkmark.circle.fill"
    static let clock = "clock"
    static let calendar = "calendar"
    static let payment = "creditcard"
    static let accessibility = "figure.roll"
    static let walkIn = "figure.walk"
    static let firstAvailable = "person.2.fill"
    static let close = "xmark"
    static let chevron = "chevron.right"
    static let gallery = "photo.on.rectangle"
    static let quote = "quote.opening"
    static let info = "info.circle"
    static let external = "arrow.up.right"
    static let map = "map"
    static let checkmark = "checkmark"

    /// Includes the symbols the shop data refers to.
    static var all: [String] {
        let own = [
            home, services, book, team, visit, reminders, remindersOn, call, directions, instagram, website,
            share, copy, starFilled, starHalf, starEmpty, favorite, favoriteFilled, included, clock, calendar,
            payment, accessibility, walkIn, firstAvailable, close, chevron, gallery, quote, info, external, map,
            checkmark,
        ]
        let data = Catalog.izzyClipz.services.map(\.symbol) + ServiceCategory.allCases.map(\.symbol)
        return Array(Set(own + data)).sorted()
    }
}
