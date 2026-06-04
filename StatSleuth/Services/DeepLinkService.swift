import Foundation

// MARK: - Deep Link

enum DeepLink: Equatable {
    case play(mlbID: Int, mode: GameMode, packType: String)
}

// MARK: - DeepLinkService

@Observable
final class DeepLinkService {

    var pendingDeepLink: DeepLink? = nil

    // statsleuth://play?mlbID=518692&mode=seasonStats&pack=notable
    func handle(url: URL) -> Bool {
        guard url.scheme == "statsleuth",
              url.host == "play",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
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
        var components = URLComponents()
        components.scheme = "statsleuth"
        components.host = "play"
        components.queryItems = [
            URLQueryItem(name: "mlbID", value: String(mlbID)),
            URLQueryItem(name: "mode", value: mode.rawValue),
            URLQueryItem(name: "pack", value: packType)
        ]
        return components.url
    }

    func clearPendingLink() {
        pendingDeepLink = nil
    }
}
