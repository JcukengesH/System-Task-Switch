#!/usr/bin/env bash
# Headless-дым: запускает сцену на 6 секунд и печатает любые ошибки GDScript.
# Использование: tools/smoke.sh [scene]   (по умолчанию res://scenes/Main.tscn)
# Смысл: у run_and_capture у godot-mcp свой парсер вывода, он пропустил
# "Parse Error" от 4.7. Здесь — грубый, но честный grep по сыдому stderr.
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/home/deck/.local/share/Steam/steamapps/common/Godot Engine/godot.x11.opt.tools.64}"
SCENE="${1:-res://scenes/Main.tscn}"

# 1) Статическая проверка парсинга всех скриптов — ловит отсутствие
#    идентификаторов/синтаксис, даже если рантайм до них не дошёл.
#    Whitelist: --check-only не грузит autoloads, ссылки на них легальны
#    (список = секция [autoload] в project.godot).
ALLOW="Identifier not found: ($(sed -n '/^\[autoload\]/,/^\[[a-z]/p' project.godot | grep -oP '^\K[A-Za-z_][A-Za-z0-9_]*(?==)' | tr '\n' '|' | sed 's/|$//'))"
[ "$ALLOW" = "Identifier not found: ()" ] && ALLOW="Identifier not found: (__none__)"
FAIL=0
for f in scripts/*.gd scripts/screens/*.gd; do
	OUT=$("$GODOT" --headless --path . --check-only --script "res://$f" 2>&1 \
		| grep -E "Parse Error|SCRIPT ERROR" \
		| grep -Ev "$ALLOW|Meta")
	if [ -n "$OUT" ]; then
		echo "== PARSE FAIL: $f"
		echo "$OUT" | head -3
		FAIL=1
	fi
done
[ $FAIL -eq 0 ] && echo "PARSE OK: все скрипты компилируются"

# 2) Короткий рантайм основной сцены.
OUT=$(timeout 6 "$GODOT" --headless --path . "$SCENE" 2>&1)
NOISE="still in use at exit|Resource.*still in use|AudioDriver|ALSA|PulseAudio"
if echo "$OUT" | grep -E "SCRIPT ERROR|Parse Error" | grep -Ev "$NOISE" | grep -q .; then
	echo "== RUNTIME ERRORS:"
	echo "$OUT" | grep -E "SCRIPT ERROR|Parse Error" | grep -Ev "$NOISE" | sort -u
else
	echo "RUNTIME OK: $SCENE стартует без ошибок скриптов"
fi
