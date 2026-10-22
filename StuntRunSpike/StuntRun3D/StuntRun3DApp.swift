import RealityKit
import SwiftUI

/// Isolated RealityKit experiment. Revision 3 (target StuntRunSpike) is untouched and runs on its own.
@main
struct StuntRun3DApp: App {
    var body: some SwiftUI.Scene {
        WindowGroup {
            Stunt3DView()
        }
    }
}

struct Stunt3DView: View {
    @State private var world = World3D()
    /// `-arviewStats YES` hosts the same world in a non-AR ARView purely for RealityKit's statistics overlay.
    private let statsHost = UserDefaults.standard.bool(forKey: "arviewStats")

    var body: some View {
        ZStack {
            if statsHost {
                ARViewHost(world: world)
            } else {
                RealityView { content in
                    content.camera = .virtual
                    content.add(world.root)
                    world.subscription = content.subscribe(to: SceneEvents.Update.self) { [world] event in
                        world.update(dt: event.deltaTime)
                    }
                }
            }
            HUD3D(hud: world.hud)
                .allowsHitTesting(false)
        }
        .background(Color(Palette.deepNavy))
        .ignoresSafeArea()
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}

struct ARViewHost: UIViewRepresentable {
    let world: World3D

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(Palette.deepNavy)
        view.debugOptions = [.showStatistics]
        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(world.root)
        view.scene.addAnchor(anchor)
        world.arSubscription = view.scene.subscribe(to: SceneEvents.Update.self) { [world] event in
            world.update(dt: event.deltaTime)
        }
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

/// HUD equivalent to Revision 3's (cards, Team Power, shared lock, banner, flash). Drawn by SwiftUI on top.
struct HUD3D: View {
    let hud: HUD3DModel
    @State private var bannerScale: CGFloat = 1
    @State private var flash = 0.0

    var body: some View {
        ZStack {
            VStack(spacing: 10) {
                HStack(alignment: .top) {
                    card("PARENT", count: hud.squats[.left] ?? 0, color: Color(Palette.coral))
                    Spacer()
                    VStack(spacing: 6) {
                        Text("TEAM POWER").font(arcade(16)).foregroundStyle(.white)
                        Capsule().fill(Color(Palette.deepNavy).opacity(0.8)).frame(width: 420, height: 26)
                            .overlay(alignment: .leading) {
                                Capsule().fill(Color(Palette.yellow))
                                    .frame(width: max(0, 412 * CGFloat(hud.teamPower) / 10), height: 18).padding(.leading, 4)
                            }
                        if hud.lockVisible { lock }
                    }
                    Spacer()
                    card("CHILD", count: hud.squats[.right] ?? 0, color: Color(Palette.teal))
                }
                Spacer()
                Text(hud.metrics).font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.75))
                    .padding(6).background(.black.opacity(0.4), in: .rect(cornerRadius: 8))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24)

            VStack(spacing: 4) {
                Text(hud.banner).font(arcade(72)).foregroundStyle(bannerColor)
                    .shadow(color: Color(Palette.deepNavy), radius: 0, x: 3, y: 4)
                if !hud.subBanner.isEmpty {
                    Text(hud.subBanner).font(arcade(24)).foregroundStyle(.white).shadow(color: .black, radius: 2)
                }
            }
            .scaleEffect(bannerScale)
            .offset(y: -150)
            .id(hud.bannerID)
            .transition(.opacity)

            Color.white.opacity(flash).allowsHitTesting(false)
        }
        .onChange(of: hud.bannerID) {
            bannerScale = 0.4
            withAnimation(.spring(duration: 0.35, bounce: 0.5)) { bannerScale = 1 }
        }
        .onChange(of: hud.flashID) {
            flash = 0.3
            withAnimation(.easeOut(duration: 0.22)) { flash = 0 }
        }
    }

    private var bannerColor: Color {
        switch hud.bannerColor {
        case .yellow: Color(Palette.yellow)
        case .mint: Color(Palette.mint)
        case .coral: Color(Palette.coral)
        case .white: .white
        }
    }

    private var lock: some View {
        HStack(spacing: 30) {
            slot(.left, color: Color(Palette.coral))
            Text("\(hud.lockFilled.count)/2").font(arcade(26)).foregroundStyle(hud.lockFilled.count == 2 ? Color(Palette.mint) : .white)
            slot(.right, color: Color(Palette.teal))
        }
        .padding(.horizontal, 18).padding(.vertical, 8)
        .background(Color(Palette.deepNavy).opacity(0.8), in: .capsule)
    }

    private func slot(_ zone: Zone, color: Color) -> some View {
        ZStack {
            Circle().stroke(color, lineWidth: 5).frame(width: 40, height: 40)
            if hud.lockFilled.contains(zone) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 34)).foregroundStyle(Color(Palette.mint))
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.25, bounce: 0.5), value: hud.lockFilled.contains(zone))
    }

    private func card(_ title: String, count: Int, color: Color) -> some View {
        HStack {
            Text(title).font(arcade(22)).foregroundStyle(.white)
            Spacer()
            Text("\(count)").font(arcade(50)).foregroundStyle(.white).contentTransition(.numericText())
        }
        .padding(.horizontal, 18)
        .frame(width: 260, height: 100)
        .background(color, in: .rect(cornerRadius: 30))
        .overlay(RoundedRectangle(cornerRadius: 30).stroke(.white, lineWidth: 6))
        .animation(.spring(duration: 0.3, bounce: 0.4), value: count)
    }

    private func arcade(_ size: CGFloat) -> Font {
        .custom("AvenirNext-HeavyItalic", size: size)
    }
}
