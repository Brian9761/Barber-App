import XCTest
@testable import IzzyClipzKit

final class TimestampTests: XCTestCase {
    typealias Timestamp = IzzyAPI.Timestamp

    func testFormatsTheContractForm() {
        XCTAssertEqual(Timestamp.string(from: utc(2026, 11, 2, 18)), "2026-11-02T18:00:00Z")
        XCTAssertEqual(Timestamp.string(from: utc(2027, 1, 5, 7, 4, 9)), "2027-01-05T07:04:09Z")
        XCTAssertEqual(Timestamp.string(from: Date(timeIntervalSince1970: 0)), "1970-01-01T00:00:00Z")
        XCTAssertEqual(Timestamp.string(from: utc(2028, 2, 29, 23, 59, 59)), "2028-02-29T23:59:59Z")
    }

    func testFormattingDropsFractionsByRoundingDown() {
        let base = utc(2026, 11, 2, 18)
        XCTAssertEqual(Timestamp.string(from: base.addingTimeInterval(0.999)), "2026-11-02T18:00:00Z")
        XCTAssertEqual(Timestamp.string(from: base.addingTimeInterval(-0.001)), "2026-11-02T17:59:59Z")
        // Before 1970, rounding down still goes to the earlier second.
        XCTAssertEqual(Timestamp.string(from: Date(timeIntervalSince1970: -0.5)), "1969-12-31T23:59:59Z")
        XCTAssertEqual(Timestamp.string(from: Date(timeIntervalSince1970: -86_400)), "1969-12-31T00:00:00Z")
    }

    func testFormattingClampsAbsurdDates() {
        XCTAssertEqual(Timestamp.string(from: .distantFuture), "4001-01-01T00:00:00Z")
        XCTAssertEqual(Timestamp.string(from: Date(timeIntervalSince1970: 1e13)), "9999-12-31T23:59:59Z")
        XCTAssertEqual(Timestamp.string(from: .distantPast), "0001-01-01T00:00:00Z")
        XCTAssertEqual(Timestamp.string(from: Date(timeIntervalSince1970: .nan)), "0001-01-01T00:00:00Z")
        XCTAssertEqual(Timestamp.string(from: Date(timeIntervalSince1970: .infinity)), "9999-12-31T23:59:59Z")
    }

    func testParsesTheContractForm() {
        XCTAssertEqual(Timestamp.date(from: "2026-11-02T18:00:00Z"), utc(2026, 11, 2, 18))
        XCTAssertEqual(Timestamp.date(from: "1970-01-01T00:00:00Z"), Date(timeIntervalSince1970: 0))
        XCTAssertEqual(Timestamp.date(from: "2028-02-29T12:30:15Z"), utc(2028, 2, 29, 12, 30, 15))
        XCTAssertEqual(Timestamp.date(from: "1969-12-31T23:59:59Z"), Date(timeIntervalSince1970: -1))
    }

    func testParsesFractionalSecondsOfAnyLength() {
        let base = utc(2026, 11, 2, 18)
        XCTAssertEqual(Timestamp.date(from: "2026-11-02T18:00:00.000Z"), base)
        XCTAssertEqual(Timestamp.date(from: "2026-11-02T18:00:00.5Z"), base.addingTimeInterval(0.5))
        XCTAssertEqual(Timestamp.date(from: "2026-11-02T18:00:00.25Z"), base.addingTimeInterval(0.25))
        let millis = Timestamp.date(from: "2026-11-02T18:00:00.123Z")!.timeIntervalSince(base)
        XCTAssertEqual(millis, 0.123, accuracy: 0.000_001)
        // Google's publishTime can carry nanoseconds; anything finer is ignored.
        let nanos = Timestamp.date(from: "2026-11-02T18:00:00.123456789Z")!.timeIntervalSince(base)
        XCTAssertEqual(nanos, 0.123_456_789, accuracy: 0.000_001)
        let tooFine = Timestamp.date(from: "2026-11-02T18:00:00.1234567891234Z")!.timeIntervalSince(base)
        XCTAssertEqual(tooFine, 0.123_456_789, accuracy: 0.000_001)
        // And formats back to whole seconds.
        XCTAssertEqual(Timestamp.string(from: Timestamp.date(from: "2026-11-02T18:00:00.999Z")!), "2026-11-02T18:00:00Z")
    }

    func testParsesOffsetsAndLowercase() {
        let moment = utc(2026, 11, 2, 18)
        XCTAssertEqual(Timestamp.date(from: "2026-11-02T18:00:00+00:00"), moment)
        XCTAssertEqual(Timestamp.date(from: "2026-11-02T10:00:00-08:00"), moment)
        XCTAssertEqual(Timestamp.date(from: "2026-11-02T10:00:00-0800"), moment)
        XCTAssertEqual(Timestamp.date(from: "2026-11-03T03:30:00+09:30"), moment)
        XCTAssertEqual(Timestamp.date(from: "2026-11-02t18:00:00z"), moment)
        // An offset that crosses midnight and a year boundary.
        XCTAssertEqual(Timestamp.date(from: "2026-12-31T20:00:00-05:00"), utc(2027, 1, 1, 1))
    }

    func testRejectsAnythingElse() {
        for bad in [
            "", "2026-11-02", "2026-11-02T18:00:00", "2026-11-02T18:00Z", "2026-11-02 18:00:00Z",
            "2026-11-02T18:00:00ZZ", "2026-11-02T18:00:00Z ", " 2026-11-02T18:00:00Z", "2026-11-02T18:00:00.Z",
            "2026-02-30T18:00:00Z", "2026-13-01T00:00:00Z", "2026-00-10T00:00:00Z", "2026-11-00T00:00:00Z",
            "2026-11-02T24:00:00Z", "2026-11-02T18:60:00Z", "2026-11-02T18:00:60Z", "2027-02-29T00:00:00Z",
            "2026-11-02T18:00:00+25:00", "2026-11-02T18:00:00+08", "2026-11-02T18:00:00+08:0",
            "26-11-02T18:00:00Z", "2026-1-02T18:00:00Z", "２０２６-11-02T18:00:00Z", "1777000000",
            "2026-11-02T18:00:00.5", "2026-11-02T18:00:00,5Z",
        ] {
            XCTAssertNil(Timestamp.date(from: bad), bad)
        }
    }

    func testRoundTripsEveryMinuteOfADSTChangeDay() {
        // Times are UTC, so daylight saving never matters; walk a whole day anyway.
        var moment = utc(2026, 11, 1, 0)
        for _ in 0..<(26 * 60) {
            let text = Timestamp.string(from: moment)
            XCTAssertEqual(Timestamp.date(from: text), moment, text)
            moment = moment.addingTimeInterval(60)
        }
    }

    func testMatchesFoundationsISO8601Formatter() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var moment = utc(1999, 12, 31, 23, 59, 59)
        for step in 0..<500 {
            XCTAssertEqual(Timestamp.string(from: moment), formatter.string(from: moment))
            XCTAssertEqual(Timestamp.date(from: formatter.string(from: moment)), moment)
            moment = moment.addingTimeInterval(TimeInterval(86_400 * 37 + step * 61))
        }
    }

    func testJSONCodersUseTheContractForm() throws {
        struct Wrapper: Codable, Equatable { let at: Date; let maybe: Date? }
        let value = Wrapper(at: utc(2026, 11, 2, 18), maybe: nil)
        let json = String(decoding: try IzzyAPI.makeEncoder().encode(value), as: UTF8.self)
        XCTAssertEqual(json, #"{"at":"2026-11-02T18:00:00Z"}"#)
        XCTAssertEqual(try decodeAPI(Wrapper.self, #"{"at":"2026-11-02T18:00:00.000Z","maybe":null}"#), value)
        XCTAssertThrowsError(try decodeAPI(Wrapper.self, #"{"at":"Nov 2, 2026"}"#)) { error in
            XCTAssertTrue(APIError.describe(error).contains("Nov 2, 2026"), APIError.describe(error))
        }
        XCTAssertThrowsError(try decodeAPI(Wrapper.self, #"{"at":1793642400}"#))
    }

    func testEncoderLeavesSlashesUnescaped() throws {
        let json = String(decoding: try IzzyAPI.makeEncoder().encode(["offeringId": "flowxbori/bbb0c294"]), as: UTF8.self)
        XCTAssertEqual(json, #"{"offeringId":"flowxbori/bbb0c294"}"#)
    }
}

final class LocalDateTests: XCTestCase {
    func testParsesAndFormatsYYYYMMDD() {
        let date = LocalDate("2026-11-02")
        XCTAssertEqual(date?.year, 2026)
        XCTAssertEqual(date?.month, 11)
        XCTAssertEqual(date?.day, 2)
        XCTAssertEqual(date?.description, "2026-11-02")
        XCTAssertEqual(LocalDate(year: 2027, month: 1, day: 5)?.description, "2027-01-05")
        XCTAssertEqual(LocalDate(year: 33, month: 1, day: 5)?.description, "0033-01-05")
        XCTAssertEqual(LocalDate("2028-02-29")?.description, "2028-02-29")
    }

    func testRejectsMalformedAndImpossibleDays() {
        for bad in ["", "2026-11-2", "2026-1-02", "26-11-02", "2026/11/02", "2026-11-02T00:00:00Z", " 2026-11-02",
                    "2026-11-02 ", "2026-02-29", "2026-02-30", "2026-04-31", "2026-13-01", "2026-00-01", "2026-01-00",
                    "0000-01-01", "+2026-11-02", "2026-11-0２"] {
            XCTAssertNil(LocalDate(bad), bad)
        }
        XCTAssertNil(LocalDate(year: 2026, month: 2, day: 29))
        XCTAssertNil(LocalDate(year: 10_000, month: 1, day: 1))
        XCTAssertNil(LocalDate(year: 2026, month: 12, day: 32))
    }

    func testOrderingAndArithmetic() {
        let days = ["2027-01-01", "2026-12-31", "2026-02-03", "2026-11-02"].compactMap(LocalDate.init)
        XCTAssertEqual(days.sorted().map(\.description), ["2026-02-03", "2026-11-02", "2026-12-31", "2027-01-01"])
        XCTAssertEqual(LocalDate("2026-12-31")!.adding(days: 1), LocalDate("2027-01-01"))
        XCTAssertEqual(LocalDate("2028-03-01")!.adding(days: -1), LocalDate("2028-02-29"))
        XCTAssertEqual(LocalDate("2026-11-02")!.adding(days: 60), LocalDate("2027-01-01"))
    }

    func testBridgesToCalendarDay() {
        let day = CalendarDay(year: 2026, month: 11, day: 1)
        XCTAssertEqual(LocalDate(day).description, day.id)
        XCTAssertEqual(LocalDate(day).calendarDay, day)
        XCTAssertEqual(LocalDate("2026-11-01")?.weekday, .sunday)
        XCTAssertEqual(LocalDate("2026-11-02")?.weekday, .monday)
    }

    func testTodayInTheShopsTimeZoneAroundMidnightAndDST() {
        // PDT until 2 AM on November 1, 2026, then PST (UTC-8).
        XCTAssertEqual(LocalDate(containing: utc(2026, 11, 1, 6, 59, 59), in: pacific).description, "2026-10-31")
        XCTAssertEqual(LocalDate(containing: utc(2026, 11, 1, 7), in: pacific).description, "2026-11-01")
        XCTAssertEqual(LocalDate(containing: utc(2026, 11, 2, 7, 59, 59), in: pacific).description, "2026-11-01")
        XCTAssertEqual(LocalDate(containing: utc(2026, 11, 2, 8), in: pacific).description, "2026-11-02")
        // Spring forward, March 8, 2026: midnight PST is 08:00 UTC.
        XCTAssertEqual(LocalDate(containing: utc(2026, 3, 8, 7, 59), in: pacific).description, "2026-03-07")
        XCTAssertEqual(LocalDate(containing: utc(2026, 3, 8, 8), in: pacific).description, "2026-03-08")
        // The same moment is a different day elsewhere.
        XCTAssertEqual(LocalDate(containing: utc(2026, 11, 2, 7), in: TimeZone(identifier: "Asia/Tokyo")!).description, "2026-11-02")
        // And matches the booking calendar's idea of the shop day.
        let calendar = ShopInfo.izzyClipz.bookingCalendar
        for hour in stride(from: 0, to: 72, by: 1) {
            let moment = utc(2026, 10, 31, 0).addingTimeInterval(TimeInterval(hour * 3_600))
            XCTAssertEqual(LocalDate(containing: moment, in: pacific).calendarDay, calendar.day(containing: moment))
        }
    }

    func testCodesAsAJSONString() throws {
        struct Wrapper: Codable, Equatable { let date: LocalDate }
        XCTAssertEqual(try decodeAPI(Wrapper.self, #"{"date":"2026-11-02"}"#).date, LocalDate("2026-11-02"))
        XCTAssertEqual(String(decoding: try IzzyAPI.makeEncoder().encode(Wrapper(date: LocalDate("2026-11-02")!)), as: UTF8.self),
                       #"{"date":"2026-11-02"}"#)
        XCTAssertThrowsError(try decodeAPI(Wrapper.self, #"{"date":"2026-11-02T00:00:00Z"}"#))
        XCTAssertThrowsError(try decodeAPI(Wrapper.self, #"{"date":20261102}"#))
    }
}
