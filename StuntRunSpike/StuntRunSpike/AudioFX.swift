import AVFoundation

/// Tiny procedural SFX kit: buffers are synthesized once at launch, played through a fixed pool of
/// voices on one SFX bus. No audio files, no microphone, no recording.
final class AudioFX {
    enum Sound: CaseIterable {
        case tick, whoosh, lock, chime, pop, team, bonk, turbo, impact, shatter, caw, splash, creak, growl, chomp, gurgle, hiss, flutter, rumble, knock, roll, swish, slap
        case boil, leap, snap, hop, land, nip
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

    func stopAmbience() { ambience.stop() }

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

    func play(_ sound: Sound, dB: Float = 0) {
        guard !isMuted, engine.isRunning, let buffer = buffers[sound]?.randomElement() else { return }
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
