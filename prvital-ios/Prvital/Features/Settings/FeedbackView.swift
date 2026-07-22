import SwiftUI

/// "Send feedback" — a short form that composes an email to the support address.
/// There's no backend and nothing is sent silently: it hands a pre-filled draft
/// to the user's mail app (with an optional, health-free diagnostics footer), or
/// a share sheet if no mail app is set up. The user always sees and sends it.
struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var category: FeedbackCategory = .idea
    @State private var message = ""
    @State private var includeDiagnostics = true
    @State private var showNoMailAlert = false

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var canSend: Bool { !trimmedMessage.isEmpty }

    /// The plain-text body, shared by the mail draft and the share-sheet fallback.
    private var composedBody: String {
        var body = trimmedMessage
        if includeDiagnostics {
            body += "\n\n———\n" + AppInfo.diagnostics
        }
        return body
    }

    private var subject: String {
        String(localized: "Prvital feedback — \(category.subjectTag)")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $category) {
                        ForEach(FeedbackCategory.allCases) { c in
                            Label(c.title, systemImage: c.symbol).tag(c)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("What's on your mind?")
                }
                .glassListRow()

                Section {
                    TextEditor(text: $message)
                        .frame(minHeight: 130)
                        .scrollContentBackground(.hidden)
                        .overlay(alignment: .topLeading) {
                            if message.isEmpty {
                                Text(category.placeholder)
                                    .foregroundStyle(Theme.textTertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("Message")
                }
                .glassListRow()

                Section {
                    Toggle("Include diagnostics", isOn: $includeDiagnostics)
                    if includeDiagnostics {
                        Text(AppInfo.diagnostics)
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.textSecondary)
                    }
                } footer: {
                    Text("Diagnostics are app, device and OS details only — never your glucose or personal data. They help us reproduce a problem.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
                .glassListRow()

                Section {
                    ShareLink(item: composedBody) {
                        Label("Share another way", systemImage: "square.and.arrow.up")
                            .foregroundStyle(Theme.accent)
                    }
                    .disabled(!canSend)
                } footer: {
                    Text("Feedback goes to \(AppInfo.supportEmail). Prefer Messages or another app? Use Share.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
                .glassListRow()
            }
            .scrollContentBackground(.hidden)
            .prvitalScreenBackground()
            .navigationTitle("Send feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send", action: send).disabled(!canSend)
                }
            }
            .alert("No mail account", isPresented: $showNoMailAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This device has no Mail account set up. Use “Share another way” to send your feedback with another app.")
            }
        }
    }

    private func send() {
        guard canSend, let url = mailtoURL() else { return }
        Haptics.play(.light)
        openURL(url) { accepted in
            if accepted { dismiss() } else { showNoMailAlert = true }
        }
    }

    /// Builds a `mailto:` URL with the subject and body percent-encoded via
    /// `URLComponents`, so punctuation and newlines survive.
    private func mailtoURL() -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = AppInfo.supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: composedBody),
        ]
        // `URLComponents` encodes spaces as "+", which some mail clients read
        // literally in a body — force the RFC-3986 "%20" spelling.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%20")
        return components.url
    }
}

/// The kind of feedback being sent — drives the subject tag and placeholder.
enum FeedbackCategory: String, CaseIterable, Identifiable {
    case idea, problem, question, praise

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .idea: return "Idea"
        case .problem: return "Problem"
        case .question: return "Question"
        case .praise: return "Praise"
        }
    }

    var symbol: String {
        switch self {
        case .idea: return "lightbulb"
        case .problem: return "ladybug"
        case .question: return "questionmark.circle"
        case .praise: return "heart"
        }
    }

    /// A resolved string for the email subject line.
    var subjectTag: String {
        switch self {
        case .idea: return String(localized: "Idea")
        case .problem: return String(localized: "Problem")
        case .question: return String(localized: "Question")
        case .praise: return String(localized: "Praise")
        }
    }

    var placeholder: String {
        switch self {
        case .idea: return String(localized: "What would make Prvital better for you?")
        case .problem: return String(localized: "What happened, and what did you expect?")
        case .question: return String(localized: "Ask us anything about Prvital.")
        case .praise: return String(localized: "We'd love to hear what's working for you.")
        }
    }
}

#Preview {
    FeedbackView()
}
