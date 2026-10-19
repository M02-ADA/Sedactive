import Foundation
import SwiftData

@Model
final class FamilyMember {
    @Attribute(.unique) var id: UUID
    var name: String
    var bodyWeightKg: Double
    var heightCm: Double?
    var avatarStyle: Int
    var createdAt: Date
    @Relationship(deleteRule: .nullify, inverse: \ParticipantSessionStat.member)
    var statistics: [ParticipantSessionStat] = []

    init(id: UUID = UUID(), name: String, bodyWeightKg: Double, heightCm: Double? = nil, avatarStyle: Int = 0) {
        self.id = id; self.name = name; self.bodyWeightKg = bodyWeightKg
        self.heightCm = heightCm; self.avatarStyle = avatarStyle; createdAt = Date()
    }
}
