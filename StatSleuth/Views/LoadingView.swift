import SwiftUI

struct LoadingView: View {
    let loadState: LoadState
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("⚾")
                .font(.system(size: 72))

            Text("StatSleuth")
                .font(.largeTitle)
                .fontWeight(.bold)

            switch loadState {
            case .idle:
                ProgressView()
                    .controlSize(.large)

            case .loading(let progress):
                VStack(spacing: 12) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                        .frame(width: 220)

                    Text(loadingMessage(for: progress))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .animation(.none, value: progress)
                }

            case .failed(let message):
                VStack(spacing: 16) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    Button("Try Again", action: onRetry)
                        .buttonStyle(.borderedProminent)
                }

            case .loaded:
                EmptyView()
            }

            Spacer()
            Spacer()
        }
    }

    private func loadingMessage(for progress: Double) -> String {
        switch progress {
        case 0..<0.15: return "Finding active players…"
        case 0.15..<0.40: return "Loading player info…"
        case 0.40..<0.85: return "Fetching stats…"
        default: return "Almost ready…"
        }
    }
}
