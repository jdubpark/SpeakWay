import Foundation

public enum ProviderWire {
    public static func inklingBody(request: TextRequest, model: String) -> [String: Any] {
        var body: [String: Any] = ["model": model, "system": request.instructions, "max_tokens": 4096,
            "messages": [["role": "user", "content": request.input]]]
        if request.mode == .ask { body["output_config"] = ["effort": "low"] }
        else { body["thinking"] = ["type": "disabled"] }
        return body
    }

    public static func decodeInkling(_ data: Data) throws -> TextResult {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let reason = object["stop_reason"] as? String, ["end_turn", "stop_sequence"].contains(reason) else {
            throw SpeakWayError.message("Inkling did not return a complete answer. Try a shorter request or another model.")
        }
        let text = (object["content"] as? [[String: Any]] ?? []).compactMap { block -> String? in
            block["type"] as? String == "text" ? block["text"] as? String : nil
        }.joined(separator: "\n\n")
        guard !text.isEmpty else { throw SpeakWayError.message("Inkling returned no answer text.") }
        return TextResult(text: text)
    }
    public static func responseBody(request: TextRequest, model: String) -> [String: Any] {
        var body: [String: Any] = ["model": model, "instructions": request.instructions,
                                  "input": request.input, "store": false, "max_output_tokens": 4096]
        if request.mode == .ask && request.webSearch {
            body["tools"] = [["type": "web_search"]]
            body["tool_choice"] = "auto"
        }
        return body
    }

    public static func decodeResponse(_ data: Data) throws -> TextResult {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SpeakWayError.message("OpenAI returned an unreadable response.")
        }
        guard object["status"] as? String == "completed" else {
            throw SpeakWayError.message("The model did not finish its response. Your transcript is still available; try a shorter request.")
        }
        var texts: [String] = []; var sources: [SourceLink] = []
        for item in object["output"] as? [[String: Any]] ?? [] {
            guard item["type"] as? String == "message" else { continue }
            for content in item["content"] as? [[String: Any]] ?? [] {
                if let refusal = content["refusal"] as? String { throw SpeakWayError.message(refusal) }
                guard content["type"] as? String == "output_text", let text = content["text"] as? String else { continue }
                texts.append(text)
                for annotation in content["annotations"] as? [[String: Any]] ?? [] {
                    guard annotation["type"] as? String == "url_citation", let raw = annotation["url"] as? String,
                          let url = URL(string: raw), RichTextDocument.isWebURL(url), !sources.contains(where: { $0.url == url }) else { continue }
                    sources.append(SourceLink(title: annotation["title"] as? String ?? url.host ?? raw, url: url))
                }
            }
        }
        guard !texts.isEmpty else { throw SpeakWayError.message("The model returned no text.") }
        return TextResult(text: texts.joined(separator: "\n\n"), sources: sources)
    }

    public static func transcriptionConfiguration(model: String, locale: String) -> [String: Any] {
        var transcription: [String: Any] = ["model": model]
        if model == "gpt-live-transcribe" {
            transcription["languages"] = [String(locale.prefix(2))]
            transcription["delay"] = "low"
        } else { transcription["language"] = String(locale.prefix(2)) }
        return ["type": "session.update", "session": ["type": "transcription", "audio": ["input": [
            "format": ["type": "audio/pcm", "rate": 24000], "transcription": transcription, "turn_detection": NSNull()
        ]]]]
    }
}

public struct CartesiaTranscript {
    public private(set) var text = ""
    public private(set) var completed = false
    private var committedText = ""
    public init() {}
    public mutating func consume(_ event: [String: Any]) throws {
        switch event["type"] as? String {
        case "error": throw SpeakWayError.message("Cartesia could not transcribe this recording. Check your API key, model and language in Settings.")
        case "transcript":
            let chunk = event["text"] as? String ?? ""
            if event["is_final"] as? Bool == true { committedText += chunk; text = committedText }
            else { text = committedText + chunk }
        case "flush_done": completed = true; text = committedText
        default: break
        }
    }
}

/// One manually committed turn per connection. Finals replace deltas, never append to them.
public struct RealtimeTranscript {
    public private(set) var text = ""
    public private(set) var committedID: String?
    public private(set) var completed = false
    private var finals: [String: String] = [:]
    private var deltas: [String: String] = [:]
    public init() {}
    public mutating func consume(_ event: [String: Any]) throws {
        let type = event["type"] as? String ?? ""
        if type == "error" || type == "conversation.item.input_audio_transcription.failed" {
            let error = event["error"] as? [String: Any]
            throw SpeakWayError.message(error?["message"] as? String ?? "Live transcription failed. Try recording again.")
        }
        if type == "input_audio_buffer.committed" { committedID = event["item_id"] as? String }
        if let id = event["item_id"] as? String {
            if type == "conversation.item.input_audio_transcription.delta" {
                deltas[id, default: ""] += event["delta"] as? String ?? ""
                if committedID == nil || committedID == id { text = deltas[id] ?? "" }
            } else if type == "conversation.item.input_audio_transcription.completed" {
                finals[id] = event["transcript"] as? String ?? ""
            }
        }
        if let id = committedID, let final = finals[id] { text = final; completed = true }
    }
}
