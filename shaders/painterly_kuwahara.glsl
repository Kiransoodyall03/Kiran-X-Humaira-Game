#[compute]
#version 450

// Painterly post-process: generalized Kuwahara filter (8 sectors, polynomial weights,
// after Kyprianidis et al. 2009/2011) with optional edge darkening and saturation.
// Driven by scripts/rendering/painterly_effect.gd (PainterlyEffect), which runs it twice
// per view: mode 0 filters the scene color into a scratch image, mode 1 copies the
// scratch image back over the scene color. Runs before tonemapping, so colors are
// linear HDR. The filter works on a Reinhard-compressed copy (c / (1 + c)) so bright sky
// doesn't swamp the sector variances, and the result is expanded back to HDR at the end.
//
// Performance (the cost is per pixel, so it scales with resolution and radius^2):
// - each 8x8 group loads its tile plus a radius-wide apron into shared memory once, so
//   the kernel reads shared memory, not the image;
// - the 8 sector weights depend only on the sample offset, so each group builds them
//   into a shared table once instead of per pixel per sample;
// - one accumulator set per sector (compressed color + weight, compressed color^2);
// - only offsets inside the circular kernel are visited.
// Measure with tests/perf/painterly_gpu_probe.gd (windowed).

#define GROUP 8
#define MAX_RADIUS 6 // keep equal to PainterlyEffect.RADIUS_MAX
#define TILE (GROUP + 2 * MAX_RADIUS)
#define KERNEL (2 * MAX_RADIUS + 1)

layout(local_size_x = GROUP, local_size_y = GROUP, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D src_image;
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D dst_image;

layout(push_constant, std430) uniform Params {
	vec2 size;            // image size in pixels
	float radius;         // kernel radius in pixels (1..MAX_RADIUS)
	float sharpness;      // q: how strongly low-variance sectors win
	float hardness;       // scales sector variance before the sharpness power
	float strength;       // 0 = source, 1 = fully filtered
	float edge_darkening; // 0..1 how much edges darken
	float edge_threshold; // luminance gradient where darkening starts
	float saturation;     // 1 = unchanged
	float mode;           // 0 = filter src -> dst, 1 = plain copy src -> dst
	float pad0;
	float pad1;
} params;

const float ZERO_CROSSING = 0.58; // sector overlap (radians); Kyprianidis' recommended value

shared vec3 tile[TILE * TILE];       // compressed color of the group's tile + apron
shared vec4 weights_a[KERNEL * KERNEL]; // sector weights 0-3 per kernel offset
shared vec4 weights_b[KERNEL * KERNEL]; // sector weights 4-7 per kernel offset

vec3 compress(vec3 c) {
	c = max(c, vec3(0.0));
	return c / (1.0 + c);
}

vec3 expand(vec3 c) {
	c = min(c, vec3(0.9995));
	return c / (1.0 - c);
}

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// Generalized Kuwahara sector weights for kernel offset v (in radius units), times the
// Gaussian falloff, normalized so the 8 sectors sum to the Gaussian.
void sector_weights(vec2 v, float zeta, float eta, out vec4 wa, out vec4 wb) {
	float vxx = zeta - eta * v.x * v.x;
	float vyy = zeta - eta * v.y * v.y;
	vec4 w0246 = vec4(v.y + vxx, -v.x + vyy, -v.y + vxx, v.x + vyy);
	vec2 rv = 0.70710678 * vec2(v.x - v.y, v.x + v.y);
	vxx = zeta - eta * rv.x * rv.x;
	vyy = zeta - eta * rv.y * rv.y;
	vec4 w1357 = vec4(rv.y + vxx, -rv.x + vyy, -rv.y + vxx, rv.x + vyy);
	w0246 = max(w0246, vec4(0.0));
	w1357 = max(w1357, vec4(0.0));
	w0246 *= w0246;
	w1357 *= w1357;
	float sum = dot(w0246, vec4(1.0)) + dot(w1357, vec4(1.0));
	float g = exp(-3.125 * dot(v, v)) / max(sum, 1e-6);
	wa = vec4(w0246.x, w1357.x, w0246.y, w1357.y) * g; // sectors 0,1,2,3
	wb = vec4(w0246.z, w1357.z, w0246.w, w1357.w) * g; // sectors 4,5,6,7
}

void main() {
	ivec2 size = ivec2(params.size);
	ivec2 uv = ivec2(gl_GlobalInvocationID.xy);

	if (params.mode > 0.5) {
		if (uv.x < size.x && uv.y < size.y) {
			imageStore(dst_image, uv, imageLoad(src_image, uv));
		}
		return; // uniform across the dispatch, so no barrier is skipped unevenly
	}

	int r = clamp(int(params.radius), 1, MAX_RADIUS);
	int tile_w = GROUP + 2 * r;
	int kernel_w = 2 * r + 1;
	int local_index = int(gl_LocalInvocationIndex);
	ivec2 origin = ivec2(gl_WorkGroupID.xy) * GROUP - ivec2(r);

	// 1. Tile + apron into shared memory (compressed, clamped at the image border).
	for (int i = local_index; i < tile_w * tile_w; i += GROUP * GROUP) {
		ivec2 p = origin + ivec2(i % tile_w, i / tile_w);
		tile[i] = compress(imageLoad(src_image, clamp(p, ivec2(0), size - 1)).rgb);
	}
	// 2. Sector weight table for this radius.
	float zeta = 2.0 / float(r);
	float sin_zc = sin(ZERO_CROSSING);
	float eta = (zeta + cos(ZERO_CROSSING)) / (sin_zc * sin_zc);
	for (int i = local_index; i < kernel_w * kernel_w; i += GROUP * GROUP) {
		vec2 v = vec2(float(i % kernel_w - r), float(i / kernel_w - r)) / float(r);
		vec4 wa;
		vec4 wb;
		sector_weights(v, zeta, eta, wa, wb);
		weights_a[i] = wa;
		weights_b[i] = wb;
	}
	barrier();

	if (uv.x >= size.x || uv.y >= size.y) {
		return;
	}

	// 3. Accumulate every offset inside the circle into the 8 sectors.
	vec4 m[8]; // xyz = weighted compressed color, w = weight
	vec3 s[8]; // weighted compressed color squared
	for (int k = 0; k < 8; k++) {
		m[k] = vec4(0.0);
		s[k] = vec3(0.0);
	}
	ivec2 local = ivec2(gl_LocalInvocationID.xy) + ivec2(r);
	float r2 = float(r * r);
	for (int y = -r; y <= r; y++) {
		int x_extent = int(floor(sqrt(max(r2 - float(y * y), 0.0)) + 1e-4));
		int row = (local.y + y) * tile_w + local.x;
		int wrow = (y + r) * kernel_w + r;
		for (int x = -x_extent; x <= x_extent; x++) {
			vec4 c = vec4(tile[row + x], 1.0);
			vec3 c2 = c.rgb * c.rgb;
			vec4 wa = weights_a[wrow + x];
			vec4 wb = weights_b[wrow + x];
			m[0] += c * wa.x; s[0] += c2 * wa.x;
			m[1] += c * wa.y; s[1] += c2 * wa.y;
			m[2] += c * wa.z; s[2] += c2 * wa.z;
			m[3] += c * wa.w; s[3] += c2 * wa.w;
			m[4] += c * wb.x; s[4] += c2 * wb.x;
			m[5] += c * wb.y; s[5] += c2 * wb.y;
			m[6] += c * wb.z; s[6] += c2 * wb.z;
			m[7] += c * wb.w; s[7] += c2 * wb.w;
		}
	}

	// 4. Blend the sector means, favouring flat (low-variance) sectors.
	vec4 acc = vec4(0.0);
	for (int k = 0; k < 8; k++) {
		if (m[k].w <= 0.0) {
			continue;
		}
		vec3 mean = m[k].rgb / m[k].w;
		vec3 var = abs(s[k] / m[k].w - mean * mean);
		float sigma2 = var.r + var.g + var.b;
		float wk = 1.0 / (1.0 + pow(params.hardness * 1000.0 * sigma2, 0.5 * params.sharpness));
		acc += vec4(mean * wk, wk);
	}
	int center = local.y * tile_w + local.x;
	vec3 filtered_c = acc.w > 0.0 ? acc.rgb / acc.w : tile[center];

	// 5. Ink-like edge darkening: Sobel on compressed luminance from the tile.
	if (params.edge_darkening > 0.0) {
		float tl = luma(tile[center - tile_w - 1]);
		float t = luma(tile[center - tile_w]);
		float tr = luma(tile[center - tile_w + 1]);
		float l = luma(tile[center - 1]);
		float rr = luma(tile[center + 1]);
		float bl = luma(tile[center + tile_w - 1]);
		float b = luma(tile[center + tile_w]);
		float br = luma(tile[center + tile_w + 1]);
		float gx = (tr + 2.0 * rr + br) - (tl + 2.0 * l + bl);
		float gy = (bl + 2.0 * b + br) - (tl + 2.0 * t + tr);
		float edge = smoothstep(params.edge_threshold, params.edge_threshold + 0.25, length(vec2(gx, gy)));
		filtered_c *= 1.0 - params.edge_darkening * edge;
	}

	vec3 filtered = expand(filtered_c);
	float lum = luma(filtered);
	filtered = max(mix(vec3(lum), filtered, params.saturation), vec3(0.0));

	vec4 source = imageLoad(src_image, uv);
	imageStore(dst_image, uv, vec4(mix(source.rgb, filtered, params.strength), source.a));
}
