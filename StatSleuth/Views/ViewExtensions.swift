import SwiftUI

extension View {
    /// Constrains content to a readable max width on iPad for sheet/modal-style views.
    /// Use on sheets and overlay content — not on full-screen game/home layouts.
    func iPadContentFrame(maxWidth: CGFloat = 600) -> some View {
        self.frame(maxWidth: maxWidth)
    }
}
