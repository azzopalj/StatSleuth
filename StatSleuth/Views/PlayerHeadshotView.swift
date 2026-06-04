import SwiftUI

struct PlayerHeadshotView: View {

    let player: Player
    let size: CGFloat

    var body: some View {
        Group {
            if let url = player.headshotURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure, .empty:
                        fallbackView
                    @unknown default:
                        fallbackView
                    }
                }
            } else {
                fallbackView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }

    private var fallbackView: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [.blue.opacity(0.7), .indigo.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            Text(initials)
                .font(.system(size: size * 0.35, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var initials: String {
        let f = player.firstName.prefix(1)
        let l = player.lastName.prefix(1)
        return "\(f)\(l)"
    }
}
