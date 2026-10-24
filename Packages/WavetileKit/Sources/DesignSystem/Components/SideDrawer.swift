import SwiftUI

/// Twitter-style reveal drawer: the main content slides aside to uncover `drawer` underneath.
///
/// - `edge` is the side the drawer lives on: `.leading` slides content right (Twitter/X),
///   `.trailing` slides it left.
/// - Tap or drag the content to close; swipe in from `edge` to open while `edgeSwipeEnabled`.
///   For `.leading`, enable it only on root screens so it never fights the system back gesture.
/// - The content gets rounded corners and dims as it slides; feel is tuned via `Theme.motion`.
/// - With VoiceOver, the hidden layer is removed from the accessibility tree, and the
///   two-finger "escape" gesture closes the drawer.
public struct SideDrawer<Content: View, Drawer: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding private var isOpen: Bool
    private let edge: HorizontalEdge
    private let edgeSwipeEnabled: Bool
    private let content: Content
    private let drawer: Drawer

    /// Live finger translation while dragging.
    @GestureState(resetTransaction: Transaction(animation: .smooth)) private var dragOffset: CGFloat = 0

    public init(
        isOpen: Binding<Bool>,
        edge: HorizontalEdge = .leading,
        edgeSwipeEnabled: Bool = true,
        @ViewBuilder content: () -> Content,
        @ViewBuilder drawer: () -> Drawer
    ) {
        _isOpen = isOpen
        self.edge = edge
        self.edgeSwipeEnabled = edgeSwipeEnabled
        self.content = content()
        self.drawer = drawer()
    }

    public var body: some View {
        GeometryReader { proxy in
            let width = drawerWidth(in: proxy.size.width)
            let resting: CGFloat = isOpen ? width : 0
            let revealed = min(width, max(0, resting + direction * dragOffset))
            let offset = direction * revealed
            let progress = revealed / width

            ZStack(alignment: edge == .leading ? .leading : .trailing) {
                drawer
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    // Subtle parallax: the drawer drifts in slower than the content.
                    .offset(x: reduceMotion ? 0 : -direction * (1 - progress) * width * 0.25)
                    .opacity(0.4 + 0.6 * progress)
                    .accessibilityHidden(!isOpen)

                // Shapes ignore the safe area so the clip covers the status bar and tab bar regions too.
                let card = RoundedRectangle(cornerRadius: theme.radius.sheet * progress, style: .continuous)
                content
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .mask { card.ignoresSafeArea() }
                    .overlay {
                        card
                            .fill(.black.opacity(0.45 * progress))
                            .ignoresSafeArea()
                            .allowsHitTesting(isOpen)
                            .onTapGesture { setOpen(false) }
                            .accessibilityHidden(true)
                    }
                    .shadow(color: .black.opacity(0.5 * progress), radius: 24)
                    .offset(x: offset)
                    .accessibilityHidden(isOpen)
                    .gesture(dragGesture(width: width), isEnabled: isOpen)
                    .overlay(alignment: edge == .leading ? .leading : .trailing) {
                        // Edge strip for swipe-to-open.
                        if !isOpen && edgeSwipeEnabled {
                            Color.clear
                                .frame(width: 20)
                                .contentShape(.rect)
                                .gesture(dragGesture(width: width))
                        }
                    }
            }
            .background(theme.palette.background.ignoresSafeArea())
            .animation(theme.motion.resolve(theme.motion.smooth, reduceMotion: reduceMotion), value: isOpen)
        }
        .accessibilityAction(.escape) { setOpen(false) }
        .sensoryFeedback(.impact(weight: .light), trigger: isOpen)
    }

    /// +1 when content moves right to reveal a leading drawer, -1 for trailing.
    private var direction: CGFloat { edge == .leading ? 1 : -1 }

    /// Wider at accessibility text sizes so long words in the drawer don't break.
    private func drawerWidth(in total: CGFloat) -> CGFloat {
        dynamicTypeSize.isAccessibilitySize ? total * 0.92 : min(340, total * 0.84)
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($dragOffset) { value, state, _ in
                state = value.translation.width
            }
            .onEnded { value in
                // Decide by projected end position so a quick flick feels natural.
                let resting: CGFloat = isOpen ? width : 0
                let projected = resting + direction * value.predictedEndTranslation.width
                setOpen(projected > width / 2)
            }
    }

    private func setOpen(_ open: Bool) {
        withAnimation(theme.motion.resolve(theme.motion.smooth, reduceMotion: reduceMotion)) {
            isOpen = open
        }
    }
}

#Preview {
    @Previewable @State var isOpen = true
    SideDrawer(isOpen: $isOpen) {
        NavigationStack {
            Color.gray.opacity(0.2)
                .navigationTitle("Content")
                .toolbar { Button("Menu", glyph: .settings) { isOpen.toggle() } }
        }
    } drawer: {
        List { Text("Settings") }
    }
}
