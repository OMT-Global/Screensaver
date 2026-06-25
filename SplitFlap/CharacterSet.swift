import Foundation

// A displayable split-flap cell. Known Solari drum characters retain the
// mechanical forward-only sequence; arbitrary Unicode grapheme clusters render
// directly as a one-step flip target.
struct SplitFlapCharacter: Hashable {
    let displayString: String

    init(_ displayString: String) {
        self.displayString = displayString.isEmpty ? " " : displayString
    }

    static let space = SplitFlapCharacter(" ")

    static let drumCharacters: [SplitFlapCharacter] = [
        " ",
        "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
        "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
        ".", ",", "-", "/", ":"
    ].map(SplitFlapCharacter.init)

    static let count: Int = drumCharacters.count

    private static let lookupByDisplayString = Dictionary(
        uniqueKeysWithValues: drumCharacters.map { ($0.displayString, $0) }
    )

    private static let drumIndexByDisplayString = Dictionary(
        uniqueKeysWithValues: drumCharacters.enumerated().map { ($0.element.displayString, $0.offset) }
    )

    private var drumIndex: Int? {
        Self.drumIndexByDisplayString[displayString]
    }

    // Advance one step forward from this character.
    var next: SplitFlapCharacter {
        guard let drumIndex else { return self }
        let nextIndex = (drumIndex + 1) % Self.drumCharacters.count
        return Self.drumCharacters[nextIndex]
    }

    // Number of forward steps needed to reach `target` from `self`.
    func stepsTo(_ target: SplitFlapCharacter) -> Int {
        guard let sourceIndex = drumIndex, let targetIndex = target.drumIndex else {
            return self == target ? 0 : 1
        }

        if targetIndex >= sourceIndex {
            return targetIndex - sourceIndex
        }
        return Self.drumCharacters.count - sourceIndex + targetIndex
    }

    func sequence(to target: SplitFlapCharacter) -> [SplitFlapCharacter] {
        guard let sourceIndex = drumIndex, target.drumIndex != nil else {
            return self == target ? [self] : [self, target]
        }

        let steps = stepsTo(target)
        var sequence: [SplitFlapCharacter] = [self]
        sequence.reserveCapacity(steps + 1)
        for offset in 1...steps {
            sequence.append(Self.drumCharacters[(sourceIndex + offset) % Self.drumCharacters.count])
        }
        return sequence
    }

    // Return a random character from the physical drum alphabet.
    static func random() -> SplitFlapCharacter {
        drumCharacters[Int.random(in: 0..<drumCharacters.count)]
    }

    static func random(in alphabet: SplitFlapRandomAlphabet) -> SplitFlapCharacter {
        let characters = alphabet.characters
        return characters[Int.random(in: 0..<characters.count)]
    }

    // Parse one extended grapheme cluster. Known ASCII drum characters normalize
    // to uppercase; all other Unicode clusters are preserved for rendering.
    static func from(_ string: String) -> SplitFlapCharacter {
        guard let first = string.first else { return .space }
        let grapheme = String(first)
        let normalized = grapheme.uppercased()
        return lookupByDisplayString[normalized] ?? SplitFlapCharacter(grapheme)
    }

    static func characters(in text: String) -> [SplitFlapCharacter] {
        text.map { from(String($0)) }
    }
}
