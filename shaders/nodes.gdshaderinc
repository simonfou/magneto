// Node uniforms and helpers shared by the two particle-process shaders
// (include common.gdshaderinc first). main.gd fills them every frame:
// MAX_NODES slots, each faded in and out by its weight, so the number of
// nodes on screen varies like in the original (0 to 6).

const int MAX_NODES = 6;

uniform vec3 nodes[MAX_NODES];
uniform vec3 axes[MAX_NODES];
uniform vec3 hues[MAX_NODES];
uniform float weights[MAX_NODES];  // 0..1, eased in main.gd
uniform vec3 centroid = vec3(0.0); // centre of the live nodes, from main.gd

// A node holds particles once it is more than half faded in.
bool alive(int i) {
	return weights[i] > 0.5;
}

// Rendezvous hashing: the node this key scores highest on, among all slots
// or only the live ones (-1 if none). Switching one node off only moves the
// particles that were on it; everyone else keeps their node.
int pick_node(uint key, bool only_alive) {
	int best = -1;
	float top = -1.0;
	for (int i = 0; i < MAX_NODES; i++) {
		float s = hash(key * 2246822519u + uint(i) * 3266489917u + 3u);
		if (s > top && (!only_alive || alive(i))) {
			best = i;
			top = s;
		}
	}
	return best;
}
