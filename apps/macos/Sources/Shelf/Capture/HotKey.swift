import AppKit
import Carbon.HIToolbox

/// A system-wide shortcut via Carbon's RegisterEventHotKey — no
/// Accessibility permission needed.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: @MainActor () -> Void

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { hotKey.action() } }
            return noErr
        }, 1, &spec, selfPointer, &handlerRef)
        guard status == noErr else { return nil }

        let id = EventHotKeyID(signature: OSType(0x5348_4C46) /* 'SHLF' */, id: 1)
        let registered = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registered == noErr else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            handlerRef = nil
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

/// Shortcut choices offered in Settings. Picked to avoid macOS defaults.
enum HotKeyPreset: String, CaseIterable, Identifiable {
    case shiftCommandSpace
    case controlOptionS
    case optionCommandS
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shiftCommandSpace: "⇧⌘Space"
        case .controlOptionS: "⌃⌥S"
        case .optionCommandS: "⌥⌘S"
        case .off: "Off"
        }
    }

    var keyCode: UInt32 {
        switch self {
        case .shiftCommandSpace: UInt32(kVK_Space)
        case .controlOptionS, .optionCommandS, .off: UInt32(kVK_ANSI_S)
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .shiftCommandSpace: UInt32(shiftKey | cmdKey)
        case .controlOptionS: UInt32(controlKey | optionKey)
        case .optionCommandS: UInt32(optionKey | cmdKey)
        case .off: 0
        }
    }

    static var current: HotKeyPreset {
        UserDefaults.standard.string(forKey: SettingsKey.hotKey).flatMap(HotKeyPreset.init(rawValue:)) ?? .shiftCommandSpace
    }
}
