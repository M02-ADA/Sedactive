import SpriteKit

@MainActor
extension Shaders {
    /// The vault corridor: floor, walls and ceiling ray-cast from the same pinhole camera as every sprite (Projection),
    /// so the architecture, the gates and the beams share one perspective. One full-screen sprite, one draw.
    ///
    /// Motion grammar: the corridor is fixed in the world and streams past the cart (`u_offset` = distance travelled);
    /// the cart deck under the players is a separate sprite and never moves. Panel seams, ceiling light bars and their
    /// reflections in the glossy floor give a strong, consistent forward flow from the vanishing point.
    ///
    /// Reactive: `u_alarm` turns the light strips red and runs a warning chase down the corridor; `u_beam` (z, height,
    /// strength) throws the active laser's red light onto the floor and walls where the gate is; `u_flash` washes the
    /// corridor after a team dodge; `u_exit` opens a golden light at the far end for the finale.
    static func corridor() -> SKShader {
        let source = """
        float hash(float n) { return fract(sin(n) * 43758.5453); }

        void main() {
            vec2 p = v_tex_coord * u_res;
            float dx = (p.x - u_cx) / u_f;
            float dy = (p.y - u_horizon) / u_f;
            float W = 2.0;
            float hF = -0.35;
            float hC = 2.3;
            float zW = W / max(abs(dx), 0.0001);
            float zF = dy < -0.0001 ? (hF - u_camH) / dy : 1000.0;
            float zC = dy > 0.0001 ? (hC - u_camH) / dy : 1000.0;
            float zH = min(zF, zC);
            float z = min(min(zW, zH), 400.0);
            float v = z + u_offset;
            float x = dx * z;
            float h = u_camH + dy * z;
            float fade = 1.0 - smoothstep(18.0, 55.0, z);   // fine detail fades before it can shimmer

            vec3 navy = vec3(0.055, 0.063, 0.20);
            vec3 violet = vec3(0.13, 0.08, 0.27);
            vec3 cyan = vec3(0.17, 0.90, 1.0);
            vec3 coral = vec3(1.0, 0.30, 0.37);
            vec3 lightC = mix(cyan, coral, u_alarm);
            // Warning chase: lights fire in sequence down the corridor toward the cart while the alarm is on.
            float chase = u_alarm * smoothstep(0.75, 1.0, fract(v / 12.0 + u_clock * 0.9));
            float pulse = 1.0 + u_alarm * 0.35 * sin(u_clock * 7.0);
            vec3 col;

            if (zW < zH) {
                // Walls: dark violet panels (seams every 2 units), a pillar every 8, a light strip, trims.
                float side = sign(dx);
                col = mix(violet, navy, 0.35);
                col *= 1.0 - 0.35 * smoothstep(0.96, 1.0, abs(fract(v / 2.0) - 0.5) * 2.0);
                float inset = step(0.35, h) * step(h, 1.25) * step(0.12, fract(v / 2.0)) * step(fract(v / 2.0), 0.88);
                col = mix(col, violet * 1.25, inset * 0.6);
                // Ribs every 8 units: a slightly raised band with lit edges (reads as structure, not as a pole).
                float pillar = step(fract(v / 8.0), 0.09);
                float ribEdge = smoothstep(0.0, 0.012, fract(v / 8.0)) * (1.0 - smoothstep(0.075, 0.09, fract(v / 8.0)));
                col = mix(col, violet * 1.1, pillar);
                col += lightC * pillar * (1.0 - ribEdge) * 0.22 * fade;
                float strip = exp(-pow((h - 1.55) / 0.035, 2.0)) * (1.0 - pillar);
                float trim = exp(-pow((h - 0.06) / 0.03, 2.0));
                col += lightC * (strip * 0.9 * pulse + trim * 0.35 + chase * strip * 1.2);
                col += lightC * pillar * exp(-pow((h - 1.0) / 0.6, 2.0)) * 0.12;
                // Shading: walls darker toward the floor (ambient occlusion feel).
                col *= 0.65 + 0.35 * smoothstep(-0.35, 1.2, h);
            } else if (dy < 0.0) {
                // Floor: glossy navy tiles, cyan guide rails, reflections of the ceiling light bars and wall strips.
                col = navy * 0.9;
                float tile = step(0.97, fract(v / 2.0)) + step(0.985, fract((x + W) / 1.0));
                col += cyan * tile * 0.06 * fade;
                float rail = exp(-pow((abs(x) - 1.55) / 0.04, 2.0));
                col += lightC * rail * 0.55;
                float bars = exp(-pow((fract(v / 4.0) - 0.5) / 0.05, 2.0)) * (1.0 - smoothstep(1.2, 2.0, abs(x)));
                col += mix(vec3(0.75, 0.95, 1.0), coral, u_alarm) * bars * 0.10 * fade;
                float wallRefl = smoothstep(1.3, 2.0, abs(x)) * (0.5 + 0.5 * sin(v * 3.1416));
                col += lightC * wallRefl * 0.08 * pulse;
                // Threat lanes: chevrons run down each player's lane from the incoming gate toward them — magenta for a
                // high beam (DUCK), amber for a floor sweep (JUMP). The floor itself says what is coming, per lane.
                for (int k = 0; k < 2; k++) {
                    float lx = k == 0 ? -0.65 : 0.65;
                    float type = k == 0 ? u_threat.x : u_threat.y;
                    if (type > 0.5 && z > 1.9 && z < u_threat.z) {
                        float inLane = 1.0 - smoothstep(0.30, 0.42, abs(x - lx));
                        float chev = step(0.55, fract((z + abs(x - lx) * 0.9) / 1.1 + u_clock * 2.4));
                        vec3 tc = type < 1.5 ? vec3(1.0, 0.25, 0.65) : vec3(1.0, 0.70, 0.15);
                        col += tc * inLane * chev * u_threat.w * 0.55 * (1.0 - smoothstep(14.0, 24.0, z));
                    }
                }
                // Patrolling spotlights sweep the floor (cyan while searching, red once the alarm is up).
                for (int k = 0; k < 2; k++) {
                    float ph = u_clock * (0.55 + 0.2 * float(k)) + float(k) * 2.1;
                    vec2 c = vec2(sin(ph) * 1.25, 7.0 + 3.5 * sin(ph * 0.7 + 1.0));
                    vec2 dd = vec2(x - c.x, (z - c.y) * 0.45);
                    float spot = 1.0 - smoothstep(0.35, 0.55, length(dd));
                    col += mix(vec3(0.55, 0.95, 1.0), coral, u_alarm) * spot * u_spots * 0.22;
                }
                // Headlights of the cart thrown onto the corridor floor ahead of it.
                float ahead = smoothstep(3.0, 4.0, z) * (1.0 - smoothstep(9.0, 16.0, z)) * (1.0 - smoothstep(0.6, 1.4, abs(x) - (z - 3.0) * 0.06));
                col += vec3(0.85, 0.95, 1.0) * ahead * 0.10;
            } else {
                // Ceiling: navy with light bars across every 4 units (the strongest flow cue) and a centre rail.
                col = navy * 0.8;
                float bar = exp(-pow((fract(v / 4.0) - 0.5) / 0.035, 2.0)) * (1.0 - smoothstep(1.3, 1.8, abs(x)));
                col += mix(vec3(0.80, 0.97, 1.0), coral, u_alarm) * bar * (0.75 + chase * 0.6) * pulse;
                col += lightC * exp(-pow(x / 0.05, 2.0)) * 0.25;
            }

            // The active laser lights the architecture where its gate is (floor line, wall and ceiling glow).
            if (u_beam.z > 0.0) {
                float near = exp(-pow((z - u_beam.x) / 0.18, 2.0));
                float onFloor = dy < 0.0 && zH < zW ? 1.0 : 0.6;
                col += coral * near * u_beam.z * onFloor * 0.7;
            }
            col += mix(cyan, vec3(1.0, 0.85, 0.4), u_exitGold) * u_flash * 0.25 * exp(-z * 0.04);

            // Depth haze, and the exit: golden light opening at the far end.
            float haze = smoothstep(14.0, 70.0, z);
            col = mix(col, mix(violet * 0.55, coral * 0.25, u_alarm * 0.5), haze);
            vec2 vp = vec2(dx, dy);
            float exitGlow = exp(-dot(vp, vp) * 60.0) * u_exit;
            col = mix(col, vec3(1.0, 0.86, 0.55), clamp(exitGlow * 1.4 + u_exit * haze * 0.6, 0.0, 1.0));
            gl_FragColor = vec4(col, 1.0);
        }
        """
        return SKShader(source: source, uniforms: [
            SKUniform(name: "u_res", vectorFloat2: .zero),
            SKUniform(name: "u_cx", float: 0),
            SKUniform(name: "u_horizon", float: 0),
            SKUniform(name: "u_f", float: 1),
            SKUniform(name: "u_camH", float: 1),
            SKUniform(name: "u_offset", float: 0),
            SKUniform(name: "u_clock", float: 0),
            SKUniform(name: "u_alarm", float: 0),
            SKUniform(name: "u_beam", vectorFloat3: .zero),
            SKUniform(name: "u_flash", float: 0),
            SKUniform(name: "u_exit", float: 0),
            SKUniform(name: "u_exitGold", float: 0),
            SKUniform(name: "u_threat", vectorFloat4: .zero),
            SKUniform(name: "u_spots", float: 1),
        ])
    }
}
