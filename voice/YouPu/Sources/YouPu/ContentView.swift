import SwiftUI

/// Main content view with 3-panel layout:
/// - Left: Live transcript (rolling stream)
/// - Center: Tagging queue (segments needing labels)
/// - Right: Speaker list (enrolled speakers)
/// - Bottom: Metrics bar
struct ContentView: View {
    @EnvironmentObject var engine: VoiceEngine

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HeaderView()

            Divider()

            // Main 3-panel layout
            HStack(spacing: 0) {
                // Left: Live Transcript
                TranscriptView()
                    .frame(minWidth: 300)

                Divider()

                // Center: Tagging Queue
                TaggingQueueView()
                    .frame(minWidth: 250)

                Divider()

                // Right: Speaker List
                SpeakerListView()
                    .frame(minWidth: 200)
            }

            Divider()

            // Bottom: Metrics Bar
            MetricsBarView()
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Header View

struct HeaderView: View {
    @EnvironmentObject var engine: VoiceEngine

    var body: some View {
        HStack {
            // App title
            Text("有谱 YouPu")
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            // Voice Isolation toggle
            Toggle(isOn: $engine.voiceIsolationEnabled) {
                HStack(spacing: 4) {
                    Image(systemName: engine.voiceIsolationEnabled ? "waveform.circle.fill" : "waveform.circle")
                    Text("Voice Isolation")
                }
            }
            .toggleStyle(.switch)
            .tint(.green)

            Spacer()
                .frame(width: 20)

            // Record button
            Button(action: { engine.toggleRecording() }) {
                HStack {
                    Image(systemName: engine.isRecording ? "stop.circle.fill" : "record.circle")
                        .foregroundColor(engine.isRecording ? .red : .primary)
                    Text(engine.isRecording ? "Stop" : "Start")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(engine.isRecording ? .red : .blue)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

// MARK: - Transcript View (Left Panel)

struct TranscriptView: View {
    @EnvironmentObject var engine: VoiceEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Panel header
            HStack {
                Image(systemName: "text.bubble")
                Text("Live Transcript")
                    .fontWeight(.medium)
                Spacer()
                Text("\(engine.transcripts.count) segments")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Transcript list (auto-scrolling)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(engine.transcripts) { segment in
                            TranscriptRow(segment: segment)
                                .id(segment.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: engine.transcripts.count) { _, _ in
                    // Auto-scroll to bottom
                    if let last = engine.transcripts.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}

struct TranscriptRow: View {
    let segment: TranscriptSegment

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(segment.timestamp)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)

            // Speaker badge
            if let speaker = segment.speaker {
                Text(speaker)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(speakerColor(speaker).opacity(0.2))
                    .foregroundColor(speakerColor(speaker))
                    .cornerRadius(4)
            } else {
                Text("?")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.gray)
                    .cornerRadius(4)
            }

            // Text
            Text(segment.text)
                .font(.body)
        }
    }

    func speakerColor(_ name: String) -> Color {
        // Consistent color based on name hash
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan]
        let index = abs(name.hashValue) % colors.count
        return colors[index]
    }
}

// MARK: - Tagging Queue View (Center Panel)

struct TaggingQueueView: View {
    @EnvironmentObject var engine: VoiceEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Panel header
            HStack {
                Image(systemName: "tag")
                Text("Needs Tagging")
                    .fontWeight(.medium)
                Spacer()
                Text("\(engine.untaggedSegments.count) pending")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Untagged segments
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(engine.untaggedSegments) { segment in
                        TaggingCard(segment: segment)
                    }
                }
                .padding()
            }
        }
    }
}

struct TaggingCard: View {
    @EnvironmentObject var engine: VoiceEngine
    let segment: TranscriptSegment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Audio preview & text
            HStack {
                Text(segment.timestamp)
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Play button (future: play audio clip)
                Button(action: {}) {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.plain)
            }

            Text(segment.text)
                .font(.callout)
                .lineLimit(2)

            // Speaker buttons
            HStack {
                ForEach(engine.speakers, id: \.name) { speaker in
                    Button(speaker.name) {
                        engine.tagSegment(segment, as: speaker.name)
                    }
                    .buttonStyle(.bordered)
                    .tint(speakerColor(speaker.name))
                }

                // Unknown / new speaker button
                Button("+ New") {
                    engine.promptNewSpeaker(for: segment)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    func speakerColor(_ name: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan]
        let index = abs(name.hashValue) % colors.count
        return colors[index]
    }
}

// MARK: - Speaker List View (Right Panel)

struct SpeakerListView: View {
    @EnvironmentObject var engine: VoiceEngine
    @State private var newSpeakerName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Panel header
            HStack {
                Image(systemName: "person.2")
                Text("Speakers")
                    .fontWeight(.medium)
                Spacer()
                Text("\(engine.speakers.count)")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Speaker list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(engine.speakers, id: \.name) { speaker in
                        SpeakerRow(speaker: speaker)
                    }
                }
                .padding()
            }

            Divider()

            // Add new speaker
            HStack {
                TextField("New speaker name", text: $newSpeakerName)
                    .textFieldStyle(.roundedBorder)

                Button(action: {
                    if !newSpeakerName.isEmpty {
                        engine.addSpeaker(name: newSpeakerName)
                        newSpeakerName = ""
                    }
                }) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .disabled(newSpeakerName.isEmpty)
            }
            .padding()
        }
    }
}

struct SpeakerRow: View {
    let speaker: SpeakerProfile

    var body: some View {
        HStack {
            // Color indicator
            Circle()
                .fill(speakerColor(speaker.name))
                .frame(width: 8, height: 8)

            // Name
            Text(speaker.name)
                .fontWeight(.medium)

            Spacer()

            // Stats
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(speaker.sampleCount) clips")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Confidence indicator
                HStack(spacing: 2) {
                    ForEach(0..<5) { i in
                        Circle()
                            .fill(i < speaker.confidenceLevel ? Color.green : Color.gray.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    func speakerColor(_ name: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan]
        let index = abs(name.hashValue) % colors.count
        return colors[index]
    }
}

// MARK: - Metrics Bar View (Bottom)

struct MetricsBarView: View {
    @EnvironmentObject var engine: VoiceEngine

    var body: some View {
        HStack(spacing: 20) {
            // Pipeline metrics
            MetricPill(label: "VAD", value: "\(engine.metrics.vadMs)ms", icon: "waveform")
            MetricPill(label: "ASR", value: "\(engine.metrics.asrMs)ms", icon: "text.bubble")
            MetricPill(label: "Speaker ID", value: "\(engine.metrics.speakerIdMs)ms", icon: "person.wave.2")
            MetricPill(label: "Total", value: "\(engine.metrics.totalMs)ms", icon: "clock")

            Divider()
                .frame(height: 20)

            // Status indicators
            HStack(spacing: 4) {
                Circle()
                    .fill(engine.voiceIsolationEnabled ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text("Voice Isolation")
                    .font(.caption)
            }

            Spacer()

            // Accuracy & auto-learn stats
            Text("Accuracy: \(engine.metrics.accuracy, specifier: "%.1f")%")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Auto-learned: \(engine.metrics.autoLearnedCount)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct MetricPill: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(4)
    }
}

#Preview {
    ContentView()
        .environmentObject(VoiceEngine())
        .frame(width: 900, height: 600)
}
