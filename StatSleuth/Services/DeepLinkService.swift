import Foundation

// MARK: - Deep Link

enum DeepLink: Equatable {
    /// `playerID` is the player's id in their own sport's data source — an MLB
    /// id for baseball, an ESPN athlete id otherwise. See `Player.sharedID`.
    case play(playerID: Int, sport: Sport, mode: GameMode, packType: String)
}

// MARK: - DeepLinkService

@Observable
final class DeepLinkService {

    private static let webBase = "https://azzopalj.github.io/StatSleuth"

    var pendingDeepLink: DeepLink? = nil

    // Handles both:
    //   Universal link: https://azzopalj.github.io/StatSleuth/?mlbID=...&mode=...&pack=...
    //   Custom scheme:  statsleuth://play?mlbID=...&mode=...&pack=...
    //
    // Links shared by older versions carry only `mlbID` and are always baseball.
    // Other sports add `id` and `sport`, so an old build receiving a new link
    // falls through harmlessly instead of opening the wrong player.
    func handle(url: URL) -> Bool {
        let isUniversalLink = url.host == "azzopalj.github.io" && url.path.hasPrefix("/StatSleuth")
        let isCustomScheme  = url.scheme == "statsleuth" && url.host == "play"
        guard isUniversalLink || isCustomScheme else { return false }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else { return false }

        // A repeated query parameter (?mode=a&mode=a) must not trap — last value wins.
        let params = Dictionary(
            queryItems.compactMap { item in item.value.map { (item.name, $0) } },
            uniquingKeysWith: { _, new in new }
        )

        guard let modeStr = params["mode"],
              let mode = GameMode(rawValue: modeStr) else { return false }

        let sport = params["sport"].flatMap(Sport.init(rawValue:)) ?? .baseball
        // `mlbID` is the legacy name and still the one baseball links use.
        guard let idStr = params["mlbID"] ?? params["id"],
              let playerID = Int(idStr) else { return false }

        let packType = params["pack"] ?? "notable"
        pendingDeepLink = .play(playerID: playerID, sport: sport, mode: mode, packType: packType)
        return true
    }

    func buildURL(playerID: Int, sport: Sport, mode: GameMode, packType: String) -> URL? {
        var components = URLComponents(string: Self.webBase)
        var items = [
            URLQueryItem(name: "mode", value: mode.rawValue),
            URLQueryItem(name: "pack", value: packType)
        ]
        if sport == .baseball {
            // Keep the parameter older builds understand.
            items.insert(URLQueryItem(name: "mlbID", value: String(playerID)), at: 0)
        } else {
            items.insert(URLQueryItem(name: "id", value: String(playerID)), at: 0)
            items.insert(URLQueryItem(name: "sport", value: sport.rawValue), at: 1)
        }
        components?.queryItems = items
        return components?.url
    }

    func clearPendingLink() {
        pendingDeepLink = nil
    }
}
