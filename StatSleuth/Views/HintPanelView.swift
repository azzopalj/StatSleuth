import SwiftUI

struct HintPanelView: View {

    let hintsAvailable: Int
    let hintsUsed: [Hint]
    let packHasHistoricPlayers: Bool
    let onRequestHint: (HintType) -> Void

    @State private var showHintPicker = false

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
            // Used hints
            if !hintsUsed.isEmpty {
                usedHintsSection
            }

            // Hint button
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
