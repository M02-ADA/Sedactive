import SwiftUI

enum AppColors {
    static let accent = Color("PrimaryAccent")
    static let player1 = Color("Player1Blue")
    static let player2 = Color("Player2Red")
    static let surface = Color("Surface")
    static let secondary = Color("SecondarySurface")
    static let text = Color("PrimaryText")
    static let secondaryText = Color("SecondaryText")
    static func game(_ type: GameType) -> Color { Color(type == .whackAMole ? "MoleCardBackground" : "BirdsCardBackground") }
}
enum AppTypography {
    static let title = Font.system(size: 32, weight: .bold, design: .rounded)
    static let score = Font.system(size: 80, weight: .bold, design: .rounded)
}
enum AppSpacing { static let page: CGFloat = 28; static let card: CGFloat = 22 }

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(AppColors.accent.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
    }
}

struct MemberAvatar: View {
    let member: FamilyMember
    var player: Int? = nil
    var size: CGFloat = 70
    var body: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable().scaledToFit().frame(width: size, height: size)
            .foregroundStyle(player == 1 ? AppColors.player1 : player == 2 ? AppColors.player2 : AppColors.accent.opacity(0.5))
            .overlay(alignment: .topTrailing) {
                if let player {
                    Text("P\(player)").font(.caption.bold()).foregroundStyle(.white).padding(5)
                        .background(player == 1 ? AppColors.player1 : AppColors.player2, in: Circle())
                }
            }
            .accessibilityLabel("\(member.name)\(player.map { ", Player \($0)" } ?? "")")
    }
}
