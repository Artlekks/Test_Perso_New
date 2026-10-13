
float random(inout uint seed) {
	int k;
	int s = int(seed);
	if (s == 0) {
		s = 305420679;
	}
	k = s / 127773;
	s = 16807 * (s - k * 127773) - 2836 * k;
	if (s < 0) {
		s += 2147483647;
	}
	seed = uint(s);
	return float(seed % uint(65536)) / 65535.0;
}

float random_range(inout uint seed, float a, float b) {
	return mix(a, b, random(seed));
}

vec3 random_direction(inout uint seed) {
	float z = random_range(seed, -1.0, 1.0);
	float t = random_range(seed, 0.0, TAU);
	float r  = sqrt(1.0 - z * z);
	float x = r * cos(t);
	float y = r * sin(t);
	
	return vec3(x, y, z);
}

uint hash(uint x) {
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = (x >> uint(16)) ^ x;
	return x;
}