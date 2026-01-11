import SwiftUI
import AVFoundation

/// YouPu (有谱) - Voice Monitor with Self-Improving Speaker Profiles
///
/// Features:
/// - Live streaming transcript with rolling display
/// - Speaker identification with auto-learning
/// - Voice Isolation toggle for noise reduction
/// - Metrics dashboard for performance tracking

@main
struct YouPuApp: App {
    @StateObject private var engine = VoiceEngine()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Main window
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(engine)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        // Menu bar icon
        MenuBarExtra {
            MenuBarView()
                .environmentObject(engine)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: engine.isRecording ? "waveform.circle.fill" : "waveform.circle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(engine.isRecording ? .green : .primary)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

// MARK: - Menu Bar View

struct MenuBarView: View {
    @EnvironmentObject var engine: VoiceEngine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Status section
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(engine.isRecording ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(engine.isRecording ? "Recording" : "Idle")
            }

            if engine.modelStatus.allLoaded {
                Text("Models: Ready")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Models: Loading...")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal)

        Divider()

        // Recording toggle
        Button(action: { engine.toggleRecording() }) {
            HStack {
                Image(systemName: engine.isRecording ? "stop.circle" : "record.circle")
                Text(engine.isRecording ? "Stop Recording" : "Start Recording")
            }
        }
        .keyboardShortcut("r", modifiers: .command)

        // Voice Isolation toggle
        Toggle(isOn: Binding(
            get: { engine.voiceIsolationEnabled },
            set: { engine.voiceIsolationEnabled = $0 }
        )) {
            HStack {
                Image(systemName: "waveform.badge.mic")
                Text("Voice Isolation")
            }
        }

        Divider()

        // Metrics
        if engine.isRecording {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pipeline: \(engine.metrics.totalMs)ms")
                    .font(.caption)
                Text("Segments: \(engine.transcripts.count)")
                    .font(.caption)
                Text("Speakers: \(engine.speakers.count)")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
            .padding(.horizontal)

            Divider()
        }

        // Open main window
        Button(action: {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }) {
            HStack {
                Image(systemName: "macwindow")
                Text("Open Window")
            }
        }
        .keyboardShortcut("o", modifiers: .command)

        Divider()

        // Quit
        Button(action: {
            NSApplication.shared.terminate(nil)
        }) {
            Text("Quit YouPu")
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
