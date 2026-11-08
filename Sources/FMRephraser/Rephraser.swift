import Foundation
import FoundationModels

enum RephraseError: LocalizedError {
    case modelUnavailable(String)
    case protectedTextChanged(String)
    case unknownBackend(String)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let reason): return "On-device model unavailable: \(reason)"
        case .protectedTextChanged(let token): return "Text left unchanged: the model altered \(token)"
        case .unknownBackend(let name): return "Unknown backend \"\(name)\" in config.json (use local or remote)"
        }
    }
}

enum Backend {
    case local
    case remote(RemoteLLMConfig)
    case invalid(Error)
}

enum Rephraser {
    static let defaultInstructions = """
        You are an editor. Rewrite the user's text: fix all grammar, spelling, capitalization and punctuation \
        mistakes, and rephrase awkward wording so it reads clearly and naturally.
        Keep the original meaning, tone, language and formatting (line breaks, lists). Keep it about the same length.
        Keep every word starting with @ (a mention) exactly as written.
        Keep every link (URL) exactly as written, character for character.
        Output only the rewritten text, with no explanations, quotes or preamble.
        """

    static var instructions = defaultInstructions
    static var backend = Backend.local

    static func rephrase(_ text: String) async throws -> String {
        let output: String
        switch backend {
        case .local: output = try await rephraseOnDevice(text)
        case .remote(let config): output = try await RemoteLLM.complete(config, instructions: instructions, text: text)
        case .invalid(let error): throw error
        }
        let result = output.trimmingCharacters(in: .whitespacesAndNewlines)

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

    private static func rephraseOnDevice(_ text: String) async throws -> String {
        if case .unavailable(let reason) = SystemLanguageModel.default.availability {
            throw RephraseError.modelUnavailable(String(describing: reason))
        }

        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: text, options: GenerationOptions(temperature: 0.3))
        return response.content
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
