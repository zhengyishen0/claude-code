import Foundation
import Cocoa

enum ASRModel: String, CaseIterable {
    case senseVoice = "sensevoice"
    case whisperTurbo = "whisper"
    case parakeet = "parakeet"

    var displayName: String {
        switch self {
        case .senseVoice: return "SenseVoice (zh/en/ja/ko)"
        case .whisperTurbo: return "Whisper Turbo (99 langs)"
        case .parakeet: return "Parakeet (en only)"
        }
    }

    var shortName: String {
        switch self {
        case .senseVoice: return "SenseVoice"
        case .whisperTurbo: return "Whisper"
        case .parakeet: return "Parakeet"
        }
    }
}

struct Hotkey: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt

    // Common presets
    static let option = Hotkey(keyCode: 0xFFFF, modifiers: NSEvent.ModifierFlags.option.rawValue)
    static let optionShift = Hotkey(keyCode: 0xFFFF, modifiers: NSEvent.ModifierFlags([.option, .shift]).rawValue)
    static let optionCommand = Hotkey(keyCode: 0xFFFF, modifiers: NSEvent.ModifierFlags([.option, .command]).rawValue)
    static let optionShiftCommand = Hotkey(keyCode: 0xFFFF, modifiers: NSEvent.ModifierFlags([.option, .shift, .command]).rawValue)
    static let controlOption = Hotkey(keyCode: 0xFFFF, modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue)

    static let defaultRecord = option

    static let presets: [(name: String, hotkey: Hotkey)] = [
        ("⌥ Option", option),
        ("⌥⇧ Option+Shift", optionShift),
        ("⌥⌘ Option+Command", optionCommand),
        ("⌃⌥ Control+Option", controlOption),
        ("⌥⇧⌘ Option+Shift+Command", optionShiftCommand),
    ]

    /// Display string with Mac symbols
    var symbolString: String {
        var parts: [String] = []
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)

        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }

        if keyCode != 0xFFFF {
            if let char = keyCodeToString(keyCode) {
                parts.append(char)
            }
        }

        return parts.isEmpty ? "⌥" : parts.joined()
    }

    /// Check if this is a preset
    var isPreset: Bool {
        Hotkey.presets.contains { $0.hotkey == self }
    }

    private func keyCodeToString(_ code: UInt16) -> String? {
        let keyMap: [UInt16: String] = [
            0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
            0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
            0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
            0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
            0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9",
            0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]",
            0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
            0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";",
            0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M",
            0x2F: ".", 0x32: "`", 0x24: "↩", 0x30: "⇥",
            0x31: "Space", 0x33: "⌫", 0x35: "⎋",
        ]
        return keyMap[code]
    }
}

class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let selectedModel = "selectedModel"
        static let recordHotkey = "recordHotkey"
    }

    var selectedModel: ASRModel {
        get {
            guard let raw = defaults.string(forKey: Keys.selectedModel),
                  let model = ASRModel(rawValue: raw) else {
                return .senseVoice
            }
            return model
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.selectedModel)
        }
    }

    var recordHotkey: Hotkey {
        get {
            guard let data = defaults.data(forKey: Keys.recordHotkey),
                  let hotkey = try? JSONDecoder().decode(Hotkey.self, from: data) else {
                return .defaultRecord
            }
            return hotkey
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.recordHotkey)
            }
        }
    }

    private init() {}
}
