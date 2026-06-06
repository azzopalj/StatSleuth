import Foundation

// MARK: - Deep Link

enum DeepLink: Equatable {
    case play(mlbID: Int, mode: GameMode, packType: String)
}

// MARK: - DeepLinkService

@Observable
final class DeepLinkService {

    private static let webBase = "https://azzopalj.github.io/statsleuth"

    var pendingDeepLink: DeepLink? = nil

    // Handles both:
    //   Universal link: https://azzopalj.github.io/statsleuth/?mlbID=...&mode=...&pack=...
    //   Custom scheme:  statsleuth://play?mlbID=...&mode=...&pack=...
    func handle(url: URL) -> Bool {
        let isUniversalLink = url.host == "azzopalj.github.io"
        let isCustomScheme  = url.scheme == "statsleuth" && url.host == "play"
        guard isUniversalLink || isCustomScheme else { return false }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else { return false }

        let params = Dictionary(uniqueKeysWithValues: queryItems.compactMap { item in
            item.value.map { (item.name, $0) }
        })

        guard let mlbIDStr = params["mlbID"],
              let mlbID = Int(mlbIDStr),
              let modeStr = params["mode"],
              let mode = GameMode(rawValue: modeStr) else { return false }

        let packType = params["pack"] ?? "notable"
        pendingDeepLink = .play(mlbID: mlbID, mode: mode, packType: packType)
        return true
    }

    func buildURL(mlbID: Int, mode: GameMode, packType: String) -> URL? {
        var components = URLComponents(string: Self.webBase)
        components?.queryItems = [
            URLQueryItem(name: "mlbID", value: String(mlbID)),
            URLQueryItem(name: "mode", value: mode.rawValue),
            URLQueryItem(name: "pack", value: packType)
        ]
        return components?.url
    }

    func clearPendingLink() {
        pendingDeepLink = nil
    }
}
