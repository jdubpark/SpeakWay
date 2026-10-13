# Architecture

SpeakWay is one Swift package. `SpeakWayCore` holds the rules that can run without AppKit. The `SpeakWay` executable is the menu bar app: microphone, network, Accessibility, Keychain, and windows.

`Package.swift` requires macOS 26 and Swift tools 6.2. The executable target depends on `SpeakWayCore`. `SpeakWayCoreTests` links only that core target. The tests build values and fakes. They do not open a window or a socket.

## One turn

1. `FnKeyMonitor` installs a session event tap. `FnShortcut` chooses Dictate, Ask, or Translate on key release, and treats the next Fn press as finish. Escape cancels. A left click on the menu bar icon calls `AppModel.toggle`, which starts a turn or finishes the one that is listening. The workspace Start/Send button uses that toggle. The capture bar's stop control calls `VoiceController.finish`.
2. `AppModel` gathers selected text for Ask and Translate, or an explicit Continue context, then calls `VoiceController.start`. Dictate does not upload the surrounding document. Translate starts only when there is a selection or Continue context.
3. `LiveSpeech` opens the OpenAI realtime transcription socket and `AudioCapture` starts the microphone at the same time. `BufferedAudioSender` keeps up to 150 PCM chunks and sends them in order after the session is ready. A connection failure or an overflow fails the turn. Listening stops after five minutes.
4. Finish commits the transcript. `TextProcessor` posts one Responses API request built by `ProviderWire.responseBody`. Ask may attach the `web_search` tool when that setting is on. The request body sets `store` to false. Dictation, Ask, and Translate each use the instructions in `TextRequest`. Ask also appends `AnswerStyle`.
5. The popover shows the result. Dictate inserts through `TextAccess` only when automatic insertion is on and the original app, field, text, and selection still match. Live typing, when enabled, revises only the span `LiveDictation` inserted at an empty caret. cmux receives one line from `TerminalDictation.insertionText`, which flattens newlines and tabs and rejects other control characters.
6. `RecordingArchive` writes a 24 kHz mono WAV and `transcript.json` on a utility queue after the result is shown. Quit waits for that queue. Cancel drops the turn.

`VoiceController` keeps a generation id for the active turn. A late transcript, model response, or second Send cannot deliver an older turn.

## App target

| File | Role |
| --- | --- |
| `AppMain.swift` | Menu bar process, status item, quit, and the debug commands below |
| `AppModel.swift` | Settings, keys, context, delivery, and history for the current turn |
| `FnKeyMonitor.swift` | Global Fn event tap |
| `AudioCapture.swift` | Microphone tap, conversion to 24 kHz 16-bit mono PCM, level meter |
| `LiveSpeech.swift` | OpenAI realtime transcription, and the unused Cartesia socket path |
| `LocalSpeech.swift` | On-device `SpeechAnalyzer` path, used by the file command below |
| `TextProcessor.swift` | OpenAI Responses call, plus unused Apple, Ollama, and Thinking Machines branches |
| `TextAccess.swift` | Selected text, focus checks, Accessibility writes, keyboard paste |
| `Keychain.swift` | API key storage for service `com.speakway.mac` |
| `PopoverController.swift` | Non-activating panel, bottom-center anchor, Escape |
| `PopoverViews.swift` | Launcher, capture bar, results, Continue chooser |
| `RichResults.swift` | Formatted result text and source cards |
| `ResultEditingView.swift` | Save and Cancel for a completed dictation |
| `HistoryView.swift` | Saved recordings in the secondary window |
| `Views.swift` | Optional workspace and Settings |
| `OverlayPreview.swift` | Debug-only synthetic UI states |

## Core target

| File | Role |
| --- | --- |
| `Models.swift` | Modes, settings migration, prompts, the JSON user payload, errors |
| `AnswerStyle.swift` | Writing rules applied only to Ask |
| `FnShortcut.swift` | Chord resolution with no AppKit types |
| `VoiceController.swift` | Phase machine: idle, preparing, listening, processing, ready, failed |
| `PendingContext.swift` | Continue, clipboard, and Clear choices for one recording |
| `BufferedAudioSender.swift` | Ordered audio queue while the socket connects |
| `ProviderWire.swift` | Request and response encoding for OpenAI, Cartesia, and Inkling |
| `LiveDictation.swift` | Ownership of the provisional typed span |
| `TerminalDictation.swift` | Single-line cmux text |
| `RichTextDocument.swift` | Markdown display, HTML copy, and plain text |
| `PopoverLayout.swift` | Fixed bottom-center frames inside the visible display |
| `RecordingHistory.swift` | History folder, WAV assembly, edit writes |

The user payload is JSON with separate `spoken_text`, `previous_transcription`, `selected_text`, and `default_target_language` fields. Each field is capped at 24,000 characters.

## Stored data

Settings live in UserDefaults under `settings`. Decoding keeps language, models, insertion, and history choices. It forces the speech and text providers to OpenAI, and applies `gpt-6-luna` plus conditional Ask search once through `textPolicyVersion`. Later model and search edits stay as saved.

The OpenAI key is a generic Keychain password, account `openai`, available when the device is unlocked. The app binary does not contain a key.

History files are under `~/Library/Application Support/SpeakWay/History/<recording-id>/`. The folder is owner-only, and the WAV and `transcript.json` are owner read and write. An edit writes `editedText` and leaves the original correction, raw transcript, and audio in place.

## Provider code outside Settings

`SpeechProvider` and `TextProvider` still list on-device speech, Cartesia, Apple Intelligence, Ollama, and Thinking Machines. `LiveSpeech`, `LocalSpeech`, `TextProcessor`, and `ProviderWire` still contain those branches. The Settings form labels both providers as OpenAI and shows one key field. A stored choice from an earlier build decodes back to OpenAI.

These process arguments stay in `AppMain` for local checks:

- `--diagnostics` prints local speech availability, installed locales, Apple Intelligence availability, Accessibility trust, and Input Monitoring.
- `--transcribe-file <path>` runs `LocalSpeech` on a file.
- `--local-process <text>` runs the Apple Intelligence text branch. `--ask`, `--translate`, and `--selection` change that request.
- In debug builds, `--benchmark-capture` times microphone startup and exits. `--preview-overlay <state>` shows a synthetic popover and does not load keys or open the event tap.

## Tests

`swift test` runs `Tests/SpeakWayCoreTests`. The files match the core behaviors: shortcuts, the voice controller, context, provider payloads, the audio queue, history, presentation, and live typing. See the Tests section in the README for what that suite does not cover.
