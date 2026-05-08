import Foundation

public enum ShellQuoter {
    public static func quote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    public static func join(_ arguments: [String]) -> String {
        arguments.map(quote).joined(separator: " ")
    }
}
