import SwiftUI

/// The mySugr-style quick-tag row used by the glucose and carb editors: one
/// horizontally scrolling line of capsule chips, multi-select. Deliberately a
/// single quiet line — tagging is optional colour, not a form field to fill.
struct EntryTagPicker: View {
    @Binding var selected: Set<ObservationTag>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ObservationTag.allCases) { tag in
                    chip(tag)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityLabel("Tags")
    }

    private func chip(_ tag: ObservationTag) -> some View {
        let isOn = selected.contains(tag)
        return Button {
            if isOn { selected.remove(tag) } else { selected.insert(tag) }
            Haptics.play(.selection)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tag.symbol)
                    .font(.caption.weight(.medium))
                Text(tag.label)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .foregroundStyle(isOn ? Color.white : Theme.textSecondary)
            .background(isOn ? Theme.accent : Theme.textPrimary.opacity(0.07), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
