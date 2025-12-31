import SwiftUI

#if os(macOS)
import AppKit

/// Efficient text view for long content using native NSTextView.
/// SwiftUI's Text + textSelection is expensive for long text.
struct NativeTextView: NSViewRepresentable {
    let text: String
    let font: NSFont
    let textColor: NSColor
    let backgroundColor: NSColor
    let isSelectable: Bool

    init(
        text: String,
        font: NSFont = .systemFont(ofSize: 13),
        textColor: NSColor = .labelColor,
        backgroundColor: NSColor = .clear,
        isSelectable: Bool = true
    ) {
        self.text = text
        self.font = font
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.isSelectable = isSelectable
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        // Configure for display (not editing)
        textView.isEditable = false
        textView.isSelectable = isSelectable
        textView.drawsBackground = true
        textView.backgroundColor = backgroundColor
        textView.textContainerInset = .zero

        // Disable scroll view's scrolling - let parent handle it
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        // Size to fit content
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Only update if text actually changed
        if textView.string != text {
            textView.string = text
            textView.font = font
            textView.textColor = textColor
            textView.backgroundColor = backgroundColor
            textView.isSelectable = isSelectable
        }
    }
}

#else
import UIKit

/// Efficient text view for long content using native UITextView.
struct NativeTextView: UIViewRepresentable {
    let text: String
    let font: UIFont
    let textColor: UIColor
    let backgroundColor: UIColor
    let isSelectable: Bool

    init(
        text: String,
        font: UIFont = .systemFont(ofSize: 15),
        textColor: UIColor = .label,
        backgroundColor: UIColor = .clear,
        isSelectable: Bool = true
    ) {
        self.text = text
        self.font = font
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.isSelectable = isSelectable
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = isSelectable
        textView.isScrollEnabled = false  // Let parent scroll
        textView.backgroundColor = backgroundColor
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            textView.text = text
            textView.font = font
            textView.textColor = textColor
            textView.backgroundColor = backgroundColor
            textView.isSelectable = isSelectable
        }
    }
}
#endif

// MARK: - SwiftUI Convenience

extension NativeTextView {
    /// Create with SwiftUI-style parameters
    static func styled(
        _ text: String,
        size: CGFloat = 13,
        color: Color = .primary,
        background: Color = .clear,
        selectable: Bool = true
    ) -> NativeTextView {
        #if os(macOS)
        return NativeTextView(
            text: text,
            font: .systemFont(ofSize: size),
            textColor: NSColor(color),
            backgroundColor: NSColor(background),
            isSelectable: selectable
        )
        #else
        return NativeTextView(
            text: text,
            font: .systemFont(ofSize: size),
            textColor: UIColor(color),
            backgroundColor: UIColor(background),
            isSelectable: selectable
        )
        #endif
    }
}
