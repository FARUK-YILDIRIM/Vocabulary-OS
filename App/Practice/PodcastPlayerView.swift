import SwiftUI
import VocabularyCore
import VocabularyData
import VocabularySpeech
import VocabularyUI

/// Plays a podcast episode (SPEC C9, ADR-008): the transcript follows the voice, saved words open
/// their detail, and the controls skip lines and change the speed. Leaving the player stops it at
/// the current line. On iPhone and iPad it keeps playing while the screen is locked.
struct PodcastPlayerView: View {
    let episode: PodcastEpisode
    @Environment(AppModel.self) private var app
    @State private var model: PodcastPlaybackModel?

    var body: some View {
        Group {
            if let model {
                PodcastPlayerContent(model: model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(Text(verbatim: episode.title))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            if model == nil {
                model = PodcastPlaybackModel(episode: episode, podcasts: app.podcasts)
            }
        }
        .onDisappear { model?.stop() }
    }
}

private struct PodcastPlayerContent: View {
    @Environment(AppModel.self) private var app
    let model: PodcastPlaybackModel
    @State private var openedWord: VocabularyEntry?
    @State private var resumesAfterWord = false
    @AppStorage("podcast.speed") private var speed = 1.0
    @ScaledMetric(relativeTo: .largeTitle) private var playButtonSize = 48.0

    private static let speeds = [0.8, 0.9, 1.0, 1.1, 1.2]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if let notice = model.voices.notice {
                        VoiceNotice(notice: notice, language: model.language)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.script.segments.indices, id: \.self) { index in
                            line(index).id(index)
                        }
                    }
                    if !model.words.isEmpty {
                        wordList
                    }
                }
                .padding()
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.top)
            .onChange(of: model.position) { _, line in
                guard model.isPlaying else { return }
                withAnimation { proxy.scrollTo(line, anchor: .center) }
            }
        }
        .safeAreaInset(edge: .bottom) { controls }
        .environment(\.openURL, OpenURLAction { url in
            guard let id = PodcastPlaybackModel.wordID(in: url) else { return .systemAction }
            openWord(id: id)
            return .handled
        })
        .sheet(item: $openedWord, onDismiss: wordClosed) { entry in
            NavigationStack {
                WordDetailView(entry: entry)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { openedWord = nil }
                                .accessibilityIdentifier("podcast-word-done")
                        }
                    }
            }
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 560)
            #endif
        }
        .onAppear { model.speed = speed }
        .onChange(of: speed) { model.speed = speed }
    }

    // MARK: Transcript

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: model.script.title)
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("podcast-title")
            Text(verbatim: [
                model.language.localizedName(),
                model.episode.level.label,
                String(localized: model.episode.style.title),
                String(localized: model.episode.length.title),
            ].joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func line(_ index: Int) -> some View {
        let segment = model.script.segments[index]
        let isCurrent = index == model.position
        let isSpeaking = isCurrent && model.player.state != .idle
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                play(from: index)
            } label: {
                Image(systemName: isSpeaking ? "speaker.wave.2.fill" : "play.circle")
                    .foregroundStyle(isSpeaking ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Play from Here"))
            VStack(alignment: .leading, spacing: 2) {
                if segment.speaker != .narrator {
                    Text(segment.speaker == .host ? "Host" : "Guest")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(model.transcript(for: index))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isCurrent ? AnyShapeStyle(isSpeaking ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.1)) : AnyShapeStyle(.clear),
            in: .rect(cornerRadius: 10)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("podcast-line-\(index)")
    }

    private var wordList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Words in This Episode")
                .font(.headline)
            ForEach(model.words) { word in
                Button {
                    openWord(id: word.id)
                } label: {
                    HStack {
                        Text(verbatim: word.term).fontWeight(.semibold)
                        Text(verbatim: word.translation).foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("podcast-word-\(word.term)")
            }
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 32) {
                Button(action: model.previous) {
                    Label("Previous Line", systemImage: "backward.fill")
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .accessibilityIdentifier("podcast-previous")
                Button(action: togglePlayback) {
                    Label(model.isPlaying ? "Pause" : "Play", systemImage: model.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: playButtonSize))
                }
                .keyboardShortcut(.space, modifiers: [])
                .accessibilityIdentifier("podcast-play")
                Button(action: model.next) {
                    Label("Next Line", systemImage: "forward.fill")
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .accessibilityIdentifier("podcast-next")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(.tint)
            .font(.title2)
            HStack {
                Text("Line \(model.position + 1) of \(model.script.segments.count)")
                    .monospacedDigit()
                    .accessibilityIdentifier("podcast-position")
                Spacer()
                Picker("Speed", selection: $speed) {
                    ForEach(Self.speeds, id: \.self) { speed in
                        Text(verbatim: speed.formatted(.number.precision(.fractionLength(1))) + "×").tag(speed)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .accessibilityIdentifier("podcast-speed")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    // MARK: Actions

    private func togglePlayback() {
        // A word still being said would talk over the episode.
        app.speech.stop()
        model.togglePlayback()
    }

    private func play(from index: Int) {
        app.speech.stop()
        model.play(from: index)
    }

    /// Pauses for the word's detail and continues when it closes.
    private func openWord(id: UUID) {
        guard let entry = try? app.repository.entry(id: id) else { return }
        resumesAfterWord = model.isPlaying
        model.pause()
        openedWord = entry
    }

    private func wordClosed() {
        // The word may have been edited or deleted in its detail.
        model.reloadWords()
        if resumesAfterWord {
            app.speech.stop()
            model.resume()
        }
        resumesAfterWord = false
    }
}

/// Why the episode doesn't sound as it should, and where to download voices (SPEC C9).
private struct VoiceNotice: View {
    let notice: PodcastVoices.Notice
    let language: LanguageCode

    var body: some View {
        Label {
            switch notice {
            case .noVoice:
                Text("No \(language.localizedName()) voice is installed, so your device's default voice reads this episode. You can download voices in \(Self.voiceSettings).")
            case .oneVoice:
                Text("Only one \(language.localizedName()) voice is installed, so both hosts share it. Download another in \(Self.voiceSettings) to hear two voices.")
            }
        } icon: {
            Image(systemName: "speaker.badge.exclamationmark")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1), in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("podcast-voice-notice")
    }

    private static var voiceSettings: String {
        #if os(macOS)
        String(localized: "System Settings > Accessibility > Spoken Content")
        #else
        String(localized: "Settings > Accessibility > Spoken Content > Voices")
        #endif
    }
}
