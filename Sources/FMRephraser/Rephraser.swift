import Foundation
import FoundationModels

enum RephraseError: Error {
    case modelUnavailable(String)
    case protectedTextChanged(String)
}

enum Rephraser {
    private static let instructions = """
        You are an editor. Rewrite the user's text: fix all grammar, spelling, capitalization and punctuation \
        mistakes, and rephrase awkward wording so it reads clearly and naturally.
        Keep the original meaning, tone, language and formatting (line breaks, lists). Keep it about the same length.
        Keep every word starting with @ (a mention) exactly as written.
        Keep every link (URL) exactly as written, character for character.
        Output only the rewritten text, with no explanations, quotes or preamble.
        """

    static func rephrase(_ text: String) async throws -> String {
        if case .unavailable(let reason) = SystemLanguageModel.default.availability {
            throw RephraseError.modelUnavailable(String(describing: reason))
        }

        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: text, options: GenerationOptions(temperature: 0.3))
        let result = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Links and @mentions must survive unchanged; otherwise leave the user's text alone.
        for token in protectedTokens(in: text)
        where result.components(separatedBy: token).count < text.components(separatedBy: token).count {
            throw RephraseError.protectedTextChanged(token)
        }

        // Keep the selection's leading/trailing whitespace (e.g. a trailing newline).
        let leading = String(text.prefix { $0.isWhitespace })
        let trailing = String(text.reversed().prefix { $0.isWhitespace }.reversed())
        return leading + result + trailing
    }

    private static func protectedTokens(in text: String) -> [String] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var ranges: [NSRange] = []
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            ranges += detector.matches(in: text, range: full).map(\.range)
        }
        let mention = try! NSRegularExpression(pattern: #"(?<![\w@])@\w(?:[\w.\-]*\w)?"#)
        ranges += mention.matches(in: text, range: full).map(\.range)
        return ranges.map { ns.substring(with: $0) }
    }
}
