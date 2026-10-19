import Foundation

struct ActivityIntensityConfiguration {
    // Provisional gameplay tuning values, not validated activity measurements.
    var whackAMoleMET: Double = 3
    var birdsAlligatorsMET: Double = 4
}
struct SessionEnergyEstimator {
    var configuration = ActivityIntensityConfiguration()
    func calories(game: GameType, weightKg: Double, durationSeconds: Double) -> Double {
        guard weightKg.isFinite, weightKg > 0, durationSeconds.isFinite, durationSeconds > 0 else { return 0 }
        let met = game == .whackAMole ? configuration.whackAMoleMET : configuration.birdsAlligatorsMET
        return max(0, met) * 3.5 * weightKg / 200 * durationSeconds / 60
    }
}
