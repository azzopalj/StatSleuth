import Foundation

/// A request to go all the way back to the home screen.
///
/// The results screen's "Home" button called `dismiss()`, which pops one
/// level — from a game started off the pack list that landed the player back
/// on the pack list, not home. Every route into a game is presented by a
/// `navigationDestination(isPresented:)` binding on the home screen (or, for a
/// shared link, on `ContentView`), and clearing that binding pops everything
/// pushed above it in one go. This is how the request reaches them.
///
/// A counter rather than a flag: two trips home in a row are two distinct
/// events, and a flag that is already `true` raises no change.
@Observable
final class NavigationCoordinator {
    private(set) var popToRootToken = 0

    func popToRoot() {
        popToRootToken += 1
    }
}
