import SwiftUI
import SwiftData

@MainActor
final class AddMemberViewModel: ObservableObject {
    @Published var name = ""
    @Published var weight = ""
    @Published var error: String?
    var parsedWeight: Double? { ProfileValidation.decimal(weight) }
    var validationMessage: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).count > 40 { return "Keep the name to 40 characters or fewer." }
        if !weight.isEmpty && !(parsedWeight.map { $0.isFinite && (1...400).contains($0) } ?? false) {
            return "Enter a weight between 1 and 400 kg."
        }
        return nil
    }
    var isValid: Bool { parsedWeight.map { ProfileValidation.valid(name: name, weight: $0) } ?? false }
    func save(context: ModelContext) -> Bool {
        guard let weight = parsedWeight, isValid else { return false }
        do { try ProfileRepository(context: context).add(name: name, weight: weight); return true }
        catch { self.error = error.localizedDescription; return false }
    }
}

struct AddMemberView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = AddMemberViewModel()
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Input your data").font(.title2.bold())
            TextField("Name", text: $model.name).textContentType(.givenName)
                .accessibilityIdentifier("memberName")
            TextField("Bodyweight (kg)", text: $model.weight).keyboardType(.decimalPad)
                .accessibilityIdentifier("memberWeight")
            Text("Use kilograms. You can add height later in Your Progress.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = model.error ?? model.validationMessage { Text(error).font(.caption).foregroundStyle(.red) }
            HStack(spacing: 14) {
                Button("Cancel") { dismiss() }.buttonStyle(.bordered).controlSize(.large)
                Button("Next") { if model.save(context: context) { dismiss() } }
                    .buttonStyle(PrimaryButtonStyle()).disabled(!model.isValid).opacity(model.isValid ? 1 : 0.45)
                    .accessibilityIdentifier("saveMember")
            }
        }
        .textFieldStyle(.roundedBorder).padding(32)
        .presentationDetents([.height(340)]).presentationDragIndicator(.visible)
    }
}
