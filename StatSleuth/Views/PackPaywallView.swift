import SwiftUI
import StoreKit

/// Shown before triggering a StoreKit purchase — lets the user see what's in
/// a pack before committing, improving conversion and reducing accidental taps.
struct PackPaywallView: View {

    let pack: Pack
    let onPurchase: () -> Void
    let onDismiss: () -> Void

    @Environment(PurchaseService.self) private var purchaseService
    @Environment(PlayerDataService.self) private var playerDataService

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 20)

            ScrollView {
                VStack(spacing: 24) {
                    // Icon + name
                    VStack(spacing: 12) {
                        Text(pack.sport.icon)
                            .font(.system(size: 56))
                            .frame(width: 88, height: 88)
                            .background(Color.secondary.opacity(0.1),
                                        in: RoundedRectangle(cornerRadius: 20))

                        Text(pack.name)
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)

                        Text(pack.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)

                    // Stats row
                    HStack(spacing: 0) {
                        paywallStat(value: "\(pack.playerCount)", label: "Players")
                        Divider().frame(height: 40)
                        paywallStat(value: "5", label: "Game Modes")
                        Divider().frame(height: 40)
                        paywallStat(value: "∞", label: "Replays")
                    }
                    .padding(.vertical, 16)
                    .background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 24)

                    // What's included
                    VStack(alignment: .leading, spacing: 10) {
                        Text("What's included")
                            .font(.headline)
                            .padding(.horizontal, 24)

                        VStack(spacing: 0) {
                            paywallFeatureRow("All \(pack.playerCount) players unlocked",
                                              icon: "person.3.fill", color: .blue)
                            Divider().padding(.leading, 56)
                            paywallFeatureRow("Season Stats mode",
                                              icon: "chart.bar", color: .green)
                            Divider().padding(.leading, 56)
                            paywallFeatureRow("Career Stats mode",
                                              icon: "trophy", color: .orange)
                            Divider().padding(.leading, 56)
                            paywallFeatureRow("Rookie Season mode",
                                              icon: "figure.run", color: .mint)
                            Divider().padding(.leading, 56)
                            paywallFeatureRow("Mystery Year mode",
                                              icon: "questionmark.circle", color: .purple)
                        }
                        .background(Color(uiColor: .secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 24)
                    }

                    // One-time purchase note
                    Text("One-time purchase. No subscription.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 120)  // clear the pinned button
                .iPadContentFrame()
            }

            // Pinned buy button
            VStack(spacing: 10) {
                Button {
                    onPurchase()
                } label: {
                    HStack {
                        Text("Unlock \(pack.name)")
                            .fontWeight(.semibold)
                        Spacer()
                        if let product = purchaseService.product(for: pack) {
                            Text(product.displayPrice)
                                .fontWeight(.bold)
                        } else if let price = pack.price {
                            Text(String(format: "$%.2f", price))
                                .fontWeight(.bold)
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(.blue, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)
                .disabled(purchaseService.isLoading)

                Button("Maybe Later", action: onDismiss)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
            .padding(.top, 12)
            .background(.regularMaterial)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Helpers

    private func paywallStat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func paywallFeatureRow(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.subheadline)
                .frame(width: 28, alignment: .center)
            Text(text)
                .font(.subheadline)
            Spacer()
            Image(systemName: "checkmark")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
