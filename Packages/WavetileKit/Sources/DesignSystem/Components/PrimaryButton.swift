import SwiftUI

/// Full-width tan action button: dark all-caps label, 8pt corners. Dims when disabled and
/// swaps the label for a spinner while `isWorking`.
public struct PrimaryButton: View {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    private let title: LocalizedStringKey
    private let isWorking: Bool
    private let action: () -> Void

    public init(_ title: LocalizedStringKey, isWorking: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isWorking = isWorking
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .opacity(isWorking ? 0 : 1)
                if isWorking {
                    ProgressView().tint(theme.palette.background)
                }
            }
            .font(.custom(BrandFont.family, size: 13, relativeTo: .footnote).weight(.semibold))
            .foregroundStyle(theme.palette.background)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(theme.palette.accent, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.pressable)
        // Stay solid while working; only an unavailable action dims.
        .opacity(isEnabled || isWorking ? 1 : 0.4)
    }
}
