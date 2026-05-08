import Foundation

public enum SAMLURLParser {
    public static func extract(from text: String) -> URL? {
        let pattern = #"https://[^\s]+/saml-vpn/[^\s]+"#
        guard let range = text.range(of: pattern, options: .regularExpression) else {
            return nil
        }

        var value = String(text[range])
        while let last = value.last, [".", ",", ";", ")"].contains(last) {
            value.removeLast()
        }

        return URL(string: value)
    }
}
