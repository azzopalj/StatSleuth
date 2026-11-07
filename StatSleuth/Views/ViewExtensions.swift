import SwiftUI

extension View {
    /// Constrains content to a readable max width on iPad for sheet/modal-style views.
    /// Use on sheets and overlay content — not on full-screen game/home layouts.
    func iPadContentFrame(maxWidth: CGFloat = 600) -> some View {
        self.frame(maxWidth: maxWidth)
    }

    /// Caps a full-screen column and centres it.
    ///
    /// The whole game is one column of cards. Left to fill an iPad in
    /// landscape it stretches to 1210pt: the feedback grid's eight cells end
    /// up a hand's width apart and the stat card is mostly empty space. On a
    /// phone the cap is wider than the screen, so nothing changes there.
    func centredColumn(maxWidth: CGFloat = 700) -> some View {
        self.frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}
