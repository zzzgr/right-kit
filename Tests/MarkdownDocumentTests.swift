import Foundation
import XCTest

final class MarkdownDocumentTests: XCTestCase {
    func testHeadingsAndInlineFormattingKeepSeparateBlocks() throws {
        let document = MarkdownDocument("""
        # 图片压缩

        包含 **加粗**、*斜体*、`QUALITY` 和 [说明](https://example.com/docs)。

        第二段。
        """)
        XCTAssertEqual(document.blocks.count, 3)
        XCTAssertEqual(document.blocks[0].kind, .header(level: 1))
        XCTAssertEqual(document.blocks[0].plainText, "图片压缩")
        let paragraph = document.blocks[1]
        XCTAssertEqual(paragraph.plainText, "包含 加粗、斜体、QUALITY 和 说明。")
        XCTAssertTrue(paragraph.text.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        XCTAssertTrue(paragraph.text.runs.contains { $0.inlinePresentationIntent?.contains(.emphasized) == true })
        XCTAssertTrue(paragraph.text.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true })
        XCTAssertEqual(paragraph.text.runs.compactMap(\.link).first?.absoluteString, "https://example.com/docs")
        XCTAssertTrue(paragraph.text.runs.allSatisfy { $0.presentationIntent == nil })
        XCTAssertEqual(document.blocks[2].plainText, "第二段。")
    }

    func testNestedListsAndContinuationParagraphsKeepTheirOrder() {
        let document = MarkdownDocument("""
        3. 选择文件

           可以一次选择多张。

           - 检查 **尺寸**
           - 确认输出
        4. 运行
        """)
        XCTAssertEqual(document.blocks.count, 1)
        let list = document.blocks[0]
        XCTAssertEqual(list.kind, .orderedList)
        XCTAssertEqual(list.children.count, 2)
        XCTAssertEqual(list.children[0].kind, .listItem(ordinal: 3))
        XCTAssertEqual(list.children[1].kind, .listItem(ordinal: 4))
        let first = list.children[0]
        XCTAssertEqual(first.children.map(\.kind), [.paragraph, .paragraph, .unorderedList])
        XCTAssertEqual(first.children[1].plainText, "可以一次选择多张。")
        XCTAssertEqual(first.children[2].children.map { $0.children[0].plainText }, ["检查 尺寸", "确认输出"])
    }

    func testFencedCodePreservesWhitespaceAndLiteralMarkdown() {
        let document = MarkdownDocument("""
        ```python
        if True:
            print("# *literal* | text")

        print("done")
        ```
        """)
        XCTAssertEqual(document.blocks.count, 1)
        XCTAssertEqual(document.blocks[0].kind, .codeBlock(languageHint: "python"))
        XCTAssertEqual(document.blocks[0].plainText, "if True:\n    print(\"# *literal* | text\")\n\nprint(\"done\")\n")
        XCTAssertTrue(document.blocks[0].text.runs.allSatisfy { $0.inlinePresentationIntent == nil })
    }

    func testParameterTablesKeepColumnsAlignmentAndEmptyCells() throws {
        let document = MarkdownDocument("""
        | 参数 | 默认值 | 说明 |
        | :--- | :---: | ---: |
        | `QUALITY` | 80 | 图片质量 |
        | OUTPUT | | 自动生成 |
        """)
        let table = try XCTUnwrap(document.blocks.first)
        guard case .table(let columns) = table.kind else { return XCTFail("Expected a parameter table") }
        XCTAssertEqual(columns.map(\.alignment), [.left, .center, .right])
        XCTAssertEqual(table.children.count, 3)
        XCTAssertEqual(table.children[0].kind, .tableHeaderRow)
        XCTAssertEqual(table.children[0].children.map(\.plainText), ["参数", "默认值", "说明"])
        let quality = try XCTUnwrap(table.children[1].children.first)
        XCTAssertEqual(quality.plainText, "QUALITY")
        XCTAssertTrue(quality.text.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true })
        let description = table.children[2].children.first { $0.kind == .tableCell(columnIndex: 2) }
        XCTAssertEqual(description?.plainText, "自动生成")
        XCTAssertFalse(table.children[2].children.contains { $0.kind == .tableCell(columnIndex: 1) && !$0.plainText.isEmpty })
    }

    func testBlockQuotesAndDividersStayDistinct() {
        let document = MarkdownDocument("""
        > ## 注意
        >
        > 原文件会保留。

        ---

        结束。
        """)
        XCTAssertEqual(document.blocks.map(\.kind), [.blockQuote, .thematicBreak, .paragraph])
        XCTAssertEqual(document.blocks[0].children.map(\.kind), [.header(level: 2), .paragraph])
        XCTAssertEqual(document.blocks[0].children[1].plainText, "原文件会保留。")
    }

    func testTaskItemsPreserveFormattingAndCompletionState() {
        let document = MarkdownDocument("""
        - [x] **已完成**
        - [ ] 待处理
        - [todo] 普通项目
        """)
        let items = document.blocks[0].children
        XCTAssertEqual(items.map(\.checked), [true, false, nil])
        XCTAssertEqual(items.map { $0.children[0].plainText }, ["已完成", "待处理", "[todo] 普通项目"])
        XCTAssertTrue(items[0].children[0].text.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
    }

    func testLinksAllowWebAndEmailButDoNotLaunchFilesOrAppActions() {
        let document = MarkdownDocument("""
        [网站](https://example.com) [本地市场](http://127.0.0.1:3000) [邮件](mailto:hello@example.com)
        [文件](file:///tmp/script.sh) [动作](rightkit://custom?ticket=1) [脚本](javascript:alert%281%29)
        """)
        let links = document.blocks.flatMap { $0.text.runs.compactMap(\.link) }
        XCTAssertEqual(links.map(\.scheme), ["https", "http", "mailto"])
        XCTAssertTrue(document.blocks[0].plainText.contains("文件 动作 脚本"))
    }

    func testHTMLIsSkippedAndImageAlternativeTextIsRetained() {
        let document = MarkdownDocument("""
        <script>alert("test")</script>

        前面 <b>文字</b> 后面。

        ![操作示意图](https://example.com/image.png)
        """)
        XCTAssertEqual(document.blocks.map(\.plainText), ["前面 文字 后面。", "操作示意图"])
        XCTAssertTrue(document.blocks.flatMap { Array($0.text.runs) }.allSatisfy { $0.imageURL == nil })
    }

    func testEmptyAndIncompleteMarkdownRemainReadable() {
        XCTAssertTrue(MarkdownDocument("").blocks.isEmpty)
        XCTAssertTrue(MarkdownDocument(" \n\n").blocks.isEmpty)
        let document = MarkdownDocument("## 说明\n\n**未闭合\n\n```sh\necho hello")
        XCTAssertEqual(document.blocks[0].plainText, "说明")
        XCTAssertEqual(document.blocks[1].plainText, "**未闭合")
        XCTAssertEqual(document.blocks.last?.plainText, "echo hello\n")
    }
}
