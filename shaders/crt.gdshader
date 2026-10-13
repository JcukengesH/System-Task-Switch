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
uniform float glow_strength : hint_range(0.0, 2.0) = 0.55;
uniform float flicker : hint_range(0.0, 0.05) = 0.012;
uniform float flicker_speed : hint_range(0.0, 40.0) = 12.0;
uniform float brightness : hint_range(0.5, 2.0) = 1.05;

// Гибрид «Authentic-but-readable»: квантизация оставлена, но почти
// невидима — лёгкое «выравнивание» краёв вместо мозаики (фидбек: текст
// должен читаться без напряжения).
uniform float pixel_block : hint_range(1.0, 8.0) = 1.2;
// Сигнальные артефакты, управляемые спектром музыки (см. spectrum_fx.gd):
// бас рвёт синхронизацию по горизонтали, верха — по вертикали + шум.
// В шейдере они гейтятся пиками огибающих (bass_pk/treb_pk), поэтому в
// тишине картинка остаётся чистой, как в старом мягком CRT.
uniform float jitter_amount : hint_range(0.0, 0.05) = 0.004;
uniform float roll_amount : hint_range(0.0, 0.08) = 0.008;
uniform float grain_amount : hint_range(0.0, 0.25) = 0.025;

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

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

vec3 glow_at(vec2 uv) {
	// Дешёвый крест из 4 отсчётов вместо 24: легче Deck'у, а при поднятой
	// силе даёт мягкое хало вокруг букв — как старый плавный bloom, без мыла.
	// Маска по яркости — чтобы glow не молочил фон.
	float r = glow_radius;
	vec3 acc = texture(screen_texture, uv + vec2(r, 0.0)).rgb
		+ texture(screen_texture, uv - vec2(r, 0.0)).rgb
		+ texture(screen_texture, uv + vec2(0.0, r)).rgb
		+ texture(screen_texture, uv - vec2(0.0, r)).rgb;
	vec3 avg = acc * 0.25;
	float lum = dot(avg, vec3(0.299, 0.587, 0.114));
	float mask = smoothstep(0.35, 0.9, lum);
	return avg * mask;
}

void fragment() {
	float eff = effect_scale;

	// Пиковые гейты: артефакты «жестяного» терминала показываем только когда
	// музыка реально бьёт. В остальное время — чистый мягкий CRT старого стиля.
	float bass_pk = smoothstep(0.55, 1.0, music_bass);
	float mid_pk  = smoothstep(0.55, 1.0, music_mid);
	float treb_pk = smoothstep(0.60, 1.0, music_treble);

	// Пространственные искажения — самые «телесные» эффекты, скейлим прямо.
	vec2 uv = SCREEN_UV;
	uv = barrel(uv, curvature * eff);
	uv = fov_distort(uv, fov_warp * eff);

	// Сигнальные артефакты квантованы по времени (~24 FPS): срывы синхронизации
	// скачут, как на настоящем мониторе, а не плавно колышутся. Срыв — полосами
	// (8 горизонтальных зон), а не построчно: иначе глитч дробит текст в шум.
	float tstep = floor(TIME * 24.0);
	vec2 grid = vec2(1.0) / (SCREEN_PIXEL_SIZE * pixel_block);
	float band = floor(uv.y * 8.0);
	uv.x += (hash21(vec2(band, tstep)) - 0.5) * jitter_amount * eff * bass_pk * 2.0;
	uv.y += (hash21(vec2(tstep, 11.0)) - 0.5) * roll_amount * eff * treb_pk;

	bool inside = (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0);

	vec3 col = vec3(0.0);
	if (inside) {
		// «Низкое разрешение»: все выборки — из центров ячеек пиксельной сетки.
		vec2 quv = (floor(uv * grid) + 0.5) / grid;
		float dist = length(quv - 0.5);

		float glow_mul = 1.0 + music_pulse * music_glow_boost * eff;
		float aberr_mul = 1.0 + (music_pulse * music_aberration_boost + music_treble * 1.5) * eff;

		vec2 dir = normalize(quv - 0.5 + 1e-6);
		vec2 off = dir * (aberration * eff) * aberr_mul * dist;
		float r = texture(screen_texture, quv - off).r;
		float g = texture(screen_texture, quv).g;
		float b = texture(screen_texture, quv + off).b;
		vec3 base = vec3(r, g, b);

		vec3 bloom = glow_at(quv) * (glow_strength * eff) * glow_mul;
		col = base + bloom;

		// Виньетку считаем первой — от неё зависит мягкость скан-линий по краям.
		vec2 vc = quv - 0.5;
		float vig = clamp(1.0 - dot(vc, vc) * (vignette_strength * eff) * 2.0, 0.0, 1.0);

		// Скан-линии: возвращаем старую плавность (нативные строки, sin-развёртка),
		// затухают к краям экрана вместе с виньеткой. Середина музыки «поджигает»
		// контраст полос, но только на пиках.
		vec2 pixel = quv / SCREEN_PIXEL_SIZE;
		float scan = sin(pixel.y * 3.14159265) * 0.5 + 0.5;
		col *= mix(1.0, scan, scanline_strength * eff * (1.0 + mid_pk * 1.2) * vig);

		col *= vig;

		// Помехи: зерно по ТВ-пикселю, но постоянная составляющая убрана —
		// шум сыплется только когда верха реально ударили (люминофор при помехе).
		float vrow = floor(quv.y * grid.y);
		float grain = hash21(vec2(vrow, floor(quv.x * grid.x) + tstep * 97.0)) - 0.5;
		col += grain * grain_amount * eff * (0.1 + treb_pk);

		col *= 1.0 + sin(TIME * flicker_speed) * (flicker * eff);
		// Доля — ступенчатая вспышка яркости, без плавного «дыхания».
		col *= 1.0 + step(0.68, music_pulse) * music_flicker_boost * 0.6 * eff;
		col *= brightness * (1.0 + step(0.8, music_pulse) * music_brightness_boost * 0.3 * eff);
	}

	COLOR = vec4(col, 1.0);
}