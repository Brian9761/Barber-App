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

    /// What Void asks first, with the amount: "Void this $58 cash sale?"
    static func voidQuestion(for sale: IzzyAPI.Sale) -> String {
        "Void this \(sale.totalLabel) \(sale.method.title.lowercased()) sale?"
    }

    /// Under the question: what voiding does, and for a card, that it doesn't refund it.
    static func voidExplanation(for sale: IzzyAPI.Sale) -> String {
        var text = "It stops counting in your sales"
        text += sale.appointmentId != nil ? ", and the appointment can be checked out again." : "."
        if sale.method == .card {
            text += " Voiding doesn't refund the card. Refund the card in your Stripe Dashboard."
        }
        return text
    }

    /// A sale as the list shows it: "11 AM · Diego Sample · Carlos · Cash".
    func rowDetail(for sale: IzzyAPI.Sale) -> String {
        [shopTime.time(sale.soldAt), sale.customerName ?? "Walk-in", sale.barberName, sale.method.title].joined(separator: " · ")
    }

    /// A sale just recorded, shown right away (before the list loads again).
    func didRecord(_ sale: IzzyAPI.Sale) {
        guard shopTime.day(containing: sale.soldAt) == shopTime.day(containing: clock()) else { return }
        generation += 1
        replace(sale)
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
