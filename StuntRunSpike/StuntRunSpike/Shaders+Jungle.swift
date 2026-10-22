import SpriteKit

@MainActor
extension Shaders {
    /// River and banks, ray-cast onto the water plane (u_waterDrop below the raft deck).
    ///
    /// Reactive: the raft's roll and bob (u_raft), the croc (u_croc) and impacts (u_ring0/1) all disturb the surface.
    ///
    /// Motion grammar (lesson from Stunt Run): the raft rides WITH the current, so the water right around it barely
    /// moves relative to us — its ripples shimmer in place and drift slowly. The banks are land: they stream past
    /// at full travel speed, from the horizon toward the camera. Bank width and curvature come from the same
    /// world-anchored functions the scenery uses, so trees always stand on the bank.
    static func river() -> SKShader {
        let source = """
        float hash2(vec2 q) { return fract(sin(dot(q, vec2(41.3, 289.1))) * 15731.743); }
        float sq(float a) { return a * a; }
        float vnoise(vec2 q) {
            vec2 i = floor(q); vec2 f = fract(q); f = f * f * (3.0 - 2.0 * f);
            return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
        }

        void main() {
            vec2 p = v_tex_coord * u_res;
            float dy = max(u_horizon - p.y, 0.75);
            float hw = u_camH + u_waterDrop;
            float z = u_f * hw / dy;
            float bend = u_curve * pow(max(0.0, z - u_zp), 2.0);
            float x = (p.x - u_cx) * z / u_f - bend;
            float v = z + u_offset;                       // land frame: full travel
            float vw = z + u_offset * 0.22;               // water frame: drifts with the raft (slower)
            float dz = z / dy;
            float fade = 1.0 - smoothstep(0.5, 1.6, dz);

            float halfWidth = 5.6 + 1.7 * sin(v / 37.0) + 0.7 * sin(v / 13.0 + 1.3);
            float ax = abs(x);
            vec3 col;

            if (ax < halfWidth) {
                float t = u_clock;
                vec3 foamC = vec3(0.86, 0.98, 0.95);
                // Layered surface: a long swell along the flow, two wind-ripple trains, fine chop. Analytic slopes
                // (sx, sz) light it, so the water has shape without texture lookups.
                float sx = 0.0;
                float sz = 0.0;
                // A slow noise warp bends every crest, so no wave train reads as straight ruled lines.
                float warp = vnoise(vec2(x * 0.6, vw * 0.45)) * 2.5;
                float c0 = 0.090 * cos(0.9 * (0.20 * x + 0.98 * vw) + 0.8 * t);
                float c1 = 0.090 * cos(2.6 * (-0.75 * x + 0.66 * vw) + 2.1 * t + warp);
                float c2 = 0.085 * cos(3.4 * (0.85 * x + 0.52 * vw) + 2.7 * t - warp * 1.3);
                float c3 = 0.072 * cos(6.0 * (-0.30 * x - 0.95 * vw) + 3.6 * t + warp * 2.0);
                sx = c0 * 0.20 - c1 * 0.75 + c2 * 0.85 - c3 * 0.30;
                sz = c0 * 0.98 + c1 * 0.66 + c2 * 0.52 - c3 * 0.95;
                // Rings: something hit or left the water (croc surfacing, lunge, bite, retreat; the raft's edge plunging).
                vec2 r0 = vec2(x, z) - u_ring0.xy;
                float rr0 = length(r0) + 0.001;
                float e0 = exp(-sq(rr0 - u_ring0.z * 1.7) * 5.0) * u_ring0.w * exp(-u_ring0.z * 1.3) * step(0.0, u_ring0.z);
                float w0 = cos((rr0 - u_ring0.z * 1.7) * 9.0);
                vec2 r1 = vec2(x, z) - u_ring1.xy;
                float rr1 = length(r1) + 0.001;
                float e1 = exp(-sq(rr1 - u_ring1.z * 1.7) * 5.0) * u_ring1.w * exp(-u_ring1.z * 1.3) * step(0.0, u_ring1.z);
                float w1 = cos((rr1 - u_ring1.z * 1.7) * 9.0);
                sx += e0 * 1.4 * w0 * r0.x / rr0 + e1 * 1.4 * w1 * r1.x / rr1;
                sz += e0 * 1.4 * w0 * r0.y / rr0 + e1 * 1.4 * w1 * r1.y / rr1;

                float edge = ax / halfWidth;
                col = mix(vec3(0.03, 0.30, 0.34), vec3(0.08, 0.46, 0.42), smoothstep(0.2, 1.0, edge));
                // Facets tilted toward the bright haze ahead are lighter, those facing the camera darker.
                float facing = clamp(0.5 - sz * 1.6 + sx * 0.35, 0.0, 1.0);
                col *= 0.80 + 0.40 * facing;
                // Reflections: the sky haze at grazing distance, the dark forest mirrored near the banks (broken by ripples).
                col = mix(col, u_skyRefl * 0.85, smoothstep(4.0, 45.0, z) * 0.5);
                float refl = smoothstep(halfWidth - 1.8 + sx * 3.0, halfWidth - 0.35, ax);
                col = mix(col, vec3(0.03, 0.17, 0.12), refl * 0.5);
                // Glints: steep facets catching the sun, gathered along the sun's path far ahead.
                float sunPath = exp(-x * x / (1.5 + z * 0.25)) * smoothstep(5.0, 30.0, z);
                float sparkle = step(0.55, vnoise(vec2(x * 9.0, vw * 9.0 + t * 0.7)));
                col += vec3(1.0, 0.95, 0.8) * smoothstep(0.84, 0.97, facing) * sparkle * (0.35 + 0.65 * sunPath) * fade * 0.5;
                // Flow streaks: short dashes drifting with the current, near the raft only (never ruled lines to the horizon).
                float dash = smoothstep(0.82, 0.95, vnoise(vec2(x * 4.0, vw * 1.5)));
                col += vec3(0.65, 0.95, 0.88) * dash * (1.0 - smoothstep(5.0, 16.0, z)) * 0.07;
                // Current arrows: which way the river is pushing the raft (gameplay readability).
                float lane = 1.0 - smoothstep(0.2, 0.5, abs(x - u_currentSide * 2.4));
                float chev = step(fract(vw * 0.35 + abs(x - u_currentSide * 2.4) * 0.5), 0.25);
                col += vec3(0.75, 1.0, 0.95) * lane * chev * u_currentShow * 0.18 * fade;
                // Foam where water meets the bank.
                float foam = smoothstep(halfWidth - 0.45, halfWidth - 0.05, ax) * (0.6 + 0.4 * vnoise(vec2(v * 2.0, x)));
                col = mix(col, foamC, foam * 0.55);

                // The raft: contact shade on the water, foam lapping at the logs (stronger with the bob and on the
                // low side), a bow pillow at the front and a wake trailing back past it.
                // The raft's footprint on the water, as seen past the deck floating above it.
                vec2 rq = vec2(ax - 1.3, max(0.3 - z, z - 2.9));   // near end is below the screen
                float d = length(max(rq, vec2(0.0))) + min(max(rq.x, rq.y), 0.0);
                float low = max(0.0, sign(x) * u_raft.x);
                col *= 1.0 - 0.32 * (1.0 - smoothstep(0.0, 0.45, d));
                float lapAmt = exp(-max(d, 0.0) * 3.5) * (0.35 + u_raft.y * 0.8 + low * 1.2);
                // Crisp, lumpy foam (no soft glow): a broken band hugging the logs, and thin wavelet crests moving out.
                float lump = vnoise(vec2(x * 7.0, z * 7.0 - t * 1.5));
                float foamLine = (1.0 - smoothstep(0.05, 0.08, d + (lump - 0.5) * 0.10 - 0.06 * (u_raft.y + low))) * step(0.3, lump);
                float lapLines = smoothstep(0.82, 0.92, sin(d * 13.0 - t * 4.5 + vnoise(vec2(x * 3.0, vw * 3.0)) * 2.0));
                float bow = exp(-sq(z - 2.98 - 0.12 * x * x) * 40.0) * (1.0 - smoothstep(1.2, 1.7, ax));
                float wx = 1.3 + max(0.0, 2.9 - z) * 0.3;
                float wake = exp(-sq(ax - wx) * 40.0) * step(z, 2.9) * smoothstep(0.3, 1.6, z) * step(0.45, vnoise(vec2(ax * 5.0, vw * 3.0)));
                col = mix(col, foamC, clamp(foamLine * 0.85 + lapLines * lapAmt * 0.5 + bow * 0.55 + wake * 0.5, 0.0, 1.0) * step(0.0, d));

                // The croc: a V-wake behind its swimming head, a foam pillow at the snout (thrashing at the raft edge).
                vec2 cd = vec2(x - u_croc.x, z - u_croc.y);
                float behind = max(cd.y, 0.0);
                float arms = exp(-sq(abs(cd.x) - behind * 0.38) * 34.0) * step(0.0, cd.y) * exp(-behind * 0.35);
                float pillow = exp(-dot(cd, cd) * 9.0);
                // Log Sweep: rapids ahead (whitewater streaks), a standing-wave ridge at the bow, foam along a floating log.
                float rap = u_log.w * smoothstep(2.95, 3.6, z) * (1.0 - smoothstep(9.0, 14.0, z));
                float white = smoothstep(0.62, 0.86, vnoise(vec2(x * 2.2, vw * 1.6 - t * 2.4))) * rap * (1.0 - smoothstep(2.6, 4.0, ax));
                float ridge = exp(-sq(z - 3.12 - 0.06 * sin(x * 2.0 + t * 3.0)) * 28.0) * u_log.w * (1.0 - smoothstep(1.7, 2.5, ax));
                float logFoam = exp(-sq(abs(z - u_log.x) - 0.22) * 80.0) * (1.0 - smoothstep(u_log.y - 0.1, u_log.y + 0.25, ax)) * u_log.z;
                col = mix(col, foamC, clamp(white * 0.6 + ridge * 0.55 + logFoam * 0.7, 0.0, 1.0));
                // Ring crests foam a little.
                float ringFoam = e0 * smoothstep(0.3, 1.0, w0) + e1 * smoothstep(0.3, 1.0, w1);
                col = mix(col, foamC, clamp(arms * u_croc.z * 0.6 + pillow * u_croc.w * 0.6 + ringFoam * 0.5, 0.0, 1.0));
            } else {
                // Bank: a wet mud lip, then layered undergrowth — dark bush clumps with lit fern tops, dappled light
                // that flickers as the canopy moves, darkening toward the forest wall inland. Streams at travel speed.
                float inland = ax - halfWidth;
                vec3 mud = vec3(0.30, 0.20, 0.13);
                vec3 floorC = mix(vec3(0.08, 0.27, 0.13), vec3(0.03, 0.12, 0.08), smoothstep(0.5, 7.0, inland));
                col = mix(mud, floorC, smoothstep(0.0, 0.6, inland));
                col += vec3(0.25, 0.35, 0.30) * (1.0 - smoothstep(0.0, 0.18, inland)) * 0.35;
                float bushes = vnoise(vec2(x * 0.9, v * 0.9)) * 0.65 + vnoise(vec2(x * 2.3 + 3.0, v * 2.3)) * 0.35;
                col = mix(col, vec3(0.03, 0.13, 0.08), smoothstep(0.5, 0.62, bushes) * 0.7 * smoothstep(0.4, 1.2, inland));
                col = mix(col, vec3(0.20, 0.44, 0.17), smoothstep(0.66, 0.74, bushes) * 0.6 * fade);
                float dapple = smoothstep(0.72, 0.86, vnoise(vec2(x * 0.6 + 11.0, v * 0.5 + u_clock * 0.05)));
                col += vec3(0.30, 0.32, 0.12) * dapple * 0.35 * fade;
            }

            float fog = smoothstep(14.0, 85.0, z);
            col = mix(col, u_fogColor, fog);
            gl_FragColor = vec4(col, 1.0);
        }
        """
        return SKShader(source: source, uniforms: [
            SKUniform(name: "u_res", vectorFloat2: .zero),
            SKUniform(name: "u_horizon", float: 0),
            SKUniform(name: "u_cx", float: 0),
            SKUniform(name: "u_f", float: 1),
            SKUniform(name: "u_camH", float: 1),
            SKUniform(name: "u_zp", float: 1.9),
            SKUniform(name: "u_waterDrop", float: 0.22),
            SKUniform(name: "u_offset", float: 0),
            SKUniform(name: "u_curve", float: 0),
            SKUniform(name: "u_clock", float: 0),
            SKUniform(name: "u_currentSide", float: 0),
            SKUniform(name: "u_currentShow", float: 0),
            SKUniform(name: "u_fogColor", vectorFloat3: SIMD3<Float>(0.35, 0.62, 0.52)),
            SKUniform(name: "u_skyRefl", vectorFloat3: SIMD3<Float>(0.85, 0.80, 0.55)),
            SKUniform(name: "u_raft", vectorFloat4: .zero),
            SKUniform(name: "u_croc", vectorFloat4: .zero),
            SKUniform(name: "u_log", vectorFloat4: .zero),
            SKUniform(name: "u_ring0", vectorFloat4: SIMD4<Float>(0, 0, 99, 0)),
            SKUniform(name: "u_ring1", vectorFloat4: SIMD4<Float>(0, 0, 99, 0)),
        ])
    }

    /// Humid jungle sky: warm light low in the haze, deep teal above, soft light shafts through the canopy.
    static func jungleSky() -> SKShader {
        let source = """
        void main() {
            vec2 p = v_tex_coord * u_res;
            float t = clamp(p.y / u_res.y, 0.0, 1.0);
            vec3 low = u_hazeColor;
            vec3 mid = mix(vec3(0.12, 0.42, 0.40), vec3(0.20, 0.30, 0.45), u_phase);
            vec3 top = mix(vec3(0.03, 0.14, 0.16), vec3(0.04, 0.08, 0.18), u_phase);
            vec3 col = mix(low, mid, smoothstep(0.0, 0.45, t));
            col = mix(col, top, smoothstep(0.45, 1.0, t));
            // Sun glow behind the haze.
            vec2 sc = vec2(u_cx + u_pan, u_res.y * 0.18);
            float r = length((p - sc) / u_res.y);
            col += vec3(1.0, 0.80, 0.45) * 0.45 * exp(-r * 4.0) * (1.0 - u_phase * 0.6);
            // Light shafts fanning down from above the canopy.
            vec2 d = p - vec2(u_cx + u_pan * 0.5, u_res.y * 1.6);
            float ang = atan(d.x, -d.y);
            float shafts = pow(max(0.0, sin(ang * 15.0 + u_clock * 0.15)), 18.0);
            col += vec3(1.0, 0.92, 0.65) * shafts * 0.10 * smoothstep(0.1, 0.7, t) * u_shafts;
            gl_FragColor = vec4(col, 1.0);
        }
        """
        return SKShader(source: source, uniforms: [
            SKUniform(name: "u_res", vectorFloat2: .zero),
            SKUniform(name: "u_cx", float: 0),
            SKUniform(name: "u_pan", float: 0),
            SKUniform(name: "u_phase", float: 0),
            SKUniform(name: "u_clock", float: 0),
            SKUniform(name: "u_shafts", float: 1),
            SKUniform(name: "u_hazeColor", vectorFloat3: SIMD3<Float>(0.85, 0.80, 0.55)),
        ])
    }
}

/// The bank half-width at a world coordinate — must match the river shader.
nonisolated func riverHalfWidth(atWorld v: Double) -> Double {
    5.6 + 1.7 * sin(v / 37.0) + 0.7 * sin(v / 13.0 + 1.3)
}
