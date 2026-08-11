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

        refresh()
    }

    // MARK: - Display

    /// F when F1-F12 are plain function keys, C when they are the printed
    /// controls. Both letters are white; the letter itself carries the state.
    private func refresh() {
        guard let button = statusItem.button else { return }
        let fn = FnKeyMode.isFunctionKeyMode
        let letter = fn ? "F" : "C"

        button.attributedTitle = NSAttributedString(string: letter, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold),
            .foregroundColor: AppDelegate.letterColor
        ])
        button.toolTip = fn
            ? "F1 to F12 are function keys. Click for media controls."
            : "F1 to F12 are media and brightness controls. Click for function keys."

        stateItem?.title = fn ? "F, function keys" : "C, media controls"
    }

    @objc private func externalChange() {
        DispatchQueue.main.async { [weak self] in self?.refresh() }
    }

    // MARK: - Actions

    @objc private func buttonClicked() {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if wantsMenu { showMenu() } else { toggle() }
    }

    private func toggle() {
        if !FnKeyMode.toggle() {
            let alert = NSAlert()
            alert.messageText = "Could not change the function key mode"
            alert.informativeText = """
                FKeys could not reach the keyboard driver. This usually means \
                macOS refused the connection to IOHIDSystem. Changing the \
                setting once by hand in System Settings, Keyboard, and then \
                trying again normally clears it.
                """
            alert.runModal()
        }
        refresh()
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
                                      action: #selector(menuToggle), keyEquivalent: "")
        toggleItem.target = self

        let login = menu.addItem(withTitle: "Open at login",
                                 action: #selector(menuLogin), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off

        menu.addItem(.separator())
        let about = menu.addItem(withTitle: "About FKeys", action: #selector(menuAbout), keyEquivalent: "")
        about.target = self
        let quit = menu.addItem(withTitle: "Quit FKeys", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self

        refresh()

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
