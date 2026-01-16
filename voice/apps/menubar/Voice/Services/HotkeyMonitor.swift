import Cocoa

class HotkeyMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    private let onRecordStart: () -> Void
    private let onRecordStop: () -> Void
    private let onHistoryPaste: () -> Void

    private var isRecordingAudio = false

    // Double-tap detection for CMD key
    private var lastCmdPressTime: Date?
    private var cmdTapCount = 0
    private var isCmdHeld = false
    private let doubleTapThreshold: TimeInterval = 0.3  // 300ms between taps

    // History hotkey: Ctrl+Option+V
    private let historyKeyCode: UInt16 = 0x09  // V
    private let historyModifiers: NSEvent.ModifierFlags = [.control, .option]

    init(onRecordStart: @escaping () -> Void,
         onRecordStop: @escaping () -> Void,
         onHistoryPaste: @escaping () -> Void) {
        self.onRecordStart = onRecordStart
        self.onRecordStop = onRecordStop
        self.onHistoryPaste = onHistoryPaste

        startMonitoring()
    }

    private func startMonitoring() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.flagsChanged, .keyDown, .keyUp]
        ) { [weak self] event in
            self?.handleEvent(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.flagsChanged, .keyDown, .keyUp]
        ) { [weak self] event in
            self?.handleEvent(event)
            return event
        }
    }

    private func handleEvent(_ event: NSEvent) {
        // Check for history hotkey (Ctrl+Shift+V)
        if event.type == .keyDown {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == historyKeyCode && flags == historyModifiers {
                onHistoryPaste()
                return
            }
        }

        // Handle double-tap CMD for recording
        handleDoubleTapCmd(event)
    }

    private func handleDoubleTapCmd(_ event: NSEvent) {
        guard event.type == .flagsChanged else { return }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmdPressed = flags.contains(.command)

        // CMD key pressed
        if cmdPressed && !isCmdHeld {
            isCmdHeld = true
            let now = Date()

            if let lastPress = lastCmdPressTime,
               now.timeIntervalSince(lastPress) < doubleTapThreshold {
                // Double-tap detected! Start recording
                cmdTapCount = 2
                if !isRecordingAudio {
                    isRecordingAudio = true
                    onRecordStart()
                }
            } else {
                // First tap
                cmdTapCount = 1
                lastCmdPressTime = now
            }
        }
        // CMD key released
        else if !cmdPressed && isCmdHeld {
            isCmdHeld = false

            // If we were recording (double-tap was active), stop recording
            if isRecordingAudio {
                isRecordingAudio = false
                onRecordStop()
                cmdTapCount = 0
                lastCmdPressTime = nil
            }
        }
    }

    deinit {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
