import SpriteKit

/// Layered crocodile. Two views share one eye design: a head-on rig for the approach (eyes and snout above
/// the water) and a side rig for the attack (jaw hinge, eye, lid, brow, body, tail, leg).
/// Everything above the water lives in a crop node whose mask is the waterline. The lower jaw and throat
/// live in a parallel tree drawn *under* the raft deck, so when the jaws close on the edge the deck hides the
/// part of the lower jaw that is beneath the logs: the bite reads as clamping the raft, not floating over it.
@MainActor
final class CrocRig {
    let crop = SKCropNode()
    private let facing = SKNode()
    let side = SKNode()
    private let body = SKSpriteNode(texture: Art.crocBody)
    private let tail = SKSpriteNode(texture: Art.crocTail)
    private let leg = SKSpriteNode(texture: Art.crocLeg)
    private let head = SKNode()
    private let upper = SKSpriteNode(texture: Art.crocUpper)
    private let eye = CrocEye()
    private let brow = SKSpriteNode(texture: Art.crocBrow)
    // Parallel tree under the deck (also cut at the waterline).
    let underCrop = SKCropNode()
    private let underRoot = SKNode()
    private let underFacing = SKNode()
    private let underSide = SKNode()
    private let underHead = SKNode()
    private let lower = SKSpriteNode(texture: Art.crocLower)
    private let throat = SKSpriteNode(texture: Art.crocThroat)
    // Head-on rig.
    let front = SKNode()
    private let frontHead = SKSpriteNode(texture: Art.crocFront)
    private let frontEyes = [CrocEye(), CrocEye()]
    /// Head-on mouth at the front of the snout (expressions: a smug closed curve, bared teeth).
    private let frontMouth = SKSpriteNode(texture: Art.crocMouthFrames[0])
    // Water contact.
    let shadow = SKSpriteNode(texture: Art.crocShadow)
    let collar = SKSpriteNode(texture: Art.foamCollar)

    /// Follow-through: body and tail lag the head (overlapping action), smoothed per frame.
    private var bodyPitch: Double = 0
    private var tailSwing: Double = 0
    /// Bite point in side-rig units (relative to the jaw hinge): where the upper teeth meet the raft edge.
    static let biteOffset = CGPoint(x: 236, y: 0)
    static let sideHeadLength: CGFloat = 344

    init() {
        for c in [crop, underCrop] {
            let mask = SKSpriteNode(color: .white, size: CGSize(width: 6000, height: 4000))
            mask.anchorPoint = CGPoint(x: 0.5, y: 0)
            c.maskNode = mask
        }
        underCrop.addChild(underRoot)
        crop.addChild(facing)
        facing.addChild(side)
        facing.addChild(front)

        func anchor(_ node: SKSpriteNode, _ p: CGPoint) {
            let s = node.texture!.size()
            node.anchorPoint = CGPoint(x: p.x / s.width, y: 1 - p.y / s.height)
        }
        // Side rig (coordinates relative to the jaw hinge, y up).
        anchor(body, Art.crocBodyAnchor)
        body.position = CGPoint(x: -14, y: -16)
        body.zPosition = 0
        side.addChild(body)
        anchor(tail, Art.crocTailAnchor)
        tail.position = CGPoint(x: -400, y: -4)
        tail.zPosition = -0.05
        body.addChild(tail)
        anchor(leg, Art.crocLegAnchor)
        leg.position = CGPoint(x: -92, y: -22)
        leg.zPosition = 0.05
        body.addChild(leg)
        head.zPosition = 0.2
        side.addChild(head)
        anchor(upper, Art.crocUpperHinge)
        head.addChild(upper)
        eye.root.position = CGPoint(x: 49, y: 87)
        eye.root.setScale(0.85)
        eye.root.zPosition = 0.02
        head.addChild(eye.root)
        brow.position = CGPoint(x: 52, y: 116)
        brow.zPosition = 0.04
        head.addChild(brow)

        underRoot.addChild(underFacing)
        underFacing.addChild(underSide)
        underSide.addChild(underHead)
        anchor(throat, Art.crocThroatHinge)
        throat.position = CGPoint(x: -10, y: -3)
        underHead.addChild(throat)
        anchor(lower, Art.crocLowerHinge)
        lower.position = CGPoint(x: 0, y: -4)
        lower.zPosition = 0.01
        underHead.addChild(lower)

        // Head-on rig: anchored on the waterline.
        frontHead.anchorPoint = CGPoint(x: 0.5, y: 1 - Art.crocFrontWaterline / Art.crocFront.size().height)
        front.addChild(frontHead)
        for (i, e) in frontEyes.enumerated() {
            let p = Art.crocFrontEyes[i]
            e.root.position = CGPoint(x: p.x - 150, y: Art.crocFrontWaterline - p.y)
            e.root.setScale(0.78)
            e.root.zPosition = 0.02
            front.addChild(e.root)
        }
        frontMouth.anchorPoint = CGPoint(x: 0.5, y: 0.75)
        frontMouth.position = CGPoint(x: 0, y: 10)
        frontMouth.setScale(0.62)
        frontMouth.zPosition = 0.03
        frontMouth.alpha = 0
        front.addChild(frontMouth)
        shadow.alpha = 0
        collar.alpha = 0
    }

    func add(to parent: SKNode) {
        for node in [crop, underCrop, shadow, collar] as [SKNode] { parent.addChild(node) }
    }

    func remove() {
        for node in [crop, underCrop, shadow, collar] as [SKNode] { node.removeFromParent() }
    }

    /// Faces the raft: side rigs point at the raft centre (left croc faces right).
    func setSide(_ zone: Zone) {
        facing.xScale = zone == .left ? 1 : -1
        underFacing.xScale = facing.xScale
    }

    /// Head-on approach. `waterPoint`: screen point of the water surface under the head; `ppu`: pixels per unit there.
    func applyHeadOn(_ pose: CrocPose, waterPoint: CGPoint, ppu: CGFloat, z: CGFloat, lookX: CGFloat, reduceMotion: Bool) {
        side.isHidden = true
        underCrop.isHidden = true
        front.isHidden = false
        crop.position = waterPoint
        crop.zPosition = z
        let scale = ppu * 1.05 / 300   // head ≈ 1.05 units wide
        front.setScale(scale)
        let height = 110 * scale
        front.position = CGPoint(x: 0, y: CGFloat(pose.rise - 1) * height)
        front.zRotation = reduceMotion ? 0 : CGFloat(pose.yaw) * 0.6
        for e in frontEyes { e.apply(lid: pose.lid, pupil: pose.pupil, look: lookX, anger: pose.lid > 0.4 ? 1 : 0) }
        setMouth(grin: pose.grin)
        collar.position = CGPoint(x: waterPoint.x, y: waterPoint.y + 2)
        // The foam sits in front of the head, except while it snarls (the teeth must read).
        collar.zPosition = pose.grin > 0.2 ? z - 0.05 : z + 0.1
        collar.size = CGSize(width: 1.15 * ppu, height: 0.22 * ppu)
        collar.alpha = CGFloat(pose.collar) * CGFloat(max(0, min(1, (pose.rise + 0.3) / 0.6))) * 0.9
    }

    /// Side attack. `bite`: the raft-edge point the jaws close on; `waterY`: water surface height there.
    func applySide(_ pose: CrocPose, bite: CGPoint, waterY: CGFloat, ppu: CGFloat, sideSign: CGFloat, raftRoll: CGFloat,
                   frontZ: CGFloat, underZ: CGFloat, dt: Double, reduceMotion: Bool) {
        front.isHidden = true
        side.isHidden = false
        underCrop.isHidden = false
        let scale = ppu * 0.78 / Self.sideHeadLength
        crop.position = CGPoint(x: bite.x, y: waterY)
        crop.zPosition = frontZ
        underCrop.position = crop.position
        underCrop.zPosition = underZ
        // Rise: 1 puts the bite point on the raft edge; lower values sink the whole croc.
        let headHeight = 150 * scale
        let back = CGFloat(pose.back) * Self.sideHeadLength * 0.8 * scale
        let hinge = CGPoint(x: -(Self.biteOffset.x * scale) - back, y: (bite.y - waterY) + CGFloat(pose.rise - 1) * headHeight * 1.4)
        let shake = reduceMotion ? 0 : CGFloat(pose.shake)
        let pitch = CGFloat(pose.pitch) + shake
        // The jaws follow the raft's roll so the bite stays on the edge; body and tail lag behind.
        let roll = raftRoll * sideSign
        for node in [side, underSide] {
            node.position = hinge
            node.setScale(scale)
            node.yScale = scale * CGFloat(2 - pose.stretch)
            node.xScale = scale * CGFloat(pose.stretch)
        }
        head.zRotation = pitch + roll
        underHead.zRotation = head.zRotation
        let follow = min(1, dt * 7)
        bodyPitch += (Double(pitch) * 0.45 - bodyPitch) * follow
        tailSwing += (pose.tail - tailSwing) * min(1, dt * 5)
        body.zRotation = 0.3 + CGFloat(bodyPitch) + shake * 0.4
        tail.zRotation = reduceMotion ? 0 : CGFloat(tailSwing) - 0.12
        // The front leg reaches up onto the deck while clinging, flails while lunging.
        let grip: CGFloat = pose.state == .clinging ? 0.9 : (pose.state == .impact ? 0.6 : 0.1)
        leg.zRotation += (grip - leg.zRotation) * CGFloat(min(1, dt * 8))
        // Jaw: hinge rotation, throat scales open with it.
        lower.zRotation = -CGFloat(pose.jaw) * 0.62
        throat.yScale = max(0.02, CGFloat(pose.jaw))
        let jawVisible = CGFloat(max(0, min(1, (pose.rise + 0.2) / 0.6)))
        lower.alpha = jawVisible
        throat.alpha = jawVisible
        eye.apply(lid: pose.lid, pupil: pose.pupil, look: 4, anger: pose.state == .clinging || pose.state == .anticipation ? 1 : 0.3)
        brow.zRotation = -0.3 * (pose.state == .clinging ? 1 : 0.4)
        // Foam collar where the body pierces the surface.
        // Foam collar around the neck, where the body enters the water (behind the head, never across the jaw).
        collar.position = CGPoint(x: bite.x - sideSign * ((Self.biteOffset.x + 70) * scale + back), y: waterY + 2)
        collar.zPosition = frontZ - 0.05
        collar.size = CGSize(width: 0.75 * ppu, height: 0.16 * ppu)
        collar.alpha = CGFloat(pose.collar) * 0.7
    }

    /// Tail sweep: lying side-on in the water off the bow corner, head pointing away from the raft, its own tail
    /// sprite hidden (the articulated TailChain takes over at `hip`). Eyes look back at the players; after the
    /// overshoot it turns round (a 2D turn: the facing squashes through zero) and is dizzy or pleased.
    func applySweepBody(_ pose: TailPose, hip: CGPoint, waterY: CGFloat, ppu: CGFloat, side zone: Zone, z: CGFloat,
                        now: Double, reduceMotion: Bool) {
        front.isHidden = true
        side.isHidden = pose.rise <= 0.01
        underCrop.isHidden = side.isHidden
        tail.isHidden = true
        let away: CGFloat = zone == .right ? 1 : -1
        let turn = CGFloat(cos(2 * .pi * pose.spin))
        facing.xScale = away * (abs(turn) < 0.08 ? 0.08 * (turn < 0 ? -1 : 1) : turn)
        underFacing.xScale = facing.xScale
        let scale = ppu * 0.78 / Self.sideHeadLength
        crop.position = CGPoint(x: hip.x, y: waterY)
        crop.zPosition = z
        underCrop.position = crop.position
        underCrop.zPosition = z - 0.01
        // The hips sit at the tail joint of the body (rig units: hinge + body offset + body length).
        let hipFromHinge = CGPoint(x: -14 - 400, y: -16 - 4)
        let float = (CGFloat(pose.rise) - 1) * 0.55 * ppu + 0.07 * ppu
        let bob = reduceMotion ? 0 : CGFloat(sin(now * 2.1)) * 0.02 * ppu
        let hinge = CGPoint(x: -hipFromHinge.x * scale, y: float + bob - hipFromHinge.y * scale - 0.1 * ppu)
        for node in [side, underSide] {
            node.position = hinge
            node.setScale(scale)
        }
        let wobble = reduceMotion ? 0 : CGFloat(pose.dizzy > 0 ? sin(pose.dizzy * 1.3) * 0.08 : 0)
        head.zRotation = CGFloat(pose.twist) * 0.5 + wobble
        underHead.zRotation = head.zRotation
        body.zRotation = 0.04 + CGFloat(pose.twist) * 0.35
        leg.zRotation = 0.1
        lower.zRotation = -CGFloat(pose.jaw) * 0.62
        throat.yScale = max(0.02, CGFloat(pose.jaw))
        lower.alpha = 1
        throat.alpha = 1
        // Eyes: back over the shoulder at the players (−x in the rig while facing away), or swirling when dizzy.
        let look: CGFloat, lookY: CGFloat
        if pose.dizzy > 0 {
            look = CGFloat(cos(pose.dizzy)) * 6
            lookY = CGFloat(sin(pose.dizzy)) * 6
        } else {
            look = CGFloat(pose.look) * 7 * (turn < 0 ? -1 : 1)
            lookY = 0
        }
        eye.apply(lid: pose.lid, pupil: pose.dizzy > 0 ? 0.6 : 0.25, look: look, anger: 0, lookY: lookY)
        brow.zRotation = 0.18   // raised: sly, not angry (the ram's brow is lowered)
        collar.position = CGPoint(x: hip.x + away * 0.6 * ppu, y: waterY + 2)
        collar.zPosition = z - 0.02
        collar.size = CGSize(width: 1.6 * ppu, height: 0.2 * ppu)
        collar.alpha = CGFloat(min(1, pose.rise)) * 0.6
    }

    /// 0 hidden … 0.5 closed smug curve … 1 teeth bared (the head must be lifted for it to clear the water).
    private func setMouth(grin: Double) {
        frontMouth.texture = Art.crocMouthFrames[grin > 0.75 ? 1 : 0]
        frontMouth.alpha = CGFloat(smoothstepD(0.15, 0.4, grin))
    }

    /// Tail sweep, head-on: floating off the bow corner facing the players; eyes track them with a sly, heavy lid,
    /// the head yaws with the whip, and afterwards the pupils swirl (dizzy) or settle on them (pleased).
    func applySweepHead(_ pose: TailPose, waterPoint: CGPoint, ppu: CGFloat, z: CGFloat, towardPlayers: CGFloat,
                        now: Double, reduceMotion: Bool) {
        side.isHidden = true
        underCrop.isHidden = true
        front.isHidden = pose.rise <= 0.01
        crop.position = waterPoint
        crop.zPosition = z
        let scale = ppu * 1.25 / 300
        front.setScale(scale)
        let bob = reduceMotion ? 0 : CGFloat(sin(now * 2.2)) * 6 * scale
        // Expressions need the mouth above the water: the head lifts a little as it grins.
        let grin = min(1, pose.jaw * 2.2)
        front.position = CGPoint(x: 0, y: CGFloat(pose.rise - 1 + 0.42 * grin) * 110 * scale + bob)
        setMouth(grin: grin)
        let wobble = reduceMotion || pose.dizzy == 0 ? 0 : CGFloat(sin(pose.dizzy * 1.3)) * 0.1
        front.zRotation = reduceMotion ? 0 : CGFloat(pose.twist) * towardPlayers * 0.8 + wobble
        for (i, e) in frontEyes.enumerated() {
            if pose.dizzy > 0 {
                // Swirling pupils, slightly out of step: properly dizzy.
                let a = pose.dizzy + Double(i) * 0.9
                e.apply(lid: pose.lid, pupil: 0.7, look: CGFloat(cos(a)) * 7, anger: 0, lookY: CGFloat(sin(a)) * 7)
            } else {
                e.apply(lid: pose.lid, pupil: 0.3, look: CGFloat(pose.look) * -towardPlayers * 6, anger: 0, lookY: -2)
            }
        }
        collar.position = CGPoint(x: waterPoint.x, y: waterPoint.y + 2)
        collar.zPosition = grin > 0.2 ? z - 0.05 : z + 0.1
        collar.size = CGSize(width: 1.2 * ppu, height: 0.22 * ppu)
        collar.alpha = CGFloat(max(0, min(1, (pose.rise + 0.2) / 0.6))) * 0.85
    }

    func hideBody() {
        side.isHidden = true
        front.isHidden = true
        underCrop.isHidden = true
        collar.alpha = 0
    }

    /// Submerged silhouette in the water plane (lurking and leaving).
    func applyShadow(at point: CGPoint, ppu: CGFloat, alpha: Double, heading: CGFloat) {
        shadow.position = point
        shadow.zPosition = Layer.floor + 1
        let s = ppu * 1.9 / 460
        shadow.xScale = s
        shadow.yScale = s * 0.42   // lying in the water plane, foreshortened
        shadow.zRotation = heading
        shadow.alpha = CGFloat(alpha)
    }
}

/// A croc eye: sclera + iris, slit pupil that dilates, a lid that slides down from the top, and a fixed glint.
@MainActor
final class CrocEye {
    let root = SKNode()
    private let ball = SKSpriteNode(texture: Art.crocEye)
    private let pupil = SKSpriteNode(texture: Art.crocPupil)
    private let glint = SKSpriteNode(texture: Art.crocGlint)
    private let lid = SKSpriteNode(texture: Art.crocLid)

    init() {
        root.addChild(ball)
        pupil.zPosition = 0.01
        root.addChild(pupil)
        glint.zPosition = 0.015
        glint.position = CGPoint(x: -9, y: 10)
        glint.setScale(0.7)
        root.addChild(glint)
        lid.anchorPoint = CGPoint(x: 0.5, y: 1)
        lid.position = CGPoint(x: 0, y: 34)
        lid.zPosition = 0.02
        root.addChild(lid)
    }

    /// lid 0 open … 1 shut; pupil 0 slit … 1 dilated; look: pupil x offset; anger tilts the lid line down-forward.
    func apply(lid lidAmount: Double, pupil dilation: Double, look: CGFloat, anger: CGFloat, lookY: CGFloat = 0) {
        pupil.xScale = 0.55 + 1.6 * CGFloat(dilation)
        pupil.position = CGPoint(x: look, y: lookY)
        let heavy = 0.18 + 0.82 * CGFloat(lidAmount)
        lid.yScale = heavy
        lid.zRotation = -anger * 0.18
        glint.alpha = lidAmount > 0.7 ? 0 : 1
    }
}

/// One macaw in a flock: texture per pose, banked and tumbling procedurally.
@MainActor
final class BirdRig {
    let node: SKSpriteNode
    /// A soft shadow that sweeps across the deck as the bird flies over the raft.
    let shadow = SKSpriteNode(texture: Art.glow)
    let traits: BirdTraits

    init(traits: BirdTraits) {
        self.traits = traits
        node = SKSpriteNode(texture: Art.macawTexture(.glide, palette: traits.palette))
        node.anchorPoint = Art.macawAnchor
        shadow.color = .black
        shadow.colorBlendFactor = 1
        shadow.alpha = 0
    }

    /// `close`: 0 … 1 as the bird reaches the camera — a slight stretch along its path sells the speed of the flyby.
    func apply(_ sample: BirdSample, position: CGPoint, ppu: CGFloat, reduceMotion: Bool, close: CGFloat = 0) {
        node.texture = Art.macawTexture(sample.pose, palette: traits.palette)
        // Bird ≈ 1.0 unit wingspan at its size; slight vertical stretch on the downstroke (≤ 4%).
        let scale = ppu * 1.0 / Art.macawCanvas.width * CGFloat(traits.size)
        var stretch: CGFloat = 1
        if case .flap(let s) = sample.pose { stretch = 1 + 0.04 * CGFloat(sin(.pi * min(1, s / 0.5))) * (s < 0.5 ? 1 : 0) }
        let flyby = reduceMotion ? 0 : close
        node.xScale = scale * (1 - 0.06 * flyby)
        node.yScale = scale * stretch * (1 + 0.16 * flyby)
        node.position = CGPoint(x: position.x, y: position.y + CGFloat(sample.bob) * ppu)
        node.zRotation = reduceMotion ? CGFloat(sample.spin) : CGFloat(sample.bank + sample.spin)
        node.alpha = CGFloat(sample.alpha)
    }
}
