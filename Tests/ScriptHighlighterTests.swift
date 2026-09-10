import AppKit
import XCTest

final class ScriptHighlighterTests: XCTestCase {
    private func fragments(_ source: String, _ language: ScriptHighlighter.Language,
                           _ kind: ScriptHighlighter.Kind) -> [String] {
        ScriptHighlighter.tokens(in: source, language: language).filter { $0.kind == kind }
            .map { (source as NSString).substring(with: $0.range) }
    }

    func testPythonCommentsStringsAndUnicodeRemainSeparate() {
        let source = "名称 = \"图片 🖼 # if 123\"\n# return 42\nfor path in paths:\n    print(path, 12)\n"
        XCTAssertEqual(fragments(source, .python, .string), ["\"图片 🖼 # if 123\""])
        XCTAssertEqual(fragments(source, .python, .comment), ["# return 42"])
        XCTAssertEqual(fragments(source, .python, .keyword), ["for", "in"])
        XCTAssertEqual(fragments(source, .python, .function), ["print"])
        XCTAssertEqual(fragments(source, .python, .number), ["12"])
        XCTAssertEqual(String(ScriptHighlighter.attributed(source, language: .python).characters), source)
    }

    func testPythonMultilineAndUnfinishedStringsDoNotColorTheirContentsAsCode() {
        let source = "doc = '''line one\n# if return\nline three'''\nvalue = f\"hello {name}\"\nunfinished = \"text # not a comment\nreturn 1"
        XCTAssertEqual(fragments(source, .python, .comment), [])
        XCTAssertEqual(fragments(source, .python, .string).count, 3)
        XCTAssertEqual(fragments(source, .python, .keyword), ["return"])
        XCTAssertEqual(fragments("value = \"\"\"unfinished\n# still a string", .python, .keyword), [])
        XCTAssertEqual(fragments("value = \"\"\"unfinished\n# still a string", .python, .string).count, 1)
    }

    func testShellVariablesQuotedHashesAndHeredocs() {
        let source = "for path in \"$@\"; do\n  printf '%s\\n' $path # selected file\n  echo file#name\n  cat <<'PY'\n# embedded Python\nprint(123)\nPY\ndone"
        XCTAssertEqual(fragments(source, .shell, .keyword), ["for", "in", "do", "done"])
        XCTAssertEqual(fragments(source, .shell, .variable), ["$path"])
        XCTAssertEqual(fragments(source, .shell, .comment), ["# selected file"])
        XCTAssertEqual(fragments(source, .shell, .string).last, "<<'PY'\n# embedded Python\nprint(123)\nPY")
    }

    func testJSONKeysAndUnknownLanguageFallbackKeepExactBytes() {
        let source = "{\"名称\": \"🖼 true\", \"enabled\": true, \"count\": -2.5, \"other\": null}\n"
        XCTAssertEqual(fragments(source, .json, .property), ["\"名称\"", "\"enabled\"", "\"count\"", "\"other\""])
        XCTAssertEqual(fragments(source, .json, .keyword), ["true", "null"])
        XCTAssertEqual(fragments(source, .json, .number), ["-2.5"])
        XCTAssertTrue(ScriptHighlighter.tokens(in: source, language: .init("unknown")).isEmpty)
        XCTAssertEqual(String(ScriptHighlighter.attributed(source, language: .plain).characters), source)
    }

    func testLongIdentifiersDoNotTriggerRepeatedFunctionSuffixSearches() {
        let source = String(repeating: "identifier", count: 16_000) + "\n"
        XCTAssertTrue(ScriptHighlighter.tokens(in: source, language: .python).isEmpty)
        XCTAssertEqual(fragments("123invalid()", .python, .function), [])
    }

    @MainActor
    func testEditorHighlightDoesNotChangePlainTextSelectionOrStoredAttributes() {
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 320))
        editor.isRichText = false
        editor.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        editor.string = "print(\"中文 🖼\") # note\n"
        // Finish AppKit's initial font fallback and select complete Unicode characters.
        editor.layoutManager?.ensureLayout(for: editor.textContainer!)
        let selection = (editor.string as NSString).range(of: "中文 🖼")
        editor.setSelectedRange(selection)
        let original = NSAttributedString(attributedString: editor.attributedString())
        ScriptHighlighter.apply(to: editor, language: .python)
        XCTAssertEqual(editor.attributedString(), original)
        XCTAssertEqual(editor.selectedRange(), selection)
        XCTAssertNotNil(editor.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 0, effectiveRange: nil))
        ScriptHighlighter.apply(to: editor, language: .plain)
        XCTAssertNil(editor.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 0, effectiveRange: nil))
        XCTAssertEqual(editor.string, original.string)
    }

    @MainActor
    func testHighlightKeepsAnEditUndoable() throws {
        let editor = UndoableTextView()
        editor.isRichText = false
        editor.allowsUndo = true
        editor.string = "print(1)\n"
        let undo = try XCTUnwrap(editor.undoManager)
        undo.beginUndoGrouping()
        editor.insertText("# comment", replacementRange: NSRange(location: 9, length: 0))
        undo.endUndoGrouping()
        XCTAssertEqual(editor.string, "print(1)\n# comment")
        ScriptHighlighter.apply(to: editor, language: .python)
        XCTAssertTrue(undo.canUndo)
        undo.undo()
        XCTAssertEqual(editor.string, "print(1)\n")
    }

    private final class UndoableTextView: NSTextView {
        private let edits = UndoManager()
        override var undoManager: UndoManager? { edits }
    }
}
