import Foundation

enum GameType: String, Codable, CaseIterable, Identifiable {
    case birdsAndAlligators, whackAMole
    var id: String { rawValue }
    var displayName: String { self == .whackAMole ? "Whack the Mole" : "Birds & Alligators" }
    var tagline: String { self == .whackAMole ? "Whack ’em, Get ’em!" : "Jump, Duck, and Watch Out!" }
    var previewAsset: String { self == .whackAMole ? "mole" : "birds-and-alligators" }
    var defaultDuration: TimeInterval { GameConstants.defaultGameDuration }
    var instructions: String {
        self == .whackAMole ? "Reach for your moles with either hand. Reach to the side, up, and down!"
            : "Duck for the bird. Jump for the alligator. Return to standing to complete each move!"
    }
}
