import Foundation
import FoundationModels
import SpeakWayCore

@MainActor enum TextProcessor {
    static var localAvailability: String {
        switch SystemLanguageModel.default.availability {
        case .available: return "Ready on this Mac"
        case .unavailable(.appleIntelligenceNotEnabled): return "Enable Apple Intelligence in System Settings"
        case .unavailable(.modelNotReady): return "Apple Intelligence is still downloading its model"
        case .unavailable(.deviceNotEligible): return "Apple Intelligence is not available on this Mac"
        case .unavailable: return "Apple Intelligence is unavailable"
        @unknown default: return "Apple Intelligence availability is unknown"
        }
    }

    static func run(_ request: TextRequest, settings: Settings, key: String) async throws -> TextResult {
        try request.validate(); try Task.checkCancellation()
        switch settings.textProvider {
        case .apple:
            guard SystemLanguageModel.default.availability == .available else { throw SpeakWayError.message(localAvailability + ". Choose OpenAI or Ollama in Settings to continue.") }
            guard request.input.count < 10_000 else { throw SpeakWayError.message("This passage is too long for Apple Intelligence. Select less text or choose OpenAI or Ollama.") }
            let session = LanguageModelSession(instructions: request.instructions)
            let response = try await session.respond(to: request.input, options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 2048))
            try Task.checkCancellation()
            return TextResult(text: response.content)
        case .openAI:
            guard !key.isEmpty else { throw SpeakWayError.message("Add your OpenAI API key in Settings to continue.") }
            let body = ProviderWire.responseBody(request: request, model: settings.openAIModel)
            let data = try await post(url: URL(string: "https://api.openai.com/v1/responses")!, body: body, provider: "OpenAI", headers: ["Authorization": "Bearer \(key)"])
            return try ProviderWire.decodeResponse(data)
        case .thinkingMachines:
            guard !key.isEmpty else { throw SpeakWayError.message("Add your Tinker API key in Settings to try Inkling.") }
            let body = ProviderWire.inklingBody(request: request, model: settings.inklingModel)
            let data = try await post(url: URL(string: "https://tinker.thinkingmachines.dev/services/tinker-prod/anthropic/api/v1/messages")!,
                body: body, provider: "Thinking Machines", headers: ["x-api-key": key, "anthropic-version": "2023-06-01"])
            return try ProviderWire.decodeInkling(data)
        case .ollama:
            let body: [String: Any] = ["model": settings.ollamaModel, "stream": false, "messages": [
                ["role": "system", "content": request.instructions], ["role": "user", "content": request.input]
            ]]
            let data = try await post(url: URL(string: "http://127.0.0.1:11434/api/chat")!, body: body, provider: "Ollama")
            guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  result["done"] as? Bool == true,
                  let message = result["message"] as? [String: Any], let text = message["content"] as? String,
                  result["done_reason"] as? String != "length" else {
                throw SpeakWayError.message("Ollama did not return a complete answer. Check the model name or use a shorter request.")
            }
            return TextResult(text: text)
        }
    }

    private static func post(url: URL, body: [String: Any], provider: String, headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw SpeakWayError.message("The AI service returned an invalid response.") }
        guard (200..<300).contains(response.statusCode) else {
            // Do not echo provider response bodies, which can contain inputs or credentials.
            let recovery: String
            switch response.statusCode {
            case 401, 403: recovery = "Check your API key and model access in Settings."
            case 404: recovery = "Check the model name in Settings and whether it is available."
            case 429: recovery = "Your rate limit or API quota was reached. Check billing or try later."
            default: recovery = "Try again after checking the service and connection."
            }
            throw SpeakWayError.message("\(provider) returned HTTP \(response.statusCode). \(recovery)")
        }
        return data
    }
}
