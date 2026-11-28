import AppKit
import Carbon.HIToolbox
import Observation

/// キーの組み合わせ。
struct KeyCombo: Codable, Hashable {
    var keyCode: UInt32
    /// NSEvent.ModifierFlags の rawValue（command / shift / option / control のみ）
    var modifiers: UInt

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if modifierFlags.contains(.command) { m |= UInt32(cmdKey) }
        if modifierFlags.contains(.shift) { m |= UInt32(shiftKey) }
        if modifierFlags.contains(.option) { m |= UInt32(optionKey) }
        if modifierFlags.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    var displayString: String {
        var s = ""
        if modifierFlags.contains(.control) { s += "⌃" }
        if modifierFlags.contains(.option) { s += "⌥" }
        if modifierFlags.contains(.shift) { s += "⇧" }
        if modifierFlags.contains(.command) { s += "⌘" }
        // PC 用キーボードの Print Screen キーは Mac では F13 として届く
        if keyCode == UInt32(kVK_F13) { return s + "\(String(localized: "Print Screen")) (F13)" }
        return s + KeyCombo.keyName(for: keyCode)
    }

    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]

    static func keyName(for keyCode: UInt32) -> String {
        let special: [Int: String] = [
            kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫",
            kVK_Escape: "⎋", kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
            kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
            kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
        ]
        if let name = special[Int(keyCode)] { return name }
        return characterForKeyCode(keyCode)?.uppercased() ?? "#\(keyCode)"
    }

    /// 現在のキーボードレイアウトで keyCode が表す文字。
    private static func characterForKeyCode(_ keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                        UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                        &deadKeyState, chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length)
        }
    }
}

enum HotkeyAction: String, CaseIterable, Identifiable {
    case captureFullScreen
    case captureArea
    case recordArea

    var id: String { rawValue }

    var title: String {
        switch self {
        case .captureFullScreen: String(localized: "Capture Full Screen")
        case .captureArea: String(localized: "Capture Area")
        case .recordArea: String(localized: "Record Area / Stop Recording")
        }
    }

    var defaultCombos: [KeyCombo] {
        let cmdShift = NSEvent.ModifierFlags([.command, .shift]).rawValue
        switch self {
        case .captureFullScreen: return [KeyCombo(keyCode: UInt32(kVK_ANSI_3), modifiers: cmdShift)]
        case .captureArea: return [KeyCombo(keyCode: UInt32(kVK_ANSI_4), modifiers: cmdShift),
                                   KeyCombo(keyCode: UInt32(kVK_F13), modifiers: 0)]
        case .recordArea: return [KeyCombo(keyCode: UInt32(kVK_ANSI_5), modifiers: cmdShift)]
        }
    }
}

/// グローバルなショートカットキーの登録と保存。アクションごとに複数のショートカットを持てる。
@Observable
final class HotkeyManager {
    static let shared = HotkeyManager()

    private(set) var combos: [HotkeyAction: [KeyCombo]] = [:]
    /// 登録に失敗したショートカット（ほかのアプリやシステムが使っている）。
    private(set) var failedCombos: [HotkeyAction: Set<KeyCombo>] = [:]

    @ObservationIgnored var handler: ((HotkeyAction) -> Void)?
    @ObservationIgnored var escapeHandler: (() -> Void)?
    @ObservationIgnored private var escapeRef: EventHotKeyRef?
    @ObservationIgnored private var refs: [HotkeyAction: [EventHotKeyRef]] = [:]
    @ObservationIgnored private var eventHandler: EventHandlerRef?
    @ObservationIgnored private let signature: OSType = 0x5052_5343 // 'PRSC'
    /// Esc 用の ID。アクションの ID は 1000 + アクション番号 * 100 + 何番目か。
    private static let escapeID: UInt32 = 100

    private init() {
        let defaults = UserDefaults.standard
        for action in HotkeyAction.allCases {
            if let data = defaults.data(forKey: Self.storageKey(action)),
               let list = try? JSONDecoder().decode([KeyCombo].self, from: data) {
                combos[action] = list
            } else if let data = defaults.data(forKey: Self.legacyStorageKey(action)) {
                // 1 つだけ保存していた頃の形式。空の Data は「なし」
                if let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
                    combos[action] = [combo]
                } else {
                    combos[action] = []
                }
            } else {
                combos[action] = action.defaultCombos
            }
        }
    }

    private static func storageKey(_ action: HotkeyAction) -> String { "hotkeys.\(action.rawValue)" }
    private static func legacyStorageKey(_ action: HotkeyAction) -> String { "hotkey.\(action.rawValue)" }

    func start() {
        installHandlerIfNeeded()
        for action in HotkeyAction.allCases { register(action) }
    }

    /// ショートカットを追加する。ほかのアクションに同じものがあればそちらから外す。
    func addCombo(_ combo: KeyCombo, for action: HotkeyAction) {
        for other in HotkeyAction.allCases where other != action {
            if let list = combos[other], list.contains(combo) {
                setCombos(list.filter { $0 != combo }, for: other)
            }
        }
        let list = combos[action] ?? []
        guard !list.contains(combo) else { return }
        setCombos(list + [combo], for: action)
    }

    func removeCombo(_ combo: KeyCombo, for action: HotkeyAction) {
        setCombos((combos[action] ?? []).filter { $0 != combo }, for: action)
    }

    func resetToDefault(_ action: HotkeyAction) {
        for combo in action.defaultCombos { addCombo(combo, for: action) }
        setCombos(action.defaultCombos, for: action)
    }

    private func setCombos(_ list: [KeyCombo], for action: HotkeyAction) {
        unregister(action)
        combos[action] = list
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: Self.storageKey(action))
        }
        UserDefaults.standard.removeObject(forKey: Self.legacyStorageKey(action))
        register(action)
    }

    /// 録画ボタンの記録中などに、一時的にすべて外す。
    func suspend() {
        for action in HotkeyAction.allCases { unregister(action) }
    }

    func resume() {
        for action in HotkeyAction.allCases { register(action) }
    }

    /// 録画中だけ Esc を受け取る。アクセシビリティの許可は要らない。
    func setEscapeEnabled(_ enabled: Bool) {
        if let escapeRef {
            UnregisterEventHotKey(escapeRef)
            self.escapeRef = nil
        }
        guard enabled else { return }
        let id = EventHotKeyID(signature: signature, id: Self.escapeID)
        var ref: EventHotKeyRef?
        if RegisterEventHotKey(UInt32(kVK_Escape), 0, id, GetApplicationEventTarget(), 0, &ref) == noErr {
            escapeRef = ref
        }
    }

    private func register(_ action: HotkeyAction) {
        unregister(action)
        failedCombos[action] = nil
        let actionIndex = UInt32(HotkeyAction.allCases.firstIndex(of: action)!)
        var failed = Set<KeyCombo>()
        for (slot, combo) in (combos[action] ?? []).enumerated() {
            let id = EventHotKeyID(signature: signature, id: 1000 + actionIndex * 100 + UInt32(slot))
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, id,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs[action, default: []].append(ref)
            } else {
                failed.insert(combo)
            }
        }
        if !failed.isEmpty { failedCombos[action] = failed }
    }

    private func unregister(_ action: HotkeyAction) {
        for ref in refs.removeValue(forKey: action) ?? [] {
            UnregisterEventHotKey(ref)
        }
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            if hotKeyID.id == HotkeyManager.escapeID {
                MainActor.assumeIsolated { HotkeyManager.shared.escapeHandler?() }
                return noErr
            }
            guard hotKeyID.id >= 1000 else { return noErr }
            let index = Int((hotKeyID.id - 1000) / 100)
            guard HotkeyAction.allCases.indices.contains(index) else { return noErr }
            let action = HotkeyAction.allCases[index]
            MainActor.assumeIsolated {
                HotkeyManager.shared.handler?(action)
            }
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }
}
