import SwiftUI

struct OnboardingView: View {
    let members: [FamilyMember]
    let onContinue: () -> Void
    @State private var addingMember = false
    @State private var checkingCamera = false
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Text("Add your family member").font(AppTypography.title)
            Text("A little movement. A lot of together.").foregroundStyle(.secondary)
            #if targetEnvironment(macCatalyst)
            Button { checkingCamera = true } label: {
                Label("Check MacBook Camera", systemImage: "camera")
            }.buttonStyle(.bordered).accessibilityIdentifier("checkMacCamera")
            #endif
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 36) {
                    ForEach(members) { member in
                        VStack(spacing: 10) { MemberAvatar(member: member); Text(member.name).font(.headline) }
                    }
                    ForEach(0..<max(1, 2 - members.count), id: \.self) { _ in
                        if members.count < 8 {
                            Button { addingMember = true } label: {
                                VStack(spacing: 10) {
                                    Circle().stroke(style: StrokeStyle(lineWidth: 2, dash: [8, 7]))
                                        .frame(width: 78, height: 78)
                                        .overlay(Image(systemName: "plus").font(.system(size: 32, weight: .light)))
                                    Text("Add Player").font(.subheadline)
                                }
                            }.buttonStyle(.plain).accessibilityIdentifier("addPlayer")
                        }
                    }
                }.padding(20)
            }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: 780)
            if members.count >= 2 {
                Button("Continue", action: onContinue).buttonStyle(PrimaryButtonStyle()).frame(width: 260)
                    .accessibilityIdentifier("continueHome")
            }
            Spacer()
            Text(members.count < 2 ? "You need at least 2 players" : "\(members.count) family members ready to move")
                .font(.subheadline).foregroundStyle(.secondary)
            Spacer().frame(height: 16)
        }
        .frame(maxWidth: .infinity).background(AppColors.surface)
        .sheet(isPresented: $addingMember) { AddMemberView() }
        .sheet(isPresented: $checkingCamera) {
            VStack(spacing: 0) {
                HStack {
                    Text("Camera Setup").font(.headline)
                    Spacer()
                    Button("Done") { checkingCamera = false }.buttonStyle(.borderedProminent)
                }.padding()
                TrackingRootView()
            }.frame(minWidth: 900, minHeight: 650)
        }
    }
}
