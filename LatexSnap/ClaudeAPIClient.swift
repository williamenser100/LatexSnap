import Foundation

struct ClaudeAPIClient {

    // MARK: - Request / Response types

    private struct APIRequest: Encodable {
        let model: String
        let max_tokens: Int
        let messages: [Message]

        struct Message: Encodable {
            let role: String
            let content: [ContentBlock]
        }

        struct ContentBlock: Encodable {
            let type: String
            let source: ImageSource?
            let text: String?

            enum CodingKeys: String, CodingKey { case type, source, text }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(type, forKey: .type)
                if let s = source { try c.encode(s, forKey: .source) }
                if let t = text   { try c.encode(t, forKey: .text) }
            }
        }

        struct ImageSource: Encodable {
            let type: String
            let media_type: String
            let data: String
        }
    }

    private struct APIResponse: Decodable {
        let content: [ContentItem]
        let error: APIErrorBody?

        struct ContentItem: Decodable {
            let type: String
            let text: String?
        }
        struct APIErrorBody: Decodable {
            let message: String
        }
    }

    // MARK: - Public API

    static func convertToLatex(imageData: Data) async throws -> String {
        guard let apiKey = KeychainHelper.apiKey, !apiKey.isEmpty else {
            throw LatexSnapError.noAPIKey
        }

        let base64 = imageData.base64EncodedString()

        let body = APIRequest(
            model: "claude-sonnet-4-6",
            max_tokens: 2048,
            messages: [.init(role: "user", content: [
                .init(type: "image",
                      source: .init(type: "base64", media_type: "image/png", data: base64),
                      text: nil),
                .init(type: "text", source: nil,
                      text: """
                      Convert the mathematical expression in this image to LaTeX.
                      - Output only the raw LaTeX code. No explanation, no markdown fences, no surrounding text.
                      - If multiple expressions are present, separate them with a newline.
                      - If the image contains no mathematical expression at all, output only the word: NONE
                      """)
            ])]
        )

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 30

        await MainActor.run { LogManager.shared.log("POST api.anthropic.com/v1/messages (image: \(base64.count / 1024) KB base64)") }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw LatexSnapError.networkError("No HTTP response")
        }

        await MainActor.run { LogManager.shared.log("API response HTTP \(http.statusCode)") }

        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)

        if http.statusCode != 200 {
            let msg = decoded.error?.message ?? String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LatexSnapError.apiError(http.statusCode, msg)
        }

        let latex = decoded.content.first(where: { $0.type == "text" })?.text?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if latex.uppercased() == "NONE" { return "" }
        return latex
    }
}

// MARK: - Errors

enum LatexSnapError: LocalizedError {
    case noAPIKey
    case apiError(Int, String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key set. Open Settings (⌘,) to add your Anthropic API key."
        case .apiError(let code, let msg):
            return "API error \(code): \(msg)"
        case .networkError(let msg):
            return "Network error: \(msg)"
        }
    }
}
