import SwiftUI

struct SettingsView: View {
    @State private var apiKey: String = KeychainHelper.apiKey ?? ""
    @State private var saveState: SaveState = .idle

    enum SaveState { case idle, saved, error }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Anthropic API Key")
                .font(.headline)

            SecureField("sk-ant-api03-…", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            HStack(spacing: 10) {
                switch saveState {
                case .saved:
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .transition(.opacity)
                case .error:
                    Label("Key appears invalid", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .transition(.opacity)
                case .idle:
                    EmptyView()
                }
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.return)
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Link("Get an API key at console.anthropic.com →",
                 destination: URL(string: "https://console.anthropic.com")!)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 400)
        .animation(.easeInOut(duration: 0.2), value: saveState == .idle)
    }

    private func save() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        KeychainHelper.apiKey = trimmed
        withAnimation { saveState = .saved }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { saveState = .idle }
        }
    }
}
