import AppKit
import RightKitShared
import SwiftUI

/// Plain text is essential for executable code: smart quotes/dashes, rich text,
/// spelling replacement and data detection must never rewrite a script.
struct ScriptTextView: NSViewRepresentable {
    @Binding var text: String
    var isEditable = true
    var language = ScriptHighlighter.Language.plain

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor

        let editor = NSTextView()
        editor.isRichText = false
        editor.isEditable = isEditable
        editor.isSelectable = true
        editor.allowsUndo = isEditable
        editor.usesFindBar = true
        editor.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        editor.textColor = .textColor
        editor.backgroundColor = .textBackgroundColor
        editor.textContainerInset = NSSize(width: 12, height: 12)
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isGrammarCheckingEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.isAutomaticDataDetectionEnabled = false
        editor.isHorizontallyResizable = true
        editor.isVerticallyResizable = true
        editor.minSize = .zero
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.containerSize = editor.maxSize
        editor.textContainer?.widthTracksTextView = false
        editor.autoresizingMask = [.width]
        editor.string = text
        editor.delegate = context.coordinator
        editor.setAccessibilityLabel(accessibilityLabel)
        scroll.documentView = editor
        ScriptHighlighter.apply(to: editor, language: language)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let languageChanged = context.coordinator.parent.language != language
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView else { return }
        editor.isEditable = isEditable
        editor.allowsUndo = isEditable
        editor.setAccessibilityLabel(accessibilityLabel)
        guard editor.string != text else {
            if languageChanged { context.coordinator.highlight(editor) }
            return
        }
        let atBottom = editor.visibleRect.maxY >= editor.bounds.maxY - 32
        let selection = editor.selectedRange()
        editor.string = text
        if isEditable {
            let count = (text as NSString).length
            editor.setSelectedRange(NSRange(location: min(selection.location, count), length: 0))
        } else if language == .plain && atBottom {
            editor.scrollRangeToVisible(NSRange(location: (text as NSString).length, length: 0))
        }
        context.coordinator.highlight(editor)
    }

    private var accessibilityLabel: String {
        isEditable ? Strings.Custom.script : language == .plain ? Strings.Custom.output : Strings.Custom.sourceCode
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScriptTextView
        private var pendingHighlight: DispatchWorkItem?
        init(_ parent: ScriptTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard parent.isEditable, let view = notification.object as? NSTextView else { return }
            parent.text = view.string
            highlight(view, delay: 0.08)
        }

        func highlight(_ editor: NSTextView, delay: TimeInterval = 0) {
            pendingHighlight?.cancel()
            let work = DispatchWorkItem { [weak self, weak editor] in
                guard let self, let editor else { return }
                ScriptHighlighter.apply(to: editor, language: self.parent.language)
            }
            pendingHighlight = work
            if delay == 0 { work.perform() }
            else { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) }
        }
    }
}
