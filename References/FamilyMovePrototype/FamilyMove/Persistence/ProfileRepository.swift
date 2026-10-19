import SwiftData
import Foundation

@MainActor
struct ProfileRepository {
    let context: ModelContext
    func all() throws -> [FamilyMember] {
        try context.fetch(FetchDescriptor<FamilyMember>(sortBy: [SortDescriptor(\.createdAt)]))
    }
    func add(name: String, weight: Double) throws {
        guard try all().count < 8 else { throw ProfileError.limit }
        guard ProfileValidation.valid(name: name, weight: weight) else { throw ProfileError.invalid }
        context.insert(FamilyMember(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                    bodyWeightKg: weight, avatarStyle: try all().count % 6))
        do { try context.save() } catch { context.rollback(); throw error }
    }
    func update(_ member: FamilyMember, weight: Double, height: Double?) throws {
        guard ProfileValidation.valid(name: member.name, weight: weight) else { throw ProfileError.invalid }
        if let height, !height.isFinite || !(30...250).contains(height) { throw ProfileError.invalidHeight }
        member.bodyWeightKg = weight; member.heightCm = height
        do { try context.save() } catch { context.rollback(); throw error }
    }
    func settings() throws -> AppSettings {
        if let settings = try context.fetch(FetchDescriptor<AppSettings>()).first { return settings }
        let settings = AppSettings(); context.insert(settings)
        do { try context.save() } catch { context.rollback(); throw error }
        return settings
    }
}

enum ProfileValidation {
    static func decimal(_ value: String) -> Double? {
        Double(value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }
    static func valid(name: String, weight: Double) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.count <= 40 && weight.isFinite && (1...400).contains(weight)
    }
}

enum ProfileError: LocalizedError {
    case invalid, invalidHeight, limit
    var errorDescription: String? {
        switch self {
        case .limit: return "You can add up to eight family members."
        case .invalid: return "Enter a name up to 40 characters and a weight between 1 and 400 kg."
        case .invalidHeight: return "Enter a height between 30 and 250 cm, or leave it blank."
        }
    }
}
