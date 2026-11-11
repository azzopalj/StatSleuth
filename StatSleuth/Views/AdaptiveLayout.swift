import SwiftUI

// MARK: - TwoPaneLayout

/// Two side-by-side panes for wide windows: an iPad, or the inner display of
/// iPhone Duo.
///
/// `ArrangementView` looks like the obvious fit and isn't. Held upright the
/// inner display is taller than it is wide, so a split arrangement stacks its
/// panes — and limiting it to the horizontal axis hides the second one
/// outright. The game wants two columns in that pose, so this keeps a plain
/// row and reads the fold for itself. It also runs on the iPads this app
/// supports below iOS 27.1, where neither API exists.
struct TwoPaneLayout<Leading: View, Trailing: View>: View {

    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        GeometryReader { proxy in
            let widths = paneWidths(in: proxy)
            HStack(spacing: widths.gap) {
                leading.frame(width: widths.leading)
                trailing.frame(width: widths.trailing)
            }
        }
    }

    /// Splits the width evenly, unless a fold runs down the window — then each
    /// pane stops at the fold, so nothing has to sit in the crease.
    private func paneWidths(in proxy: GeometryProxy) -> (leading: CGFloat, gap: CGFloat, trailing: CGFloat) {
        let width = proxy.size.width
        if let fold = proxy.activeFoldFrame {
            return (fold.minX, fold.width, width - fold.maxX)
        }
        return (width / 2, 0, width / 2)
    }
}

private extension GeometryProxy {
    /// The fold running down this view, while the device is partly folded.
    /// Local coordinates; nil on anything else, including every iPad.
    var activeFoldFrame: CGRect? {
        guard #available(iOS 27.1, *) else { return nil }
        return reservedRegions(kind: .division).first {
            $0.isActive && $0.frame.height > $0.frame.width
                && $0.frame.minX > 0 && $0.frame.maxX < size.width
        }?.frame
    }
}

// MARK: - Fold avoidance

extension View {
    /// Starts this view after the fold, for a wide control that would otherwise
    /// run through the crease. No effect unless the device is partly folded.
    func startingAfterFold(spacing: CGFloat) -> some View {
        modifier(StartAfterFold(spacing: spacing))
    }
}

extension View {
    /// Re-centres a wide column on the fold, so the middle of an even grid
    /// lands in the crease rather than a card. A side rail takes width from
    /// one edge only, which otherwise leaves the column's centre off the
    /// display's. No effect unless the device is partly folded.
    func centredOnFold() -> some View {
        modifier(CentreOnFold())
    }
}

private struct CentreOnFold: ViewModifier {

    /// Positive pushes the column toward the trailing edge.
    @State private var shift: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(.leading, max(shift, 0))
            .padding(.trailing, max(-shift, 0))
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.activeFoldFrame.map { 2 * ($0.midX - proxy.size.width / 2) } ?? 0
            } action: { newShift in
                shift = newShift
            }
    }
}

private struct StartAfterFold: ViewModifier {

    let spacing: CGFloat

    @State private var leadingInset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(.leading, leadingInset)
            // Measured outside the padding, so the inset can't feed back into
            // the frame it was worked out from.
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.activeFoldFrame.map { $0.maxX + spacing } ?? 0
            } action: { inset in
                leadingInset = inset
            }
    }
}

// MARK: - BarActionButton

/// A toolbar button that keeps its word in a normal bar and gains a symbol on
/// a side rail.
///
/// iPhone Duo only moves a toolbar item to the side if it has a symbol, but a
/// toolbar item given a symbol shows that symbol instead of its title
/// everywhere else too. Offering the symbol only when the bar really is
/// vertical keeps "Done" reading as "Done" on every other iPhone.
struct BarActionButton: View {

    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    init(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        if #available(iOS 27.1, *) {
            VerticalBarAware(title: title, systemImage: systemImage, action: action)
        } else {
            Button(title, action: action)
        }
    }
}

@available(iOS 27.1, *)
private struct VerticalBarAware: View {

    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    @Environment(\.toolbarVerticalEdge) private var verticalEdge

    var body: some View {
        if verticalEdge == nil {
            Button(title, action: action)
        } else {
            Button(title, systemImage: systemImage, action: action)
        }
    }
}
