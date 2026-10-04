import MediaPlayer
import VocabularyUI

/// Shows the open episode on the lock screen and in Control Center, whose buttons play, pause and
/// skip lines (ADR-008).
@MainActor
final class PodcastNowPlaying {
    private let model: PodcastPlaybackModel
    private var targets: [(command: MPRemoteCommand, target: Any)] = []

    init(model: PodcastPlaybackModel) {
        self.model = model
    }

    /// Takes the remote commands while the player is open.
    func start() {
        guard targets.isEmpty else { return }
        let commands = MPRemoteCommandCenter.shared()
        handle(commands.playCommand) { $0.player.state == .paused ? $0.resume() : $0.togglePlayback() }
        handle(commands.pauseCommand) { $0.pause() }
        handle(commands.togglePlayPauseCommand) { $0.togglePlayback() }
        handle(commands.nextTrackCommand) { $0.next() }
        handle(commands.previousTrackCommand) { $0.previous() }
        update()
    }

    /// Mirrors the episode: its title, the line it is on, and whether it plays.
    func update() {
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = [
            MPMediaItemPropertyTitle: model.script.title,
            MPMediaItemPropertyArtist: "Vocabulary-OS",
            MPNowPlayingInfoPropertyPlaybackRate: model.isPlaying ? model.speed : 0.0,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: model.position,
            MPNowPlayingInfoPropertyPlaybackQueueCount: model.script.segments.count,
        ]
        #if os(macOS)
        center.playbackState = model.isPlaying ? .playing : (model.player.state == .paused ? .paused : .stopped)
        #endif
    }

    /// Gives the commands back when the player closes.
    func stop() {
        for (command, target) in targets {
            command.removeTarget(target)
        }
        targets = []
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func handle(_ command: MPRemoteCommand, _ action: @escaping @MainActor (PodcastPlaybackModel) -> Void) {
        command.isEnabled = true
        let target = command.addTarget { [weak self] _ in
            // Remote commands arrive on the main thread.
            MainActor.assumeIsolated {
                guard let self else { return .commandFailed }
                action(self.model)
                self.update()
                return .success
            }
        }
        targets.append((command, target))
    }
}
