shader_type canvas_item;

// ================= STARFIELD SHADER v1.6.0 =================
// Level-2 geodesic (subdivided icosahedron) projection.
// 320 triangular faces — seams imperceptible at any rotation.
// Grid-based star placement within each face for performance.
// Full rotation freedom, no poles, no stretching.
//
// Lookup is hierarchical:
//   1. Find nearest icosahedron face (20 dot products)
//   2. Find nearest level-1 subdivision tri within it (4 dot products)
//   3. Find nearest level-2 subdivision tri within that (4 dot products)
//   4. Map to 2D UV for grid star lookup

uniform float spark_count    : hint_range(0.0, 100000.0) = 0.0;
uniform float time_offset    : hint_range(0.0, 1000.0)   = 0.0;
uniform mat3  view_matrix;

// Constellation star overlays — fed from starfield_background.gd each frame
const int MAX_CONST_STARS = 64;
uniform int   constellation_star_count                        = 0;
uniform vec3  constellation_star_dirs[MAX_CONST_STARS];
uniform float constellation_star_brightnesses[MAX_CONST_STARS];

// --- Hash functions ---
float hash11(float n) {
	return fract(sin(n) * 43758.5453123);
}
float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}
vec2 hash22(vec2 p) {
	return fract(sin(vec2(
		dot(p, vec2(127.1, 311.7)),
		dot(p, vec2(269.5, 183.3))
	)) * 43758.5453123);
}

// --- Icosahedron vertices (unit sphere) ---
// Golden ratio phi = (1 + sqrt(5)) / 2 ≈ 1.61803
// 12 vertices from three orthogonal golden rectangles
const float PHI = 1.61803398875;
const float INORM = 0.52573111;  // 1/sqrt(1 + phi^2)
const float PNORM = 0.85065080;  // phi/sqrt(1 + phi^2)

vec3 ico_vert(int i) {
	// 12 icosahedron vertices on unit sphere
	if (i == 0)  return vec3( 0.0,    INORM,  PNORM);
	if (i == 1)  return vec3( 0.0,   -INORM,  PNORM);
	if (i == 2)  return vec3( 0.0,    INORM, -PNORM);
	if (i == 3)  return vec3( 0.0,   -INORM, -PNORM);
	if (i == 4)  return vec3( INORM,  PNORM,  0.0);
	if (i == 5)  return vec3(-INORM,  PNORM,  0.0);
	if (i == 6)  return vec3( INORM, -PNORM,  0.0);
	if (i == 7)  return vec3(-INORM, -PNORM,  0.0);
	if (i == 8)  return vec3( PNORM,  0.0,    INORM);
	if (i == 9)  return vec3(-PNORM,  0.0,    INORM);
	if (i == 10) return vec3( PNORM,  0.0,   -INORM);
	             return vec3(-PNORM,  0.0,   -INORM);
}

// 20 icosahedron faces (vertex index triples, outward winding)
void ico_face(int f, out int a, out int b, out int c) {
	if      (f==0)  { a=0;  b=1;  c=8;  }
	else if (f==1)  { a=0;  b=8;  c=4;  }
	else if (f==2)  { a=0;  b=4;  c=5;  }
	else if (f==3)  { a=0;  b=5;  c=9;  }
	else if (f==4)  { a=0;  b=9;  c=1;  }
	else if (f==5)  { a=1;  b=6;  c=8;  }
	else if (f==6)  { a=8;  b=6;  c=10; }
	else if (f==7)  { a=8;  b=10; c=4;  }
	else if (f==8)  { a=4;  b=10; c=2;  }
	else if (f==9)  { a=4;  b=2;  c=5;  }
	else if (f==10) { a=5;  b=2;  c=11; }
	else if (f==11) { a=5;  b=11; c=9;  }
	else if (f==12) { a=9;  b=11; c=7;  }
	else if (f==13) { a=9;  b=7;  c=1;  }
	else if (f==14) { a=1;  b=7;  c=6;  }
	else if (f==15) { a=3;  b=10; c=6;  }
	else if (f==16) { a=3;  b=2;  c=10; }
	else if (f==17) { a=3;  b=11; c=2;  }
	else if (f==18) { a=3;  b=7;  c=11; }
	else            { a=3;  b=6;  c=7;  }
}

// --- Find nearest icosahedron face for a ray ---
// Returns face index 0..19
int nearest_ico_face(vec3 ray) {
	int best = 0;
	float best_d = -2.0;
	for (int f = 0; f < 20; f++) {
		int a; int b; int c;
		ico_face(f, a, b, c);
		vec3 fn = normalize(ico_vert(a) + ico_vert(b) + ico_vert(c));
		float d = dot(ray, fn);
		if (d > best_d) { best_d = d; best = f; }
	}
	return best;
}

// --- Subdivide a triangle once (level 1 -> 4 children) ---
// Given parent triangle (va, vb, vc), child index 0..3:
//   0: va, mab, mca
//   1: mab, vb, mbc
//   2: mca, mbc, vc
//   3: mab, mbc, mca  (center)
// Edge midpoints normalized to sphere surface.
void subdivide(vec3 va, vec3 vb, vec3 vc, int child,
			   out vec3 oa, out vec3 ob, out vec3 oc) {
	vec3 mab = normalize(va + vb);
	vec3 mbc = normalize(vb + vc);
	vec3 mca = normalize(vc + va);
	if      (child == 0) { oa = va;  ob = mab; oc = mca; }
	else if (child == 1) { oa = mab; ob = vb;  oc = mbc; }
	else if (child == 2) { oa = mca; ob = mbc; oc = vc;  }
	else                 { oa = mab; ob = mbc; oc = mca; }
}

// --- Find nearest child triangle ---
int nearest_child(vec3 ray, vec3 va, vec3 vb, vec3 vc) {
	int best = 0;
	float best_d = -2.0;
	for (int child = 0; child < 4; child++) {
		vec3 oa; vec3 ob; vec3 oc;
		subdivide(va, vb, vc, child, oa, ob, oc);
		vec3 fn = normalize(oa + ob + oc);
		float d = dot(ray, fn);
		if (d > best_d) { best_d = d; best = child; }
	}
	return best;
}

// --- Project ray onto triangle -> 2D UV ---
// Uses the two edge vectors as a local 2D basis.
vec2 tri_to_uv(vec3 ray, vec3 va, vec3 vb, vec3 vc) {
	vec3 ab = vb - va;
	vec3 ac = vc - va;
	vec3 n  = cross(ab, ac);
	float t = dot(va, n) / max(dot(ray, n), 0.0001);
	vec3 p  = ray * t - va;
	// Project onto ab, ac as local axes
	float u = dot(p, ab) / max(dot(ab, ab), 0.0001);
	float v = dot(p, ac) / max(dot(ac, ac), 0.0001);
	return vec2(u, v);
}

uniform vec2 viewport_size = vec2(1920.0, 1080.0);

void fragment() {
    vec2 res = viewport_size;

    // Screen UV -> ray with correct FOV
    vec2 ndc = (UV - 0.5) * 2.0;
    ndc.x *= res.x / res.y;
    const float HFOV_DEG = 75.0;
    float focal = (res.x / res.y) / tan(radians(HFOV_DEG * 0.5));
    vec3 ray = normalize(vec3(ndc, focal));
    ray = view_matrix * ray;
    ray = normalize(ray);

    vec3 color = vec3(0.0, 0.0, 0.02);

    // -------------------------------------------------------
    // SEAMLESS SPHERICAL STAR FIELD
    // Stars are placed by hashing 3D sphere cells directly.
    // No face boundaries, no UV seams, no structural repeats.
    // -------------------------------------------------------
    float star_density = spark_count < 10.0
        ? 0.0
        : smoothstep(10.0, 2000.0, spark_count);

    // Cell size controls star density — smaller = more stars.
    // 0.08 gives roughly 1500-2000 stars across the full sphere.
    const float CELL_SIZE = 0.08;

    // Build two orthogonal tangent vectors to the ray so we can
    // search neighbouring sphere cells in all directions.
    vec3 up      = abs(ray.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(up, ray));
    vec3 bitangent = cross(ray, tangent);

    // Search a 3x3x3 neighbourhood of sphere cells.
    for (int ix = -1; ix <= 1; ix++) {
        for (int iy = -1; iy <= 1; iy++) {
            for (int iz = -1; iz <= 1; iz++) {
                // Candidate cell centre on the unit sphere
                vec3 offset = vec3(float(ix), float(iy), float(iz)) * CELL_SIZE;
                vec3 cell_dir = normalize(ray + tangent * offset.x
                                              + bitangent * offset.y
                                              + ray * offset.z);

                // Quantise to cell
                vec3 cell = floor(cell_dir / CELL_SIZE) * CELL_SIZE;
                float cell_hash = hash11(
                    hash11(cell.x * 127.1 + cell.y * 311.7) * 43758.5
                    + cell.z * 74.3
                );

                // Cull by density
                if (cell_hash > star_density) continue;

                // Place star randomly within cell on sphere surface
                vec2 jitter = hash22(vec2(cell_hash * 7.3, cell_hash * 13.1));
                vec3 star_dir = normalize(cell + vec3(jitter, hash11(cell_hash * 3.7)) * CELL_SIZE);

                float align = dot(ray, star_dir);
                if (align < 0.9998) continue;

                float angle = acos(clamp(align, -1.0, 1.0));

                // Clean round point — no UV distortion possible
                float base_brightness = 0.45 + hash11(cell_hash * 5.1) * 0.55;

                float twinkle_phase = hash11(cell_hash * 3.7) * 6.28318;
                float twinkle_speed = 0.15 + hash11(cell_hash * 11.1) * 0.6;
                float twinkle       = 0.85 + 0.15 * sin(time_offset * twinkle_speed + twinkle_phase);

                float brightness = base_brightness * twinkle;
                float star_size  = 0.0012 + hash11(cell_hash * 5.1) * 0.0018;
                float star       = smoothstep(star_size, 0.0, angle) * brightness;

                float blue_shift = 0.85 + hash11(cell_hash * 2.3) * 0.15;
                color += vec3(
                    star * (0.85 + hash11(cell_hash) * 0.15),
                    star * (0.90 + hash11(cell_hash * 1.7) * 0.10),
                    star * blue_shift
                );
            }
        }
    }

    // -------------------------------------------------------
    // CONSTELLATION STARS — unchanged from original
    // -------------------------------------------------------
    for (int i = 0; i < MAX_CONST_STARS; i++) {
        if (i >= constellation_star_count) break;
        float b = constellation_star_brightnesses[i];
        if (b <= 0.0) continue;
        vec3  sdir  = normalize(constellation_star_dirs[i]);
        float align = dot(ray, sdir);
        if (align < 0.97) continue;
        float angle  = acos(clamp(align, -1.0, 1.0));
        float core   = smoothstep(0.005, 0.0,   angle) * b;
        float glow   = smoothstep(0.022, 0.005,  angle) * b * 0.45;
        float corona = smoothstep(0.05,  0.022,  angle) * b * 0.12;
        color += vec3(1.0, 0.96, 0.80) * core
               + vec3(0.9, 0.80, 0.55) * glow
               + vec3(0.6, 0.50, 0.35) * corona;
    }

    COLOR = vec4(color, 1.0);
}