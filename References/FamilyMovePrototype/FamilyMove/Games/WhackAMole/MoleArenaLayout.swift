import Foundation
import CoreGraphics

struct MoleSite: Identifiable {
    let playerID: Int
    let zone: MoleZone
    let position: CGPoint
    let radius: CGFloat
    var id: String { "\(playerID)-\(zone.rawValue)" }
}

enum MoleArenaLayout {
    static func sites(calibrations: [Int: CalibrationSnapshot], screen: CGSize) -> [MoleSite] {
        (1...2).flatMap { id in
            guard let baseline = calibrations[id] else { return [MoleSite]() }
            return MoleZone.allCases.map { site(playerID: id, zone: $0, calibration: baseline, screen: screen) }
        }
    }

    static func site(playerID: Int, zone: MoleZone, calibration: CalibrationSnapshot, screen: CGSize) -> MoleSite {
        let torso = calibration.torsoHeight
        let width = calibration.shoulderWidth
        let radius = min(50, max(28, torso * 0.28))
        let shoulder = calibration.shoulderCenter
        var point: CGPoint
        switch zone {
        case .side:
            point = CGPoint(x: shoulder.x + (playerID == 1 ? -1 : 1) * width * 1.15,
                            y: shoulder.y + torso * 0.35)
        case .overhead:
            point = CGPoint(x: shoulder.x, y: shoulder.y - torso * 0.55)
        case .low:
            point = CGPoint(x: calibration.hipCenter.x, y: calibration.hipCenter.y + torso * 0.4)
        }
        let margin = radius + 16
        let left = playerID == 1 ? margin : screen.width / 2 + margin
        let right = playerID == 1 ? screen.width / 2 - margin : screen.width - margin
        point.x = min(max(left, point.x), max(left, right))
        let top = MoleConstants.arenaTopInset + radius
        let bottom = screen.height - MoleConstants.arenaBottomInset - radius
        point.y = min(max(top, point.y), max(top, bottom))
        return MoleSite(playerID: playerID, zone: zone, position: point, radius: radius)
    }
}
