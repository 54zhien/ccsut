import SwiftUI
import UIKit
import CoreText

/// TextKit draws masked glyphs; the separate binding retains the actual submission value.
/// AX and the copy menu must never expose the underlying sensitive digit sequences.
struct CampusMaskedEditor: UIViewRepresentable {
    @Binding var text: String
    let label: String
    var identifier = ""
    var onFocus: ((Bool) -> Void)? = nil
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> CampusPrivateTextView {
        let view = CampusPrivateTextView(usingTextLayoutManager: false)
        view.backgroundColor = .clear
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.autocorrectionType = .no; view.spellCheckingType = .no
        view.textContentType = nil; view.dataDetectorTypes = []
        view.writingToolsBehavior = .none
        view.textDragInteraction?.isEnabled = false
        view.textDragDelegate = context.coordinator
        view.smartQuotesType = .no; view.smartDashesType = .no
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.delegate = context.coordinator; view.layoutManager.delegate = context.coordinator
        view.accessibilityLabel = label; view.accessibilityIdentifier = identifier
        return view
    }
    func updateUIView(_ view: CampusPrivateTextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text {
            let selection = view.selectedRange
            view.text = text
            if selection.location + selection.length <= (text as NSString).length { view.selectedRange = selection }
            context.coordinator.refresh(view)
        }
        view.font = .preferredFont(forTextStyle: .body)
    }
    final class Coordinator: NSObject, UITextViewDelegate, NSLayoutManagerDelegate, UITextDragDelegate {
        var parent: CampusMaskedEditor
        init(_ parent: CampusMaskedEditor) { self.parent = parent }
        func textViewDidBeginEditing(_ textView: UITextView) { parent.onFocus?(true) }
        func textViewDidEndEditing(_ textView: UITextView) { parent.onFocus?(false) }
        func textDraggableView(_ textDraggableView: any UIView & UITextDraggable, itemsForDrag dragRequest: any UITextDragRequest) -> [UIDragItem] { return [] }
        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text; refresh(textView) }
        func refresh(_ textView: UITextView) {
            let all = NSRange(location: 0, length: (textView.text as NSString).length)
            textView.layoutManager.invalidateGlyphs(forCharacterRange: all, changeInLength: 0, actualCharacterRange: nil)
            textView.setNeedsDisplay()
        }
        func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                           properties props: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes indexes: UnsafePointer<Int>,
                           font: UIFont, forGlyphRange range: NSRange) -> Int {
            guard let text = layoutManager.textStorage?.string else { return 0 }
            let hidden = CampusFormPrivacy.ranges(text)
            guard !hidden.isEmpty else { return 0 }
            var output = Array(UnsafeBufferPointer(start: glyphs, count: range.length))
            var character: UniChar = 0x2022, bullet: CGGlyph = 0
            CTFontGetGlyphsForCharacters(font as CTFont, &character, &bullet, 1)
            for index in 0..<range.length where hidden.contains(where: { NSLocationInRange(indexes[index], $0) }) { output[index] = bullet }
            output.withUnsafeBufferPointer { buffer in
                layoutManager.setGlyphs(buffer.baseAddress!, properties: props, characterIndexes: indexes, font: font, forGlyphRange: range)
            }
            return range.length
        }
    }
}

final class CampusPrivateTextView: UITextView {
    override var accessibilityValue: String? {
        get { CampusFormPrivacy.masked(text ?? "") }
        set { }
    }
    override var accessibilityAttributedValue: NSAttributedString? {
        get { NSAttributedString(string: CampusFormPrivacy.masked(text ?? "")) }
        set { }
    }
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        let editing = [#selector(paste(_:)), #selector(select(_:)), #selector(selectAll(_:)), #selector(delete(_:))]
        return editing.contains(action) && super.canPerformAction(action, withSender: sender)
    }
}

struct CampusAreaNode: Decodable, Identifiable, Sendable {
    let name: String
    let children: [CampusAreaNode]
    var id: String { name }
}
enum CampusAreaCatalog {
    private struct Resource: Decodable { let regions: [CampusAreaNode] }
    static let regions: [CampusAreaNode] = {
        guard let url = Bundle.main.url(forResource: "CampusAreas", withExtension: "json"),
              let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Resource.self, from: data) else { return [] }
        return value.regions
    }()
}
