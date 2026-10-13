# SpeakWay

<!-- impeccable:product-schema 1 -->

## Platform

Native macOS, for a MacBook. This is a desktop utility, not a website.

## Purpose

Press a button, speak, and press again to process the recording. Dictate polished text into the current app, ask a question with optional selected-text context, or translate selected text using a spoken instruction.

## Confirmed constraints

- Use OpenAI only for now, for both speech and text processing. This supersedes the initial hybrid-provider exploration.
- Use `gpt-6-luna` for cleanup, answers, and translation.
- Apply the supplied No AI Slop and Simplified Technical English rules to Ask answers only, not intelligent transcription.
- Allow web search only in Ask when the question requires current or external information. The user can disable search.
- Remove filler words and repetitions, and respect spoken corrections.
- Let users continue from a completed transcription as background for the next dictation, question, or translation.
- Offer optional live typing for Dictate only. Revisions and deletion may affect only text inserted by the current dictation, preserving existing content.
- Start capturing without waiting for the cloud connection. Let users edit completed and saved dictations.
- In cmux, automatically insert the final corrected text when dictation finishes, as explicitly chosen by the user.
- Work across Mac apps, subject to their accessibility support.
- The user referenced Typeless as the functional model, not as a source of branding or assets.

## Implementation assumptions

These choices define the first runnable version:

- Swift and SwiftUI with AppKit integration; macOS 26 or later.
- Fn starts Dictate; Fn + Shift starts Translate; Fn + Space starts Ask. Fn ends all three. These shortcuts were explicitly confirmed by the user. A menu bar button and on-screen button also toggle recording.
- OpenAI live transcription handles speech. OpenAI Responses handles cleanup, questions, and translation using the same API key.
- Microphone startup and cloud session setup run concurrently. A bounded queue preserves early audio in order; cancellation and overflow end delivery without silent truncation.
- Other providers and local processing are deferred. Settings offers OpenAI model controls and one key field; existing provider choices migrate to OpenAI. This update sets the requested text model and conditional search once, while preserving unrelated preferences.
- Send finalizes speech and produces text. It never submits a chat message or email in another app.
- AI answers and translations appear for review. Dictation inserts only when the original focus is unchanged.
- A compact, fixed-position bottom-center popover is the primary interface during preparation, recording, and processing. Results expand upward at the same anchor. Settings, History, and the optional workspace use a secondary window.
- Corrected dictation leads the result popover and is the final content inserted. It applies contextual self-corrections and spoken formatting instructions; it summarizes only when explicitly requested. Raw transcription remains available separately.
- Edit opens a focused native text editor with Save and Cancel. Saving updates the displayed result immediately and its history metadata asynchronously. Keep the original correction, raw transcript, and audio unchanged. Later edits require Copy for use in another app, without repeat automatic insertion. History also supports editing saved dictations.
- Continue uses corrected dictation as explicit context; the raw disclosure offers the original speech instead. A preview and Clear action precede mode selection. Context replaces automatic selection for one recording, survives setup failures, and is consumed on listening. Dictate produces only the new text, Ask answers about the context, and Translate translates it. The prior transcription is a separate untrusted reference field, limited to 24,000 characters. Independent recordings do not inherit it.
- Live typing is off by default and requires automatic insertion to be enabled. It inserts provisional transcription at an empty cursor, then replaces its own span with the corrected result. Focus, full field text, and selection must match the last verified state. A mismatch stops updates for that turn. Existing selections and unsupported fields are left unchanged; results remain available to copy. Cancel removes only an unchanged provisional span. Completed earlier dictations are outside that span.
- Dictation supports Markdown headings, emphasis, bullet and numbered lists, quotations, and tables. Copy and final-only insertion supply rich HTML plus readable plain text. Live typing uses readable plain text with list markers and verified Accessibility range replacement; it never falls back to blind backspaces or clipboard paste.
- cmux is an explicit final-only exception to unsupported-field handling. Its native text entry accepts one append after dictation, with newlines and tabs flattened to spaces to avoid terminal submission. It never deletes or revises terminal content. Require the same terminal focus, no selection, and no observed intervening input; cmux does not expose a complete buffer for comparison, and programmatic input may bypass monitoring. Copy preserves line breaks and formatting.
- Save corrected text, raw transcription, and 24 kHz mono PCM audio locally for future reference. Queue audio buffers without waiting for disk; assemble and save files in the background after processing. History is enabled by default and can be disabled for future turns. Cancelled turns are discarded; saved files remain until the user removes them. API keys use Keychain.
- Ask renders formatted answers and native source previews, including images when available. Preview loading must not delay the answer. It contacts cited websites after the result appears.

## Status

Version 0.1.0 runs the OpenAI path above. Settings shows OpenAI for speech and for text, with one key field. Local speech, Cartesia, Apple Intelligence, Ollama, and Thinking Machines remain in the source and are not offered in Settings.
