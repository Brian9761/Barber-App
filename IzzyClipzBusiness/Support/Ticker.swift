import Foundation

/// Runs an action now and then every `interval` until the task is cancelled:
/// the schedule's auto-refresh. The view starts it in `.task`, so SwiftUI
/// cancels it when the screen goes away or the app leaves the foreground.
enum Ticker {
    static func run(every interval: Duration, _ action: () async -> Void) async {
        while !Task.isCancelled {
            await action()
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
        }
    }
}
