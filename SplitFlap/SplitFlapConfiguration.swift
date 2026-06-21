import AppKit
import Foundation
import ScreenSaver

enum SplitFlapDisplayMode: String, CaseIterable {
    case random
    case messages
    case clock
    case date

    var title: String {
        switch self {
        case .random: return "Random"
        case .messages: return "Messages"
        case .clock: return "Clock"
        case .date: return "Date"
        }
    }
}

enum SplitFlapMessageOrder: String, CaseIterable {
    case sequential
    case random

    var title: String {
        switch self {
        case .sequential: return "Sequential"
        case .random: return "Random"
        }
    }
}

struct SplitFlapPalette {
    let identifier: String
    let panelBackground: CGColor
    let character: CGColor
    let divider: CGColor
    let screenBg: CGColor
}

enum SplitFlapTheme: String, CaseIterable {
    case classic
    case terminal
    case monochrome

    var title: String {
        switch self {
        case .classic: return "Classic Amber"
        case .terminal: return "Terminal Green"
        case .monochrome: return "Monochrome"
        }
    }

    var palette: SplitFlapPalette {
        switch self {
        case .classic:
            return SplitFlapPalette(
                identifier: rawValue,
                panelBackground: CGColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1.0),
                character: CGColor(red: 0.98, green: 0.82, blue: 0.25, alpha: 1.0),
                divider: CGColor(red: 0.01, green: 0.01, blue: 0.02, alpha: 1.0),
                screenBg: CGColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1.0)
            )
        case .terminal:
            return SplitFlapPalette(
                identifier: rawValue,
                panelBackground: CGColor(red: 0.02, green: 0.05, blue: 0.04, alpha: 1.0),
                character: CGColor(red: 0.35, green: 1.0, blue: 0.58, alpha: 1.0),
                divider: CGColor(red: 0.0, green: 0.02, blue: 0.015, alpha: 1.0),
                screenBg: CGColor(red: 0.01, green: 0.025, blue: 0.02, alpha: 1.0)
            )
        case .monochrome:
            return SplitFlapPalette(
                identifier: rawValue,
                panelBackground: CGColor(red: 0.08, green: 0.08, blue: 0.085, alpha: 1.0),
                character: CGColor(red: 0.94, green: 0.94, blue: 0.9, alpha: 1.0),
                divider: CGColor(red: 0.015, green: 0.015, blue: 0.018, alpha: 1.0),
                screenBg: CGColor(red: 0.035, green: 0.035, blue: 0.04, alpha: 1.0)
            )
        }
    }
}

struct SplitFlapConfiguration {
    var displayMode: SplitFlapDisplayMode = .messages
    var messageText: String = "SplitFlap\nUnicode OK\nHello World"
    var messageOrder: SplitFlapMessageOrder = .sequential
    var waveIntervalSeconds: TimeInterval = 8
    var idleShuffleEnabled: Bool = true
    var idleDensity: Double = 0.04
    var targetRows: Int = 9
    var theme: SplitFlapTheme = .classic

    var messages: [String] {
        let lines = messageText
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.isEmpty ? ["SplitFlap"] : lines
    }

    func rowCount(isPreview: Bool) -> Int {
        if isPreview {
            return min(max(3, targetRows), 5)
        }
        return min(max(4, targetRows), 24)
    }
}

enum SplitFlapConfigurationStore {
    private static let moduleName = "com.omt.SplitFlap"

    private enum Key {
        static let displayMode = "displayMode"
        static let messageText = "messageText"
        static let messageOrder = "messageOrder"
        static let waveIntervalSeconds = "waveIntervalSeconds"
        static let idleShuffleEnabled = "idleShuffleEnabled"
        static let idleDensity = "idleDensity"
        static let targetRows = "targetRows"
        static let theme = "theme"
    }

    private static var defaults: UserDefaults {
        ScreenSaverDefaults(forModuleWithName: moduleName) ?? .standard
    }

    static func load() -> SplitFlapConfiguration {
        let fallback = SplitFlapConfiguration()
        let defaults = defaults
        defaults.register(defaults: [
            Key.displayMode: fallback.displayMode.rawValue,
            Key.messageText: fallback.messageText,
            Key.messageOrder: fallback.messageOrder.rawValue,
            Key.waveIntervalSeconds: fallback.waveIntervalSeconds,
            Key.idleShuffleEnabled: fallback.idleShuffleEnabled,
            Key.idleDensity: fallback.idleDensity,
            Key.targetRows: fallback.targetRows,
            Key.theme: fallback.theme.rawValue
        ])

        return SplitFlapConfiguration(
            displayMode: SplitFlapDisplayMode(rawValue: defaults.string(forKey: Key.displayMode) ?? "") ?? fallback.displayMode,
            messageText: defaults.string(forKey: Key.messageText) ?? fallback.messageText,
            messageOrder: SplitFlapMessageOrder(rawValue: defaults.string(forKey: Key.messageOrder) ?? "") ?? fallback.messageOrder,
            waveIntervalSeconds: bounded(defaults.double(forKey: Key.waveIntervalSeconds), min: 2, max: 60, fallback: fallback.waveIntervalSeconds),
            idleShuffleEnabled: defaults.object(forKey: Key.idleShuffleEnabled) as? Bool ?? fallback.idleShuffleEnabled,
            idleDensity: bounded(defaults.double(forKey: Key.idleDensity), min: 0, max: 0.2, fallback: fallback.idleDensity),
            targetRows: min(max(defaults.integer(forKey: Key.targetRows), 4), 24),
            theme: SplitFlapTheme(rawValue: defaults.string(forKey: Key.theme) ?? "") ?? fallback.theme
        )
    }

    static func save(_ configuration: SplitFlapConfiguration) {
        let defaults = defaults
        defaults.set(configuration.displayMode.rawValue, forKey: Key.displayMode)
        defaults.set(configuration.messageText, forKey: Key.messageText)
        defaults.set(configuration.messageOrder.rawValue, forKey: Key.messageOrder)
        defaults.set(configuration.waveIntervalSeconds, forKey: Key.waveIntervalSeconds)
        defaults.set(configuration.idleShuffleEnabled, forKey: Key.idleShuffleEnabled)
        defaults.set(configuration.idleDensity, forKey: Key.idleDensity)
        defaults.set(configuration.targetRows, forKey: Key.targetRows)
        defaults.set(configuration.theme.rawValue, forKey: Key.theme)
        defaults.synchronize()
    }

    private static func bounded(_ value: Double, min: Double, max: Double, fallback: Double) -> Double {
        guard value.isFinite, value >= min, value <= max else { return fallback }
        return value
    }
}

final class SplitFlapContentProvider {
    private var configuration: SplitFlapConfiguration
    private var messageIndex = 0

    init(configuration: SplitFlapConfiguration) {
        self.configuration = configuration
    }

    func update(configuration: SplitFlapConfiguration) {
        self.configuration = configuration
        messageIndex = min(messageIndex, max(configuration.messages.count - 1, 0))
    }

    func nextTargets(rows: Int, cols: Int, preview: Bool = false) -> [[SplitFlapCharacter]] {
        switch configuration.displayMode {
        case .random:
            if preview {
                return textTargets(["SplitFlap"], rows: rows, cols: cols)
            }
            return randomTargets(rows: rows, cols: cols)
        case .messages:
            return textTargets([nextMessage()], rows: rows, cols: cols)
        case .clock:
            return textTargets([Self.clockFormatter.string(from: Date())], rows: rows, cols: cols)
        case .date:
            return textTargets([Self.dateFormatter.string(from: Date())], rows: rows, cols: cols)
        }
    }

    private func nextMessage() -> String {
        let messages = configuration.messages
        switch configuration.messageOrder {
        case .sequential:
            let message = messages[messageIndex % messages.count]
            messageIndex = (messageIndex + 1) % messages.count
            return message
        case .random:
            return messages.randomElement() ?? "SplitFlap"
        }
    }

    private func randomTargets(rows: Int, cols: Int) -> [[SplitFlapCharacter]] {
        (0..<rows).map { _ in
            (0..<cols).map { _ in SplitFlapCharacter.random() }
        }
    }

    private func textTargets(_ textLines: [String], rows: Int, cols: Int) -> [[SplitFlapCharacter]] {
        var targets = Array(
            repeating: Array(repeating: SplitFlapCharacter.space, count: cols),
            count: rows
        )
        guard rows > 0, cols > 0 else { return targets }

        let wrapped = textLines.flatMap { wrappedLines($0, maxWidth: cols) }
        let visibleLines = Array(wrapped.prefix(rows))
        let startRow = max(0, (rows - visibleLines.count) / 2)

        for (offset, line) in visibleLines.enumerated() {
            let characters = Array(line.prefix(cols))
            let startCol = max(0, (cols - characters.count) / 2)
            for (index, character) in characters.enumerated() {
                targets[startRow + offset][startCol + index] = character
            }
        }

        return targets
    }

    private func wrappedLines(_ text: String, maxWidth: Int) -> [[SplitFlapCharacter]] {
        let characters = SplitFlapCharacter.characters(in: text)
        guard !characters.isEmpty else { return [[.space]] }
        guard maxWidth > 0 else { return [] }

        var lines: [[SplitFlapCharacter]] = []
        var index = 0
        while index < characters.count {
            let end = min(index + maxWidth, characters.count)
            lines.append(Array(characters[index..<end]))
            index = end
        }
        return lines
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
