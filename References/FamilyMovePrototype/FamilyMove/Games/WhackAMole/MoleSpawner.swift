import Foundation
import CoreGraphics

struct MoleSpawner {
    private var history: [Int: [MoleZone]] = [:]
    mutating func spawn(player: TrackedPlayer, calibration: CalibrationSnapshot,
                        screen: CGSize, now: TimeInterval) -> Mole {
        let roll = Int.random(in: 0..<10)
        var zone: MoleZone = roll < 4 ? .side : roll < 7 ? .overhead : .low
        let recent = history[player.id, default: []]
        if recent.count == 2 && recent.allSatisfy({ $0 == zone }) {
            zone = MoleZone.allCases.filter { $0 != zone }.randomElement()!
        }
        history[player.id] = Array((recent + [zone]).suffix(2))
        // Holes stay anchored to the calibrated arena. Moving a hand/body must
        // not make the target drift away from the player who is reaching for it.
        let site = MoleArenaLayout.site(playerID: player.id, zone: zone, calibration: calibration, screen: screen)
        return Mole(playerID: player.id, zone: zone, position: site.position, radius: site.radius, spawnedAt: now)
    }
}
