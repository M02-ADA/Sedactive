import SpriteKit

/// Full-screen procedural shaders. One draw call each; they replace thousands of scrolling floor tiles
/// and give exact, seamless perspective at any speed.
@MainActor
enum Shaders {
    /// Ray-casts each pixel below the horizon onto two planes: the train roof the players stand on,
    /// and the ground far below. Both scroll with the same world offset, so the gap between them reads as depth.
    ///
    /// Motion grammar: every pattern moves toward the camera and grows. Features are large (≥ 3 units) and
    /// high-contrast near the bottom of the frame, because near-field ground texture is the strongest speed cue
    /// and fine patterns (the old 0.75-unit sleepers) alias into apparent backward crawl in 30 fps captures.
    static func floor() -> SKShader {
        let source = """
        float lineMask(float d, float halfWidth, float aa) {
            return 1.0 - smoothstep(halfWidth, halfWidth + aa, d);
        }

        void main() {
            vec2 p = v_tex_coord * u_res;
            // SpriteKit rewrites gl_FragColor assignments into returns, so no early exit: clamp instead.
            float dy = max(u_horizon - p.y, 0.75);

            vec3 fogDusk = vec3(1.0, 0.50, 0.46);
            vec3 fogNight = vec3(0.22, 0.52, 0.98);
            vec3 fogCol = mix(mix(fogDusk, fogNight, u_phase), vec3(0.05, 0.04, 0.16), u_dim * 0.7);

            float zRoof = u_f * u_camH / dy;
            float bendR = u_curve * pow(max(0.0, zRoof - u_zp), 2.0);
            float xRoof = (p.x - u_cx) * zRoof / u_f - bendR;
            vec3 col;
            float z;

            // The train deck travels WITH the players: its features use the train frame (no scroll). Only the
            // world (ground, track, scenery) streams past. A floor sliding toward the camera under camera-facing
            // players reads as them being dragged backwards — that was the root of the "moving backwards" feel.
            if (abs(xRoof) < u_roofHalf && zRoof < u_trainFront) {
                z = zRoof;
                float v = zRoof;
                float dz = zRoof / dy;
                float dx = zRoof / u_f;
                float fade = 1.0 - smoothstep(0.35, 1.2, dz);
                float ax = abs(xRoof);

                float panel = mod(floor(v / 3.0), 2.0);
                vec3 roofA = vec3(0.15, 0.10, 0.34);
                vec3 roofB = vec3(0.22, 0.16, 0.48);
                col = mix(roofA, roofB, panel * fade + 0.5 * (1.0 - fade));
                col += vec3(0.22, 0.15, 0.45) * pow(max(0.0, 1.0 - ax / u_roofHalf), 2.0) * 0.35;

                float seam = lineMask(abs(fract(v / 3.0 + 0.5) - 0.5) * 3.0, 0.035, dz * 1.5);
                col = mix(col, vec3(0.04, 0.03, 0.12), seam * 0.9 * fade);

                // Gaps between carriages (every u_carLength) with a coupling.
                float carPhase = abs(fract((v + 1.4) / u_carLength + 0.5) - 0.5) * u_carLength;
                float gap = lineMask(carPhase, 0.22, dz * 1.5);
                col = mix(col, vec3(0.02, 0.02, 0.07), gap);
                col = mix(col, vec3(0.55, 0.45, 0.95), gap * lineMask(ax, 0.18, dx * 1.5));

                vec3 teal = vec3(0.12, 0.88, 0.80);
                float dash = step(fract(v / 4.0), 0.5);
                float centre = lineMask(ax, 0.05, dx * 1.5);
                col = mix(col, teal, centre * mix(1.0, dash, fade) * (1.0 - gap));
                col += teal * 0.10 * exp(-ax * 5.0);

                float band = step(u_roofHalf - 0.42, ax) * step(ax, u_roofHalf - 0.2);
                float chevron = step(0.5, fract(v / 2.0 + ax * 0.9));
                vec3 hazard = mix(vec3(0.07, 0.06, 0.20), vec3(1.0, 0.45, 0.38), chevron * fade + 0.4 * (1.0 - fade));
                col = mix(col, hazard, band * 0.9);

                float rail = lineMask(abs(ax - (u_roofHalf - 0.12)), 0.05, dx * 1.5);
                col = mix(col, vec3(1.0, 0.82, 0.25), rail);
                float lip = smoothstep(u_roofHalf - 0.06, u_roofHalf, ax);
                col = mix(col, vec3(0.03, 0.03, 0.10), lip);

                // Marker lights on the carriage: they blink in place (alive) but never travel along the deck.
                float lz = (fract(v / 3.0 + 0.5) - 0.5) * 3.0;
                float lx = ax - (u_roofHalf - 0.62);
                float light = exp(-(lx * lx) / 0.004 - (lz * lz) / 0.02);
                float blink = 0.65 + 0.35 * sin(u_clock * 5.0 + floor(v / 3.0) * 1.7);
                col += mix(vec3(1.0, 0.85, 0.35), teal, step(0.0, xRoof)) * light * 1.6 * blink;

                // Approach lanes: lit between the gate and each player while the action window is open. Static
                // chevrons pointing at the players — the warning glows, it does not slide along the deck.
                float laneSide = step(0.0, xRoof);
                vec3 laneCol = mix(u_leftColor, u_rightColor, laneSide);
                float lane = 1.0 - smoothstep(0.18, 0.30, abs(ax - u_laneX));
                float span = step(u_zp, zRoof) * (1.0 - smoothstep(u_gateZ - 2.0, u_gateZ, zRoof));
                float arrows = step(fract(zRoof * 0.55 + abs(ax - u_laneX) * 1.3), 0.4);
                col += laneCol * lane * span * (0.10 + 0.42 * arrows * fade) * u_warn;
            } else {
                float hGround = u_camH + u_drop;
                z = u_f * hGround / dy;
                float bendG = u_curve * pow(max(0.0, z - u_zp), 2.0);
                float x = (p.x - u_cx) * z / u_f - bendG;
                float v = z + u_offset;
                float dz = z / dy;
                float dx = z / u_f;
                float fade = 1.0 - smoothstep(0.45, 1.5, dz);

                col = mix(vec3(0.05, 0.04, 0.17), vec3(0.03, 0.06, 0.20), u_phase);
                vec3 grid = mix(vec3(0.66, 0.32, 1.0), vec3(0.20, 0.80, 1.0), u_phase);
                float gx = lineMask(abs(fract(x / 4.0 + 0.5) - 0.5) * 4.0, 0.04, dx * 1.5);
                float gz = lineMask(abs(fract(v / 4.0 + 0.5) - 0.5) * 4.0, 0.04, dz * 1.5);
                col += grid * max(gx, gz * fade) * 0.8;

                // Neighbouring track plus our own track continuing ahead of the locomotive: the sleepers stream
                // out from under the train toward the camera only at the sides, and toward us from the horizon ahead.
                float sleeperBand = lineMask(abs(fract(v / 3.0 + 0.5) - 0.5) * 3.0, 0.22, dz * 1.5) * fade;
                float side = abs(abs(x) - 4.2);
                float rails = max(lineMask(abs(side - 0.5), 0.05, dx * 1.5), lineMask(abs(side + 0.5), 0.05, dx * 1.5));
                col = mix(col, vec3(0.30, 0.22, 0.48), sleeperBand * step(side, 0.65) * 0.75);
                float own = abs(x);
                float ownRails = lineMask(abs(own - 0.75), 0.05, dx * 1.5);
                col = mix(col, vec3(0.30, 0.22, 0.48), sleeperBand * step(own, 0.95) * 0.75);
                col = mix(col, vec3(1.0, 0.70, 0.35), max(rails, ownRails) * 0.85);

                // Headlights: a warm cone thrown ahead of the locomotive onto its own track.
                float ahead = z - u_trainFront;
                if (ahead > 0.0) {
                    float width = 0.9 + ahead * 0.11;
                    float cone = (1.0 - smoothstep(width * 0.6, width, own)) * exp(-ahead * 0.045) * smoothstep(0.0, 1.5, ahead);
                    col += vec3(1.0, 0.86, 0.55) * cone * 0.55 * (1.0 - u_dim * 0.5);
                }

                // Shadow of the train along its edge (only where the train is).
                float edgeDist = abs(xRoof) - u_roofHalf;
                float trainHere = 1.0 - step(u_trainFront, zRoof);
                col *= mix(1.0, mix(0.45, 1.0, smoothstep(0.0, 0.6, edgeDist)), trainHere);
            }

            col *= 1.0 - 0.45 * u_dim;
            float fog = smoothstep(18.0, 95.0, z);
            col = mix(col, fogCol, fog);
            gl_FragColor = vec4(col, 1.0);
        }
        """
        return SKShader(source: source, uniforms: [
            SKUniform(name: "u_res", vectorFloat2: .zero),
            SKUniform(name: "u_horizon", float: 0),
            SKUniform(name: "u_cx", float: 0),
            SKUniform(name: "u_f", float: 1),
            SKUniform(name: "u_camH", float: 1),
            SKUniform(name: "u_zp", float: 2),
            SKUniform(name: "u_drop", float: 1.8),
            SKUniform(name: "u_roofHalf", float: 1.6),
            SKUniform(name: "u_offset", float: 0),
            SKUniform(name: "u_phase", float: 0),
            SKUniform(name: "u_curve", float: 0),
            SKUniform(name: "u_dim", float: 0),
            SKUniform(name: "u_warn", float: 0),
            SKUniform(name: "u_gateZ", float: 0),
            SKUniform(name: "u_laneX", float: 0.65),
            SKUniform(name: "u_clock", float: 0),
            SKUniform(name: "u_trainFront", float: 34),
            SKUniform(name: "u_carLength", float: 9),
            SKUniform(name: "u_leftColor", vectorFloat3: SIMD3<Float>(1.0, 0.42, 0.37)),
            SKUniform(name: "u_rightColor", vectorFloat3: SIMD3<Float>(0.10, 0.83, 0.77)),
        ])
    }

    /// Dusk-to-night gradient, a striped retro sun and twinkling stars. `u_pan` slides the sun opposite
    /// the track curve, like a camera yawing into a bend.
    static func sky() -> SKShader {
        let source = """
        float hash(vec2 q) { return fract(sin(dot(q, vec2(127.1, 311.7))) * 43758.5453); }

        void main() {
            vec2 p = v_tex_coord * u_res;
            float t = clamp(p.y / u_res.y, 0.0, 1.0);
            vec3 top = mix(vec3(0.04, 0.05, 0.18), vec3(0.01, 0.02, 0.10), u_phase);
            vec3 mid = mix(vec3(0.32, 0.14, 0.58), vec3(0.08, 0.14, 0.46), u_phase);
            vec3 low = mix(vec3(1.0, 0.47, 0.42), vec3(0.14, 0.70, 0.95), u_phase);
            vec3 col = mix(low, mid, smoothstep(0.0, 0.38, t));
            col = mix(col, top, smoothstep(0.38, 1.0, t));

            float radius = u_res.y * 0.42;
            vec2 sc = vec2(u_cx + u_pan, radius * 0.55);
            float r = length(p - sc) / radius;
            float sunMask = 1.0 - smoothstep(0.985, 1.0, r);
            float vy = (p.y - (sc.y - radius)) / (2.0 * radius);
            vec3 sunCol = mix(vec3(1.0, 0.36, 0.48), vec3(1.0, 0.88, 0.32), clamp(vy, 0.0, 1.0));
            float below = (sc.y - p.y) / radius;
            float slit = 1.0;
            if (below > -0.1) {
                float band = fract(below * 6.0 - u_t * 0.22);
                slit = step(clamp(below + 0.1, 0.0, 1.0) * 0.6, band);
            }
            float sunStrength = 1.0 - u_phase * 0.75;
            col = mix(col, sunCol, sunMask * slit * sunStrength);
            col += vec3(1.0, 0.45, 0.38) * 0.30 * exp(-r * 2.0) * sunStrength;

            vec2 cell = floor(p / 7.0);
            float h = hash(cell);
            vec2 f = fract(p / 7.0) - 0.5;
            float star = step(0.992, h) * (1.0 - smoothstep(0.08, 0.22, length(f))) * smoothstep(0.42, 0.85, t);
            float twinkle = 0.55 + 0.45 * sin(u_t * 2.5 + h * 60.0);
            col += vec3(star * twinkle * (0.6 + 0.6 * u_phase));

            col *= 1.0 - 0.5 * u_dim;
            gl_FragColor = vec4(col, 1.0);
        }
        """
        return SKShader(source: source, uniforms: [
            SKUniform(name: "u_res", vectorFloat2: .zero),
            SKUniform(name: "u_cx", float: 0),
            SKUniform(name: "u_phase", float: 0),
            SKUniform(name: "u_t", float: 0),
            SKUniform(name: "u_pan", float: 0),
            SKUniform(name: "u_dim", float: 0),
        ])
    }
}
