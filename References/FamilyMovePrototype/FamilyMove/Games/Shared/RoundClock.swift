import Foundation

struct RoundClock {
    let duration: TimeInterval
    private var accumulated: TimeInterval = 0
    private var runningSince: TimeInterval?
    init(duration: TimeInterval = GameConstants.defaultGameDuration) { self.duration = duration }
    mutating func resume(at now: TimeInterval) { if runningSince == nil { runningSince = now } }
    mutating func pause(at now: TimeInterval) { accumulated = elapsed(at: now); runningSince = nil }
    func elapsed(at now: TimeInterval) -> TimeInterval {
        min(duration, max(0, accumulated + (runningSince.map { max(0, now - $0) } ?? 0)))
    }
    func remaining(at now: TimeInterval) -> TimeInterval { max(0, duration - elapsed(at: now)) }
}
