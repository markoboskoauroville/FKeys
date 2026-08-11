import AppKit
import Carbon.HIToolbox

/// A single global hotkey, Control Option Command K.
///
/// Registered through Carbon's `RegisterEventHotKey` rather than an event tap.
/// This matters: an event tap would monitor every keystroke on the system and
/// would demand Accessibility permission. A registered hotkey asks the window
/// server to deliver one specific combination and nothing else, so FKeys still
/// needs no permissions at all.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    /// Shown in the tooltip and the menu.
    static let display = "⌃⌥⌘K"

    var onTrigger: (() -> Void)?
    private(set) var isRegistered = false

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let signature: OSType = 0x464B4559   // 'FKEY'

    private init() {}

    func start() {
        installHandlerIfNeeded()
        register()
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async { HotKeyCenter.shared.onTrigger?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }

    private func register() {
        unregister()
        let id = EventHotKeyID(signature: signature, id: 1)
        var ref: EventHotKeyRef?
        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_K), modifiers, id,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            hotKeyRef = ref
            isRegistered = true
        } else {
            // Another app already owns this combination. FKeys still works by
            // clicking, so this is reported in the tooltip rather than as an alert.
            isRegistered = false
            NSLog("FKeys: could not register \(HotKeyCenter.display), status \(status)")
        }
    }

    private func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
        isRegistered = false
    }
}
