import SwiftUI

/// Audit trail. A reverse-chronological list of every sensitive operation —
/// source access, sync, export, edits, permission changes, conflict resolution,
/// deletions — recorded as facts, never as medical values. Loaded through the
/// audit service and refreshable on demand.
struct AuditLogView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var records: [PrivacyAuditRecord] = []

    var body: some View {
        List {
            Section {
                if records.isEmpty {
                    EmptyStateView(
                        systemImage: "checkmark.shield",
                        title: "No activity yet",
                        message: "Sensitive actions will be recorded here as they happen."
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(records, id: \.id) { record in
                        AuditRow(record: record)
                    }
                }
            } footer: {
                Text("The trail records that an operation happened — when, to which source and with what result — never the medical values themselves.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Audit trail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Haptics.play(.light)
                    reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh")
            }
        }
        .task { reload() }
    }

    private func reload() {
        records = env.audit.recent()
    }
}

// MARK: - Private helpers

/// One audit entry: action glyph and label, result, relative time, source and
/// any non-medical detail.
private struct AuditRow: View {
    let record: PrivacyAuditRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: record.actionType.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(resultColor)
                .frame(width: 26, height: 26)
                .background(resultColor.opacity(0.14), in: .rect(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(record.actionType.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(record.result.label)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(resultColor.opacity(0.16), in: .capsule)
                        .foregroundStyle(resultColor)
                }

                if let detail = record.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    Text(record.timestamp.formatted(.relative(presentation: .named)))
                    if let source = record.dataSource {
                        Text("·")
                        Label(source.displayName, systemImage: source.symbol)
                            .labelStyle(.titleAndIcon)
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var resultColor: Color {
        switch record.result {
        case .granted, .success: return Theme.zoneInRange
        case .denied, .failure: return Theme.zoneCritical
        case .revoked: return Theme.zoneWarning
        }
    }

    private var accessibilityText: String {
        var parts = [record.actionType.label, record.result.label,
                     record.timestamp.formatted(.relative(presentation: .named))]
        if let source = record.dataSource { parts.append(source.displayName) }
        if let detail = record.detail, !detail.isEmpty { parts.append(detail) }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return NavigationStack { AuditLogView() }
        .environment(env)
        .modelContainer(env.modelContainer)
}
