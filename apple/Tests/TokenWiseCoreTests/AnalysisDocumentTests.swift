import XCTest
@testable import TokenWiseCore

final class AnalysisDocumentTests: XCTestCase {
    private let report = """
    ## Actionable fixes

    1. **Delete the 10 duplicated `*.backup.*` skills** — `verify-issue.backup.*` (×6). Their
    descriptions are near-identical 60–80 word blocks; conservatively ~1.5–2.5K tokens.

    2. **Move Clawly's routine work off `claude-opus-5`.** Clawly is $101.29 of $132.68 across
    16 sessions.

    ## Narrative

    Nearly all your money is one project on one model: Clawly is $101 of $133.

    - A bullet that is not a numbered fix.
    """

    func testHeadingsAreParsedAsHeadingsNotLiteralText() {
        // Regression: the report rendered `## Actionable fixes` verbatim because
        // only inline markdown was interpreted.
        let headings = AnalysisDocument(report).blocks.compactMap { block -> String? in
            if case let .heading(_, level, text) = block, level == 2 { return text }
            return nil
        }
        XCTAssertEqual(headings, ["Actionable fixes", "Narrative"])
    }

    func testNumberedItemsBecomeSelectableFixes() {
        let fixes = AnalysisDocument(report).fixes
        XCTAssertEqual(fixes.count, 2)
        XCTAssertEqual(fixes.map(\.number), [1, 2])
        XCTAssertEqual(fixes.map(\.id).count, Set(fixes.map(\.id)).count, "ids must be unique")
    }

    func testWrappedContinuationLinesStayWithTheirItem() {
        let first = AnalysisDocument(report).fixes[0]
        XCTAssertTrue(first.markdown.contains("near-identical 60–80 word blocks"))
        XCTAssertFalse(first.markdown.contains("Move Clawly's"))
    }

    func testTitleUsesTheLeadingBoldRunWithoutMarkers() {
        let fixes = AnalysisDocument(report).fixes
        XCTAssertEqual(fixes[0].title, "Delete the 10 duplicated *.backup.* skills")
        XCTAssertEqual(fixes[1].title, "Move Clawly's routine work off claude-opus-5.")
    }

    func testTitleFallsBackToTheFirstSentence() {
        XCTAssertEqual(AnalysisDocument.title(of: "Trim the import chain. Then measure again."),
                       "Trim the import chain.")
    }

    func testBulletsAndParagraphsAreKeptApartFromFixes() {
        let blocks = AnalysisDocument(report).blocks
        let bullets = blocks.filter { if case .bullet = $0 { return true } else { return false } }
        let paragraphs = blocks.filter { if case .paragraph = $0 { return true } else { return false } }
        XCTAssertEqual(bullets.count, 1)
        XCTAssertEqual(paragraphs.count, 1)
    }

    func testEmptyReportProducesNoBlocks() {
        XCTAssertTrue(AnalysisDocument("").blocks.isEmpty)
        XCTAssertTrue(AnalysisDocument("   \n\n  ").blocks.isEmpty)
    }

    func testProseDecimalsAreNotMistakenForListMarkers() {
        // "3. " starts an item; "3.7M exceeds" does not.
        let doc = AnalysisDocument("115 × 32.4K = 3.7M exceeds the observed writes.")
        XCTAssertTrue(doc.fixes.isEmpty)
        XCTAssertEqual(doc.blocks.count, 1)
    }
}
