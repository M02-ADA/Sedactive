import Foundation
import SwiftData

@Model
final class AppSettings {
    @Attribute(.unique) var key: String = "settings"
    var weeklyGameGoal: Int = 10
    var debugModeEnabled: Bool = false
    var soundEnabled: Bool = true
    init() {}
}
