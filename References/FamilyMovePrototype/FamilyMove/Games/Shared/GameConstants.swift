import Foundation

enum GameConstants {
    static let defaultGameDuration: TimeInterval = 60
    static let readyHoldDuration: TimeInterval = 1
    static let calibrationDuration: TimeInterval = 1
    static let calibrationMaximumMovementRatio: CGFloat = 0.12
    static let calibrationMaximumScaleVariation: CGFloat = 0.15
    static let bothPlayersLostPauseDelay: TimeInterval = 2
    static let scorePerSuccess = 10
    static let gameplayTopInset: CGFloat = 205
    static let gameplayBottomInset: CGFloat = 85
    static let nextEventDelay: ClosedRange<Double> = 0.25...0.50
    static let minimumJointConfidence: Float = 0.30
    static let smoothingAlpha: CGFloat = 0.30
    static let playerLostGracePeriod: TimeInterval = 1.0
    static let maximumPoseAge: TimeInterval = 0.30
    static let visionFramesPerSecond: Double = 15
    static let maximumPlayers = 2
    static let debugMode = false
}
