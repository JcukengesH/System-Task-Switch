shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;

// Два слоя силы эффектов (см. main.gd _update_effect_scale):
// base_effect  — «геометрия и свет» CRT: бочка, FOV, виньетка, скан-линии,
//                glow, аберрация. Растёт только с комбо — на музыку не
//                реагирует вовсе. Бочка — это терминал, она живёт всегда.
// music_effect — «помехи»: срывы синхронизации, зерно, вспышки. Живёт только
//                музыкой; в тишине = 0 и картинка чистая.
uniform float base_effect : hint_range(0.0, 2.0) = 0.15;
uniform float music_effect : hint_range(0.0, 2.0) = 0.0;

// Стадийные слои «безумия системы» (см. main.gd _update_stage_fx_layers):
// какой артефакт вообще имеет право шевелиться картинкой. Индекс слоя =
// этап разблокировки: 1 HEX — артефактов нет (живёт только пульс рамок в
// GDScript); 2 POLYMETRY — fx_scan (дыхание скан-линий/виньетки/glow);
// 3 STROOPTEST — fx_glitch (микро-срывы строки и RGB-расщепление);
// 4 THE SEQUENCE — fx_madness (зерно, ролл, вспышки: полная потеря синхронизации).
uniform float fx_scan : hint_range(0.0, 1.0) = 0.0;
uniform float fx_glitch : hint_range(0.0, 1.0) = 0.0;
uniform float fx_madness : hint_range(0.0, 1.0) = 0.0;

// FOV-подобное искажение (эффект «расширения» картинки).
uniform float fov_warp : hint_range(0.0, 0.6) = 0.10;

// Базовые значения — работают как множители при base_effect = 1.0.
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
// бас/beat рвут синхронизацию по горизонтали, верха/hiss — по вертикали + шум.
uniform float jitter_amount : hint_range(0.0, 0.05) = 0.004;
uniform float roll_amount : hint_range(0.0, 0.08) = 0.008;
uniform float grain_amount : hint_range(0.0, 0.25) = 0.025;

// Аудио-каналы (задаёт GDScript; 5 полос + beat + hiss + общий pulse).
uniform float music_bass : hint_range(0.0, 1.0) = 0.0;
uniform float music_lowmid : hint_range(0.0, 1.0) = 0.0;
uniform float music_mid : hint_range(0.0, 1.0) = 0.0;
uniform float music_highmid : hint_range(0.0, 1.0) = 0.0;
uniform float music_treble : hint_range(0.0, 1.0) = 0.0;
uniform float music_pulse : hint_range(0.0, 1.0) = 0.0;
uniform float music_beat : hint_range(0.0, 1.0) = 0.0;
uniform float music_texture : hint_range(0.0, 1.0) = 0.0;
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
	float base = base_effect;
	float mus = music_effect;
	// Жёсткие артефакты (срывы/расщепление) суммируют глитч-этапы: на
	// «четвёртом» glitch откатан к дефолту, но madness его усиливает.
	float hard = fx_glitch + fx_madness;

	// Пиковые гейты каналов: «жестяные» артефакты берём из верха отклика
	// каждой полосы, чтобы тихие партии не шевелили картинку.
	float bass_pk = smoothstep(0.30, 0.95, music_bass);
	float lowmid_pk = smoothstep(0.30, 0.95, music_lowmid);
	float mid_pk  = smoothstep(0.35, 0.95, music_mid);
	float highmid_pk = smoothstep(0.35, 0.95, music_highmid);
	float treb_pk = smoothstep(0.35, 0.95, music_treble);

	// Пространственные искажения — только базовый слой (комбо), без музыки.
	vec2 uv = SCREEN_UV;
	uv = barrel(uv, curvature * base);
	uv = fov_distort(uv, fov_warp * base);

	// Сигнальные артефакты квантованы по времени (~24 FPS): срывы синхронизации
	// скачут, как на настоящем мониторе, а не плавно колышутся. Срыв — полосами
	// (8 горизонтальных зон), а не построчно: иначе глитч дробит текст в шум.
	float tstep = floor(TIME * 24.0);
	vec2 grid = vec2(1.0) / (SCREEN_PIXEL_SIZE * pixel_block);
	float band = floor(uv.y * 8.0);
	// Бас «бьёт» развёртку, beat (фронт удара) добавляет колкость.
	float punch = clamp(bass_pk + music_beat * 1.4, 0.0, 1.5);
	uv.x += (hash21(vec2(band, tstep)) - 0.5) * jitter_amount * mus * punch * 2.0 * hard;
	// Верхa и шипение уводят вертикалку.
	uv.y += (hash21(vec2(tstep, 11.0)) - 0.5) * roll_amount * mus * fx_madness
		* (treb_pk + music_texture * 0.6);

	bool inside = (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0);

	vec3 col = vec3(0.0);
	if (inside) {
		// «Низкое разрешение»: все выборки — из центров ячеек пиксельной сетки.
		vec2 quv = (floor(uv * grid) + 0.5) / grid;
		float dist = length(quv - 0.5);

		float glow_mul = 1.0 + music_pulse * music_glow_boost * mus * fx_scan;
		float aberr_mul = 1.0 + (music_pulse * music_aberration_boost + highmid_pk * 1.5) * mus * hard;

		vec2 dir = normalize(quv - 0.5 + 1e-6);
		vec2 off = dir * (aberration * base) * aberr_mul * dist;
		float r = texture(screen_texture, quv - off).r;
		float g = texture(screen_texture, quv).g;
		float b = texture(screen_texture, quv + off).b;
		vec3 basec = vec3(r, g, b);

		vec3 bloom = glow_at(quv) * (glow_strength * base) * glow_mul;
		col = basec + bloom;

		// Виньетку считаем первой — от неё зависит мягкость скан-линий по краям.
		vec2 vc = quv - 0.5;
		float vig = clamp(1.0 - dot(vc, vc) * (vignette_strength * base) * 2.0, 0.0, 1.0);
		// Дыхание краёв на ударах — тоже scan-слой: этап 2+.
		vig *= 1.0 - fx_scan * mus * music_pulse * 0.18;

		// Скан-линии: плавные (нативные строки), затухают к краям вместе с
		// виньеткой. Середина/нижняя середина музыки «поджигают» контраст
		// полос, но только на пиках и только слоем помех.
		vec2 pixel = quv / SCREEN_PIXEL_SIZE;
		float scan = sin(pixel.y * 3.14159265) * 0.5 + 0.5;
		float burn = (mid_pk * 0.9 + lowmid_pk * 0.5) * mus * fx_scan;
		col *= mix(1.0, scan, scanline_strength * base * (1.0 + burn) * vig);

		col *= vig;

		// Помехи: зерно по ТВ-пикселю сыплется с верхами и «сыпучестью»
		// (hiss); в тишине постоянная составляющая почти нулевая.
		float vrow = floor(quv.y * grid.y);
		float grain = hash21(vec2(vrow, floor(quv.x * grid.x) + tstep * 97.0)) - 0.5;
		col += grain * grain_amount * mus * (fx_madness + fx_glitch * 0.25) * (0.1 + treb_pk * 0.8 + music_texture * 0.9);

		col *= 1.0 + sin(TIME * flicker_speed) * (flicker * base);
		// Доля — ступенчатая вспышка яркости, без плавного «дыхания».
		col *= 1.0 + step(0.68, music_pulse) * music_flicker_boost * 0.6 * mus * fx_madness;
		col *= brightness * (1.0 + step(0.8, music_pulse) * music_brightness_boost * 0.3 * mus * fx_madness);
	}

	COLOR = vec4(col, 1.0);
}
