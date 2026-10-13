import Foundation
import CoreGraphics
import Testing
@testable import SpeakWayCore

@Test func expandedResultsKeepTheirCaptureAnchorAndFitTheDisplay() {
    for visibleFrame in [CGRect(x: 0, y: 80, width: 1440, height: 790),
                         CGRect(x: -1920, y: -300, width: 1920, height: 1080),
                         CGRect(x: 20, y: 0, width: 400, height: 350)] {
        let capture = PopoverLayout.capture.frame(in: visibleFrame)
        for layout in [PopoverLayout.launcher, .continuation, .result(.dictate), .result(.translate), .result(.ask), .failure] {
            let result = layout.frame(in: visibleFrame)
            #expect(result.midX == capture.midX && result.minY == capture.minY)
            #expect(visibleFrame.contains(result))
            #expect(result.height > capture.height)
        }
    }
}

@Test func richDictationPreservesListsEmphasisAndReadablePlainText() {
    let document = RichTextDocument("""
    ## Wednesday

    Meet in the **large room**.

    - Review the design.
    - Confirm the plan.

    3. Send the draft to Bob.
    4. Book the room.
    """)
    #expect(document.plainText == "Wednesday\n\nMeet in the large room.\n• Review the design.\n• Confirm the plan.\n3. Send the draft to Bob.\n4. Book the room.")
    #expect(document.html.contains("<h2>Wednesday</h2>"))
    #expect(document.html.contains("<strong>large room</strong>"))
    #expect(document.html.contains("<ul><li value=\"1\">"))
    #expect(document.html.contains("<ol><li value=\"3\">"))
    #expect(document.hasFormatting)
    #expect(document.paragraphs.compactMap(\.marker) == ["•", "•", "3.", "4."])
}

@Test func richTextExportsCannotIntroduceExecutableHTMLOrPrivateURLSchemes() {
    let document = RichTextDocument("[Website](https://example.org/?a=1&b=2) and [local file](file:///private/secret) and `</script><img src=x onerror=alert(1)>`.")
    #expect(document.html.contains("href=\"https://example.org/?a=1&amp;b=2\""))
    #expect(!document.html.contains("href=\"file:"))
    #expect(!document.html.contains("<script") && !document.html.contains("<img"))
    #expect(document.plainText.contains("local file"))
    #expect(document.plainText.contains("</script><img"))
    #expect(!RichTextDocument.isWebURL(URL(string: "https:missing-host")!))
}

@Test func tablesRetainTheirRowsAndColumnsAcrossRichAndPlainText() {
    let document = RichTextDocument("| Task | Owner |\n| --- | --- |\n| Draft | Bob |\n| Review | Alice |")
    #expect(document.plainText == "Task\tOwner\nDraft\tBob\nReview\tAlice")
    #expect(document.html.contains("<table><tr><td>Task</td><td>Owner</td></tr>"))
    #expect(document.paragraphs.filter(\.isTableHeader).count == 2)
}
