import SwiftUI
import StoreKit

struct HintPanelView: View {

    let hintsAvailable: Int
    let hintsUsed: [Hint]
    let packHasHistoricPlayers: Bool
    let onRequestHint: (HintType) -> Void

    @Environment(UserProgressService.self) private var progressService
    @Environment(PurchaseService.self) private var purchaseService

    @State private var showHintPicker = false
    @State private var showBuyHints = false

    private var availableHintTypes: [HintType] {
        var types: [HintType] = [.position, .team, .nationality]
        if packHasHistoricPlayers { types.append(.era) }
        types += [.jerseyNumber, .initials, .firstNameOnly]
        return types
    }

    private var unusedHintTypes: [HintType] {
        let usedTypes = Set(hintsUsed.map { $0.type })
        return availableHintTypes.filter { !usedTypes.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !hintsUsed.isEmpty { usedHintsSection }
            hintButton
            if hintsAvailable < UserProgress.naturalHintMax { rechargeRow }
        }
        .sheet(isPresented: $showBuyHints) {
            BuyHintsSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Used Hints

    private var usedHintsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hints revealed")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            FlowLayout(spacing: 8) {
                ForEach(hintsUsed) { hint in
                    HintChip(hint: hint)
                }
            }
        }
    }

    // MARK: - Hint Button

    private var hintButton: some View {
        Button {
            showHintPicker = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                Text("Use a hint")
                    .fontWeight(.medium)
                Spacer()
                Text("\(hintsAvailable) left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .disabled(hintsAvailable == 0 || unusedHintTypes.isEmpty)
        .opacity((hintsAvailable == 0 || unusedHintTypes.isEmpty) ? 0.5 : 1)
        .sheet(isPresented: $showHintPicker) {
            HintPickerSheet(
                hintTypes: unusedHintTypes,
                hintsAvailable: hintsAvailable
            ) { type in
                showHintPicker = false
                onRequestHint(type)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Recharge row

    private var rechargeRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if hintsAvailable == 0 {
                Text("Out of hints")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(hintsAvailable)/\(UserProgress.naturalHintMax) hints")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Live countdown
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let secs = progressService.progress.secondsUntilNextHint {
                    let h = Int(secs) / 3600
                    let m = (Int(secs) % 3600) / 60
                    let s = Int(secs) % 60
                    let timeStr = h > 0
                        ? String(format: "+1 in %d:%02d:%02d", h, m, s)
                        : String(format: "+1 in %d:%02d", m, s)
                    Text(timeStr)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.orange)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }

            Spacer()

            Button {
                HapticEngine.tap()
                showBuyHints = true
            } label: {
                Text("Get More")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.blue.opacity(0.1), in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - BuyHintsSheet

private struct BuyHintsSheet: View {
    @Environment(PurchaseService.self) private var purchaseService
    @Environment(UserProgressService.self) private var progressService
    @Environment(\.dismiss) private var dismiss

    @State private var purchaseError: String? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Current status
                VStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.yellow)
                    Text("You have \(progressService.progress.hintsAvailable) hint\(progressService.progress.hintsAvailable == 1 ? "" : "s")")
                        .font(.title3).fontWeight(.bold)
                    if let secs = progressService.progress.secondsUntilNextHint {
                        let h = Int(secs) / 3600
                        let m = (Int(secs) % 3600) / 60
                        let s = Int(secs) % 60
                        let str = h > 0
                            ? String(format: "%d:%02d:%02d", h, m, s)
                            : String(format: "%d:%02d", m, s)
                        Text("Next free hint in \(str)")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .monospacedDigit()
                    } else {
                        Text("1 hint regenerates every 2 hours · max \(UserProgress.naturalHintMax)")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 8)

                Divider()

                // Purchase options
                VStack(spacing: 12) {
                    hintPackButton(
                        productID: PurchaseService.hints5ID,
                        count: 5,
                        icon: "lightbulb.fill",
                        label: "5 Hints"
                    )
                    hintPackButton(
                        productID: PurchaseService.hints15ID,
                        count: 15,
                        icon: "lightbulb.max.fill",
                        label: "15 Hints",
                        badge: "Best Value"
                    )
                }
                .padding(.horizontal, 4)

                Spacer()
            }
            .padding(.horizontal, 20)
            .navigationTitle("Get More Hints")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Purchase Failed", isPresented: .constant(purchaseError != nil)) {
                Button("OK") { purchaseError = nil }
            } message: {
                if let msg = purchaseError { Text(msg) }
            }
        }
    }

    @ViewBuilder
    private func hintPackButton(
        productID: String,
        count: Int,
        icon: String,
        label: String,
        badge: String? = nil
    ) -> some View {
        Button {
            HapticEngine.impact()
            Task {
                await purchaseService.purchase(productID: productID)
                if let err = purchaseService.errorMessage {
                    purchaseError = err
                } else {
                    dismiss()
                }
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.yellow)
                    .frame(width: 44, height: 44)
                    .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(label).font(.headline).foregroundStyle(.primary)
                        if let badge {
                            Text(badge)
                                .font(.caption2).fontWeight(.bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.blue, in: Capsule())
                        }
                    }
                    if let product = purchaseService.products[productID] {
                        Text(product.displayPrice)
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if purchaseService.isLoading {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14))
        }
        .disabled(purchaseService.isLoading)
    }
}

// MARK: - HintChip

private struct HintChip: View {
    let hint: Hint

    var body: some View {
        HStack(spacing: 5) {
            Text(hint.type.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(hint.value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.yellow.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(.yellow.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - HintPickerSheet

private struct HintPickerSheet: View {
    let hintTypes: [HintType]
    let hintsAvailable: Int
    let onSelect: (HintType) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(hintsAvailable) hints remaining")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                List(hintTypes, id: \.self) { type in
                    Button {
                        HapticEngine.hint()
                        onSelect(type)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(type.displayName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)
                                Text("Costs \(type.hintCost) hint\(type.hintCost > 1 ? "s" : "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 2) {
                                ForEach(0..<type.hintCost, id: \.self) { _ in
                                    Image(systemName: "lightbulb.fill")
                                        .font(.caption)
                                        .foregroundStyle(.yellow)
                                }
                            }
                        }
                    }
                    .disabled(hintsAvailable < type.hintCost)
                    .opacity(hintsAvailable < type.hintCost ? 0.4 : 1)
                }
                .listStyle(.plain)
            }
            .navigationTitle("Choose a Hint")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - FlowLayout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > width && rowWidth > 0 {
                height += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
