---
name: SpeakWay
description: A quiet native Mac popover for dictation, questions, and translation.
colors:
  foreground-accent-light: "rgb(19% 33% 80%)"
  foreground-accent-dark: "rgb(51% 66% 100%)"
  action-blue: "rgb(19% 33% 80%)"
typography:
  title:
    fontFamily: "SF Pro"
    fontSize: "28pt"
    fontWeight: 600
  capture-title:
    fontFamily: "SF Pro"
    fontSize: "21pt"
    fontWeight: 500
  popover-title:
    fontFamily: "SF Pro"
    fontSize: "15pt"
    fontWeight: 600
  compact-status:
    fontFamily: "SF Pro"
    fontSize: "13pt"
    fontWeight: 600
  result-body:
    fontFamily: "SF Pro"
    fontSize: "15pt"
    fontWeight: 400
  result-heading:
    fontFamily: "SF Pro"
    fontSize: "21pt"
    fontWeight: 600
  result-subheading:
    fontFamily: "SF Pro"
    fontSize: "17pt"
    fontWeight: 600
  detail:
    fontFamily: "SF Pro"
    fontSize: "11pt"
    fontWeight: 400
  label:
    fontFamily: "SF Pro"
    fontSize: "12pt"
    fontWeight: 500
  shortcut:
    fontFamily: "SF Mono"
    fontSize: "12pt"
    fontWeight: 500
  code:
    fontFamily: "SF Mono"
    fontSize: "13pt"
    fontWeight: 400
rounded:
  shortcut: "6pt"
  navigation: "8pt"
  context: "10pt"
  result: "12pt"
  overlay: "16pt"
  capture: "22pt"
spacing:
  row-gap: "8pt"
  control-gap: "12pt"
  context-inset: "14pt"
  capture-inset: "16pt"
  panel-inset: "20pt"
  workspace-inset: "30pt"
components:
  button-primary:
    backgroundColor: "{colors.action-blue}"
  navigation-item:
    rounded: "{rounded.navigation}"
    padding: "11pt 12pt"
  launcher-row:
    rounded: "{rounded.navigation}"
    padding: "9pt 8pt"
  shortcut-badge:
    typography: "{typography.shortcut}"
    rounded: "{rounded.shortcut}"
    padding: "6pt 10pt"
  selected-context:
    rounded: "{rounded.context}"
    padding: "{spacing.context-inset}"
  result-panel:
    typography: "{typography.result-body}"
    rounded: "{rounded.result}"
    padding: "{spacing.panel-inset}"
  capture-popover:
    typography: "{typography.compact-status}"
    rounded: "{rounded.capture}"
    padding: "0pt 16pt"
    width: "352pt"
    height: "68pt"
  launcher-popover:
    rounded: "{rounded.overlay}"
    padding: "{spacing.panel-inset}"
    width: "380pt"
    height: "330pt"
  continuation-popover:
    rounded: "{rounded.overlay}"
    padding: "{spacing.panel-inset}"
    width: "420pt"
    height: "490pt"
  dictation-popover:
    rounded: "{rounded.overlay}"
    width: "520pt"
    height: "340pt"
  translation-popover:
    rounded: "{rounded.overlay}"
    width: "520pt"
    height: "420pt"
  ask-popover:
    rounded: "{rounded.overlay}"
    width: "560pt"
    height: "560pt"
  error-popover:
    rounded: "{rounded.overlay}"
    padding: "{spacing.panel-inset}"
    width: "460pt"
    height: "300pt"
  source-preview:
    rounded: "{rounded.result}"
    padding: "{spacing.control-gap}"
  source-thumbnail:
    rounded: "{rounded.navigation}"
    width: "104pt"
    height: "80pt"
---

# Design System: SpeakWay

## Overview

**Creative North Star: "The Quiet Mac Utility"**

SpeakWay keeps the user's words and next action prominent. A compact popover is the primary interface: it stays at the bottom center during capture and expands upward for results. Settings, History, and the optional workspace live in a secondary window. Native macOS surfaces, system type, and SF Symbols preserve the quiet Mac utility identity.

This record describes the SwiftUI and AppKit implementation in `PopoverController.swift`, `PopoverViews.swift`, `RichResults.swift`, `HistoryView.swift`, `Views.swift`, `TextAccess.swift`, `AppModel.swift`, and `SpeakWayCore/PopoverLayout.swift`. Dimensions are native points; the named SF families describe SwiftUI system and monospaced selections. Semantic AppKit colors remain appearance-dependent rather than fixed color tokens.

The rules below are the interface contract. They do not establish live OpenAI processing, microphone capture, Fn shortcuts, or automatic insertion.

**Key Characteristics:**

- **Type:** SF system text, SF Mono keyboard hints, and SF Symbols.
- **Material:** native semantic surfaces and controls with the AppKit panel shadow.
- **Ground:** adaptive window and text backgrounds in light and dark appearances.
- **Layout:** compact capture at a fixed bottom-center anchor, larger results with internal scrolling, and a secondary workspace for Settings and History.
- **Motion:** supplied audio levels and panel state transitions respond to work; Reduce Motion removes interpolation and resizing animation.

## Colors

Blue identifies the active mode, speech activity, and prominent actions. AppKit supplies the neutral surface and text colors.

### Primary

- **Foreground accent:** `foreground-accent-light` and `foreground-accent-dark` follow the current Aqua appearance. They tint icons, active navigation text, status labels, and the microphone meter. The workspace navigation fill uses 11% opacity; its capture icon disc uses 9%.
- **Action blue:** `action-blue` stays fixed across appearances for native prominent buttons with white labels.

### Neutral

Use `NSColor.windowBackgroundColor` for the workspace and popover, `controlBackgroundColor` at 40% opacity for the sidebar, and `textBackgroundColor` for the workspace result container. Keep SwiftUI primary, secondary, and quaternary styles semantic. Context, source cards, thumbnail fallbacks, and code blocks use primary at 4% opacity; the permission prompt uses 4.5%. Error messages remain readable text with a symbol; the workspace and History additionally use the system red foreground.

**The Accent Roles Rule.** Use the adaptive accent for foreground emphasis and the fixed action blue for prominent button fills.

## Typography

Use system SF type and SF Symbols. Mode, Settings, and History headings use `title`; the optional workspace capture prompt uses `capture-title`. Popover result and error headings use `popover-title`; the compact capture status uses `compact-status`, with a secondary `detail` line. The launcher title uses system semibold at 17 points.

Formatted output uses `result-body` with 4 points of added line spacing. Markdown level-one headings use `result-heading`; other heading levels use `result-subheading`. Code uses `code`, quotations use the secondary foreground, and bullet and numbered markers remain visible. Supporting text retains native callout and caption styles.

Workspace shortcut badges use `shortcut`; compact hints use the same monospaced family at 11 points, medium in the sidebar and regular in launcher rows. Keyboard hints stay subordinate to the action they explain.

**The Native Type Rule.** Preserve macOS system type and SF Symbols; keep result structure readable through native weight, size, and list markers.

## Layout

The primary popover uses the preferred sizes in the frontmatter: `launcher-popover` before capture, `capture-popover` while preparing, listening, or processing, the mode-specific result popover after completion, and `error-popover` for failures. Content does not resize capture. Results preserve a header and action footer while their body scrolls internally; the raw disclosure and source previews stay within that body.

The popover centers horizontally on the selected display and sits 42 points above its visible bottom edge. Results expand upward from the same bottom anchor. The display is selected from the pointer location when the panel first appears or capture begins and retained through that turn. `PopoverLayout.frame(in:)` clamps the preferred frame to the visible screen, normally leaving 16 points at the sides and top; exceptionally small visible frames also reduce the bottom inset. Display removal triggers a new screen choice. The panel cannot be dragged.

The secondary resizable window opens at 880 × 680 points with an 820 × 620 minimum content frame. A 184-point sidebar remains visible beside the workspace, Settings, or History. The workspace uses `workspace-inset` and 20-point vertical gaps. Keep the mode title and shortcut together, then context when applicable, capture or result, permission help, and the provider privacy summary. Its capture area retains a minimum height of 320 points for Dictate and 260 for Ask or Translate; its result body scrolls within 160–260 points. Settings uses a grouped form and History scrolls its selected entry. There is no web breakpoint or mobile layout.

**The Fixed Capture Rule.** Keep preparation, recording, and processing in the compact frame; put long text, source previews, and raw transcription in an internally scrolling result.

**The Focus Rule.** Capture cannot become key or main. Launcher, result, and error panels may accept keyboard focus after a click, but presenting them never activates SpeakWay or makes them key. Beginning another capture releases a previously key panel.

## Elevation & Depth

The workspace and popover use tonal surfaces and native dividers. Context, permission, result, and source containers have no custom shadow. AppKit provides the floating panel's system shadow through `NSPanel.hasShadow`; there is no fixed custom shadow recipe.

Panel size changes animate over 0.2 seconds when the visible state changes. `accessibilityDisplayShouldReduceMotion` disables that transition. The microphone level uses a 0.1-second ease-out interpolation; SwiftUI `accessibilityReduceMotion` disables it. Neither behavior supplies ambient animation.

## Shapes

Use the named corner roles in the frontmatter: compact shortcut, navigation, context, result, overlay, and capture. The capture bar has the softest corners; launcher and result panels share the overlay radius. Source cards use the result radius, while their clipped thumbnails and code blocks use the navigation radius. The stop action is a 30-point circle; the optional workspace capture symbol retains its 80-point circle. The microphone meter uses slim capsules. Native buttons and form controls retain their platform-provided shapes and focus treatment.

## Components

- **Launcher:** native icon-and-text rows start Dictate, Ask, or Translate and show their Fn shortcuts. Each row uses primary at 5% on hover and 10% when pressed. Settings, History, and Dismiss remain compact symbol actions with accessibility labels. A missing key produces a Set up action.
- **Capture bar:** the primary status, mode, and finish hint remain visible while listening. The supplied audio level drives nine capsules. Finish is the circular stop action; Escape or the close control cancels. Preparation and processing use a native progress indicator and text. Processing explicitly says the microphone is off.
- **Workspace navigation and context:** mode buttons use the adaptive accent and an 11% selected fill; Settings and History use a neutral 6% fill. The Ask and Translate context container identifies the source app, previews up to three lines, and offers Clear, Use selection, or Use clipboard. Mode changes, settings, history, and context editing are unavailable while busy.
- **Primary actions:** native `borderedProminent` buttons use `action-blue`; AppKit may adjust their inactive presentation. Copy is prominent in results. The optional workspace capture action changes from Start to Send while listening and is disabled during preparation or processing. Focus and hover behavior remain native except for the documented launcher row treatment.
- **Corrected result:** Dictate leads with Corrected text, then the formatted output. A collapsed Raw transcription disclosure retains the original speech and a separate Copy raw text action. Contextual self-corrections and spoken formatting belong in the corrected result; summarization occurs only when requested. Copy and dictation delivery use the corrected document. The workspace keeps its existing Original speech disclosure label.
- **Continue:** completed dictations offer Continue beside Speak again. Continue opens a scrollable mode chooser at the same bottom anchor, with a three-line transcription preview and Clear action. Corrected text is the default; the raw disclosure offers Use raw as context. Clear restores the completed result before recording. Dictate uses the text as background, Ask answers about it, and Translate translates it. Context is explicit, applies to one recording, and remains visible after setup failures. The workspace also previews pending or active transcription context. Capture retains its compact size and indicates context during listening.
- **Rich text:** native text renders headings, emphasis, bullet and numbered lists, quotations, code, tables, and web links. Paragraphs use 12-point gaps; nested lists indent 16 points per level and table cells share available width. Copy supplies generated HTML and readable plain text. Non-web links are not actionable. This does not require an embedded web view.
- **Delivery status:** Dictate attempts automatic insertion only when enabled and the original app, field, selection, and text are unchanged. An Accessibility write reports Inserted; a posted keyboard paste reports Paste sent and offers Copy if it did not appear. Ask and Translate remain reviewable results and never auto-insert. Showing a result never submits another app's form or message.
- **Ask sources:** formatted answers precede vertical source cards. Each card keeps a title, host, external-link symbol, and bounded `source-thumbnail`. Native LinkPresentation loads metadata asynchronously after the answer appears, with an eight-second timeout; missing images retain a globe fallback and a working link. Preview loading cannot delay or replace the answer. The cards contact cited websites and do not imply generated media.
- **Errors:** an explanatory heading and scrollable error text precede recovery actions. If speech was captured, show it and provide Copy speech. Missing credentials offer Open Settings; other failures offer Try again, with Use clipboard for Ask or Translate. Copy feedback remains visible.
- **History:** the secondary window shows saved entries by date and mode. A selected entry leads with the corrected result, followed by raw transcription, audio controls, and file actions. Background save completion refreshes the list through `historyRevision`; an existing selection is preserved. Local history is enabled by default and can be disabled for future turns. Utility-queue writes save owner-only WAV and JSON files after result presentation; saving and failures appear as secondary status. Cancellation discards the current recording. Empty history uses an honest empty state.
- **Settings:** grouped sections contain native language pickers, OpenAI model fields, search and insertion toggles, a secure OpenAI key field, permission status, and the local-history setting. Keep provider and retention explanations readable. The form is disabled while busy.
- **Microphone meter:** nine capsules in the compact bar and fifteen in the workspace respond only to the supplied level. The accessibility value reports Sound detected or Quiet. Decorative waveform symbols are static; the live meter has no independent loop.

**The Corrected First Rule.** Present the useful corrected result before raw speech, while keeping raw transcription and saved audio available for reference.

**The Honest Delivery Rule.** Distinguish a confirmed Accessibility write from an unconfirmed keyboard paste, and never imply that Ask or Translate inserted text.

## Do's and Don'ts

### Do:

- **Do** keep native system surfaces, controls, typography, and focus behavior.
- **Do** keep capture compact and anchored while results scroll inside their larger frame.
- **Do** show corrected text first and keep raw transcription separately accessible.
- **Do** keep selected context above workspace capture and provider privacy information visible.
- **Do** use instructional examples only in empty states and actual content for transcripts and results.
- **Do** communicate recording, processing, errors, and permission needs with text as well as color.
- **Do** keep source thumbnails bounded and preserve usable source links when metadata loading fails.
- **Do** describe background history saving and insertion outcomes truthfully.

### Don't:

- **Don't** use the pale dark-appearance foreground accent behind white action labels.
- **Don't** invent fixed light or dark values for semantic AppKit surfaces.
- **Don't** create fake transcript history or present samples as real results.
- **Don't** add ambient meter animation or take keyboard focus when presenting the popover.
- **Don't** auto-insert Ask answers or translations, or label a keyboard paste as confirmed insertion.
- **Don't** make source previews or history writes block the visible result.
