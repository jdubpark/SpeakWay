# SpeakWay

A native Mac menu bar app for intelligent dictation, spoken questions, and translating selected text. This version uses OpenAI for both speech and text processing. Requires macOS 26 or later, internet access, and your own OpenAI API key.

Product constraints are in [PRODUCT.md](PRODUCT.md). Interface rules are in [DESIGN.md](DESIGN.md). The source map is in [docs/architecture.md](docs/architecture.md).

## Run

Build the app with Xcode's Swift tools, then open it. `dist/` is a local build product and is not in this repository.

```sh
zsh scripts/build.sh
open dist/SpeakWay.app
```

The build signs with the first Apple Development certificate in your keychain, or with `SPEAKWAY_SIGN_IDENTITY` when set, so Mac permissions survive rebuilds. Without a certificate it falls back to an ad hoc signature, which macOS treats as a different app after every rebuild. It is not notarized for distribution. Keep the app at a stable path when granting Mac permissions.

1. Use **Set up** in the small SpeakWay launcher, or right-click the menu bar icon and open **Settings**. Save your OpenAI API key to Keychain. The same key handles transcription, cleanup, answers, and translation.
2. Choose your spoken language and default translation language. The default models are `gpt-live-transcribe` for speech and `gpt-6-luna` for text; model names remain editable for your account's available models.
3. Enable **Accessibility** and **Input Monitoring** in macOS Privacy & Security for global Fn shortcuts, selected text, and insertion. Allow the microphone when the first recording requests it. The on-screen button also works without global shortcuts.
   If System Settings shows SpeakWay enabled but SpeakWay still reports a permission as required, the grant belongs to an earlier signature. Remove SpeakWay from the list with **−** (or run `tccutil reset Accessibility com.speakway.mac`), then choose **Enable permissions** again.
4. If macOS opens emoji or its own dictation, set **Keyboard → Press Globe key to → Do Nothing**. SpeakWay does not change system settings automatically.

| Start | Mode | Result |
| --- | --- | --- |
| Fn | Dictate | Removes fillers and repetitions, applies spoken corrections, inserts into the original text field when still safe |
| Fn + Shift | Translate | Uses selected text plus your spoken language/style instruction; shows the translation |
| Fn + Space | Ask | Answers the spoken question, with selected text when available |

Press **Fn again** to finish and process any mode. **Escape** cancels capture or dismisses a result. Fn alone and Fn + Shift start on key release so the app can distinguish chords. Fn + Space starts when Space is pressed. A menu bar click and the on-screen button also start/finish; right-click the menu bar icon for modes, History, the optional workspace, and Settings. Command-Q quits.

The primary interface is a 352 × 68-point capture popover, fixed at the bottom center of the display containing the pointer when a turn starts. It keeps that display and bottom edge when it expands into the result. Results scroll inside the popover, remain available until dismissed or replaced, and never take keyboard focus automatically. Configured launches stay in the menu bar. Reopening the app shows the launcher or current result.

Wait until **Listening** before speaking. Microphone startup runs alongside the OpenAI connection; a bounded queue holds early audio until that connection is ready, then sends it in order. Connection failures or queue overflow stop the turn with an error instead of silently dropping speech. A recording ends automatically after five minutes. “Send” means finish this recording and produce text; SpeakWay never presses Return or submits a message in another app.

For selected text, select it in the other app and use the shortcut. Apps differ in their Accessibility support. If a selection cannot be read, copy it and choose **Use clipboard** in SpeakWay before recording. **Clear** excludes the selection from the next question; **Use selection** or **Use clipboard** adds context again. Clipboard and Clear choices survive setup failures and are consumed when a question or translation starts listening. Ask and Translate keep results for review and copying. In standard text editors, dictation inserts only if the original application, field, contents, and selection are unchanged. Otherwise the result stays available to copy. cmux uses the final-only terminal path described below.

## Corrected text and formatting

The result leads with **Corrected text**, and **Raw transcription** expands underneath it. For example, “Book the small room Tuesday. Oh wait, that’s incorrect; I meant the large room Wednesday” should become “Book the large room Wednesday.” Correction quality depends on the text model; the original remains available to compare. Summarization requires an explicit spoken request.

Say “make these bullet points,” “number one,” “new paragraph,” or other formatting cues. Results render headings, bold/italic text, bullets, numbered lists, quotations, code, and tables. Copy and dictation insertion offer HTML to rich-text editors and readable plain text to other fields. The receiving app chooses the supported format. “Paste sent” means the keyboard paste was requested; use Copy if the receiving app does not accept it. Ask adds native source previews with images when the cited page exposes them; unavailable previews retain their title and link. Translations and answers are never automatically pasted.

Choose **Edit** on a completed dictation, change its text or Markdown, then **Save changes** (⌘S). Cancel discards the draft. Editing explicitly focuses SpeakWay; simply showing a result does not. The result updates immediately and, when history is enabled, its revision saves in the background. The original corrected text, raw speech, and audio remain intact. Later edits are available through **Copy** and are not automatically written back into another app. Saved dictations also offer **History → Edit**.

## Continue from a transcription

After a dictation finishes, choose **Continue** to use its corrected text as background for your next recording. Review the context preview, then choose **Dictate**, **Ask**, or **Translate**, or use that mode’s Fn shortcut. **Raw transcription → Use raw as context** uses the original speech instead. **Speak again** starts without adding the previous transcription.

- **Dictate** uses the context for names, terminology, and references while producing only the new words. It does not merge or rewrite the earlier text.
- **Ask** answers your new spoken question about the transcription.
- **Translate** translates the transcription using your spoken language or style instruction.

The context replaces automatic selected-text context for that recording. **Clear** removes it; before recording starts, clearing returns to the completed result. The choice stays in memory through setup failures and is consumed when listening starts, including if that recording is later cancelled or fails. It is not carried into subsequent recordings automatically. Context is limited to 24,000 characters and goes to OpenAI with the new transcript when you send. The existing insertion and live-typing checks still apply; earlier completed text is outside the new live-typing span.

## Live typing

Enable **Settings → Type dictation as I speak** under the automatic-insertion toggle. It is off by default and applies only to Dictate. With an empty cursor in a supported text field, provisional transcription appears as you speak; the final corrected result replaces that same span once processing completes.

SpeakWay tracks the text it inserted during this recording. Before each revision, it checks the original application and field, the complete field value, and the cursor position. Only its owned span is selected for replacement. Existing text on either side, including earlier completed dictations, stays outside the edit range. If focus, text, or selection no longer matches, live typing stops for that turn and the result stays available to copy. It does not resume automatically. Starting over selected text is refused so existing content is never intentionally replaced by live dictation.

Cancel removes the provisional span only if those checks still pass. After an external edit or focus change is detected, Cancel leaves the field alone. A processing failure leaves the current draft for review. Supported fields must expose readable text and selection plus writable Accessibility text ranges; unsupported fields use the popover without a final insertion fallback, except for the explicit cmux path below.

Live updates are coalesced at 150 ms and make no additional model requests. They use plain text, including readable bullets and numbering. **Copy** in the result still supplies rich formatting. Live mode never sends backspaces or clipboard paste events, never replaces the full field, and never presses Return to submit.

### cmux

cmux 0.64.25 accepts inserted text but does not expose a readable full text buffer or writable ranges. SpeakWay therefore inserts the final corrected dictation automatically when you finish, even if live typing is enabled. It appends once through cmux's native Accessibility text entry, never revises or deletes terminal content, and never sends Return. Newlines and tabs become spaces for this terminal path; **Copy** retains the formatted document and line breaks.

Delivery requires the same focused terminal, no selected terminal text, and no intervening input observed by macOS's global event monitor. Programmatic input can bypass that monitor, so this is not a full-buffer comparison. Changed focus or a detected interruption leaves the result available to copy. Ask and Translate never insert into cmux.

## Local history

History keeps each turn’s corrected result, raw transcription, and audio on this Mac. Open it from the popover’s clock button or the menu bar. You can edit a dictation, compare its latest revision with the original correction and raw speech, copy text, and replay the recording. Edits update metadata without rewriting audio. Saves and edits share a serial utility queue so an immediate edit cannot overtake its initial recording save.

Audio capture only enqueues references to PCM chunks already prepared for speech recognition. A utility queue assembles a playable 24 kHz, 16-bit mono WAV and atomically writes `transcript.json` after processing. Result display and insertion never await file writes. Archival errors appear separately and do not discard the result. A five-minute capture limit bounds the audio buffer; normal Quit asynchronously finishes pending saves.

Files live under `~/Library/Application Support/SpeakWay/History/<recording-id>/`, with owner-only file permissions. They remain until removed through **History → Open folder**. **Settings → Local history** disables saving for future turns without deleting existing files. Cancelled recordings are discarded; failed turns preserve available speech/audio. A forced process exit before saving completes can lose that turn.

## OpenAI setup

Speech streams through the [realtime transcription API](https://developers.openai.com/api/docs/guides/realtime-transcription). Fn manually finalizes the turn. Cleanup, answers, and translation then use the [Responses API](https://developers.openai.com/api/docs/guides/text). Ask permits web search by default, with automatic tool choice and instructions to search only when the question needs current or external information. Disable it in Settings to prevent all web searches.

Create a key in your [OpenAI API account](https://platform.openai.com/api-keys), then paste it into **Settings → OpenAI API key**. No developer key is embedded. API usage is billed to your OpenAI account.

Earlier saved local, Cartesia, and Thinking Machines choices migrate to OpenAI when this version launches. This update sets the text model to `gpt-6-luna` and enables conditional Ask search once. Language, speech model, and insertion preferences are preserved. Later model and search edits survive restarts. Those other providers are deferred and are not available in the app's Settings. Earlier adapters and local diagnostic helpers remain in source for future development.

## Answer style

Ask uses writing rules adapted from No AI Slop and Simplified Technical English (ASD-STE100) guidelines. The rules are compiled into `Sources/SpeakWayCore/AnswerStyle.swift`, so the app needs no external style files at runtime. Answers use direct wording, short sentences, concrete facts, and preserved uncertainty. No draft-editing workflow or style report is added.

These rules apply only to Ask. Intelligent dictation retains its correction and cleanup prompt, and translation retains its meaning, tone, and language requirements. All three use the configured text model. Web-search necessity and writing quality depend on the model following the prompt; local tests do not establish hosted behavior.

## Data and behavior

- OpenAI receives microphone audio while you record; pressing Send finalizes it. Cancellation stops capture and the connection but cannot retract already transmitted audio.
- OpenAI text processing receives the transcript, explicitly chosen transcription context in any mode, and selected text for Ask/Translate when you send. Dictation does not upload the surrounding document. Web search is restricted to Ask and can be disabled in Settings. Search decisions follow the answer prompt and automatic tool choice.
- SpeakWay stores settings, its Keychain credential, and local recording history when enabled. Clearing the active result removes it from the popover, not from History. Copying or inserting creates content in the destination app/clipboard. OpenAI text requests set `store:false`, which is not a zero-retention guarantee; OpenAI's retention policies apply.
- There is one recording and one text request per turn. Repeated Send clicks cannot duplicate delivery. Cancellation fences late callbacks and results; sleep or session lock cancels capture. Incomplete cloud responses and transcription failures do not become inserted text.
- Selection, previous-transcription context, and new speech have separate structured fields. Prompts treat context as untrusted reference material. This reduces accidental instruction following; model outputs still need judgment, especially names, numbers, corrections, and translations.
- Ask sees only the spoken question and supplied context. It has no general screen, file, account, or action access. It can use the optional web-search tool.

## Tests

```sh
swift test
zsh scripts/build.sh
codesign --verify --strict dist/SpeakWay.app
```

`Tests/SpeakWayCoreTests` covers shortcut chords, one request per capture, cancellation, empty speech, context choices, provider payloads, settings migration, rich text, history files, the audio queue, live-typing span ownership, and the cmux insertion string. The suite does not start the microphone, press Fn, insert into another app, or call OpenAI.
