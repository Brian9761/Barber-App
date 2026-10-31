import Foundation
import Observation

/// Who an appointment is for: a name and a US mobile number, as the client typed them.
struct CustomerDetails: Hashable, Codable {
    var name: String
    var phone: String

    static let maxNameLength = 60

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The number, if it's a valid US number.
    var phoneNumber: PhoneNumber? { PhoneNumber(parsing: phone) }

    /// What's wrong with the name, in words for the form, or `nil` when it's fine.
    var nameProblem: String? {
        if trimmedName.isEmpty { return "Enter your name so the shop knows who's coming." }
        if trimmedName.count > Self.maxNameLength { return "Use \(Self.maxNameLength) characters or fewer." }
        return nil
    }

    /// What's wrong with the number, or `nil` when it's a valid US number.
    var phoneProblem: String? {
        let typed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty { return "Enter your mobile number so the shop can reach you." }
        if phoneNumber == nil { return "Enter a 10-digit US number, like (442) 341-3053." }
        return nil
    }

    var isValid: Bool { nameProblem == nil && phoneProblem == nil }

    /// The details as the server takes them: the name trimmed, the number in E.164.
    var newCustomer: IzzyAPI.NewCustomer {
        IzzyAPI.NewCustomer(name: trimmedName, phone: phoneNumber?.e164 ?? phone)
    }

    /// "(442) 341-3053", or the number as typed if it doesn't parse.
    var displayPhone: String {
        phoneNumber?.display ?? phone.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The client's name and number, remembered on this iPhone (if they want) so the next booking is
/// quicker. They're only sent to the shop when an appointment is booked.
@MainActor
@Observable
final class CustomerDetailsStore {
    private enum Keys {
        static let name = "customer.name"
        static let phone = "customer.phone"
    }

    /// `nil` until the client books with "Remember me" on, or after "Forget".
    private(set) var saved: CustomerDetails?

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        if let name = defaults.string(forKey: Keys.name), let phone = defaults.string(forKey: Keys.phone) {
            let details = CustomerDetails(name: name, phone: phone)
            saved = details.isValid ? details : nil
        }
    }

    /// Keeps `details` for next time, tidied up: the name trimmed, the number formatted.
    func remember(_ details: CustomerDetails) {
        guard details.isValid else { return }
        let tidy = CustomerDetails(name: details.trimmedName, phone: details.displayPhone)
        saved = tidy
        defaults.set(tidy.name, forKey: Keys.name)
        defaults.set(tidy.phone, forKey: Keys.phone)
    }

    func forget() {
        saved = nil
        defaults.removeObject(forKey: Keys.name)
        defaults.removeObject(forKey: Keys.phone)
    }
}
