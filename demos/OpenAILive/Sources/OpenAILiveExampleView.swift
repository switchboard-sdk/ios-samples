//
//  OpenAILiveExampleView.swift
//  OpenAILive
//

import SwiftUI

struct OpenAILiveExampleView: View {
    @State private var model = ViewModel()

    var body: some View {
        VStack(spacing: 16) {
            Text("Press Start and talk to the assistant. Ask it to play, pause or stop the music.")
                .font(.callout)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(model.lines) { line in
                            lineView(line)
                                .id(line.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: model.updates) {
                    if let last = model.lines.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Button(model.isRunning ? "Stop" : "Start") {
                model.toggle()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .onDisappear {
            model.stop()
        }
    }

    @ViewBuilder
    private func lineView(_ line: TranscriptLine) -> some View {
        if let speaker = line.speaker {
            Text("\(Text("\(speaker):").bold()) \(line.text)")
        } else {
            Text(line.text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// A transcript line: what "You" or "Assistant" said, or a status line when `speaker` is nil.
struct TranscriptLine: Identifiable {
    let id: Int
    let speaker: String?
    var text: String
}

extension OpenAILiveExampleView {
    @Observable
    class ViewModel: OpenAILiveExampleDelegate {
        private let example = OpenAILiveExample()

        var isRunning = false
        var lines: [TranscriptLine] = []
        // Changes on every transcript update, to scroll to the end.
        var updates = 0

        init() {
            example.delegate = self
        }

        func toggle() {
            if example.isRunning {
                example.stop()
            } else {
                example.start()
            }
            isRunning = example.isRunning
        }

        func stop() {
            example.stop()
            isRunning = false
        }

        func transcript(speaker: String, delta: String) {
            if let last = lines.indices.last, lines[last].speaker == speaker {
                lines[last].text += delta
            } else {
                lines.append(TranscriptLine(id: lines.count, speaker: speaker, text: delta))
            }
            updates += 1
        }

        func status(_ text: String) {
            lines.append(TranscriptLine(id: lines.count, speaker: nil, text: text))
            updates += 1
        }
    }
}
