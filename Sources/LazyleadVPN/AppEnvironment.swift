import Foundation

struct AppEnvironment {
    static let defaultConfigPath = "/usr/local/etc/lazylead-vpn/env"

    let values: [String: String]
    let configPath: String
    let loadedConfig: Bool

    init(processEnvironment: [String: String] = ProcessInfo.processInfo.environment) {
        let configuredPath = processEnvironment["LAZYLEAD_VPN_CONFIG"].flatMap { $0.isEmpty ? nil : $0 }
        let configPath = configuredPath ?? Self.defaultConfigPath
        let fileValues = Self.readConfig(at: configPath)

        self.values = fileValues.merging(processEnvironment) { _, processValue in processValue }
        self.configPath = configPath
        self.loadedConfig = !fileValues.isEmpty
    }

    subscript(_ key: String) -> String? {
        values[key].flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func readConfig(at path: String) -> [String: String] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            return [:]
        }

        var result: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else {
                continue
            }

            if line.hasPrefix("export ") {
                line.removeFirst("export ".count)
                line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            guard let separator = line.firstIndex(of: "=") else {
                continue
            }

            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            let rawValue = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                continue
            }

            result[key] = unquote(rawValue)
        }

        return result
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2 else {
            return value
        }

        let first = value.first
        let last = value.last
        if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            return String(value.dropFirst().dropLast())
        }

        return value
    }
}
