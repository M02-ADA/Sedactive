import SwiftUI
import SwiftData

struct FamilyProgressView: View {
    let members: [FamilyMember]
    let sessions: [GameSession]
    @Environment(\.modelContext) private var context
    @State private var selectedID: UUID?
    @State private var editingMember = false
    @State private var editingGoal = false
    @State private var settings: AppSettings?
    @State private var error: String?
    private var selected: FamilyMember? { members.first { $0.id == selectedID } ?? members.first }
    private var statistics: StatisticsService { StatisticsService(sessions: sessions.map(\.record)) }

    var body: some View {
        ScrollView {
            if let member = selected {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Look at all those moves!").font(AppTypography.title)
                            Text("small moments of play add up").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("Family member", selection: $selectedID) {
                            ForEach(members) { Text($0.name).tag(Optional($0.id)) }
                        }.pickerStyle(.menu).accessibilityIdentifier("progressMember")
                    }
                    HStack(spacing: 30) {
                        Button { editingMember = true } label: {
                            Label("HEIGHT  \(member.heightCm.map { String(format: "%.0f cm", $0) } ?? "Add height")", systemImage: "pencil")
                        }
                        Button { editingMember = true } label: {
                            Label(String(format: "BODYWEIGHT  %.1f kg", member.bodyWeightKg), systemImage: "pencil")
                        }.accessibilityIdentifier("editBodyweight")
                    }.font(.caption.monospaced()).buttonStyle(.plain)
                    Divider()
                    HStack(spacing: 14) {
                        MetricCard(title: "GAMES PLAYED", value: "\(statistics.weeklyGames(member: member.id)) Games", detail: "This Week")
                        MetricCard(title: "ESTIMATED CALORIES", value: String(format: "%.0f kcal", statistics.weeklyCalories(member: member.id)), detail: "This Week · estimate")
                        MetricCard(title: "STREAK", value: "\(statistics.currentStreak(member: member.id)) Days", detail: "Keep moving together!")
                    }
                    Button { editingGoal = true } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            let goal = settings?.weeklyGameGoal ?? 10
                            let count = statistics.weeklyGames(member: member.id)
                            let progress = statistics.weeklyGoalProgress(member: member.id, goal: goal)
                            HStack { Text("Your Weekly Goal").font(.headline); Spacer(); Text("\(Int(progress * 100))%").font(.title2.bold()) }
                            Text(count >= goal ? "You reached your weekly goal!" : "\(goal - count) more games to reach your goal!")
                                .font(.caption).foregroundStyle(.secondary)
                            SwiftUI.ProgressView(value: progress).tint(.blue)
                        }.padding(18).background(AppColors.secondary, in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Great style!").font(.headline)
                        HStack(spacing: 12) {
                            ForEach(statistics.achievements(member: member.id)) { achievement in
                                VStack(spacing: 10) {
                                    Image(systemName: achievement.symbol).font(.title).foregroundStyle(achievement.unlocked ? AppColors.accent : .gray)
                                    Text(achievement.title).font(.caption.bold())
                                    Text(achievement.unlocked ? "Unlocked ✓" : achievement.progressLabel)
                                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                                }.padding(16).frame(maxWidth: .infinity).background(.white, in: RoundedRectangle(cornerRadius: 16))
                                    .accessibilityElement(children: .combine)
                            }
                        }
                    }.padding(18).background(AppColors.secondary, in: RoundedRectangle(cornerRadius: 18))
                    let movements = statistics.movementTotals(member: member.id)
                    HStack(spacing: 22) {
                        Text("Your moves so far").font(.headline)
                        Label("\(movements.reaches) reaches", systemImage: "hand.raised.fill")
                        Label("\(movements.squats) ducks", systemImage: "arrow.down.circle.fill")
                        Label("\(movements.jumps) jumps", systemImage: "figure.jumprope")
                    }.font(.subheadline).padding(.vertical, 8)
                    ActivityHistoryView(sessions: statistics.completed(member: member.id).sorted { $0.startedAt > $1.startedAt })
                    Text("Calorie estimates use provisional game intensity values. They are not measured energy expenditure.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(.red).font(.caption) }
                }
                .sheet(isPresented: $editingMember) { EditMeasurementsView(member: member) }
                .sheet(isPresented: $editingGoal) {
                    if let settings { WeeklyGoalEditor(settings: settings) }
                }
            }
        }
        .onAppear {
            selectedID = selected?.id
            do { settings = try ProfileRepository(context: context).settings() }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2)
            Text(value).font(.system(size: 30, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(AppColors.secondary, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct ActivityHistoryView: View {
    let sessions: [SessionRecord]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity History").font(.headline)
            if sessions.isEmpty { Text("Your first family adventure starts in Games.").foregroundStyle(.secondary) }
            ForEach(Array(sessions.prefix(30)), id: \.id) { session in
                HStack {
                    Image(systemName: session.game == .whackAMole ? "target" : "figure.play")
                    Text(session.game.displayName)
                    Spacer()
                    Text(session.startedAt, format: .dateTime.month().day().hour().minute()).foregroundStyle(.secondary)
                    Text("\(session.score) pts").fontWeight(.semibold).frame(width: 90, alignment: .trailing)
                }.font(.subheadline).padding(14).background(AppColors.secondary, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

struct EditMeasurementsView: View {
    let member: FamilyMember
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var weight: String
    @State private var height: String
    @State private var error: String?
    init(member: FamilyMember) {
        self.member = member
        _weight = State(initialValue: String(member.bodyWeightKg))
        _height = State(initialValue: member.heightCm.map { String($0) } ?? "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("\(member.name)’s measurements").font(.title2.bold())
            TextField("Bodyweight (kg)", text: $weight).keyboardType(.decimalPad).accessibilityIdentifier("editWeight")
            TextField("Height (cm, optional)", text: $height).keyboardType(.decimalPad)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.bordered)
                Button("Save") {
                    guard let parsed = ProfileValidation.decimal(weight) else { error = "Enter a valid weight in kg."; return }
                    let heightText = height.trimmingCharacters(in: .whitespacesAndNewlines)
                    let heightValue = heightText.isEmpty ? nil : ProfileValidation.decimal(heightText)
                    guard heightText.isEmpty || heightValue != nil else { error = "Enter a valid height in cm."; return }
                    do { try ProfileRepository(context: context).update(member, weight: parsed, height: heightValue); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("saveMeasurements")
            }
        }.textFieldStyle(.roundedBorder).padding(30).presentationDetents([.height(340)])
    }
}

struct WeeklyGoalEditor: View {
    let settings: AppSettings
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var goal: Int
    @State private var error: String?
    init(settings: AppSettings) { self.settings = settings; _goal = State(initialValue: settings.weeklyGameGoal) }
    var body: some View {
        VStack(spacing: 22) {
            Text("Your Weekly Goal").font(.title2.bold())
            Stepper("\(goal) games per week", value: $goal, in: 1...30)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.bordered)
                Button("Save") {
                    settings.weeklyGameGoal = goal
                    do { try context.save(); dismiss() } catch { context.rollback(); self.error = error.localizedDescription }
                }.buttonStyle(PrimaryButtonStyle())
            }
        }.padding(30).presentationDetents([.height(260)])
    }
}
