import Foundation
@testable import IzzyClipzKit

let pacific = TimeZone(identifier: "America/Los_Angeles")!

var pacificCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = pacific
    return calendar
}

/// A moment on the shop's wall clock.
func pacificDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = 0
    return pacificCalendar.date(from: components)!
}

/// Monday through Saturday 10–7, Sunday 10–6: the shop's regular hours.
let shopClock = ShopInfo.izzyClipz.clock
