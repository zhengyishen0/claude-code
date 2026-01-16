import Cocoa

enum RecordingState {
    case idle
    case recording
    case processing
}

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var modelMenuItems: [NSMenuItem] = []
    private var historySubmenu: NSMenu!

    private let onModelChange: (ASRModel) -> Void
    private let historyManager: HistoryManager

    init(onModelChange: @escaping (ASRModel) -> Void,
         historyManager: HistoryManager) {
        self.onModelChange = onModelChange
        self.historyManager = historyManager

        super.init()

        setupStatusItem()
        setupMenu()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Voice Translator")
            button.image?.isTemplate = true
        }
    }

    private func setupMenu() {
        menu = NSMenu()

        // Hotkey info (read-only)
        let hotkeyInfo = NSMenuItem(title: "Double-tap ⌘ to record", action: nil, keyEquivalent: "")
        hotkeyInfo.isEnabled = false
        menu.addItem(hotkeyInfo)

        menu.addItem(NSMenuItem.separator())

        // Model selection header
        let modelHeader = NSMenuItem(title: "ASR Model", action: nil, keyEquivalent: "")
        modelHeader.isEnabled = false
        menu.addItem(modelHeader)

        for model in ASRModel.allCases {
            let item = NSMenuItem(
                title: model.displayName,
                action: #selector(modelSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = model
            item.indentationLevel = 1
            modelMenuItems.append(item)
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // History submenu
        let historyItem = NSMenuItem(title: "History (⌃⇧V)", action: nil, keyEquivalent: "")
        historySubmenu = NSMenu()
        historyItem.submenu = historySubmenu
        menu.addItem(historyItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        menu.delegate = self
    }

    func setState(_ state: RecordingState) {
        guard let button = statusItem.button else { return }

        switch state {
        case .idle:
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)
            button.contentTintColor = nil

        case .recording:
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)
            button.contentTintColor = .systemRed

        case .processing:
            button.image = NSImage(systemSymbolName: "ellipsis.circle.fill", accessibilityDescription: nil)
            button.contentTintColor = .systemBlue
        }
    }

    func updateSelectedModel(_ model: ASRModel) {
        for item in modelMenuItems {
            item.state = (item.representedObject as? ASRModel) == model ? .on : .off
        }
    }

    @objc private func modelSelected(_ sender: NSMenuItem) {
        guard let model = sender.representedObject as? ASRModel else { return }
        AppSettings.shared.selectedModel = model
        updateSelectedModel(model)
        onModelChange(model)
    }

    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }

    @objc private func historyItemClicked(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let source = CGEventSource(stateID: .hidSystemState)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            keyDown?.flags = .maskCommand
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    }
}

extension StatusBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // Update history submenu
        historySubmenu.removeAllItems()

        let history = historyManager.getAll()
        if history.isEmpty {
            let emptyItem = NSMenuItem(title: "(empty)", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            historySubmenu.addItem(emptyItem)
        } else {
            for (index, text) in history.enumerated() {
                let preview = String(text.prefix(40)) + (text.count > 40 ? "..." : "")
                let item = NSMenuItem(
                    title: "\(index + 1). \(preview)",
                    action: #selector(historyItemClicked(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = text
                historySubmenu.addItem(item)
            }
        }
    }
}
