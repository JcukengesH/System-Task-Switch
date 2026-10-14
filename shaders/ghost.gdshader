shader_type canvas_item;

// Фосфорное послесвечение квадранта (CRT ghosting): после вспышки верного
// ответа белое ядро гаснет через жёлтый шлейф, как люминофор кинескопа.
// ghost_amount ведёт GDScript (item_display.gd): 1.0 на ударе -> 0.0 за ~0.6 c.
uniform float ghost_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// return внутри fragment() в Godot запрещён — пустой вывод через ветку.
	if (ghost_amount <= 0.002) {
		COLOR = vec4(0.0);
	} else {
		vec2 c = UV - 0.5;
		float d = length(c * vec2(1.0, 1.15));
		float core = 1.0 - smoothstep(0.05, 0.30, d);
		float halo = 1.0 - smoothstep(0.0, 0.62, d);
		// «Остывание» люминофора: центр сначала бело-горячий, потом янтарный.
		vec3 hot = vec3(1.0, 0.97, 0.88);
		vec3 amber = vec3(1.0, 0.66, 0.18);
		vec3 col = mix(amber, hot, core * ghost_amount);
		float a = (halo * 0.30 + core * 0.45) * ghost_amount;
		COLOR = vec4(col, clamp(a, 0.0, 0.85));
	}
}
