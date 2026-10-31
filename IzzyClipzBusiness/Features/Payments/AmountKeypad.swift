import SwiftUI

/// A cash-register keypad: digits push in from the right, so 3, 5, 0, 0 is
/// $35.00. Every key is at least 56 pt tall and named for VoiceOver.
struct AmountKeypad: View {
    @Binding var entry: AmountEntry
    @ScaledMetric(relativeTo: .title2) private var keyHeight: CGFloat = 56

    private enum Key: Hashable {
        case digit(Int)
        case doubleZero
        case delete
    }

    private let rows: [[Key]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)],
        [.doubleZero, .digit(0), .delete],
    ]

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { key in
                        button(for: key)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Amount keypad")
    }

    private func button(for key: Key) -> some View {
        Button {
            press(key)
        } label: {
            label(for: key)
                .font(.title2.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: max(keyHeight, BusinessTheme.minimumTapSize))
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.tertiarySystemFill)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: key))
        .accessibilityIdentifier(identifier(for: key))
        .modifier(DeleteHold(isDelete: key == .delete, entry: $entry))
    }

    @ViewBuilder
    private func label(for key: Key) -> some View {
        switch key {
        case .digit(let digit): Text("\(digit)")
        case .doubleZero: Text("00")
        case .delete: Image(systemName: "delete.left")
        }
    }

    private func press(_ key: Key) {
        switch key {
        case .digit(let digit): entry.append(digit: digit)
        case .doubleZero: entry.appendDoubleZero()
        case .delete: entry.deleteLast()
        }
    }

    private func accessibilityLabel(for key: Key) -> String {
        switch key {
        case .digit(let digit): return "\(digit)"
        case .doubleZero: return "Double zero"
        case .delete: return "Delete"
        }
    }

    private func identifier(for key: Key) -> String {
        switch key {
        case .digit(let digit): return "key-\(digit)"
        case .doubleZero: return "key-00"
        case .delete: return "key-delete"
        }
    }
}

/// Holding Delete clears the amount; VoiceOver gets a "Clear amount" action.
private struct DeleteHold: ViewModifier {
    let isDelete: Bool
    @Binding var entry: AmountEntry

    func body(content: Content) -> some View {
        if isDelete {
            content
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in entry.clear() })
                .accessibilityAction(named: "Clear amount") { entry.clear() }
        } else {
            content
        }
    }
}
