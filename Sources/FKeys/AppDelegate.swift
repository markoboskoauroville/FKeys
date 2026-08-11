import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let shared = AppDelegate()

    private var statusItem: NSStatusItem!
    private var stateItem: NSMenuItem?

    /// The letter is white in both states.
    private static let letterColor = NSColor.white

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(buttonClicked)
        // Both up-events go to the same handler so a left click can toggle
        // directly while a right click opens the menu.
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item

        // Somebody else may change the setting: System Settings, another tool,
        // or a keyboard being reconnected after sleep. Re-read on all of them.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(externalChange),
            name: Notification.Name("com.apple.keyboard.fnstatedidchange"), object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(externalChange),
            name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(externalChange),
            name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)

        HotKeyCenter.shared.onTrigger = { [weak self] in self?.toggle() }
        HotKeyCenter.shared.start()

        // Paint the letter from the stored preference straight away. This costs
        // nothing and guarantees the item has a visible title before anything
        // slow happens.
        render(functionKeys: FnKeyMode.storedPreference)
        refreshFromHardware()
    }

    // MARK: - Display

    /// F when F1-F12 are plain function keys, C when they are the printed
    /// controls. Both letters are white; the letter itself carries the state.
    /// Asks the hardware what it really thinks, off the main thread, then
    /// repaints. Kept off the main thread because a HID round trip waits on
    /// another process and a stalled main thread means an item with no title,
    /// which is indistinguishable from the app not running.
    private func refreshFromHardware() {
        DispatchQueue.global(qos: .userInitiated).async {
            let live = FnKeyMode.isFunctionKeyMode
            DispatchQueue.main.async { [weak self] in self?.render(functionKeys: live) }
        }
    }

    private func render(functionKeys fn: Bool) {
        guard let button = statusItem.button else { return }
        let letter = fn ? "F" : "C"

        button.attributedTitle = NSAttributedString(string: letter, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold),
            .foregroundColor: AppDelegate.letterColor
        ])
        let target = fn ? "media and brightness controls" : "function keys"
        let now = fn ? "Now: F1 to F12 are function keys."
                     : "Now: F1 to F12 are media and brightness controls."
        let shortcut = HotKeyCenter.shared.isRegistered
            ? "Shortcut: \(HotKeyCenter.display)"
            : "Shortcut: \(HotKeyCenter.display) is taken by another app"
        button.toolTip = """
            FKeys — function key switcher
            Switches F1 to F12 between plain function keys and the printed \
            media and brightness controls.
            \(now)
            Click to switch to \(target).
            \(shortcut)
            """

        stateItem?.title = fn ? "F, function keys" : "C, media controls"
    }

    @objc private func externalChange() {
        refreshFromHardware()
    }

    // MARK: - Actions

    @objc private func buttonClicked() {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if wantsMenu { showMenu() } else { toggle() }
    }

    private func toggle() {
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = FnKeyMode.toggle()
            let live = FnKeyMode.isFunctionKeyMode
            DispatchQueue.main.async { [weak self] in
                self?.render(functionKeys: live)
                if !outcome.succeeded { self?.reportFailure() }
            }
        }
    }

    private func reportFailure() {
        let alert = NSAlert()
        alert.messageText = "The function keys did not change"
        alert.informativeText = """
            FKeys wrote the setting but the keyboard reported back a different \
            value, so nothing really changed.

            Copy the diagnostics and send them on: they say which layer \
            answered and which stayed silent, which is the only way to tell \
            what this Mac wants.
            """
        alert.addButton(withTitle: "Copy diagnostics")
        alert.addButton(withTitle: "Close")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { copyDiagnostics() }
    }

    private func copyDiagnostics() {
        let report = FnKeyMode.diagnostics()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }

    // MARK: - Menu

    private func showMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let state = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        state.isEnabled = false
        stateItem = state
        menu.addItem(state)
        menu.addItem(.separator())

        let toggleItem = menu.addItem(withTitle: "Switch mode",
                                      action: #selector(menuToggle), keyEquivalent: "k")
        toggleItem.keyEquivalentModifierMask = [.control, .option, .command]
        toggleItem.target = self

        let login = menu.addItem(withTitle: "Open at login",
                                 action: #selector(menuLogin), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off

        menu.addItem(.separator())
        let diag = menu.addItem(withTitle: "Copy diagnostics",
                                action: #selector(menuDiagnostics), keyEquivalent: "")
        diag.target = self
        let about = menu.addItem(withTitle: "About FKeys", action: #selector(menuAbout), keyEquivalent: "")
        about.target = self
        let quit = menu.addItem(withTitle: "Quit FKeys", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self

        // Fill the state line from the instant local value, then let the
        // background read correct it. The menu must never wait on HID.
        render(functionKeys: FnKeyMode.storedPreference)
        refreshFromHardware()

        // Attaching the menu and clicking is the supported way to pop a menu
        // from a status item that also handles plain clicks.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    func menuDidClose(_ menu: NSMenu) {
        stateItem = nil
    }

    @objc private func menuToggle() { toggle() }
    @objc private func menuDiagnostics() { copyDiagnostics() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    @objc private func menuLogin() {
        LoginItem.set(enabled: !LoginItem.isEnabled)
    }

    @objc private func menuAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "FKeys",
            .credits: NSAttributedString(
                string: "Switches the F1 to F12 keys between function keys and "
                      + "media controls from the menu bar.\nNo permissions required.",
                attributes: [.font: NSFont.systemFont(ofSize: 11)])
        ])
    }
}

/// Open at login. SMAppService is macOS 13 and later, which matches the
/// package's minimum, so there is no fallback path to maintain.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("FKeys: login item change failed: \(error.localizedDescription)")
        }
    }
}
