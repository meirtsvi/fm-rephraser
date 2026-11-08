import Foundation
import Security

struct SecretSource {
    enum Kind: String { case keychain, env, file }

    let kind: Kind
    let service: String
    let account: String
    let env: String
    let file: String

    init(_ dict: [String: Any]) throws {
        let source = dict["source"] as? String ?? Kind.keychain.rawValue
        guard let kind = Kind(rawValue: source) else {
            throw RemoteLLMError.config("unknown secret.source \"\(source)\" (use keychain, env or file)")
        }
        self.kind = kind
        service = dict["service"] as? String ?? "fm-rephraser"
        account = dict["account"] as? String ?? "llm"
        env = dict["env"] as? String ?? "FM_REPHRASES_LLM_SECRET"
        file = dict["file"] as? String ?? "~/.config/fm-rephraser/.env-secret"
        if kind == .env, env.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) == nil {
            throw RemoteLLMError.config("invalid secret.env name \"\(env)\"")
        }
    }
}

enum SecretError: LocalizedError {
    case keychainNotFound(service: String, account: String)
    case keychain(service: String, account: String, status: OSStatus)
    case envMissing(String)
    case loginShell(String)
    case fileMissing(String)
    case fileEmpty(String)

    var errorDescription: String? {
        switch self {
        case .keychainNotFound(let service, let account):
            return "Keychain item \(service)/\(account) not found; run: security add-generic-password -s \(service) -a \(account) -w <key> -T /Applications/FMRephraser.app"
        case .keychain(let service, let account, let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
            return "Keychain read of \(service)/\(account) failed: \(message) (\(status))"
        case .envMissing(let name):
            return "Environment variable \(name) is not set (also checked the login shell)"
        case .loginShell(let message):
            return "Login shell lookup failed: \(message)"
        case .fileMissing(let path):
            return "Secret file \(path) not found or unreadable"
        case .fileEmpty(let path):
            return "Secret file \(path) is empty"
        }
    }
}

enum Secrets {
    private static let lock = NSLock()
    private static var loginShellCache: [String: String] = [:]

    static func read(_ source: SecretSource) throws -> String {
        switch source.kind {
        case .keychain: return try readKeychain(service: source.service, account: source.account)
        case .env: return try readEnv(source.env)
        case .file: return try readFile(source.file)
        }
    }

    static func clearCache() {
        lock.withLock { loginShellCache.removeAll() }
    }

    private static func readKeychain(service: String, account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { throw SecretError.keychainNotFound(service: service, account: account) }
        guard status == errSecSuccess, let data = item as? Data,
              let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { throw SecretError.keychain(service: service, account: account, status: status) }
        return value
    }

    private static func readEnv(_ name: String) throws -> String {
        if let value = ProcessInfo.processInfo.environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }
        if let cached = lock.withLock({ loginShellCache[name] }) { return cached }
        let value = try loginShellValue(name)
        guard !value.isEmpty else { throw SecretError.envMissing(name) }
        lock.withLock { loginShellCache[name] = value }
        return value
    }

    /// Apps launched from Finder or Login Items do not inherit exports from ~/.zshrc, so ask a login shell.
    /// The markers keep any output printed by the shell's startup files out of the value.
    private static func loginShellValue(_ name: String) throws -> String {
        let begin = "__FMR_BEGIN__", end = "__FMR_END__"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lic", "printf '%s%s%s' '\(begin)' \"${\(name)}\" '\(end)'"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        final class Box: @unchecked Sendable { var data = Data() }
        let box = Box()
        let group = DispatchGroup()
        do { try process.run() } catch { throw SecretError.loginShell(error.localizedDescription) }
        group.enter()
        DispatchQueue.global().async {
            box.data = pipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        if group.wait(timeout: .now() + 3) == .timedOut {
            process.terminate()
            throw SecretError.loginShell("timed out after 3s")
        }
        let output = String(decoding: box.data, as: UTF8.self)
        guard let start = output.range(of: begin, options: .backwards),
              let stop = output.range(of: end, range: start.upperBound..<output.endIndex)
        else { return "" }
        return String(output[start.upperBound..<stop.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func readFile(_ path: String) throws -> String {
        let expanded = (path as NSString).expandingTildeInPath
        guard let content = try? String(contentsOfFile: expanded, encoding: .utf8) else {
            throw SecretError.fileMissing(path)
        }
        let value = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw SecretError.fileEmpty(path) }
        return value
    }
}
