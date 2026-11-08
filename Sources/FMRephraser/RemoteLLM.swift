import Foundation

enum RemoteLLMError: LocalizedError {
    case config(String)
    case invalidURL(String)
    case timeout(Int)
    case network(String)
    case http(Int, String)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .config(let message): return "Remote LLM config error: \(message)"
        case .invalidURL(let url): return "Invalid remote LLM URL: \(url)"
        case .timeout(let seconds): return "Remote LLM timed out after \(seconds)s"
        case .network(let message): return "Remote LLM network error: \(message)"
        case .http(let status, let message): return "Remote LLM HTTP \(status): \(message)"
        case .badResponse(let message): return "Unexpected remote LLM response: \(message)"
        }
    }
}

struct RemoteLLMConfig {
    enum API: String { case openai, azure, anthropic }

    let api: API
    let url: String
    let model: String
    let apiVersion: String
    let temperature: Double
    let maxTokens: Int
    let timeoutSeconds: Int
    let secret: SecretSource

    init(_ dict: [String: Any]) throws {
        let apiName = dict["api"] as? String ?? API.openai.rawValue
        guard let api = API(rawValue: apiName) else {
            throw RemoteLLMError.config("unknown api \"\(apiName)\" (use openai, azure or anthropic)")
        }
        self.api = api
        guard let model = dict["model"] as? String, !model.isEmpty else {
            throw RemoteLLMError.config("remote.model is required")
        }
        self.model = model
        let url = (dict["url"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        switch api {
        case .openai: self.url = url ?? "https://api.openai.com/v1/chat/completions"
        case .anthropic: self.url = url ?? "https://api.anthropic.com/v1/messages"
        case .azure:
            guard let url else { throw RemoteLLMError.config("remote.url (resource endpoint) is required for azure") }
            self.url = url
        }
        apiVersion = dict["apiVersion"] as? String ?? ""
        if api == .azure, apiVersion.isEmpty {
            throw RemoteLLMError.config("remote.apiVersion is required for azure")
        }
        temperature = (dict["temperature"] as? NSNumber)?.doubleValue ?? 0.3
        maxTokens = (dict["maxTokens"] as? NSNumber)?.intValue ?? 2048
        timeoutSeconds = (dict["timeoutSeconds"] as? NSNumber)?.intValue ?? 30
        secret = try SecretSource(dict["secret"] as? [String: Any] ?? [:])
    }

    var describe: String { "\(api.rawValue), \(model)" }
}

enum RemoteLLM {
    static func complete(_ config: RemoteLLMConfig, instructions: String, text: String) async throws -> String {
        let key = try Secrets.read(config.secret)
        let request = try makeRequest(config, key: key, instructions: instructions, text: text)

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw RemoteLLMError.timeout(config.timeoutSeconds)
        } catch {
            throw RemoteLLMError.network(redact(error.localizedDescription, key))
        }

        let json = try? JSONSerialization.jsonObject(with: data)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw RemoteLLMError.http(http.statusCode, redact(errorMessage(json, data), key))
        }
        guard let object = json as? [String: Any] else {
            throw RemoteLLMError.badResponse("not a JSON object: \(excerpt(data))")
        }
        let content = config.api == .anthropic ? anthropicText(object) : openAIText(object)
        guard let content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RemoteLLMError.badResponse(config.api == .anthropic ? "no text in content[]" : "no choices[0].message.content")
        }
        return content
    }

    private static func makeRequest(_ config: RemoteLLMConfig, key: String, instructions: String, text: String) throws -> URLRequest {
        let urlString: String
        if config.api == .azure {
            let base = config.url.hasSuffix("/") ? String(config.url.dropLast()) : config.url
            let deployment = config.model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? config.model
            let version = config.apiVersion.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? config.apiVersion
            urlString = "\(base)/openai/deployments/\(deployment)/chat/completions?api-version=\(version)"
        } else {
            urlString = config.url
        }
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host != nil
        else { throw RemoteLLMError.invalidURL(urlString) }

        var request = URLRequest(url: url, timeoutInterval: TimeInterval(config.timeoutSeconds))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = ["model": config.model, "temperature": config.temperature]
        switch config.api {
        case .openai, .azure:
            if config.api == .openai {
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            } else {
                request.setValue(key, forHTTPHeaderField: "api-key")
            }
            body["messages"] = [
                ["role": "system", "content": instructions],
                ["role": "user", "content": text],
            ]
            body[usesMaxCompletionTokens(config.model) ? "max_completion_tokens" : "max_tokens"] = config.maxTokens
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body["system"] = instructions
            body["messages"] = [["role": "user", "content": text]]
            body["max_tokens"] = config.maxTokens
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// GPT-5 and later reject max_tokens and require max_completion_tokens (same rule as refinify).
    private static func usesMaxCompletionTokens(_ model: String) -> Bool {
        model.range(of: #"^gpt-[5-9][0-9]*([.-]|$)"#, options: .regularExpression) != nil
    }

    private static func openAIText(_ object: [String: Any]) -> String? {
        guard let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any]
        else { return nil }
        return message["content"] as? String
    }

    private static func anthropicText(_ object: [String: Any]) -> String? {
        guard let content = object["content"] as? [[String: Any]] else { return nil }
        return content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
    }

    private static func errorMessage(_ json: Any?, _ data: Data) -> String {
        let object = json as? [String: Any]
        if let error = object?["error"] as? [String: Any], let message = error["message"] as? String, !message.isEmpty {
            return message
        }
        if let message = object?["error"] as? String ?? object?["message"] as? String, !message.isEmpty {
            return message
        }
        return excerpt(data)
    }

    private static func excerpt(_ data: Data) -> String {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "(empty body)" }
        return text.count > 200 ? String(text.prefix(200)) + "..." : text
    }

    /// Providers echo a masked key in auth errors (e.g. "sk-abc1****wxyz"); drop that too.
    private static func redact(_ message: String, _ key: String) -> String {
        let unmasked = key.isEmpty ? message : message.replacingOccurrences(of: key, with: "***")
        return unmasked.replacingOccurrences(of: #"\S*\*{4,}\S*"#, with: "***", options: .regularExpression)
    }
}
