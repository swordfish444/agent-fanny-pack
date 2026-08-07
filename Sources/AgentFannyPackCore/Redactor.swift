import Foundation

public enum Redactor {
    private static let expressions: [(String, String)] = [
        (#"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, "<redacted-email>"),
        (#"(?i)\b(?:bearer\s+)?(?:sk|sess|token|key|oauth)[-_][A-Za-z0-9._-]{8,}\b"#, "<redacted-token>"),
        (#"(?i)(authorization\s*[:=]\s*)[^\s,;}]+"#, "$1<redacted>")
    ]

    public static func text(_ input: String, homeDirectory: String = NSHomeDirectory()) -> String {
        var output = input.replacingOccurrences(of: homeDirectory, with: "~")
        for (pattern, replacement) in expressions {
            output = output.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        if output.count > 240 {
            output = String(output.prefix(237)) + "…"
        }
        return output
    }
}
