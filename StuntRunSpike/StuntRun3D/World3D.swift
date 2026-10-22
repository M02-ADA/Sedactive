import Combine
import QuartzCore
import RealityKit
import UIKit

/// Overhead gate built from real geometry. Same dimensions as Revision 3's `Gate` (posts ±2.35, beam at 1.62,
/// lane panels hanging from 1.4 over each player).
@MainActor
final class Gate3D {
    let root = Entity()
    let beam: ModelEntity
    var posts: [ModelEntity] = []
    var panels: [Zone: ModelEntity] = [:]
    var checks: [Zone: ModelEntity] = [:]
    var glows: [Zone: ModelEntity] = [:]
    let beacon: ModelEntity
    var depth: Float = 68
    var warned = false
    var resolved = false

    init(playerX: Float, colors: [Zone: UIColor], beamTexture: TextureResource?, panelTexture: TextureResource?,
         checkTexture: TextureResource?, beaconTexture: TextureResource?) {
        let postMesh = MeshResource.generateCylinder(height: 1.95, radius: 0.12)
        let postMat = Mat3D.lit(Palette.violet, roughness: 0.35, metallic: 0.4)
        for x: Float in [-2.35, 2.35] {
            let post = ModelEntity(mesh: postMesh, materials: [postMat])
            post.position = [x, 0.975, 0]
            let cap = ModelEntity(mesh: .generateSphere(radius: 0.16), materials: [Mat3D.neon(Palette.coral)])
            cap.position = [0, 1.0, 0]
            post.addChild(cap)
            root.addChild(post)
            posts.append(post)
        }
        var beamMat = Mat3D.lit(.white, roughness: 0.4, texture: beamTexture)
        beamMat.emissiveColor = .init(color: Palette.yellow.withAlphaComponent(0.2))
        beamMat.emissiveIntensity = 0.3
        beam = ModelEntity(mesh: .generateBox(width: 5.1, height: 0.45, depth: 0.35, cornerRadius: 0.08), materials: [beamMat])
        beam.position = [0, 1.62, 0]
        root.addChild(beam)
        beacon = ModelEntity(mesh: .generatePlane(width: 2.2, height: 7), materials: [Mat3D.sprite(beaconTexture, tint: Palette.yellow, opacity: 0.55)])
        beacon.position = [0, 1.85 + 3.5, 0]
        beacon.components.set(DynamicLightShadowComponent(castsShadow: false))
        root.addChild(beacon)
        let shade = ModelEntity(mesh: .generatePlane(width: 3.2, depth: 0.9), materials: [Mat3D.neon(.black, alpha: 0.4)])
        shade.position = [0, 0.012, 0]
        root.addChild(shade)
        for zone in Zone.allCases {
            let x: Float = zone == .left ? -playerX : playerX
            let panel = ModelEntity(mesh: .generatePlane(width: 0.78, height: 0.52),
                                    materials: [Mat3D.sprite(panelTexture, tint: colors[zone] ?? .white, opacity: 0.95)])
            panel.position = [x, 1.14, 0.2]
            panel.scale = [1, 0.01, 1]
            panel.components.set(DynamicLightShadowComponent(castsShadow: false))
            root.addChild(panel)
            panels[zone] = panel
            let check = ModelEntity(mesh: .generatePlane(width: 0.24, height: 0.24), materials: [Mat3D.sprite(checkTexture)])
            check.position = [x, 1.14, 0.22]
            check.isEnabled = false
            root.addChild(check)
            checks[zone] = check
            let glow = ModelEntity(mesh: .generateBox(width: 2.45, height: 0.5, depth: 0.4, cornerRadius: 0.1),
                                   materials: [Mat3D.neon(colors[zone] ?? .white, alpha: 0.75)])
            glow.position = [zone == .left ? -1.27 : 1.27, 1.62, 0]
            glow.isEnabled = false
            root.addChild(glow)
            glows[zone] = glow
        }
    }
}

@MainActor
final class World3D {
    let root = Entity()
    let cameraEntity = PerspectiveCamera()
    var subscription: EventSubscription?
    var arSubscription: (any Cancellable)?
    let hud = HUD3DModel()
    let coop = Coop3D()

    // Same framing as Revision 3's Projection: camera 1.0 above the roof, player plane at 1.9 units,
    // ~58° vertical FOV, pitched 3.8° down so the horizon sits at 56% of screen height.
    let camH: Float = 1.0, zp: Float = 1.9, playerX: Float = 0.65, roofHalf: Float = 1.6, drop: Float = 1.8
    let baseFOV: Float = 58
    let baseSpeed: Float = 10

    private(set) var speed: Float = 10
    private var distance: Float = 0
    private var curve: Float = 0
    private(set) var time: Double = 0
    private var boostUntil: Double = 0

    private struct Mover {
        let entity: Entity
        var depth: Float
        var x: Float
        var y: Float
        let span: Float
        let near: Float
        let follow: Bool
        var fadeFar: Float = 85
    }
    private var movers: [Mover] = []
    private var wheelSpinner: Entity?
    private var gates: [Gate3D] = []
    private var nextGateAt: Float = 30
    private var resolvedCount = 0
    private var shards: [(entity: ModelEntity, velocity: SIMD3<Float>, spin: Float, life: Float)] = []
    private var tunnelRings: [Entity] = []
    private var tunnelDepths: [Float] = []
    private var tunnelActive = false
    private var bridge = Entity()
    private var bridgeDepth: Float = -1
    private var players: [Zone: Entity] = [:]
    private var cues: [Zone: ModelEntity] = [:]
    private var laneStrips: [Zone: ModelEntity] = [:]
    private var sky = Entity()
    private var farLayers: [Entity] = []

    // Textures (built once).
    private let beamTexture = Mat3D.texture(Art.beam)
    private let panelTexture = Mat3D.texture(Art.lanePanel)
    private let checkTexture = Mat3D.texture(Art.check)
    private let beaconTexture = Mat3D.texture(Art.searchlight)
    private let chevronTexture = Mat3D.texture(Art.chevron)
    private let glowTexture = Mat3D.texture(Art.glow)

    /// Optional compositing probe (`-liveTexture YES`).
    private var live: LiveCutout3D?

    // Metrics.
    private var frameTimes: [Double] = []
    private var lastMetrics: Double = 0
    private var modelCount = 0

    init() {
        // Stylised dusk lighting: damp RealityKit's default (bright, neutral) environment lighting so the coloured
        // key/rim lights and emissive neon carry the palette instead of washing it out.
        root.components.set(EnvironmentLightingConfigurationComponent(environmentLightingWeight: 0.15))
        buildCamera()
        buildLights()
        buildBackdrop()
        buildTrack()
        buildCity()
        buildLandmark()
        buildBridge()
        buildTunnel()
        buildPlayers()
        buildShards()
        modelCount = Self.countModels(root)
        Self.dampEnvironmentLighting(root)
        coop.onFeedback = { [weak self] feedback in self?.handle(feedback) }
        if UserDefaults.standard.bool(forKey: "liveTexture"), let probe = LiveCutout3D() {
            probe.plane.position = [0, 0.975, -zp - 0.01]
            root.addChild(probe.plane)
            for player in players.values { player.isEnabled = false }
            probe.start()
            live = probe
        }
        print("[WORLD3D] model entities: \(modelCount)")
    }

    // MARK: - Build

    private func buildCamera() {
        cameraEntity.camera.fieldOfViewInDegrees = baseFOV
        cameraEntity.camera.fieldOfViewOrientation = .vertical
        cameraEntity.camera.near = 0.05
        cameraEntity.camera.far = 600
        cameraEntity.position = [0, camH, 0]
        cameraEntity.orientation = simd_quatf(angle: -3.8 * .pi / 180, axis: [1, 0, 0])
        root.addChild(cameraEntity)
    }

    private func buildLights() {
        // Warm key light from behind the camera, high and to the right: lights the faces we see and
        // throws real shadows forward across the roof.
        let key = DirectionalLight()
        key.light.color = UIColor(red: 1.0, green: 0.80, blue: 0.72, alpha: 1)
        key.light.intensity = 1300
        key.shadow = DirectionalLightComponent.Shadow(maximumDistance: 45, depthBias: 1.5)
        key.look(at: [0, 0, -12], from: [7, 16, 9], relativeTo: nil)
        root.addChild(key)
        // Cool violet rim from the horizon, no shadows.
        let rim = DirectionalLight()
        rim.light.color = UIColor(red: 0.55, green: 0.40, blue: 1.0, alpha: 1)
        rim.light.intensity = 700
        rim.look(at: [0, 0, 0], from: [-4, 6, -60], relativeTo: nil)
        root.addChild(rim)
    }

    private func buildBackdrop() {
        var skyMat = UnlitMaterial()
        if let tex = Mat3D.sky { skyMat.color = .init(texture: .init(tex)) }
        let sphere = ModelEntity(mesh: .generateSphere(radius: 400), materials: [skyMat])
        sphere.scale = [-1, 1, 1]   // render the inside
        sphere.components.set(DynamicLightShadowComponent(castsShadow: false))
        sky = sphere
        root.addChild(sphere)

        // Retro sun, mountains and skyline: very distant flat layers (as in 2.5D), panned against curves.
        let sun = ModelEntity(mesh: .generatePlane(width: 106, height: 106), materials: [Mat3D.sprite(Mat3D.sun)])
        sun.position = [0, camH + 28.7, -260]
        let mountains = ModelEntity(mesh: .generatePlane(width: 520, height: 50), materials: [Mat3D.sprite(Mat3D.texture(Art.mountains), opacity: 1)])
        mountains.position = [0, camH + 22, -250]
        let skyline = ModelEntity(mesh: .generatePlane(width: 430, height: 36), materials: [Mat3D.sprite(Mat3D.texture(Art.skyline), opacity: 1)])
        skyline.position = [0, camH + 15, -240]
        for layer in [sun, mountains, skyline] {
            layer.components.set(DynamicLightShadowComponent(castsShadow: false))
            root.addChild(layer)
            farLayers.append(layer)
        }
    }

    private func buildTrack() {
        // Train roof: 3-unit tiles, recycled.
        let tileMesh = MeshResource.generateBox(width: roofHalf * 2, height: 0.3, depth: 3.0)
        // Unlit too: even dark-tinted lit materials came out near-white under RealityKit's exposure on iOS, so the
        // roof cannot use real-time shadows without losing the palette. Overhead shadows are baked-style planes.
        let roofA = Mat3D.sprite(Mat3D.roofTile)
        let roofB = Mat3D.sprite(Mat3D.roofTile, tint: UIColor(white: 0.86, alpha: 1))
        let skirt = Mat3D.lit(UIColor(red: 0.10, green: 0.08, blue: 0.26, alpha: 1), roughness: 0.6)
        for i in 0..<26 {
            let tile = ModelEntity(mesh: tileMesh, materials: [i % 2 == 0 ? roofA : roofB])
            // Train body below the roof gives the roof edge real thickness against the ground far below.
            let body = ModelEntity(mesh: .generateBox(width: roofHalf * 2 - 0.1, height: 1.5, depth: 3.0), materials: [skirt])
            body.position = [0, -0.9, 0]
            tile.addChild(body)
            root.addChild(tile)
            movers.append(Mover(entity: tile, depth: Float(i) * 3, x: 0, y: -0.15, span: 78, near: -1.6, follow: true))
        }
        // Ground grid far below, with the adjacent rails.
        let groundMesh = MeshResource.generateBox(width: 70, height: 0.05, depth: 12)
        let ground = Mat3D.sprite(Mat3D.groundTile)
        let railMat = Mat3D.neon(Palette.yellow.withAlphaComponent(0.85))
        for i in 0..<10 {
            let tile = ModelEntity(mesh: groundMesh, materials: [ground])
            for x: Float in [-4.7, -3.7, 3.7, 4.7] {
                let rail = ModelEntity(mesh: .generateBox(width: 0.08, height: 0.06, depth: 12), materials: [railMat])
                rail.position = [x, 0.05, 0]
                tile.addChild(rail)
            }
            root.addChild(tile)
            movers.append(Mover(entity: tile, depth: Float(i) * 12, x: 0, y: -drop - 0.03, span: 120, near: -6, follow: true, fadeFar: 1000))
        }
        // Pylons with glowing orbs, both sides.
        let poleMesh = MeshResource.generateCylinder(height: 3.5, radius: 0.07)
        let orbMesh = MeshResource.generateSphere(radius: 0.2)
        let barMesh = MeshResource.generateBox(width: 0.7, height: 0.08, depth: 0.08)
        let poleMat = Mat3D.lit(Palette.violet, roughness: 0.3, metallic: 0.6)
        let orbMat = Mat3D.neon(Palette.yellow)
        for side: Float in [-1, 1] {
            for i in 0..<20 {
                let pylon = Entity()
                let pole = ModelEntity(mesh: poleMesh, materials: [poleMat])
                pole.position = [0, 1.75, 0]
                let orb = ModelEntity(mesh: orbMesh, materials: [orbMat])
                orb.position = [0, 3.55, 0]
                let bar = ModelEntity(mesh: barMesh, materials: [poleMat])
                bar.position = [0, 3.2, 0]
                pylon.addChild(pole); pylon.addChild(orb); pylon.addChild(bar)
                root.addChild(pylon)
                movers.append(Mover(entity: pylon, depth: Float(i) * 5 + 2, x: side * 2.35, y: -drop, span: 100, near: 0.3, follow: false))
            }
        }
        // Neon arches over the track (same rhythm as Revision 3: every 33 units).
        let segMesh = MeshResource.generateBox(width: 0.18, height: 0.75, depth: 0.18)
        let archMats = [Mat3D.neon(Palette.teal), Mat3D.neon(Palette.violet)]
        for i in 0..<3 {
            let arch = Entity()
            let radius: Float = 2.9
            for s in 0...12 {
                let a = Float(s) / 12 * .pi
                let seg = ModelEntity(mesh: segMesh, materials: [archMats[s % 2]])
                seg.position = [cos(a) * radius, 2.0 + sin(a) * radius, 0]
                seg.orientation = simd_quatf(angle: a, axis: [0, 0, 1])
                arch.addChild(seg)
            }
            for x in [-radius, radius] {
                let leg = ModelEntity(mesh: .generateBox(width: 0.18, height: 3.8, depth: 0.18), materials: [archMats[0]])
                leg.position = [x, 0.1, 0]
                arch.addChild(leg)
            }
            root.addChild(arch)
            movers.append(Mover(entity: arch, depth: Float(i) * 33 + 20, x: 0, y: -drop, span: 99, near: 0.2, follow: true))
        }
        // Approach lanes (lit while a gate is inbound).
        for zone in Zone.allCases {
            let strip = ModelEntity(mesh: .generateBox(width: 0.32, height: 0.02, depth: 1),
                                    materials: [Mat3D.neon(Palette.color(for: zone, swapped: false), alpha: 0.45)])
            strip.isEnabled = false
            strip.components.set(DynamicLightShadowComponent(castsShadow: false))
            root.addChild(strip)
            laneStrips[zone] = strip
        }
    }

    private func buildCity() {
        var rng = SeededRandom(seed: 314)
        let textures = Art.buildings.compactMap { Mat3D.texture($0) }
        // Faux lighting per face (front, top, back, bottom, right, left): unlit keeps the palette, shading keeps volume.
        let shades: [CGFloat] = [1.0, 1.15, 0.8, 0.3, 0.55, 0.55]
        let faceSets: [[any RealityKit.Material]] = textures.map { tex in shades.map { Mat3D.sprite(tex, tint: UIColor(white: min(1, $0), alpha: 1)) } }
        let roofEdge = [Mat3D.neon(Palette.coral), Mat3D.neon(Palette.teal), Mat3D.neon(Palette.yellow)]
        for side: Float in [-1, 1] {
            for i in 0..<10 {
                let w = Float(2.6 + rng.next() * 2), h = Float(4.5 + rng.next() * 6), d = Float(3 + rng.next() * 4)
                // Unlit: an A/B test showed lit PBR (auto exposure + tone mapping) washes this palette to grey.
                let building = ModelEntity(mesh: .generateBox(width: w, height: h, depth: d, cornerRadius: 0, splitFaces: true),
                                           materials: faceSets[i % faceSets.count])
                let edge = ModelEntity(mesh: .generateBox(width: w + 0.05, height: 0.12, depth: d + 0.05), materials: [roofEdge[i % 3]])
                edge.position = [0, h / 2, 0]
                building.addChild(edge)
                root.addChild(building)
                let mover = Mover(entity: building, depth: Float(i) * 10 + Float(rng.next() * 4) + 3, x: side * Float(8 + rng.next() * 5),
                                  y: -drop + h / 2, span: 100, near: -d, follow: true)
                movers.append(mover)
            }
        }
    }

    /// The showcase for true 3D: a ferris wheel seen three-quarter on, with two rims, spokes and gondolas.
    private func buildLandmark() {
        let wheel = Entity()
        let spinner = Entity()
        let radius: Float = 10.5
        let rimMats = [Mat3D.neon(Palette.coral), Mat3D.neon(Palette.yellow)]
        let segMesh = MeshResource.generateBox(width: 0.35, height: 2.8, depth: 0.35)
        for zOffset: Float in [-0.9, 0.9] {
            for s in 0..<24 {
                let a = Float(s) / 24 * 2 * .pi
                let seg = ModelEntity(mesh: segMesh, materials: [rimMats[s % 2]])
                seg.position = [cos(a) * radius, sin(a) * radius, zOffset]
                seg.orientation = simd_quatf(angle: a, axis: [0, 0, 1])
                spinner.addChild(seg)
            }
        }
        let spokeMat = Mat3D.lit(UIColor(red: 0.55, green: 0.45, blue: 0.95, alpha: 1), roughness: 0.3, metallic: 0.5)
        let gondolaMats = [Palette.teal, Palette.yellow, Palette.coral, Palette.violet].map { Mat3D.lit($0, roughness: 0.4, emissive: $0, intensity: 0.6) }
        for s in 0..<12 {
            let a = Float(s) / 12 * 2 * .pi
            let spoke = ModelEntity(mesh: .generateBox(width: 0.12, height: radius, depth: 0.12), materials: [spokeMat])
            spoke.position = [cos(a) * radius / 2, sin(a) * radius / 2, 0]
            spoke.orientation = simd_quatf(angle: a - .pi / 2, axis: [0, 0, 1])
            spinner.addChild(spoke)
            let gondola = ModelEntity(mesh: .generateBox(width: 1.1, height: 0.9, depth: 1.6, cornerRadius: 0.2), materials: [gondolaMats[s % 4]])
            gondola.position = [cos(a) * radius, sin(a) * radius - 0.6, 0]
            spinner.addChild(gondola)
        }
        let hub = ModelEntity(mesh: .generateCylinder(height: 2.2, radius: 0.8), materials: [Mat3D.neon(Palette.yellow)])
        hub.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        spinner.addChild(hub)
        spinner.position = [0, 12, 0]
        wheel.addChild(spinner)
        for (x, z) in [(Float(-5), Float(-1.2)), (5, -1.2), (-5, 1.2), (5, 1.2)] {
            let leg = ModelEntity(mesh: .generateBox(width: 0.5, height: 13.5, depth: 0.5), materials: [spokeMat])
            leg.position = [x / 2, 6, z]
            leg.orientation = simd_quatf(angle: x < 0 ? -0.36 : 0.36, axis: [0, 0, 1])
            wheel.addChild(leg)
        }
        let turned = Entity()
        turned.addChild(wheel)
        wheel.orientation = simd_quatf(angle: 0.55, axis: [0, 1, 0])   // three-quarter view
        root.addChild(turned)
        wheelSpinner = spinner
        movers.append(Mover(entity: turned, depth: 150, x: -19, y: -drop, span: 220, near: -12, follow: false, fadeFar: 170))
    }

    private func buildBridge() {
        let towerMat = Mat3D.lit(UIColor(red: 0.20, green: 0.14, blue: 0.48, alpha: 1), roughness: 0.4, metallic: 0.5)
        let accent = Mat3D.neon(Palette.coral)
        let cableMat = Mat3D.neon(Palette.teal)
        for x: Float in [-7, 7] {
            let tower = ModelEntity(mesh: .generateBox(width: 0.9, height: 11, depth: 0.9), materials: [towerMat])
            tower.position = [x, 5.5, 0]
            let lamp = ModelEntity(mesh: .generateSphere(radius: 0.35), materials: [accent])
            lamp.position = [0, 5.7, 0]
            tower.addChild(lamp)
            bridge.addChild(tower)
        }
        let deck = ModelEntity(mesh: .generateBox(width: 20, height: 0.5, depth: 1.8), materials: [towerMat])
        deck.position = [0, 3.9, 0]
        bridge.addChild(deck)
        let trim = ModelEntity(mesh: .generateBox(width: 20, height: 0.1, depth: 1.85), materials: [Mat3D.neon(Palette.yellow)])
        trim.position = [0, 3.62, 0]
        bridge.addChild(trim)
        for i in 0..<12 {   // truss diagonals on the deck sides
            let x = -9.2 + Float(i) * 1.67
            for z: Float in [-0.95, 0.95] {
                let d = ModelEntity(mesh: .generateBox(width: 0.08, height: 1.1, depth: 0.08), materials: [Mat3D.neon(Palette.violet)])
                d.position = [x, 4.6, z]
                d.orientation = simd_quatf(angle: i % 2 == 0 ? 0.6 : -0.6, axis: [0, 0, 1])
                bridge.addChild(d)
            }
        }
        for i in 0..<14 {   // suspension cable approximated by segments
            let t0 = Float(i) / 14, t1 = Float(i + 1) / 14
            func p(_ t: Float) -> SIMD3<Float> { [-7 + 14 * t, 10.8 - 6.0 * 4 * t * (1 - t), 0] }
            let a = p(t0), b = p(t1)
            let len = simd_length(b - a)
            let seg = ModelEntity(mesh: .generateBox(width: len, height: 0.07, depth: 0.07), materials: [cableMat])
            seg.position = (a + b) / 2
            seg.orientation = simd_quatf(angle: atan2(b.y - a.y, b.x - a.x), axis: [0, 0, 1])
            bridge.addChild(seg)
        }
        let shade = ModelEntity(mesh: .generatePlane(width: 3.2, depth: 2.2), materials: [Mat3D.neon(.black, alpha: 0.45)])
        shade.position = [0, drop + 0.012, 0]
        bridge.addChild(shade)
        bridge.isEnabled = false
        root.addChild(bridge)
    }

    private func buildTunnel() {
        let segMesh = MeshResource.generateBox(width: 0.22, height: 1.45, depth: 0.22)
        let colors = [Palette.teal, Palette.violet, Palette.coral]
        for i in 0..<10 {
            let ring = Entity()
            let mat = Mat3D.neon(colors[i % 3])
            for s in 0..<16 {
                let a = Float(s) / 16 * 2 * .pi
                let seg = ModelEntity(mesh: segMesh, materials: [mat])
                seg.position = [cos(a) * 3.6, sin(a) * 3.6, 0]
                seg.orientation = simd_quatf(angle: a, axis: [0, 0, 1])
                ring.addChild(seg)
            }
            ring.isEnabled = false
            ring.components.set(DynamicLightShadowComponent(castsShadow: false))
            root.addChild(ring)
            tunnelRings.append(ring)
            tunnelDepths.append(0)
        }
    }

    private func buildPlayers() {
        for zone in Zone.allCases {
            let isChild = zone == .right
            let tex = Mat3D.texture(Art.placeholder(color: Palette.color(for: zone, swapped: false), child: isChild))
            let height: Float = isChild ? 0.82 : 1.18
            let width = height * (isChild ? 220 / 380 : 240 / 520)
            let player = Entity()
            let figure = ModelEntity(mesh: .generatePlane(width: width, height: height), materials: [Mat3D.sprite(tex)])
            figure.position = [0, height / 2, 0]
            figure.components.set(DynamicLightShadowComponent(castsShadow: false))
            player.addChild(figure)
            let x: Float = zone == .left ? -playerX : playerX
            player.position = [x, 0, -zp]
            root.addChild(player)
            players[zone] = player

            let pad = ModelEntity(mesh: .generateCylinder(height: 0.02, radius: 0.55),
                                  materials: [Mat3D.neon(Palette.color(for: zone, swapped: false), alpha: 0.45)])
            pad.position = [x, 0.02, -zp]
            pad.scale = [1, 1, 0.4]
            pad.components.set(DynamicLightShadowComponent(castsShadow: false))
            root.addChild(pad)
            let contact = ModelEntity(mesh: .generatePlane(width: 0.7, depth: 0.25), materials: [Mat3D.sprite(glowTexture, tint: .black, opacity: 0.6)])
            contact.position = [x, 0.03, -zp]
            root.addChild(contact)

            let cue = ModelEntity(mesh: .generatePlane(width: 0.3, height: 0.25),
                                  materials: [Mat3D.sprite(chevronTexture, tint: Palette.color(for: zone, swapped: false))])
            cue.position = [x, height + 0.3, -zp]
            cue.isEnabled = false
            root.addChild(cue)
            cues[zone] = cue
        }
    }

    private func buildShards() {
        let mesh = MeshResource.generateBox(size: 0.12)
        let colors = [Palette.coral, Palette.teal, Palette.yellow, Palette.violet, .white]
        for i in 0..<24 {
            let shard = ModelEntity(mesh: mesh, materials: [Mat3D.neon(colors[i % colors.count])])
            shard.isEnabled = false
            root.addChild(shard)
            shards.append((shard, .zero, 0, 0))
        }
    }

    // MARK: - Frame loop

    func update(dt rawDT: Double) {
        let dt = Float(min(rawDT, 0.1))
        time += Double(dt)
        recordFrame(rawDT)

        let boosting = time < boostUntil
        let target = baseSpeed * (boosting ? 1.6 : 1)
        speed += (target - speed) * min(1, dt * 2)
        let travel = speed * dt
        distance += travel
        let curveTarget: Float = 0.0045 * sin(distance * 2 * .pi / 320) + 0.0015 * sin(distance * 2 * .pi / 130)
        curve += (curveTarget - curve) * min(1, dt * 2)

        // True camera motion: FOV kick while boosting, a gentle bank into bends, a subtle ride bob.
        let fovTarget: Float = boosting ? 68 : baseFOV
        cameraEntity.camera.fieldOfViewInDegrees += (fovTarget - cameraEntity.camera.fieldOfViewInDegrees) * min(1, dt * 3)
        let bank = simd_quatf(angle: -curve * 260 * .pi / 180, axis: [0, 0, 1])
        cameraEntity.orientation = bank * simd_quatf(angle: -3.8 * .pi / 180, axis: [1, 0, 0])
        cameraEntity.position = [0, camH + 0.012 * sin(Float(time) * 11), 0]

        let pan = -curve * 4200
        for layer in farLayers { layer.position.x = pan }

        for i in movers.indices {
            movers[i].depth -= travel
            if movers[i].depth < movers[i].near { movers[i].depth += movers[i].span }
            let m = movers[i]
            place(m.entity, x: m.x, y: m.y, depth: m.depth, follow: m.follow)
            let fade = 1 - smoothstep3(m.fadeFar * 0.8, m.fadeFar, m.depth)
            m.entity.components.set(OpacityComponent(opacity: fade))
        }
        wheelSpinner?.orientation = simd_quatf(angle: Float(time) * 0.18, axis: [0, 0, 1])

        updateGates(dt: dt, travel: travel)
        coop.update(at: time)
        updatePlayers()
        live?.update()
        updateShards(dt: dt)
        updateTunnel(travel: travel)
        updateBridge(travel: travel)
        publishMetricsIfNeeded()
    }

    private func bend(_ depth: Float) -> Float {
        let d = max(0, depth - zp)
        return curve * d * d
    }

    private func place(_ entity: Entity, x: Float, y: Float, depth: Float, follow: Bool) {
        entity.position = [x + bend(depth), y, -depth]
        if follow {
            entity.orientation = simd_quatf(angle: -atan(2 * curve * max(0, depth - zp)), axis: [0, 1, 0])
        }
    }

    // MARK: - Gates & co-op

    private var setPieceBlocksGates: Bool {
        (tunnelActive && tunnelDepths.contains { $0 > zp + 4 }) || (bridge.isEnabled && bridgeDepth > 3) || time < boostUntil + 0.5
    }

    private func updateGates(dt: Float, travel: Float) {
        if distance >= nextGateAt, !gates.contains(where: { !$0.resolved }), !setPieceBlocksGates {
            spawnGate()
            nextGateAt = .greatestFiniteMagnitude
        }
        for gate in gates {
            gate.depth -= travel
            place(gate.root, x: 0, y: 0, depth: gate.depth, follow: true)
            gate.root.components.set(OpacityComponent(opacity: 1 - smoothstep3(55, 68, gate.depth)))
            let timeToArrival = (gate.depth - zp) / max(speed, 0.1)
            if !gate.warned, timeToArrival <= 2.5 {
                gate.warned = true
                beginWarning(gate)
            }
            if gate.warned, !gate.resolved {
                for zone in Zone.allCases {
                    guard let strip = laneStrips[zone] else { continue }
                    let length = max(0.1, gate.depth - zp)
                    strip.isEnabled = true
                    strip.scale = [1, 1, length]
                    place(strip, x: zone == .left ? -playerX : playerX, y: 0.02, depth: zp + length / 2, follow: false)
                    cues[zone]?.position.y = (zone == .left ? 1.18 : 0.82) + 0.3 + 0.05 * sin(Float(time) * 12)
                }
            }
            if !gate.resolved, gate.depth <= zp {
                gate.resolved = true
                for strip in laneStrips.values { strip.isEnabled = false }
                for cue in cues.values { cue.isEnabled = false }
                coop.resolve(at: time)
                nextGateAt = distance + 14
            }
            if gate.resolved, gate.depth < zp * 0.8 {
                for p in gate.panels.values { p.isEnabled = false }
                for c in gate.checks.values { c.isEnabled = false }
            }
        }
        gates.removeAll { gate in
            if gate.depth < -1 { gate.root.removeFromParent(); return true }
            return false
        }
    }

    private var currentGate: Gate3D? { gates.first { $0.warned && !$0.resolved } }

    private func spawnGate() {
        let colors: [Zone: UIColor] = [.left: Palette.coral, .right: Palette.teal]
        let gate = Gate3D(playerX: playerX, colors: colors, beamTexture: beamTexture, panelTexture: panelTexture,
                          checkTexture: checkTexture, beaconTexture: beaconTexture)
        root.addChild(gate.root)
        gates.append(gate)
        // Anticipation: posts grow out of the roof, beam drops in from above.
        for post in gate.posts {
            post.scale = [1, 0.01, 1]
            var t = post.transform; t.scale = [1, 1, 1]
            post.move(to: t, relativeTo: post.parent, duration: 0.45, timingFunction: .easeOut)
        }
        var beamEnd = gate.beam.transform
        gate.beam.position.y += 1.6
        beamEnd.translation.y = 1.62
        gate.beam.move(to: beamEnd, relativeTo: gate.root, duration: 0.5, timingFunction: .easeOut)
    }

    private func beginWarning(_ gate: Gate3D) {
        gate.beacon.isEnabled = false
        for panel in gate.panels.values {
            var t = panel.transform; t.scale = [1, 1, 1]
            panel.move(to: t, relativeTo: panel.parent, duration: 0.28, timingFunction: .easeOut)
        }
        for cue in cues.values { cue.isEnabled = true }
        coop.challengeWarned(at: time)
        hud.lockFilled = []
        hud.lockVisible = true
        show("DUCK!", sub: "Both squat before it arrives", color: .yellow)
    }

    private func handle(_ feedback: Coop3D.Feedback) {
        let gate = currentGate ?? gates.last
        switch feedback {
        case .provisional(let zone):
            guard let panel = gate?.panels[zone] else { return }
            panel.model?.materials = [Mat3D.sprite(panelTexture, tint: Palette.mint, opacity: 0.95)]
            var t = panel.transform; t.translation.y += 0.1
            panel.move(to: t, relativeTo: panel.parent, duration: 0.12, timingFunction: .easeOut)
        case .contributed(let zone, let banked):
            hud.lockFilled.insert(zone)
            hud.teamPower = min(10, hud.teamPower + banked)
            if let check = gate?.checks[zone] {
                check.isEnabled = true
                check.position.y += 0.1
                check.scale = [0.6, 0.6, 0.6]
                var t = check.transform; t.scale = [1, 1, 1]
                check.move(to: t, relativeTo: check.parent, duration: 0.15, timingFunction: .easeOut)
            }
            gate?.glows[zone]?.isEnabled = true
        case .rep(let zone, let total):
            hud.squats[zone] = total
        case .incomplete:
            show("GO DEEPER!", sub: "", color: .yellow)
        case .resolved(let outcome, let bonus):
            hud.teamPower = min(10, hud.teamPower + bonus)
            switch outcome {
            case .team:
                if let gate { shatter(gate) }
                show("TEAM DUCK!", sub: "Both of you made it!", color: .mint)
                hud.flashID += 1
                boostUntil = time + 1.6
            case .partial(let done, let missing):
                for zone in missing { gate?.panels[zone]?.model?.materials = [Mat3D.sprite(panelTexture, tint: Palette.coral.mixed(with: Palette.deepNavy, amount: 0.4))] }
                show(done.isEmpty ? "ALMOST!" : "NICE!", sub: "Squat together for the TEAM bonus", color: .coral)
            case .cancelled:
                break
            }
            hud.lockVisible = false
            resolvedCount += 1
            stageSetPiece()
        }
    }

    private func shatter(_ gate: Gate3D) {
        gate.beam.isEnabled = false
        for glow in gate.glows.values { glow.isEnabled = false }
        for p in gate.panels.values { p.isEnabled = false }
        let origin = gate.root.position(relativeTo: nil)
        for i in shards.indices {
            let x = Float.random(in: -2.4...2.4)
            shards[i].entity.isEnabled = true
            shards[i].entity.position = origin + [x, 1.62 + Float.random(in: -0.2...0.2), 0]
            shards[i].velocity = [x * Float.random(in: 0.5...1.4), Float.random(in: 2.5...5.5), Float.random(in: -1...2)]
            shards[i].spin = Float.random(in: -9...9)
            shards[i].life = Float.random(in: 0.6...0.95)
        }
    }

    private func updateShards(dt: Float) {
        for i in shards.indices where shards[i].life > 0 {
            shards[i].life -= dt
            shards[i].velocity.y -= 9 * dt
            shards[i].entity.position += shards[i].velocity * dt
            shards[i].entity.orientation *= simd_quatf(angle: shards[i].spin * dt, axis: simd_normalize([1, 1, 0]))
            if shards[i].life <= 0 { shards[i].entity.isEnabled = false }
        }
    }

    private func updatePlayers() {
        for zone in Zone.allCases {
            guard let player = players[zone] else { continue }
            let d = Float(coop.depth[zone] ?? 0)
            player.scale = [1 + 0.1 * d, 1 - 0.32 * d, 1]
        }
    }

    private func show(_ text: String, sub: String, color: UIColorBox) {
        hud.banner = text
        hud.subBanner = sub
        hud.bannerColor = color
        hud.bannerID += 1
    }

    // MARK: - Set pieces (staged between challenges, as in Revision 3)

    private func stageSetPiece() {
        if resolvedCount % 3 == 0, !tunnelActive {
            tunnelActive = true
            for i in tunnelRings.indices {
                tunnelDepths[i] = 34 + Float(i) * 2.8
                tunnelRings[i].isEnabled = true
            }
        } else if resolvedCount % 5 == 2, !bridge.isEnabled {
            bridge.isEnabled = true
            bridgeDepth = 55
        }
    }

    private func updateTunnel(travel: Float) {
        guard tunnelActive else { return }
        var any = false
        for i in tunnelRings.indices where tunnelRings[i].isEnabled {
            tunnelDepths[i] -= travel
            if tunnelDepths[i] < 0.3 { tunnelRings[i].isEnabled = false; continue }
            any = true
            place(tunnelRings[i], x: 0, y: 1.0, depth: tunnelDepths[i], follow: true)
            tunnelRings[i].orientation *= simd_quatf(angle: Float(i) * 0.2 + Float(time) * 0.5, axis: [0, 0, 1])
            let fade = smoothstep3(zp + 1.5, zp + 6, tunnelDepths[i]) * (1 - smoothstep3(50, 75, tunnelDepths[i]))
            tunnelRings[i].components.set(OpacityComponent(opacity: fade))
        }
        if !any { tunnelActive = false }
    }

    private func updateBridge(travel: Float) {
        guard bridge.isEnabled else { return }
        bridgeDepth -= travel
        if bridgeDepth < -3 { bridge.isEnabled = false; return }
        place(bridge, x: 0, y: -drop, depth: bridgeDepth, follow: true)
    }

    // MARK: - Metrics

    private func recordFrame(_ dt: Double) {
        frameTimes.append(dt * 1000)
    }

    private func publishMetricsIfNeeded() {
        guard time - lastMetrics >= 5 else { return }
        lastMetrics = time
        let n = Double(frameTimes.count)
        let avg = frameTimes.reduce(0, +) / max(1, n)
        let maxFrame = frameTimes.max() ?? 0
        let over = frameTimes.filter { $0 > 17.5 }.count
        let mem = DeviceStats.memoryFootprintMB()
        var line = String(format: "[METRICS3D] fps=%.1f frame=%.1f/%.1fms frames>17.5ms=%d models=%d mem=%.0fMB",
                          1000 / max(avg, 0.1), avg, maxFrame, over, modelCount, mem)
        if let live, !live.uploadMs.isEmpty {
            line += String(format: " liveUploads=%d upload=%.2f/%.2fms", live.uploads,
                           live.uploadMs.reduce(0, +) / Double(live.uploadMs.count), live.uploadMs.max() ?? 0)
        }
        print(line)
        hud.metrics = line.replacingOccurrences(of: "[METRICS3D] ", with: "")
        frameTimes.removeAll(keepingCapacity: true)
    }

    /// The lighting-weight component is per entity, so apply it to every model in the hierarchy.
    private static func dampEnvironmentLighting(_ entity: Entity) {
        if entity.components.has(ModelComponent.self) {
            entity.components.set(EnvironmentLightingConfigurationComponent(environmentLightingWeight: 0))
        }
        for child in entity.children { dampEnvironmentLighting(child) }
    }

    private static func countModels(_ entity: Entity) -> Int {
        (entity.components.has(ModelComponent.self) ? 1 : 0) + entity.children.reduce(0) { $0 + countModels($1) }
    }
}

func smoothstep3(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
    let t = max(0, min(1, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)
}
