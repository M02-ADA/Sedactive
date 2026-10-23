import SpriteKit

@MainActor
extension Shaders {
    /// Moonbound's world, ray-cast from the same pinhole camera as every sprite (Projection: centre, eye level, f).
    ///
    /// The camera sits `u_alt` above a planet of radius `u_R` and looks horizontally (pitched down by `u_pitch` high
    /// up, so the limb stays in view). One formula covers the whole trip:
    ///   • the ground is a sphere: the launch complex under the deck, fields, forests, lakes, coast and ocean at
    ///     growing scales. As the camera climbs, the ground drops away and its details shrink toward the horizon,
    ///     which dips and curves — Earth turning into a planet below the players;
    ///   • a cloud deck (a shell at `u_cloudAlt`) is a ceiling at lift-off, a white-out as the rocket punches through,
    ///     then a sea of clouds below, and finally weather on the planet seen from space;
    ///   • sky colour, haze and the atmosphere's limb glow follow altitude; stars fade in above the air;
    ///   • `u_body` = 1 turns the planet into the Moon (grey, cratered, no air) for the landing.
    static func ascentWorld() -> SKShader {
        let source = """
        float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
        float noise(vec2 p) {
            vec2 i = floor(p); vec2 f = fract(p);
            vec2 u = f * f * (3.0 - 2.0 * f);
            return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
        }
        float fbm(vec2 p) { return 0.5 * noise(p) + 0.25 * noise(p * 2.03 + 7.1) + 0.125 * noise(p * 4.01 + 3.7); }

        // Ray against a sphere centred at the origin, from o (inside or outside). Returns the nearest t > 0 or -1.
        float sphere(vec3 o, vec3 d, float r) {
            float b = dot(o, d);
            float c = dot(o, o) - r * r;
            float disc = b * b - c;
            if (disc < 0.0) { return -1.0; }
            float s = sqrt(disc);
            if (c > 0.0) {
                if (b > 0.0) { return -1.0; }
                return c / (-b + s);            // stable form (no cancellation near the horizon)
            }
            return -b + s;                       // from inside the shell
        }

        void main() {
            vec2 p = v_tex_coord * u_res;
            float dx = (p.x - u_cx) / u_f;
            float dy = (p.y - u_horizon) / u_f;
            float cp = cos(u_pitch), sp = sin(u_pitch);
            vec3 d = normalize(vec3(dx, dy * cp - sp, dy * sp + cp));
            float alt = u_alt;
            vec3 o = vec3(0.0, u_R + alt, 0.0);
            float air = 1.0 - smoothstep(30.0, 290.0, alt);           // 1 near the ground, 0 in space (dark by the space phase)
            air *= (1.0 - u_body);

            // Sky.
            float elev = d.y;
            vec3 dayZenith = vec3(0.24, 0.52, 0.98), dayHorizon = vec3(0.70, 0.88, 1.0);
            vec3 highZenith = vec3(0.06, 0.07, 0.26), spaceCol = vec3(0.015, 0.012, 0.05);
            vec3 zenith = mix(spaceCol, mix(highZenith, dayZenith, smoothstep(0.45, 1.0, air)), smoothstep(0.0, 0.35, air));
            vec3 horizonCol = mix(mix(vec3(0.25, 0.45, 0.95), dayHorizon, air), spaceCol, u_body);   // the Moon has no air
            // Angle above the limb: the glow hugs the planet's edge (geometric horizon below eye level when high up).
            float limbY = -sqrt(max(0.0, 1.0 - (u_R * u_R) / ((u_R + alt) * (u_R + alt))));
            float above = elev - limbY;
            vec3 col = mix(horizonCol, zenith, smoothstep(0.0, 0.55 * mix(0.35, 1.0, air), above));
            float limbGlow = exp(-max(above, 0.0) * mix(26.0, 6.0, air)) * (1.0 - u_body);
            col += vec3(0.30, 0.62, 1.0) * limbGlow * (0.35 + 0.65 * (1.0 - air)) * 0.9;
            // Stars (camera-frame, at infinity): only where the air is thin.
            float starsOn = smoothstep(0.55, 0.05, air) + u_body;
            vec2 cell = floor(p / 7.0);
            float h = hash(cell);
            if (h > 0.985) {
                vec2 sp2 = (cell + vec2(hash(cell + 3.1), hash(cell + 5.7))) * 7.0;
                float s = smoothstep(1.6, 0.0, length(p - sp2)) * (0.6 + 0.4 * sin(u_clock * (2.0 + 5.0 * h) + h * 50.0));
                col += vec3(0.9, 0.95, 1.0) * s * starsOn * smoothstep(-0.02, 0.06, above);
            }

            // Planet.
            float tG = sphere(o, d, u_R);
            float tC = u_body > 0.5 ? -1.0 : sphere(o, d, u_R + u_cloudAlt);
            if (tG > 0.0) {
                vec3 P = o + d * tG;
                vec3 n = normalize(P);
                vec2 q = vec2(P.x, P.z) * (u_R / max(P.y, 1.0));
                float lod = tG / u_f * 1.6;                              // world size of a pixel
                vec3 g;
                if (u_body < 0.5) {
                    // Continents and ocean (thousands of units), then forests/lakes, then fields, then the pad.
                    float cont = fbm(q / 2600.0 + vec2(4.2, 1.3));
                    vec3 land = mix(vec3(0.36, 0.66, 0.30), vec3(0.62, 0.70, 0.36), fbm(q / 700.0));
                    float forest = smoothstep(0.52, 0.62, fbm(q / 90.0 + 11.0)) * (1.0 - smoothstep(30.0, 90.0, lod * 30.0));
                    land = mix(land, vec3(0.18, 0.44, 0.24), forest * 0.8);
                    float fieldsFade = 1.0 - smoothstep(1.5, 5.0, lod);
                    vec2 fc = floor(q / 9.0);
                    vec3 field = mix(vec3(0.48, 0.74, 0.32), vec3(0.86, 0.80, 0.42), hash(fc));
                    float stripes = 0.5 + 0.5 * sin((q.x + q.y * 0.3) * 2.2 + hash(fc) * 6.0);
                    field *= 0.9 + 0.1 * stripes * fieldsFade;
                    land = mix(land, field, 0.55 * fieldsFade);
                    float lake = smoothstep(0.66, 0.70, fbm(q / 160.0 + 2.0));
                    land = mix(land, vec3(0.20, 0.55, 0.85), lake);
                    float ocean = smoothstep(0.47, 0.44, cont);
                    g = mix(land, mix(vec3(0.10, 0.36, 0.72), vec3(0.16, 0.50, 0.82), fbm(q / 300.0)), ocean);
                    // Launch complex: concrete apron, painted ring and roads around the pad (under the deck).
                    float r = length(q);
                    float pad = 1.0 - smoothstep(13.0, 14.0, r);
                    vec3 concrete = vec3(0.62, 0.64, 0.70) * (0.92 + 0.08 * noise(q * 2.0));
                    float ring = smoothstep(0.25, 0.0, abs(r - 7.0)) + smoothstep(0.2, 0.0, abs(r - 11.5));
                    concrete = mix(concrete, vec3(1.0, 0.80, 0.30), ring * 0.9);
                    float spokes = smoothstep(0.18, 0.0, abs(fract(atan(q.y, q.x) / 6.2832 * 8.0) - 0.5) * r * 0.8) * step(7.0, r);
                    concrete = mix(concrete, vec3(0.95, 0.95, 1.0), spokes * 0.5);
                    g = mix(g, concrete, pad);
                    float road = smoothstep(0.9, 0.3, abs(q.x)) * step(13.0, abs(q.y)) * (1.0 - smoothstep(60.0, 120.0, abs(q.y)));
                    g = mix(g, vec3(0.30, 0.31, 0.36), road * fieldsFade);
                } else {
                    // The Moon: grey regolith, craters at three scales, soft rim highlights.
                    float m = fbm(q / 30.0);
                    g = mix(vec3(0.48, 0.48, 0.55), vec3(0.70, 0.70, 0.76), m);
                    for (int k = 0; k < 3; k++) {
                        float sc = k == 0 ? 6.0 : (k == 1 ? 18.0 : 55.0);
                        vec2 cc = floor(q / sc);
                        vec2 cen = (cc + vec2(0.2 + 0.6 * hash(cc), 0.2 + 0.6 * hash(cc + 9.0))) * sc;
                        float rad = sc * (0.15 + 0.2 * hash(cc + 4.0));
                        float dd = length(q - cen) / rad;
                        float crater = (1.0 - smoothstep(0.75, 1.0, dd)) * 0.18 - smoothstep(0.9, 1.0, dd) * (1.0 - smoothstep(1.0, 1.2, dd)) * 0.12;
                        g -= vec3(crater) * step(0.35, hash(cc + 2.0));
                    }
                }
                // Light from the upper left, a touch of terminator shading high up.
                float light = 0.80 + 0.20 * dot(n, normalize(vec3(-0.4, 1.0, 0.25)));
                g *= light;
                // Aerial perspective (thick near the ground, thin high up) and the atmosphere rim seen from space.
                float hazeAmt = (1.0 - exp(-tG * mix(0.0006, 0.0055, air))) * (1.0 - u_body);
                g = mix(g, mix(vec3(0.45, 0.65, 1.0), dayHorizon, air), hazeAmt);
                float rim = pow(1.0 - abs(dot(n, -d)), 4.0) * (1.0 - air) * (1.0 - u_body);
                g += vec3(0.25, 0.55, 1.0) * rim * 0.8;
                col = g;
            }

            // Cloud deck (in front of whatever it covers).
            if (tC > 0.0 && (tG < 0.0 || tC < tG)) {
                vec3 C = o + d * tC;
                vec2 q = vec2(C.x, C.z) * ((u_R + u_cloudAlt) / max(C.y, 1.0));
                float cover = fbm(q / 55.0 + vec2(u_clock * 0.004, 0.0)) + 0.35 * fbm(q / 900.0);
                float a = smoothstep(0.58, 0.72, cover);
                float below = step(alt, u_cloudAlt);                    // seen from underneath: greyer, flatter
                vec3 cloud = mix(vec3(1.0, 0.99, 1.0), vec3(0.78, 0.82, 0.95), below * 0.7 + (1.0 - smoothstep(0.62, 0.8, cover)) * 0.35);
                float fade = exp(-tC * mix(0.0004, 0.0035, air));
                col = mix(col, cloud, a * mix(0.55, 1.0, fade) * (1.0 - u_body));
            }
            // Inside the cloud deck: white-out.
            float inCloud = 1.0 - smoothstep(0.0, 7.0, abs(alt - u_cloudAlt));
            col = mix(col, vec3(0.95, 0.97, 1.0), inCloud * 0.85 * (1.0 - u_body));

            col += vec3(1.0, 0.95, 0.85) * u_flash * 0.35;
            gl_FragColor = vec4(col, 1.0);
        }
        """
        return SKShader(source: source, uniforms: [
            SKUniform(name: "u_res", vectorFloat2: .zero),
            SKUniform(name: "u_cx", float: 0),
            SKUniform(name: "u_horizon", float: 0),
            SKUniform(name: "u_f", float: 1),
            SKUniform(name: "u_alt", float: 1),
            SKUniform(name: "u_pitch", float: 0),
            SKUniform(name: "u_R", float: 6000),
            SKUniform(name: "u_cloudAlt", float: 70),
            SKUniform(name: "u_body", float: 0),
            SKUniform(name: "u_clock", float: 0),
            SKUniform(name: "u_flash", float: 0),
        ])
    }
}
