import Cocoa
import VoicePipeline

private var appDelegateRef: AppDelegate?

@main
struct VoiceApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        appDelegateRef = delegate
        app.delegate = delegate
        app.run()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController!
    private var hotkeyMonitor: HotkeyMonitor!
    private var audioRecorder: AudioRecorder!
    private var transcriber: Transcriber!
    private var historyManager: HistoryManager!
    private var recordingOverlay: RecordingOverlay!
    private var asrEngine: ASREngine!

    private var totalStartTime: Date?
    private var isTranscribing = false
    private var escMonitor: Any?

    // Paths to KMP models and assets
    private let modelDir = "/Users/zhengyishen/Codes/claude-code/voice/models/coreml"
    private let assetsDir = "/Users/zhengyishen/Codes/claude-code/voice/models/assets"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Initialize ASR engine (loads CoreML models once at startup)
        print("Loading ASR models...")
        let loadStart = Date()
        asrEngine = ASREngine(modelDir: modelDir, assetsDir: assetsDir)
        if asrEngine.initialize() {
            let loadTime = Int(Date().timeIntervalSince(loadStart) * 1000)
            print("ASR engine initialized in \(loadTime)ms")
        } else {
            print("WARNING: ASR engine failed to initialize")
        }

        historyManager = HistoryManager()
        transcriber = Transcriber(engine: asrEngine)
        audioRecorder = AudioRecorder()
        recordingOverlay = RecordingOverlay()

        hotkeyMonitor = HotkeyMonitor(
            onRecordStart: { [weak self] in
                self?.startRecording()
            },
            onRecordStop: { [weak self] in
                self?.stopRecordingAndTranscribe()
            },
            onHistoryPaste: { [weak self] in
                self?.pasteFromHistory()
            }
        )

        statusBarController = StatusBarController(
            onModelChange: { [weak self] model in
                self?.transcriber.setModel(model)
            },
            historyManager: historyManager
        )

        let settings = AppSettings.shared
        transcriber.setModel(settings.selectedModel)
        statusBarController.updateSelectedModel(settings.selectedModel)

        print("Voice started")
        print("Double-tap ⌘ to record, release to transcribe")
        print("ESC to cancel | ⌃⇧V for history")
        print("─────────────────────────────────────")
    }

    private func startRecording() {
        print("🎤 Recording...")
        statusBarController.setState(.recording)
        recordingOverlay.show()
        audioRecorder.startRecording()
    }

    private func stopRecordingAndTranscribe() {
        totalStartTime = Date()  // Start total timing when CMD released
        recordingOverlay.hide()

        audioRecorder.stopRecording { [weak self] audioURL in
            guard let self = self, let url = audioURL else {
                print("✗ No audio")
                self?.statusBarController.setState(.idle)
                return
            }

            self.startTranscription(audioURL: url)
        }
    }

    private func startTranscription(audioURL: URL) {
        isTranscribing = true
        statusBarController.setState(.processing)

        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 0x35 {
                self?.cancelTranscription()
            }
        }

        transcriber.transcribe(audioURL: audioURL) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, self.isTranscribing else { return }
                self.finishTranscription(result: result)
            }
        }
    }

    private func cancelTranscription() {
        guard isTranscribing else { return }
        isTranscribing = false
        removeEscMonitor()
        statusBarController.setState(.idle)
        print("✗ Cancelled")
    }

    private func finishTranscription(result: TranscriptionResult) {
        isTranscribing = false
        removeEscMonitor()

        let totalTime = totalStartTime.map { Date().timeIntervalSince($0) } ?? 0
        let modelTime = result.modelTime

        if let text = result.text, !text.isEmpty {
            let modelMs = Int(modelTime * 1000)
            let totalMs = Int(totalTime * 1000)
            print("✓ \(text)")
            print("  ⏱ model: \(modelMs)ms | total: \(totalMs)ms")
            historyManager.add(text)
            pasteText(text)
        } else {
            print("✗ No result (model: \(Int(modelTime * 1000))ms)")
        }

        statusBarController.setState(.idle)
    }

    private func removeEscMonitor() {
        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor)
            escMonitor = nil
        }
    }

    private func pasteFromHistory() {
        if let text = historyManager.getNext() {
            pasteText(text)
        }
    }

    private func pasteText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let source = CGEventSource(stateID: .hidSystemState)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            keyDown?.flags = .maskCommand
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeEscMonitor()
    }
}
