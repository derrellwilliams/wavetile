import SwiftUI

/// A flat segmented filter: a tinted capsule with the selected option in a deeper tinted capsule.
/// Stands in for the system segmented control and search scope bar, whose glass can't be toned
/// down; it matches the app's other tinted controls and sits on the screen margins.
public struct SegmentedFilter<Value: Hashable>: View {
    @Environment(\.theme) private var theme
    @Namespace private var selectionSpace
    @Binding private var selection: Value
    private let options: [(value: Value, title: String)]

    public init(selection: Binding<Value>, options: [(value: Value, title: String)]) {
        _selection = selection
        self.options = options
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection
                Button {
                    withAnimation(theme.motion.snappy) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(theme.typography.itemTitle)
                        .foregroundStyle(isSelected ? theme.palette.textPrimary : theme.palette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(theme.palette.tintPressed)
                                    .matchedGeometryEffect(id: "selection", in: selectionSpace)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(theme.spacing.xxs)
        .background(theme.palette.tint, in: .capsule)
        .sensoryFeedback(.selection, trigger: selection)
    }
}
