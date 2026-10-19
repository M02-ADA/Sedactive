import AVFoundation
import UIKit

@MainActor
final class SessionSoundPlayer {
    enum Cue: String { case countdown = "CountdownSound", success = "SuccessSound", complete = "CompleteSound" }
    var enabled = true
    private var players: [Cue: AVAudioPlayer] = [:]

    func play(_ cue: Cue) {
        guard enabled, !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        do {
            if players[cue] == nil, let asset = NSDataAsset(name: cue.rawValue) {
                let player = try AVAudioPlayer(data: asset.data)
                player.volume = 0.45
                players[cue] = player
            }
            // Ambient respects the silent switch and other audio on the device.
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            players[cue]?.currentTime = 0
            players[cue]?.play()
        } catch { NSLog("[AUDIO] %@", error.localizedDescription) }
    }

    func stop() { for player in players.values { player.stop() } }
}
