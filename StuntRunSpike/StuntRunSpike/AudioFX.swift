import AVFoundation

/// Tiny procedural SFX kit: buffers are synthesized once at launch, played through a fixed pool of
/// voices on one SFX bus. No audio files, no microphone, no recording.
final class AudioFX {
    enum Sound: CaseIterable {
        case tick, whoosh, lock, chime, pop, team, bonk, turbo, impact, shatter, caw, splash, creak, growl, chomp, gurgle, hiss, flutter, rumble, knock, roll, swish, slap
        case boil, leap, snap, hop, land, nip
        case siren, zap, beamOn, doorSlam, alarmOff
        case thrust, touchdown
        case countBeep, launchRoar, overtake, phaseUp, sprintHorn, victory
        case servo, clunk, hydraulic, droneChirp
        case laserWarn, deploy, chargeHigh, chargeLow, ignite, passBy, powerDown, sweepScan, comboStep
    }

    private let engine = AVAudioEngine()
    private let sfxBus = AVAudioMixerNode()
    private var voices: [AVAudioPlayerNode] = []
    private var nextVoice = 0
    private var buffers: [Sound: [AVAudioPCMBuffer]] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    var isMuted = false {
        didSet { ambience.volume = isMuted ? 0 : Self.gain(dB: -20) }
    }
    /// Looping jungle bed (insects, distant birds, water), on its own voice under the SFX.
    private let ambience = AVAudioPlayerNode()
    private var ambienceBuffer: AVAudioPCMBuffer?
    // Adaptive music (Moonbound): four sample-locked stems on their own bus, crossfaded by gameplay intensity, plus a
    // looping engine roar. Vertical layering: the arrangement thickens as the race heats up.
    private let musicBus = AVAudioMixerNode()
    private var stems: [AVAudioPlayerNode] = []
    private var stemLevels: [Float] = [0, 0, 0, 0]
    private var stemTargets: [Float] = [0, 0, 0, 0]
    private let engineLoop = AVAudioPlayerNode()
    private var engineLevel: Float = 0
    private var duckUntil: TimeInterval = 0
    private(set) var musicPlaying = false
    /// Laser hums (one per beam height, distinct timbres), looping at zero volume until a beam is live.
    private let humHigh = AVAudioPlayerNode()
    private let humLow = AVAudioPlayerNode()
    private var humsStarted = false
    private var humLevels: (high: Float, low: Float) = (0, 0)

    init() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)

        engine.attach(sfxBus)
        engine.connect(sfxBus, to: engine.mainMixerNode, format: format)
        for _ in 0..<10 {
            let voice = AVAudioPlayerNode()
            engine.attach(voice)
            engine.connect(voice, to: sfxBus, format: format)
            voices.append(voice)
        }
        engine.attach(ambience)
        engine.connect(ambience, to: sfxBus, format: format)
        engine.attach(musicBus)
        engine.connect(musicBus, to: engine.mainMixerNode, format: format)
        for _ in 0..<4 {
            let stem = AVAudioPlayerNode()
            engine.attach(stem)
            engine.connect(stem, to: musicBus, format: format)
            stem.volume = 0
            stems.append(stem)
        }
        engine.attach(engineLoop)
        engine.connect(engineLoop, to: sfxBus, format: format)
        engineLoop.volume = 0
        for hum in [humHigh, humLow] {
            engine.attach(hum)
            engine.connect(hum, to: sfxBus, format: format)
            hum.volume = 0
        }
        musicBus.outputVolume = Self.gain(dB: -9)
        // Headroom: the bus sits at -4 dB so stacked team effects do not clip.
        sfxBus.outputVolume = Self.gain(dB: -4)
        synthesizeAll()
        do {
            try engine.start()
            voices.forEach { $0.play() }
        } catch {
            print("[Audio] engine failed to start: \(error)")
        }
    }

    func startAmbience() {
        guard engine.isRunning else { return }
        if ambienceBuffer == nil { ambienceBuffer = makeAmbience() }
        guard let buffer = ambienceBuffer else { return }
        ambience.volume = isMuted ? 0 : Self.gain(dB: -20)
        ambience.scheduleBuffer(buffer, at: nil, options: [.loops, .interrupts])
        ambience.play()
    }

    func stopAmbience() { ambience.stop(); stopMusic() }

    // MARK: - Adaptive music

    enum MusicStyle { case moon, heist }
    private var musicBuffers: [AVAudioPCMBuffer]?
    private var musicStyle: MusicStyle = .moon
    private var engineBuffer: AVAudioPCMBuffer?

    /// Starts the four stems together (sample-locked to one start time) and the engine loop. The stems are
    /// synthesized once (~0.1 s) at mode start, before the countdown.
    func startMusic(style: MusicStyle = .moon) {
        guard engine.isRunning, !musicPlaying else { return }
        musicPlaying = true
        if musicBuffers == nil || musicStyle != style { musicBuffers = style == .heist ? makeHeistStems() : makeMusicStems(); musicStyle = style }
        if engineBuffer == nil { engineBuffer = makeEngineLoop() }
        guard let buffers = musicBuffers, let roar = engineBuffer else { return }
        let start = AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.15))
        for (stem, buffer) in zip(stems, buffers) {
            stem.scheduleBuffer(buffer, at: nil, options: [.loops])
            stem.play(at: start)
        }
        engineLoop.scheduleBuffer(roar, at: nil, options: [.loops])
        engineLoop.play()
    }

    func stopMusic() {
        musicPlaying = false
        stems.forEach { $0.stop() }
        engineLoop.stop()
    }

    /// Per frame. `intensity` 0 … 1 (speed + race heat) thickens the drive layer; `close` brings in the arpeggio;
    /// `sprint` the final-sprint layer; `engine` 0 … 1 the roar. Levels glide (no zipper noise).
    func updateMusic(dt: Double, intensity: Float, close: Bool, sprint: Bool, engine: Float, now: TimeInterval) {
        guard musicPlaying else { return }
        let duck: Float = now < duckUntil ? Self.gain(dB: -7) : 1
        let mute: Float = isMuted ? 0 : 1
        stemTargets = [0.9, min(1, 0.25 + intensity), close || intensity > 0.65 ? 0.8 : 0.1, sprint ? 1 : 0]
        let k = Float(min(1, dt * 2.5))
        for i in 0..<4 {
            stemLevels[i] += (stemTargets[i] - stemLevels[i]) * k
            stems[i].volume = stemLevels[i] * duck * mute
        }
        engineLevel += (engine - engineLevel) * Float(min(1, dt * 6))
        engineLoop.volume = Self.gain(dB: -16) * (0.25 + 0.75 * engineLevel) * mute
    }

    /// Live beam hum per height (0 … 1 each, from beam proximity and intensity). Levels glide; silent when muted.
    func setLaserHum(high: Float, low: Float, dt: Double) {
        guard engine.isRunning else { return }
        if !humsStarted, high > 0 || low > 0 {
            humsStarted = true
            humHigh.scheduleBuffer(makeHum(base: 118, buzz: 0.35), at: nil, options: [.loops])
            humLow.scheduleBuffer(makeHum(base: 74, buzz: 0.6), at: nil, options: [.loops])
            humHigh.play(); humLow.play()
        }
        let k = Float(min(1, dt * 8))
        humLevels.high += (high - humLevels.high) * k
        humLevels.low += (low - humLevels.low) * k
        let mute: Float = isMuted ? 0 : 1
        humHigh.volume = Self.gain(dB: -14) * humLevels.high * mute
        humLow.volume = Self.gain(dB: -12) * humLevels.low * mute
    }

    /// An electrical hum: a buzzy fundamental with a slow beating partial; whole cycles in 2 s so it loops cleanly.
    private func makeHum(base: Double, buzz: Double) -> AVAudioPCMBuffer {
        render(2.0) { t in
            let f = base
            let tone = sin(2 * .pi * f * t) + buzz * sin(2 * .pi * f * 3 * t) + 0.25 * sin(2 * .pi * (f * 2 + 1) * t)
            let mains = 0.15 * sin(2 * .pi * 100 * t)
            return tanh(1.6 * tone) * 0.4 * (0.8 + 0.2 * sin(2 * .pi * 3 * t)) + mains
        }
    }

    /// Dips the music under an announcement or a big stinger.
    func duckMusic(for seconds: Double, now: TimeInterval) { duckUntil = max(duckUntil, now + seconds) }

    private func makeMusicStems() -> [AVAudioPCMBuffer] {
        // 128 BPM, 4 bars of 4/4 = 7.5 s. Progression (A minor): Am – F – C – G, one chord per bar.
        let beat = 60.0 / 128, bar = beat * 4, length = bar * 4
        let roots = [110.0, 87.31, 130.81, 98.0]
        let chords: [[Double]] = [[220, 261.63, 329.63], [174.61, 220, 261.63], [261.63, 329.63, 392], [196, 246.94, 293.66]]
        func chordIndex(_ t: Double) -> Int { min(3, Int(t / bar)) }
        // Base: kick on every beat + a gliding saw bass (8ths).
        let base = render(length) { t in
            let bt = t.truncatingRemainder(dividingBy: beat)
            let kick = sin(2 * .pi * (48 + 110 * exp(-bt * 30)) * bt) * exp(-bt * 9) * 0.9
            let f = roots[chordIndex(t)] / 2
            let et = t.truncatingRemainder(dividingBy: beat / 2)
            let phase = (f * t).truncatingRemainder(dividingBy: 1)
            let bass = (2 * phase - 1) * 0.35 * exp(-et * 5) * min(1, et * 80)
            return kick + bass
        }
        // Drive: off-beat hats + snare on 2 and 4.
        var noise = SeededGenerator(seed: 11)
        let drive = render(length) { t in
            let ht = t.truncatingRemainder(dividingBy: beat / 2)
            let hat = (noise.next() * 2 - 1) * exp(-ht * 70) * 0.28 * (Int(t / (beat / 2)) % 2 == 1 ? 1 : 0.4)
            let bt = t.truncatingRemainder(dividingBy: beat * 2)
            let snare = bt > beat ? ((noise.next() * 2 - 1) * 0.5 + sin(2 * .pi * 190 * (bt - beat)) * 0.4) * exp(-(bt - beat) * 14) : 0
            return hat + snare * 0.8
        }
        // Lead: a bright 16th-note arpeggio over the chord.
        let lead = render(length) { t in
            let s = beat / 4
            let n = Int(t / s)
            let chord = chords[chordIndex(t)]
            let f = chord[n % 3] * (n % 8 >= 6 ? 2 : 1)
            let lt = t.truncatingRemainder(dividingBy: s)
            let sq = sin(2 * .pi * f * t) + 0.3 * sin(2 * .pi * f * 3 * t)
            return sq * exp(-lt * 18) * 0.22
        }
        // Sprint: 16th hats, a bass octave stab and a rising riser across the loop.
        var noise2 = SeededGenerator(seed: 23)
        let sprint = render(length) { t in
            let s = beat / 4
            let ht = t.truncatingRemainder(dividingBy: s)
            let hat = (noise2.next() * 2 - 1) * exp(-ht * 90) * 0.22
            let f = roots[chordIndex(t)]
            let bt = t.truncatingRemainder(dividingBy: beat)
            let stab = sin(2 * .pi * f * t) * exp(-bt * 7) * 0.25
            let x = t.truncatingRemainder(dividingBy: bar) / bar
            let riser = sin(2 * .pi * (400 + 900 * x) * t) * 0.05 * x
            return hat + stab + riser
        }
        return [base, drive, lead, sprint]
    }

    /// Heist score: 112 BPM, E minor (Em – C – Am – B), a walking bass and rim clicks under a minor spy riff.
    /// Stems: base (bass + kick), drive (hats + rim), lead (the riff), sprint (driving 16ths + brass-like stabs).
    private func makeHeistStems() -> [AVAudioPCMBuffer] {
        let beat = 60.0 / 112, bar = beat * 4, length = bar * 4
        let roots = [82.41, 65.41, 110.0, 61.74]
        func chordIndex(_ t: Double) -> Int { min(3, Int(t / bar)) }
        let walk = [1.0, 1.5, 2.0, 1.5]
        let base = render(length) { t in
            let bt = t.truncatingRemainder(dividingBy: beat)
            let kick = Int(t / beat) % 2 == 0 ? sin(2 * .pi * (45 + 100 * exp(-bt * 32)) * bt) * exp(-bt * 10) * 0.85 : 0
            let step = Int(t / (beat / 2)) % 4
            let f = roots[chordIndex(t)] * walk[step]
            let et = t.truncatingRemainder(dividingBy: beat / 2)
            let bass = (sin(2 * .pi * f * t) + 0.35 * sin(2 * .pi * f * 2 * t)) * exp(-et * 6) * 0.4 * min(1, et * 90)
            return kick + bass
        }
        var noise = SeededGenerator(seed: 41)
        let drive = render(length) { t in
            let ht = t.truncatingRemainder(dividingBy: beat / 2)
            let hat = (noise.next() * 2 - 1) * exp(-ht * 80) * 0.22
            let rt = t.truncatingRemainder(dividingBy: beat * 2)
            let rim = rt > beat ? sin(2 * .pi * 1700 * (rt - beat)) * exp(-(rt - beat) * 60) * 0.35 : 0
            return hat + rim
        }
        // A sly minor riff (E minor pentatonic with a chromatic step), one phrase per bar.
        let riff: [Double] = [329.63, 392.0, 369.99, 329.63, 293.66, 329.63, 0, 246.94]
        let lead = render(length) { t in
            let s = beat / 2
            let n = Int(t / s) % riff.count
            let f = riff[n] * (chordIndex(t) == 3 ? 1.06 : 1)
            guard f > 0 else { return 0 }
            let lt = t.truncatingRemainder(dividingBy: s)
            let tone = sin(2 * .pi * f * t + 0.8 * sin(2 * .pi * f * 2 * t))
            return tone * exp(-lt * 7) * 0.2 * min(1, lt * 120)
        }
        var noise2 = SeededGenerator(seed: 59)
        let sprint = render(length) { t in
            let s = beat / 4
            let ht = t.truncatingRemainder(dividingBy: s)
            let hat = (noise2.next() * 2 - 1) * exp(-ht * 95) * 0.2
            let f = roots[chordIndex(t)] * 4
            let bt = t.truncatingRemainder(dividingBy: beat)
            let saw = 2 * ((f * t).truncatingRemainder(dividingBy: 1)) - 1
            let stab = Int(t / beat) % 4 == 3 ? tanh(2 * saw) * exp(-bt * 9) * 0.18 : 0
            return hat + stab
        }
        return [base, drive, lead, sprint]
    }

    private func makeEngineLoop() -> AVAudioPCMBuffer {
        var low = 0.0, lower = 0.0
        var rng = SeededGenerator(seed: 5)
        return render(2.0) { t in
            low += ((rng.next() * 2 - 1) - low) * 0.08
            lower += (low - lower) * 0.25
            let throb = 0.75 + 0.25 * sin(2 * .pi * 11 * t)
            // Fade the loop's ends into each other so it never clicks.
            let edge = min(1, min(t, 2 - t) / 0.05)
            return (lower * 3.0 * throb + sin(2 * .pi * 42 * t) * 0.15) * edge
        }
    }

    private func makeAmbience() -> AVAudioPCMBuffer {
        var rng = SeededGenerator(seed: 99)
        let chirps = (0..<14).map { _ in (at: rng.next() * 7.6, f: 2200 + rng.next() * 2200, len: 0.06 + rng.next() * 0.12, sweep: rng.next() < 0.5 ? 1.0 : -1.0) }
        var water = 0.0
        return render(8.0) { t in
            // Insects: a high buzz, slowly swelling (loop-safe: whole cycles in 8 s).
            let insects = sin(2 * .pi * 4600 * t) * (0.5 + 0.5 * sin(2 * .pi * 0.25 * t)) * (0.5 + 0.5 * sin(2 * .pi * 31 * t)) * 0.05
            var birds = 0.0
            for c in chirps where t >= c.at && t < c.at + c.len * 3 {
                let lt = t - c.at
                let f = c.f * (1 + c.sweep * 0.25 * lt / c.len)
                birds += sin(2 * .pi * f * lt) * exp(-lt / c.len * 2) * 0.12
            }
            water += (Double.random(in: -1...1) - water) * 0.03
            return insects + birds + water * 0.5
        }
    }

    /// `variant`: a specific pitch variant (e.g. a rising step in a combo); random when nil.
    func play(_ sound: Sound, dB: Float = 0, variant: Int? = nil) {
        guard !isMuted, engine.isRunning, let set = buffers[sound], !set.isEmpty else { return }
        let buffer = variant.map { set[min(max(0, $0), set.count - 1)] } ?? set.randomElement()!
        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        voice.volume = Self.gain(dB: dB)
        voice.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !voice.isPlaying { voice.play() }
    }

    private static func gain(dB: Float) -> Float { pow(10, dB / 20) }

    // MARK: - Synthesis

    private func synthesizeAll() {
        // Small pitch variation on repeated sounds keeps them from sounding mechanical.
        buffers[.tick] = [1.0, 1.06].map { p in render(0.07) { t in sin(2 * .pi * 1650 * p * t) * exp(-t * 55) * 0.5 } }
        buffers[.lock] = [1.0].map { _ in
            render(0.3) { t in (sin(2 * .pi * 660 * t) + 0.6 * sin(2 * .pi * 990 * t)) * exp(-t * 16) * 0.45 }
        }
        buffers[.whoosh] = [0.9, 1.0, 1.1].map { p in whoosh(duration: 0.36, brightness: p) }
        buffers[.chime] = [1.0, 1.0595, 0.9439].map { p in
            render(0.6) { t in
                let notes: [(Double, Double)] = [(1318.5, 0), (1975.5, 0.07)]
                return notes.reduce(0) { sum, note in
                    let lt = t - note.1
                    guard lt >= 0 else { return sum }
                    let f = note.0 * p
                    return sum + (sin(2 * .pi * f * lt) + 0.3 * sin(2 * .pi * f * 2.01 * lt)) * exp(-lt * 6.5) * 0.32
                }
            }
        }
        buffers[.pop] = [1.0, 1.12, 0.9].map { p in
            var phase = 0.0
            return render(0.13) { t in
                let f = (300 + 650 * exp(-t * 30)) * p
                phase += 2 * .pi * f / 44_100
                return sin(phase) * exp(-t * 24) * 0.55
            }
        }
        buffers[.team] = [render(1.4) { t in
            let chord = [523.25, 659.25, 783.99, 1046.5]
            let attack = min(1, t / 0.015)
            var v = chord.reduce(0) { $0 + tanh(1.6 * sin(2 * .pi * $1 * t)) } * 0.13 * attack * exp(-t * 2.2)
            for (i, f) in [2093.0, 2637.0, 3136.0, 4186.0].enumerated() {
                let lt = t - 0.06 * Double(i + 1)
                if lt >= 0 { v += sin(2 * .pi * f * lt) * exp(-lt * 9) * 0.12 }
            }
            return v
        }]
        buffers[.bonk] = [render(0.28) { t in
            let f = 110 + 90 * exp(-t * 18)
            return sin(2 * .pi * f * t) * exp(-t * 13) * 0.6 + (t < 0.02 ? Double.random(in: -0.3...0.3) : 0)
        }]
        // Jungle Drift.
        buffers[.caw] = [1.0, 1.12, 0.9].map { p in
            var phase = 0.0
            return render(0.45) { t in
                let squawk = t < 0.16 ? 1.0 : (t > 0.22 && t < 0.38 ? 0.8 : 0)
                let f = (980 - 900 * min(1, t / 0.45)) * p + 120 * sin(2 * .pi * 40 * t)
                phase += f / 44_100
                let saw = 2 * (phase - floor(phase + 0.5))
                return (saw * 0.5 + Double.random(in: -0.2...0.2)) * squawk * 0.4
            }
        }
        buffers[.splash] = [0.9, 1.0, 1.1].map { p in
            var low = 0.0
            return render(0.7) { t in
                low += (Double.random(in: -1...1) - low) * (0.35 * p * exp(-t * 3) + 0.04)
                let plop = t > 0.12 ? sin(2 * .pi * (380 - 200 * (t - 0.12)) * (t - 0.12)) * exp(-(t - 0.12) * 18) * 0.4 : 0
                return low * exp(-t * 4.5) * 1.2 + plop
            }
        }
        buffers[.creak] = [1.0, 0.85].map { p in
            var phase = 0.0
            return render(0.55) { t in
                let f = (95 + 40 * sin(2 * .pi * 7 * t) + 60 * t) * p
                phase += f / 44_100
                let saw = 2 * (phase - floor(phase + 0.5))
                let grain = (sin(2 * .pi * 23 * t) > 0.6 ? 1.0 : 0.4)
                return saw * grain * sin(.pi * t / 0.55) * 0.35
            }
        }
        buffers[.growl] = [1.0, 0.9].map { p in
            var low = 0.0
            return render(0.9) { t in
                low += (Double.random(in: -1...1) - low) * 0.05
                let body = sin(2 * .pi * (62 * p) * t + 3 * sin(2 * .pi * 9 * t)) * (0.6 + 0.4 * sin(2 * .pi * 11 * t))
                return (body * 0.6 + low * 0.8) * sin(.pi * t / 0.9) * 0.6
            }
        }
        // Croc performance: the snap of the jaws, bubbles while it lurks, a rising hiss as it gathers to strike.
        buffers[.chomp] = [1.0, 0.92, 1.08].map { p in
            var low = 0.0
            return render(0.3) { t in
                low += (Double.random(in: -1...1) - low) * 0.5
                let click = t < 0.012 ? Double.random(in: -1...1) : 0                        // tooth contact
                let thud = sin(2 * .pi * 95 * p * t) * exp(-t * 26) * 0.8                      // jaw mass
                let wood = t > 0.01 ? low * exp(-(t - 0.01) * 40) * 0.6 : 0                   // biting into the logs
                return click * 0.9 + thud + wood
            }
        }
        buffers[.gurgle] = [1.0, 1.15].map { p in
            var rng = SeededGenerator(seed: UInt64(p * 100))
            let pops = (0..<7).map { _ in (at: rng.next() * 0.75, f: (240 + rng.next() * 260) * p) }
            return render(0.95) { t in
                pops.reduce(0) { sum, b in
                    let lt = t - b.at
                    guard lt >= 0 else { return sum }
                    return sum + sin(2 * .pi * b.f * (1 + 2.5 * lt) * lt) * exp(-lt * 28) * 0.35   // rising "bloop"
                }
            }
        }
        buffers[.hiss] = [1.0, 0.9].map { p in
            var hp = 0.0, last = 0.0
            return render(0.6) { t in
                let white = Double.random(in: -1...1)
                hp = white - last * 0.6; last = white
                let throat = sin(2 * .pi * 70 * p * t) * 0.25
                return (hp * 0.35 + throat) * min(1, t / 0.35) * (t > 0.5 ? (0.6 - t) / 0.1 : 1)
            }
        }
        buffers[.flutter] = [1.0, 1.1, 0.9].map { p in
            var low = 0.0
            return render(0.5) { t in
                low += (Double.random(in: -1...1) - low) * 0.12 * p
                let beats = pow(max(0, sin(2 * .pi * 11 * p * t)), 3)                          // overlapping wingbeats
                return low * beats * sin(.pi * t / 0.5) * 1.6
            }
        }
        // Piranha Jump. The warning boils (fast, dense bloops: a school, not one croc), the leap is a bright
        // upward burst, the pass-by is a tiny tooth clack per lane — playful, never a scary roar.
        buffers[.boil] = [1.0, 1.12].map { p in
            var rng = SeededGenerator(seed: UInt64(p * 300))
            let pops = (0..<16).map { _ in (at: rng.next() * 1.0, f: (420 + rng.next() * 520) * p) }
            return render(1.15) { t in
                pops.reduce(0) { sum, b in
                    let lt = t - b.at
                    guard lt >= 0 else { return sum }
                    return sum + sin(2 * .pi * b.f * (1 + 3.5 * lt) * lt) * exp(-lt * 40) * 0.26
                } * min(1, t / 0.2)
            }
        }
        buffers[.leap] = [0.94, 1.0, 1.08].map { p in
            var low = 0.0
            return render(0.4) { t in
                low += (Double.random(in: -1...1) - low) * (0.5 * exp(-t * 9) + 0.05)
                let bloop = sin(2 * .pi * (300 + 900 * t) * p * t) * exp(-t * 10) * 0.45   // rising: out of the water
                return low * exp(-t * 12) * 0.9 + bloop
            }
        }
        buffers[.snap] = [1.0, 1.1, 0.92].map { p in
            render(0.12) { t in
                let clack = { (at: Double) -> Double in
                    let lt = t - at
                    guard lt >= 0 else { return 0 }
                    return sin(2 * .pi * 2600 * p * lt) * exp(-lt * 160) + Double.random(in: -1...1) * exp(-lt * 300) * 0.5
                }
                return (clack(0) + clack(0.045) * 0.8) * 0.4
            }
        }
        buffers[.hop] = [1.0, 1.1].map { p in
            var phase = 0.0
            return render(0.18) { t in
                let f = (220 + 480 * t / 0.18) * p
                phase += 2 * .pi * f / 44_100
                return sin(phase) * sin(.pi * t / 0.18) * 0.28
            }
        }
        buffers[.land] = [1.0, 0.9, 1.12].map { p in
            var low = 0.0
            return render(0.22) { t in
                low += (Double.random(in: -1...1) - low) * 0.3
                return sin(2 * .pi * 150 * p * t) * exp(-t * 30) * 0.6 + low * exp(-t * 45) * 0.4   // feet on logs
            }
        }
        buffers[.nip] = [1.0, 1.15].map { p in
            var phase = 0.0
            return render(0.3) { t in
                let f = (700 + 1400 * min(1, t / 0.12) - 900 * max(0, t - 0.12)) * p   // cartoon "nyip!"
                phase += 2 * .pi * f / 44_100
                let click = t < 0.01 ? Double.random(in: -1...1) * 0.6 : 0
                return (sin(phase) * 0.35 + click) * exp(-t * 9)
            }
        }
        // Log and tail sweeps. Rapids: a low churning roar (filtered noise with a slow swell).
        buffers[.rumble] = [1.0, 0.9].map { p in
            var low = 0.0, lower = 0.0
            return render(1.6) { t in
                low += (Double.random(in: -1...1) - low) * 0.08 * p
                lower += (low - lower) * 0.2
                let swell = sin(.pi * min(1, t / 1.6)) * (0.7 + 0.3 * sin(2 * .pi * 3 * t))
                return lower * swell * 3.2
            }
        }
        // A hollow wooden knock (log on logs): a short resonant body plus a click, with pitch variants.
        buffers[.knock] = [1.0, 0.88, 1.12].map { p in
            var phase = 0.0
            return render(0.35) { t in
                let f = (180 + 60 * exp(-t * 30)) * p
                phase += 2 * .pi * f / 44_100
                let click = t < 0.008 ? Double.random(in: -1...1) * 0.7 : 0
                return (sin(phase) + 0.4 * sin(phase * 2.76)) * exp(-t * 16) * 0.6 + click
            }
        }
        // Rolling: low rumble with irregular wooden clatter (the bark hitting the deck as it turns).
        buffers[.roll] = [1.0, 1.1].map { p in
            var low = 0.0
            var rng = SeededGenerator(seed: UInt64(p * 50))
            let hits = (0..<9).map { _ in rng.next() * 0.75 }
            return render(0.85) { t in
                low += (Double.random(in: -1...1) - low) * 0.06
                var v = low * 1.6 * sin(.pi * t / 0.85)
                for h in hits where t >= h && t < h + 0.05 { v += sin(2 * .pi * 210 * p * (t - h)) * exp(-(t - h) * 70) * 0.5 }
                return v
            }
        }
        // The tail whip: a heavy, rising swoosh (deeper and longer than the bird whoosh).
        buffers[.swish] = [1.0, 0.92].map { p in
            var low = 0.0
            return render(0.55) { t in
                let x = t / 0.55
                low += (Double.random(in: -1...1) - low) * (0.03 + 0.25 * x * x) * p
                return low * pow(sin(.pi * min(1, x * 1.15)), 2) * 1.3
            }
        }
        // A wet slap (tail on water, or across the shins: cartoon, not pain).
        buffers[.slap] = [1.0, 1.15, 0.9].map { p in
            var low = 0.0
            return render(0.3) { t in
                low += (Double.random(in: -1...1) - low) * 0.5
                let body = sin(2 * .pi * 140 * p * t) * exp(-t * 30)
                return (low * exp(-t * 28) * 0.9 + body * 0.5)
            }
        }
        // Laser Breakout. A playful two-tone heist siren (never a harsh emergency wail), an electric zap, the hum of
        // emitters charging, a heavy blast-door slam and a falling "all clear" when the alarm shuts off.
        buffers[.siren] = [render(1.3) { t in
            let f = (t.truncatingRemainder(dividingBy: 0.5) < 0.25) ? 880.0 : 660.0
            let tone = sin(2 * .pi * f * t) + 0.35 * sin(2 * .pi * f * 2 * t)
            return tanh(1.4 * tone) * 0.22 * min(1, t / 0.03) * min(1, (1.3 - t) / 0.15)
        }]
        buffers[.zap] = [1.0, 1.12, 0.9].map { p in
            var phase = 0.0
            return render(0.28) { t in
                let f = (1800 - 1500 * min(1, t / 0.25)) * p
                phase += f / 44_100
                let saw = 2 * (phase - floor(phase + 0.5))
                let crackle = Double.random(in: -1...1) * (sin(2 * .pi * 60 * t) > 0.3 ? 0.5 : 0.1)
                return (saw * 0.45 + crackle * 0.35) * exp(-t * 9)
            }
        }
        buffers[.beamOn] = [1.0, 1.06].map { p in
            render(0.55) { t in
                let f = (220 + 520 * min(1, t / 0.45)) * p
                let hum = sin(2 * .pi * f * t) * 0.5 + sin(2 * .pi * 120 * t) * 0.2
                return hum * min(1, t / 0.08) * (t > 0.45 ? max(0, (0.55 - t) / 0.1) : 1) * 0.3
            }
        }
        buffers[.doorSlam] = [1.0, 0.9].map { p in
            var low = 0.0
            return render(0.9) { t in
                low += (Double.random(in: -1...1) - low) * 0.12
                let boom = sin(2 * .pi * (55 + 40 * exp(-t * 20)) * p * t) * exp(-t * 5)
                let clang = sin(2 * .pi * 410 * p * t) * exp(-t * 14) * 0.25 + sin(2 * .pi * 633 * p * t) * exp(-t * 18) * 0.15
                return boom * 0.75 + clang + low * exp(-t * 12) * 0.6
            }
        }
        buffers[.alarmOff] = [render(0.9) { t in
            let f = 880 - 440 * min(1, t / 0.6)
            return sin(2 * .pi * f * t) * exp(-t * 3) * 0.3 * min(1, t / 0.02)
        }]
        // Moonbound. Thrust: a punchy ignition crack into a rising roar (filtered noise + a low rumble) — one per rep,
        // with variants so steady squatting never sounds mechanical. Touchdown: a soft heavy thump with a dusty hiss.
        buffers[.thrust] = [0.92, 1.0, 1.08].map { p in
            var low = 0.0, lower = 0.0
            return render(0.8) { t in
                low += (Double.random(in: -1...1) - low) * (0.25 * p * exp(-t * 3) + 0.05)
                lower += (low - lower) * 0.3
                let crack = t < 0.02 ? Double.random(in: -1...1) * (1 - t / 0.02) : 0
                let rumble = sin(2 * .pi * (48 + 30 * t) * p * t) * 0.5
                let swell = min(1, t / 0.04) * exp(-t * 3.2)
                return (lower * 2.6 + rumble) * swell + crack * 0.7
            }
        }
        buffers[.touchdown] = [render(1.0) { t in
            var v = sin(2 * .pi * (60 + 30 * exp(-t * 14)) * t) * exp(-t * 6) * 0.8
            v += Double.random(in: -1...1) * exp(-t * 4) * 0.18 * min(1, t / 0.05)
            return v
        }]
        // Moonbound race stingers.
        buffers[.countBeep] = [render(0.25) { t in sin(2 * .pi * 880 * t) * exp(-t * 14) * 0.5 }]
        buffers[.launchRoar] = [render(2.4) { t in
            var v = sin(2 * .pi * (38 + 20 * t) * t) * 0.6 * min(1, t / 0.05) * exp(-t * 0.8)
            v += Double.random(in: -1...1) * 0.35 * exp(-t * 0.9) * min(1, t / 0.02)
            return v
        }]
        buffers[.overtake] = [1.0, 1.06].map { p in
            var low = 0.0
            return render(0.9) { t in
                let x = t / 0.9
                low += (Double.random(in: -1...1) - low) * (0.05 + 0.3 * x) * p
                let sweep = low * sin(.pi * x) * 0.9
                let stab = t > 0.32 ? [523.25, 659.25, 783.99].reduce(0) { $0 + sin(2 * .pi * $1 * p * (t - 0.32)) } * exp(-(t - 0.32) * 5) * 0.16 : 0
                return sweep + stab
            }
        }
        buffers[.phaseUp] = [render(1.0) { t in
            [523.25, 659.25, 783.99, 1046.5].enumerated().reduce(0.0) { sum, n in
                let lt = t - Double(n.offset) * 0.09
                return lt < 0 ? sum : sum + sin(2 * .pi * n.element * lt) * exp(-lt * 4) * 0.18
            }
        }]
        buffers[.sprintHorn] = [render(1.2) { t in
            let f = 220 + 220 * min(1, t / 0.5)
            let saw = 2 * ((f * t).truncatingRemainder(dividingBy: 1)) - 1
            return tanh(1.5 * saw) * 0.25 * min(1, t / 0.03) * (t > 0.9 ? max(0, (1.2 - t) / 0.3) : 1)
        }]
        buffers[.victory] = [render(2.6) { t in
            let notes: [(Double, Double)] = [(523.25, 0), (659.25, 0.16), (783.99, 0.32), (1046.5, 0.5), (1318.5, 0.5), (783.99, 0.5)]
            return notes.reduce(0.0) { sum, n in
                let lt = t - n.1
                guard lt >= 0 else { return sum }
                let env = n.1 < 0.5 ? exp(-lt * 6) : exp(-lt * 1.6)
                return sum + (sin(2 * .pi * n.0 * lt) + 0.3 * sin(2 * .pi * n.0 * 2 * lt)) * env * 0.15
            }
        }]
        // Heist mechanisms: a servo whine (emitters deploying), a heavy lever/lock clunk, the lockdown gate's
        // hydraulic hiss-and-rumble, and the drone's little two-note chirp (its mood, not a threat).
        buffers[.servo] = [1.0, 1.08].map { p in
            render(0.5) { t in
                let f = (300 + 500 * min(1, t / 0.35)) * p
                let whine = sin(2 * .pi * f * t) * 0.25 + sin(2 * .pi * f * 2.01 * t) * 0.08
                return whine * min(1, t / 0.03) * (t > 0.38 ? max(0, (0.5 - t) / 0.12) : 1)
            }
        }
        buffers[.clunk] = [1.0, 0.9, 1.1].map { p in
            var low = 0.0
            return render(0.4) { t in
                low += (Double.random(in: -1...1) - low) * 0.4
                let body = sin(2 * .pi * (90 + 60 * exp(-t * 30)) * p * t) * exp(-t * 14)
                let ring = sin(2 * .pi * 740 * p * t) * exp(-t * 30) * 0.2
                return body * 0.8 + ring + low * exp(-t * 50) * 0.5
            }
        }
        buffers[.hydraulic] = [render(1.8) { t in
            var v = Double.random(in: -1...1) * 0.3 * exp(-t * 1.6) * min(1, t / 0.05)
            v += sin(2 * .pi * (40 + 12 * t) * t) * 0.45 * min(1, t / 0.3) * exp(-t * 0.9)
            return v
        }]
        buffers[.droneChirp] = [1.0, 1.12].map { p in
            render(0.3) { t in
                let f = (t < 0.12 ? 1400 : 1050) * p
                return sin(2 * .pi * f * t) * 0.22 * exp(-(t.truncatingRemainder(dividingBy: 0.12)) * 18)
            }
        }
        // Laser lifecycle: warning beep → deploy (latch + motor) → charge (rising whine; the high beam's is brighter
        // than the low beam's) → ignition (snap + fizz) → pass-by (doppler zap) → power-down (falling whine);
        // the sweep's scanning warble and the combo's step beep.
        buffers[.laserWarn] = [
            render(0.42) { t in
                let on = t < 0.12 || (t > 0.2 && t < 0.32)
                let f = t < 0.16 ? 1560.0 : 1170.0
                return on ? sin(2 * .pi * f * t) * 0.28 * (0.6 + 0.4 * sin(2 * .pi * 2 * f * t)) : 0
            },
            // Later pulses / steps: three quick rising blips.
            render(0.4) { t in
                let k = Int(t / 0.12), lt = t - Double(k) * 0.12
                guard k < 3, lt < 0.08 else { return 0 }
                let f = [1560.0, 1860.0, 2090.0][k]
                return sin(2 * .pi * f * t) * 0.26 * min(1, lt / 0.005) * min(1, (0.08 - lt) / 0.01)
            },
        ]
        buffers[.deploy] = [1.0, 0.94].map { p in
            var low = 0.0
            var phase = 0.0
            return render(0.55) { t in
                low += (Double.random(in: -1...1) - low) * 0.5
                let latch = low * exp(-t * 60) * 0.7 + sin(2 * .pi * 1900 * p * t) * exp(-t * 45) * 0.2
                let mt = max(0, t - 0.06)
                phase += (180 + 260 * min(1, mt / 0.35)) * p / 44_100
                let motor = (2 * (phase - floor(phase + 0.5))) * 0.16 * min(1, mt / 0.04) * (mt > 0.38 ? max(0, (0.49 - mt) / 0.11) : 1) * (t > 0.06 ? 1 : 0)
                let settle = t > 0.47 ? sin(2 * .pi * 120 * p * t) * exp(-(t - 0.47) * 30) * 0.4 : 0
                return latch + motor + settle
            }
        }
        for (sound, base) in [(Sound.chargeHigh, 520.0), (.chargeLow, 260.0)] {
            buffers[sound] = [1.0, 1.04].map { p in
                var phase = 0.0
                return render(0.75) { t in
                    let f = base * p * (1 + 2.2 * pow(t / 0.75, 1.6))
                    phase += f / 44_100
                    let tone = sin(2 * .pi * phase) + 0.3 * sin(4 * .pi * phase)
                    let tremolo = 0.7 + 0.3 * sin(2 * .pi * (8 + 30 * t) * t)
                    return tone * tremolo * 0.22 * min(1, t / 0.1) * min(1, (0.75 - t) / 0.04)
                }
            }
        }
        buffers[.ignite] = [1.0, 1.1].map { p in
            var low = 0.0
            return render(0.4) { t in
                low += (Double.random(in: -1...1) - low) * 0.6
                let snap = low * exp(-t * 40) * 0.8
                let body = sin(2 * .pi * (240 - 120 * min(1, t / 0.2)) * p * t) * exp(-t * 8) * 0.4
                let fizz = Double.random(in: -1...1) * 0.12 * exp(-t * 6) * (sin(2 * .pi * 90 * t) > 0 ? 1 : 0.3)
                return snap + body + fizz
            }
        }
        buffers[.passBy] = [0.95, 1.05].map { p in
            var phase = 0.0
            var low = 0.0
            return render(0.5) { t in
                let x = t / 0.5
                let f = (900 - 520 * x) * p          // falls as it passes (doppler)
                phase += f / 44_100
                low += (Double.random(in: -1...1) - low) * 0.15
                let env = pow(sin(.pi * min(1, x * 1.6)), 2) * (x < 0.62 ? 1 : max(0, (1 - x) / 0.38))
                return (2 * (phase - floor(phase + 0.5)) * 0.18 + low * 0.5) * env
            }
        }
        buffers[.powerDown] = [1.0].map { _ in
            var phase = 0.0
            return render(0.6) { t in
                phase += (700 * exp(-t * 4.5) + 40) / 44_100
                return sin(2 * .pi * phase) * 0.24 * exp(-t * 3) * min(1, t / 0.02)
            }
        }
        buffers[.sweepScan] = [1.0].map { _ in
            var phase = 0.0
            return render(1.2) { t in
                phase += (430 + 160 * sin(2 * .pi * 2.5 * t)) / 44_100
                return sin(2 * .pi * phase) * 0.18 * min(1, t / 0.1) * min(1, (1.2 - t) / 0.15)
            }
        }
        buffers[.comboStep] = [1.0, 1.122, 1.26].map { p in
            render(0.16) { t in (sin(2 * .pi * 988 * p * t) + 0.4 * sin(2 * .pi * 1976 * p * t)) * exp(-t * 22) * 0.3 }
        }
        // Hero TEAM DUCK layers. Three seeded variants each so repeated successes never sound identical.
        buffers[.impact] = [0.92, 1.0, 1.08].map { p in
            var low = 0.0
            var phase = 0.0
            return render(0.42) { t in
                let f = (42 + 70 * exp(-t * 22)) * p
                phase += 2 * .pi * f / 44_100
                low += (Double.random(in: -1...1) - low) * 0.18
                let body = sin(phase) * exp(-t * 9) * 0.9
                let crunch = t < 0.06 ? low * (1 - t / 0.06) * 1.4 : 0
                return body + crunch
            }
        }
        buffers[.shatter] = [11, 23, 37].map { (seed: UInt64) in
            var rng = SeededGenerator(seed: seed)
            let pings = (0..<10).map { _ in (freq: 2200 + rng.next() * 3000, at: rng.next() * 0.18, gain: 0.4 + rng.next() * 0.5) }
            var hiss = 0.0, last = 0.0
            return render(0.5) { t in
                var v = 0.0
                for ping in pings where t >= ping.at {
                    let lt = t - ping.at
                    v += (sin(2 * .pi * ping.freq * lt) + 0.35 * sin(2 * .pi * ping.freq * 2.71 * lt)) * exp(-lt * 26) * ping.gain * 0.22
                }
                let white = Double.random(in: -1...1)
                hiss = white - last; last = white   // crude high-pass: sizzle, not rumble
                return v + hiss * 0.12 * exp(-t * 12)
            }
        }
        buffers[.turbo] = [{
            var phase = 0.0
            var smooth = 0.0
            return render(1.0) { t in
                let f = 180 + 540 * min(1, t / 0.85)
                phase += f / 44_100
                let saw = 2 * (phase - floor(phase + 0.5))
                smooth += (saw - smooth) * 0.25
                let envelope = min(1, t / 0.6) * (t > 0.85 ? max(0, 1 - (t - 0.85) / 0.15) : 1)
                return smooth * envelope * 0.35
            }
        }()]
    }

    /// Offline mix of timed layers, written as a WAV for listening checks (evidence harness only).
    func exportMix(_ layers: [(Sound, at: Double, dB: Float)], duration: Double, to url: URL) {
        let frames = AVAudioFrameCount(duration * format.sampleRate)
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        out.frameLength = frames
        let dst = out.floatChannelData![0]
        for i in 0..<Int(frames) { dst[i] = 0 }
        for layer in layers {
            guard let buffer = buffers[layer.0]?.first else { continue }
            let src = buffer.floatChannelData![0]
            let offset = Int(layer.at * format.sampleRate)
            let gain = Self.gain(dB: layer.dB) * sfxBus.outputVolume
            for i in 0..<Int(buffer.frameLength) where offset + i < Int(frames) { dst[offset + i] += src[i] * gain }
        }
        guard let file = try? AVAudioFile(forWriting: url, settings: format.settings) else { return }
        try? file.write(from: out)
    }

    private func whoosh(duration: Double, brightness: Double) -> AVAudioPCMBuffer {
        var low = 0.0
        return render(duration) { t in
            let x = t / duration
            let cutoff = (0.04 + 0.22 * sin(.pi * x)) * brightness
            low += (Double.random(in: -1...1) - low) * cutoff
            return low * pow(sin(.pi * x), 2) * 0.9
        }
    }

    private func render(_ duration: Double, _ sample: (Double) -> Double) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(duration * format.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let data = buffer.floatChannelData![0]
        var peak = 0.0
        var values = [Double](repeating: 0, count: Int(frames))
        for i in 0..<Int(frames) {
            let v = sample(Double(i) / format.sampleRate)
            values[i] = v
            peak = max(peak, abs(v))
        }
        let normalize = peak > 0.85 ? 0.85 / peak : 1
        for i in 0..<Int(frames) { data[i] = Float(values[i] * normalize) }
        return buffer
    }
}

/// Deterministic generator for synthesized SFX variants.
struct SeededGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
    }
}
