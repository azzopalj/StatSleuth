import UIKit

// MARK: - HapticEngine
// Lightweight static wrapper around UIKit feedback generators.
// Call from the main thread / view layer only.

enum HapticEngine {

    /// Fired when a guess is correct — strong positive pulse
    static func correctGuess() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Fired when a guess is wrong — error pulse
    static func wrongGuess() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// Fired when a hint is revealed
    static func hint() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Fired when a player is selected from the search dropdown
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Generic light tap for button presses, row taps, sheet dismissals
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Heavier tap for important confirmations (purchase, unlock, etc.)
    static func impact() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Fired on the results reveal entrance — success or failure variant
    static func resultReveal(won: Bool) {
        if won {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }
}
