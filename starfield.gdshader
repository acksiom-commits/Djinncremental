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
uniform float rotation_speed : hint_range(0.0, 1.0)      = 0.025;
uniform mat3  view_matrix;

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


void fragment() {
	vec2 res = 1.0 / TEXTURE_PIXEL_SIZE;

	// Screen UV -> ray
	vec2 ndc = (UV - 0.5) * 2.0;
	ndc.x *= res.x / res.y;
	vec3 ray = normalize(vec3(ndc, 0.5));

	// Auto-rotation around Y
	float auto_angle = time_offset * rotation_speed * 0.12;
	float ca = cos(auto_angle); float sa = sin(auto_angle);
	mat3 auto_rot = mat3(
		vec3( ca, 0.0, sa),
		vec3(0.0, 1.0, 0.0),
		vec3(-sa, 0.0, ca)
	);
	ray = view_matrix * auto_rot * ray;
	ray = normalize(ray);

	// --- Hierarchical face lookup ---
	// Level 0: nearest icosahedron face
	int face0 = nearest_ico_face(ray);
	int fa; int fb; int fc;
	ico_face(face0, fa, fb, fc);
	vec3 v0a = ico_vert(fa);
	vec3 v0b = ico_vert(fb);
	vec3 v0c = ico_vert(fc);

	// Level 1: nearest subdivision child
	int child1 = nearest_child(ray, v0a, v0b, v0c);
	vec3 v1a; vec3 v1b; vec3 v1c;
	subdivide(v0a, v0b, v0c, child1, v1a, v1b, v1c);

	// Level 2: nearest subdivision child of child
	int child2 = nearest_child(ray, v1a, v1b, v1c);
	vec3 v2a; vec3 v2b; vec3 v2c;
	subdivide(v1a, v1b, v1c, child2, v2a, v2b, v2c);

	// Project ray onto final triangle -> UV
	vec2 tri_uv = tri_to_uv(ray, v2a, v2b, v2c);

	// Unique seed for this level-2 triangle
	// Encode face0 (0..19), child1 (0..3), child2 (0..3) into seed
float face_seed = hash11(float(face0) * 100.0
                + float(child1) * 17.0
                + float(child2) * 7.0) * 43758.5453;

	// Star density
	float max_stars    = 2000.0;
	float star_density = spark_count < 10.0 ? 0.0 : smoothstep(10.0, 2000.0, spark_count);
	float visible      = star_density * max_stars;
	// Each of 320 faces gets equal share
	float face_visible = visible / 320.0 * 4.0; // ~4 stars max per face

	vec3 color = vec3(0.0, 0.0, 0.02);

	// Grid star lookup within this face's UV space
	float grid_size = 6.0; // small grid per face — faces are tiny
	vec2 cell    = floor(tri_uv * grid_size);
	vec2 cell_uv = fract(tri_uv * grid_size);

	for (float x = -1.0; x <= 1.0; x += 1.0) {
		for (float y = -1.0; y <= 1.0; y += 1.0) {
			vec2 neighbor   = cell + vec2(x, y);
			// Bake face seed into hash to prevent cross-face collisions
			float cell_hash = hash21(neighbor + vec2(face_seed, face_seed * 0.7));

			if (cell_hash > face_visible) continue;

			vec2 star_pos = hash22(neighbor + vec2(face_seed + 13.7, face_seed + 41.3));
			vec2 offset   = cell_uv - star_pos - vec2(x, y);

			float base_brightness = 0.55 + hash11(cell_hash * 7.3) * 0.45;

			float twinkle_phase = hash11(cell_hash * 3.7) * 6.28318;
			float twinkle_speed = 0.15 + hash11(cell_hash * 11.1) * 0.6;
			float twinkle = 0.5 + 0.5 * sin(time_offset * twinkle_speed + twinkle_phase);

            float brightness = base_brightness * twinkle;

			float star_size = 0.025 + hash11(cell_hash * 5.1) * 0.035;
			float dist      = length(offset);
			float star      = smoothstep(star_size, 0.0, dist) * brightness;

			float blue_shift = 0.85 + hash11(cell_hash * 2.3) * 0.15;
			vec3 star_color = vec3(
				star * (0.85 + hash11(cell_hash) * 0.15),
				star * (0.90 + hash11(cell_hash * 1.7) * 0.10),
				star * blue_shift
			);

			color += star_color;
		}
	}

	COLOR = vec4(color, 1.0);
}
