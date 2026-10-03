/// How taps on words become a selection in the capture view (SPEC C5).
///
/// One tap selects a word; tapping a second word selects the phrase between them; tapping the selected
/// word again clears it. After a phrase, any tap starts a new selection.
public enum TokenSelection {
    /// Longest phrase, in words, a second tap may create; idioms rarely exceed this.
    public static let maximumPhraseLength = 8

    public static func afterTap(on index: Int, current: ClosedRange<Int>?) -> ClosedRange<Int>? {
        guard let current else { return index...index }
        guard current.count == 1 else { return index...index }
        let anchor = current.lowerBound
        if index == anchor { return nil }
        let phrase = min(anchor, index)...max(anchor, index)
        return phrase.count <= maximumPhraseLength ? phrase : index...index
    }
}
