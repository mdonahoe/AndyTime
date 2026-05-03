import Foundation

/// Reads LiveKit credentials from the bundled `env` resource (sourced from
/// the project-root `.env` file by a Run Script build phase). The `.env`
/// is gitignored — copy `.env.example` to `.env` and fill in real values.
enum Secrets {
    static let livekitURL:       String = require("LIVEKIT_URL")
    static let livekitAPIKey:    String = require("LIVEKIT_API_KEY")
    static let livekitAPISecret: String = require("LIVEKIT_API_SECRET")

    private static let values: [String: String] = {
        guard let url = Bundle.main.url(forResource: "env", withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return [:]
        }
        var out: [String: String] = [:]
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                  let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
            var val = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            // Strip surrounding quotes if present
            if val.count >= 2,
               (val.hasPrefix("\"") && val.hasSuffix("\"")) ||
               (val.hasPrefix("'")  && val.hasSuffix("'")) {
                val = String(val.dropFirst().dropLast())
            }
            out[key] = val
        }
        return out
    }()

    private static func require(_ key: String) -> String {
        guard let v = values[key], !v.isEmpty else {
            fatalError("Missing \(key) in .env — copy .env.example to .env and fill in real values")
        }
        return v
    }
}
