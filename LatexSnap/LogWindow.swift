import SwiftUI

struct LogWindowView: View {
    @ObservedObject var log = LogManager.shared

    private let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("LatexSnap Log")
                    .font(.headline)
                Spacer()
                Button("Clear") { log.entries.removeAll() }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()

            if log.entries.isEmpty {
                Spacer()
                Text("No activity yet.\nPress ⌘⇧⌃L to capture.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .font(.callout)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(log.entries) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(fmt.string(from: entry.timestamp))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 60, alignment: .leading)
                                Circle()
                                    .fill(color(for: entry.level))
                                    .frame(width: 7, height: 7)
                                    .padding(.top, 4)
                                Text(entry.message)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(color(for: entry.level))
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 3)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(width: 560, height: 320)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .info:    return .primary
        case .success: return .green
        case .error:   return .red
        }
    }
}
