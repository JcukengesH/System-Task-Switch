shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;

// Глобальная сила эффектов. Управляется из GDScript по прогрессу игрока.
uniform float effect_scale : hint_range(0.0, 2.0) = 0.15;

// FOV-подобное искажение (эффект «расширения» картинки).
uniform float fov_warp : hint_range(0.0, 0.6) = 0.10;

// Базовые значения — работают как множители при effect_scale = 1.0.
uniform float curvature : hint_range(0.0, 0.3) = 0.06;
uniform float scanline_strength : hint_range(0.0, 0.6) = 0.18;
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.45;
uniform float aberration : hint_range(0.0, 0.006) = 0.0006;
uniform float glow_radius : hint_range(0.0, 0.01) = 0.003;
uniform float glow_strength : hint_range(0.0, 2.0) = 0.35;
uniform float flicker : hint_range(0.0, 0.05) = 0.012;
uniform float flicker_speed : hint_range(0.0, 40.0) = 12.0;
uniform float brightness : hint_range(0.5, 2.0) = 1.05;

// Аудио-реакция (задаётся GDScript'ом).
uniform float music_bass : hint_range(0.0, 1.0) = 0.0;
uniform float music_mid : hint_range(0.0, 1.0) = 0.0;
uniform float music_treble : hint_range(0.0, 1.0) = 0.0;
uniform float music_pulse : hint_range(0.0, 1.0) = 0.0;
uniform float music_glow_boost : hint_range(0.0, 10.0) = 2.0;
uniform float music_aberration_boost : hint_range(0.0, 12.0) = 1.5;
uniform float music_flicker_boost : hint_range(0.0, 4.0) = 0.5;
uniform float music_brightness_boost : hint_range(0.0, 3.0) = 0.6;

vec2 barrel(vec2 uv, float k) {
	vec2 cc = uv - 0.5;
	float d = dot(cc, cc);
	return uv + cc * d * k;
}

// FOV-подобное искажение: центр почти не трогается, края раздуваются сильнее.
vec2 fov_distort(vec2 uv, float amount) {
	vec2 cc = uv - 0.5;
	float d = dot(cc, cc);
	float d2 = d * d;
	return uv + cc * (d * 0.55 + d2 * 1.45) * amount;
}

vec3 glow_at(vec2 uv) {
	vec3 acc = vec3(0.0);
	float total = 0.0;
	for (int i = 0; i < 12; i++) {
		float a = float(i) / 12.0 * 6.2831853;
		float r1 = glow_radius * 0.6;
		float r2 = glow_radius * 1.2;
		vec2 o1 = vec2(cos(a), sin(a)) * r1;
		vec2 o2 = vec2(cos(a) + 0.5, sin(a) + 0.5) * r2;
		vec3 s1 = texture(screen_texture, uv + o1).rgb;
		vec3 s2 = texture(screen_texture, uv + o2).rgb;
		acc += s1 * 1.0 + s2 * 0.6;
		total += 1.6;
	}
	vec3 avg = acc / total;
	float lum = dot(avg, vec3(0.299, 0.587, 0.114));
	float mask = smoothstep(0.35, 0.9, lum);
	return avg * mask;
}

void fragment() {
	float eff = effect_scale;

	// Пространственные искажения — самые «телесные» эффекты, скейлим прямо.
	vec2 uv = SCREEN_UV;
	uv = barrel(uv, curvature * eff);
	uv = fov_distort(uv, fov_warp * eff);

	bool inside = (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0);

	vec3 col = vec3(0.0);
	if (inside) {
		float dist = length(uv - 0.5);

		float glow_mul = 1.0 + music_pulse * music_glow_boost * eff;
		float aberr_mul = 1.0 + (music_pulse * music_aberration_boost + music_treble * 1.5) * eff;

		vec2 dir = normalize(uv - 0.5 + 1e-6);
		vec2 off = dir * (aberration * eff) * aberr_mul * dist;
		float r = texture(screen_texture, uv - off).r;
		float g = texture(screen_texture, uv).g;
		float b = texture(screen_texture, uv + off).b;
		vec3 base = vec3(r, g, b);

		vec3 bloom = glow_at(uv) * (glow_strength * eff) * glow_mul;
		col = base + bloom;

		vec2 pixel = uv / SCREEN_PIXEL_SIZE;
		float scan = sin(pixel.y * 3.14159265) * 0.5 + 0.5;
		col *= mix(1.0, scan, scanline_strength * eff);

		vec2 vc = uv - 0.5;
		float vig = 1.0 - dot(vc, vc) * (vignette_strength * eff) * 2.0;
		col *= clamp(vig, 0.0, 1.0);

		col *= 1.0 + sin(TIME * flicker_speed) * (flicker * eff);
		col *= 1.0 + music_pulse * music_flicker_boost * eff;
		col *= brightness * (1.0 + music_pulse * music_brightness_boost * eff);
	}

	COLOR = vec4(col, 1.0);
}