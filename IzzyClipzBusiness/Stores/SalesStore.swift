import Foundation
import IzzyClipzKit
import Observation

/// Today's sales, at the bottom of Take payment (`GET /api/owner/sales`): every checkout of the shop
/// day, newest first, cash, card and other, with voided ones struck through, and Void sale
/// (`POST /api/owner/sales/:id/void`).
@MainActor
@Observable
final class SalesStore {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var day: IzzyAPI.SalesDay?
    private(set) var loadState: LoadState = .idle
    /// The last refresh failed while older sales are still on screen.
    private(set) var refreshError: String?
    /// Sales being voided right now.
    private(set) var voiding: Set<String> = []
    /// What the server said after the last void ("The sale was voided, so it no longer counts…").
    private(set) var voidMessages: [String: String] = [:]
    /// A void that didn't work, for an alert.
    var actionError: String?
    /// The same for a void from an appointment's details (its own alert, so Today's sales doesn't
    /// show it too).
    var appointmentVoidError: String?
    /// Called after a sale was voided (its appointment can be checked out again).
    @ObservationIgnored var onVoided: ((IzzyAPI.Sale) -> Void)?

    let shopTime: ShopTime
    @ObservationIgnored private let api: any OwnerAPI
    @ObservationIgnored private let clock: () -> Date
    /// Bumped by every load, so a slow answer never replaces a newer one.
    @ObservationIgnored private var generation = 0

    init(api: any OwnerAPI, shopTime: ShopTime, clock: @escaping () -> Date) {
        self.api = api
        self.shopTime = shopTime
        self.clock = clock
    }

    var sales: [IzzyAPI.Sale] { day?.sales ?? [] }

    /// "$184 · 5 sales", for the live (not voided) sales.
    var totalsText: String? {
        guard let totals = day?.totals else { return nil }
        let count = totals.count == 1 ? "1 sale" : "\(totals.count) sales"
        return "\(Money.amount(totals.totalCents)) · \(count)"
    }

    func sale(withID id: String) -> IzzyAPI.Sale? {
        sales.first { $0.id == id }
    }

    /// Loads today's sales (the shop's day). Keeps what's on screen if it fails.
    func refresh() async {
        generation += 1
        let requested = generation
        if loadState != .loaded { loadState = .loading }
        do {
            let today = shopTime.day(containing: clock())
            let loaded = try await api.sales(on: today)
            guard requested == generation else { return }
            day = loaded
            refreshError = nil
            loadState = .loaded
        } catch is CancellationError {
            if requested == generation, loadState == .loading { loadState = .idle }
        } catch {
            guard requested == generation else { return }
            let message = ErrorText.message(for: error)
            if loadState == .loaded {
                refreshError = message
            } else {
                loadState = .failed(message)
            }
        }
    }

    /// Voids a sale (after the owner confirmed it): it stops counting. Voiding a card sale doesn't
    /// refund the card; the server's message says refunds are made in the Stripe Dashboard.
    @discardableResult
    func void(_ sale: IzzyAPI.Sale, reason: String) async -> Bool {
        guard !voiding.contains(sale.id) else { return false }
        voiding.insert(sale.id)
        defer { voiding.remove(sale.id) }
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= Self.maxReasonLength else {
            actionError = "Keep the reason to 200 characters or fewer."
            return false
        }
        do {
            let answer = try await api.voidSale(id: sale.id, reason: trimmed.isEmpty ? nil : trimmed)
            generation += 1
            replace(answer.sale)
            voidMessages[sale.id] = answer.message
            onVoided?(answer.sale)
            return true
        } catch is CancellationError {
            return false
        } catch {
            actionError = ErrorText.message(for: error)
            return false
        }
    }

    static let maxReasonLength = 200

    /// Voids an appointment's sale from its details (after the owner confirmed it), whatever day it
    /// was made: Today's sales lists only today's, and a sale from an earlier day still has to be
    /// voidable before the appointment can be reopened, cancelled or marked a no-show.
    @discardableResult
    func void(_ sale: IzzyAPI.AppointmentSale, reason: String) async -> Bool {
        guard !voiding.contains(sale.id) else { return false }
        voiding.insert(sale.id)
        defer { voiding.remove(sale.id) }
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= Self.maxReasonLength else {
            appointmentVoidError = "Keep the reason to 200 characters or fewer."
            return false
        }
        do {
            let answer = try await api.voidSale(id: sale.id, reason: trimmed.isEmpty ? nil : trimmed)
            // Shown in Today's sales too, when it's one of today's.
            if shopTime.day(containing: answer.sale.soldAt) == shopTime.day(containing: clock()) {
                generation += 1
                replace(answer.sale)
            }
            voidMessages[sale.id] = answer.message
            onVoided?(answer.sale)
            return true
        } catch is CancellationError {
            return false
        } catch {
            appointmentVoidError = ErrorText.message(for: error)
            return false
        }
    }

    /// What Void asks first, with the amount: "Void this $58 cash sale?"
    static func voidQuestion(for sale: IzzyAPI.Sale) -> String {
        voidQuestion(totalCents: sale.totalCents, method: sale.method)
    }

    /// The same for an appointment's sale, from its details.
    static func voidQuestion(totalCents: Int, method: IzzyAPI.SaleMethod) -> String {
        "Void this \(Price.currencyString(cents: totalCents)) \(method.title.lowercased()) sale?"
    }

    /// Under the question: what voiding does, and for a card, that it doesn't refund it.
    static func voidExplanation(for sale: IzzyAPI.Sale) -> String {
        voidExplanation(method: sale.method, forAppointment: sale.appointmentId != nil)
    }

    static func voidExplanation(method: IzzyAPI.SaleMethod, forAppointment: Bool) -> String {
        var text = "It stops counting in your sales"
        text += forAppointment ? ", and the appointment can be checked out again." : "."
        if method == .card {
            text += " Voiding doesn't refund the card. Refund the card in your Stripe Dashboard."
        }
        return text
    }

    /// A sale as the list shows it: "11 AM · Diego Sample · Carlos · Cash".
    func rowDetail(for sale: IzzyAPI.Sale) -> String {
        [shopTime.time(sale.soldAt), sale.customerName ?? "Walk-in", sale.barberName, sale.method.title].joined(separator: " · ")
    }

    private func replace(_ sale: IzzyAPI.Sale) {
        var sales = self.sales
        if let index = sales.firstIndex(where: { $0.id == sale.id }) {
            sales[index] = sale
        } else {
            sales.append(sale)
        }
        sales.sort { $0.soldAt != $1.soldAt ? $0.soldAt > $1.soldAt : $0.id > $1.id }
        day = IzzyAPI.SalesDay(date: day?.date ?? shopTime.day(containing: clock()), sales: sales)
        if loadState != .loaded { loadState = .loaded }
    }
}
