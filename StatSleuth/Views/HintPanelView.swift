import SwiftUI

struct HintPanelView: View {

    let hintsUsed: [Hint]
    /// Which hints make sense for this answer — see `GameViewModel.availableHintTypes`.
    let availableHintTypes: [HintType]
    /// Called once the hint has been paid for, never before.
    let onRequestHint: (HintType) -> Void
    /// Whether a hint would actually reveal something. Checked before the
    /// video plays — see `GameViewModel.hintIsResolvable`.
    let isResolvable: (HintType) -> Bool

    @Environment(PurchaseService.self) private var purchaseService
    @Environment(AdService.self) private var adService

    /// Paying to remove ads also removes the video a hint is earned with, so
    /// the purchase hands hints over directly instead.
    private var hintsAreFree: Bool { purchaseService.isAdFree }

    @State private var showHintPicker = false
    @State private var isClaiming = false

    private var unusedHintTypes: [HintType] {
        let usedTypes = Set(hintsUsed.map { $0.type })
        return availableHintTypes.filter { !usedTypes.contains($0) }
    }

    private var isDisabled: Bool { unusedHintTypes.isEmpty || isClaiming }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !hintsUsed.isEmpty { usedHintsSection }
            hintButton
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
                Text(isClaiming ? "Loading\u{2026}" : "Use a hint")
                    .fontWeight(.medium)
                Spacer()
                if hintsAreFree {
                    Text("\u{221E}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "play.rectangle.fill")
                        Text("Watch a video")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .sheet(isPresented: $showHintPicker) {
            HintPickerSheet(
                hintTypes: unusedHintTypes,
                needsVideo: !hintsAreFree
            ) { type in
                showHintPicker = false
                Task { await claim(type) }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Paying for a hint

    /// Every hint costs the same thing: one video. There is no balance to
    /// spend, nothing to run out of, and nothing to wait for.
    private func claim(_ type: HintType) async {
        guard isResolvable(type) else { return }
        guard !hintsAreFree else {
            onRequestHint(type)
            return
        }

        isClaiming = true
        defer { isClaiming = false }

        switch await adService.showRewarded() {
        case .earned:
            HapticEngine.correctGuess()
            onRequestHint(type)
        case .unavailable:
            // Nothing to show. The player asked for a hint and did nothing
            // wrong, so our empty inventory is not their problem.
            onRequestHint(type)
        case .dismissed:
            break
        }
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
    let needsVideo: Bool
    let onSelect: (HintType) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(needsVideo
                     ? "Any hint costs one short video."
                     : "Hints are included \u{2014} no video needed.")
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
                            Text(type.displayName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Spacer()
                            if needsVideo {
                                Image(systemName: "play.rectangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.yellow)
                            }
                        }
                    }
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
