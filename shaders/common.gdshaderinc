// Helpers shared by every magneto shader.

float hash(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return float(x) / 4294967295.0;
}

vec3 random_unit(uint seed) {
	float z = hash(seed) * 2.0 - 1.0;
	float a = hash(seed + 1u) * TAU;
	float r = sqrt(1.0 - z * z);
	return vec3(r * cos(a), r * sin(a), z);
}

// Cheap swirly flow: each component depends on the other axes, which
// gives long ribbon-like streams rather than random noise.
vec3 flow_noise(vec3 p, float t) {
	return vec3(
		sin(p.y * 1.3 + t) + cos(p.z * 1.7 - t * 0.7),
		sin(p.z * 1.1 - t * 0.8) + cos(p.x * 1.5 + t * 0.6),
		sin(p.x * 1.2 + t * 0.9) + cos(p.y * 1.4 - t * 0.5)) * 0.5;
}

// Breathing: each instance has a fixed rank; it shows only while the
// music's presence (0..1) is above that rank, with a soft edge.
float presence_fade(uint id, float level) {
	float rank = hash(id * 3266489917u + 17u);
	return smoothstep(level + 0.04, level - 0.04, rank);
}
