import Foundation

// Characters in the order they appear on a mechanical Solari drum.
// Panels always advance *forward* through this sequence (never backward),
// just like a physical split-flap display.
enum SplitFlapCharacter: Int, CaseIterable {
    case space = 0
    case A, B, C, D, E, F, G, H, I, J, K, L, M
    case N, O, P, Q, R, S, T, U, V, W, X, Y, Z
    case zero, one, two, three, four, five, six, seven, eight, nine
    case period, comma, hyphen, slash, colon

    var displayString: String {
        switch self {
        case .space:   return " "
        case .A: return "A"; case .B: return "B"; case .C: return "C"
        case .D: return "D"; case .E: return "E"; case .F: return "F"
        case .G: return "G"; case .H: return "H"; case .I: return "I"
        case .J: return "J"; case .K: return "K"; case .L: return "L"
        case .M: return "M"; case .N: return "N"; case .O: return "O"
        case .P: return "P"; case .Q: return "Q"; case .R: return "R"
        case .S: return "S"; case .T: return "T"; case .U: return "U"
        case .V: return "V"; case .W: return "W"; case .X: return "X"
        case .Y: return "Y"; case .Z: return "Z"
        case .zero:  return "0"; case .one:   return "1"; case .two:   return "2"
        case .three: return "3"; case .four:  return "4"; case .five:  return "5"
        case .six:   return "6"; case .seven: return "7"; case .eight: return "8"
        case .nine:  return "9"
        case .period: return "."; case .comma:  return ","
        case .hyphen: return "-"; case .slash:  return "/"
        case .colon:  return ":"
        }
    }

    static let count: Int = SplitFlapCharacter.allCases.count
    private static let lookupByDisplayString: [String: SplitFlapCharacter] = {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0.displayString, $0) })
    }()

    // Advance one step forward from this character.
    var next: SplitFlapCharacter {
        let nextRaw = (rawValue + 1) % SplitFlapCharacter.count
        return SplitFlapCharacter(rawValue: nextRaw)!
    }

    // Number of forward steps needed to reach `target` from `self`.
    func stepsTo(_ target: SplitFlapCharacter) -> Int {
        if target.rawValue >= rawValue {
            return target.rawValue - rawValue
        }
        return SplitFlapCharacter.count - rawValue + target.rawValue
    }

    // Return a random character (excluding space for more visual interest).
    static func random() -> SplitFlapCharacter {
        let all = SplitFlapCharacter.allCases
        return all[Int.random(in: 0..<all.count)]
    }

    // Parse a single character string into a SplitFlapCharacter, or return .space.
    static func from(_ string: String) -> SplitFlapCharacter {
        let ch = string.uppercased()
        return lookupByDisplayString[ch] ?? .space
    }
}
