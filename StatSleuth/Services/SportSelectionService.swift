import Foundation

/// Which sport the player is currently browsing.
///
/// Sport is a context rather than a step in the flow: it is remembered between
/// launches, and the home screen, pack list and daily challenge all read from
/// it. That keeps a one-sport player from answering the same question before
/// every game, and keeps the pack list from mixing 30 MLB teams with the NBA.
@Observable
final class SportSelectionService {

    private static let storageKey = "com.lucasazzopardi.StatSleuth.selectedSport"

    private(set) var selected: Sport

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey)
        selected = stored.flatMap(Sport.init(rawValue:)) ?? .baseball
    }

    func select(_ sport: Sport) {
        guard sport != selected else { return }
        selected = sport
        UserDefaults.standard.set(sport.rawValue, forKey: Self.storageKey)
    }

    /// Falls back to a sport that actually has players, so a remembered choice
    /// can't strand the player on an empty screen if that sport's data file
    /// becomes unreachable.
    func reconcile(available: [Sport]) {
        guard !available.isEmpty, !available.contains(selected),
              let fallback = available.first else { return }
        selected = fallback
        UserDefaults.standard.set(fallback.rawValue, forKey: Self.storageKey)
    }
}
