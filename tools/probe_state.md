# Шпаргалка по live-отладке через godot-mcp (для агента)

Состояние игры читаем из автозагрузки-пробы `MCPRuntimeProbe` (зарегистрирована
в project.godot как autoload). Ключевые вызовы идут через `execute` →
`tools["godot"]`.

## Быстрый текстовый дамп (без скриншотов!)
Один вызов читает главное состояние `/root/Main`:
```js
const g = tools["godot"];
const STATES = ["BOOT","MENU","CONFIG","HELP","GAME","CUTSCENE","SHOP"]; // enum State
const base = "/root/Main";
const names = ["current_state","active","paused","combo","timer_value",
               "current_quadrant","waiting_for_garbage","_debug_run"];
const props = {};
for (const p of names) props[p] = (await g.godot_runtime_read_property({node_path:base,property:p})).value;
const item = (await g.godot_runtime_read_property({node_path:base,property:"current_item"})).value;
return { state: STATES[props.current_state], ...props, item: String(item).slice(0,160) };
```
Полей `errors` у Main нет — число ошибок живёт в `_meta`/snapshot, за ним идти
не обязательно (для smoke хватает combo/timer).

## Пауза, чтобы таймер не истёк во время раздумий
Игра паузится клавишей **F4** (`_unhandled_input`, только в состоянии GAME):
```js
await g.godot_input_simulate_key({ key: "f4", action: "press" });
await g.godot_input_simulate_key({ key: "f4", action: "release" });
```
`paused=true` → countdown/garbage таймеры встают. Повторный F4 — снять.
ВАЖНО: пауза работает только в GAME; в CUTSCENE (интро/катсцена) active=false и
таймера ещё нет — там и так не «истекаем».

## Скриншот кадра игры (когда всё-таки нужен глаз)
```js
await g.godot_runtime_capture_game_screenshot({ timeout_ms: 25000 });
```
Возвращает PNG. Дорого и медленно — предпочитать текстовый дамп выше.

## Как играть через проб (симуляция ввода)
- Меню: стрелки/W-S + Enter; `simulate_key({key:"enter"|"s"|"w", ...})`.
- Ответ в GAME: ЛКМ/ПКМ по активному квадранту — `simulate_mouse({x,y,button:"left"|"right",pressed:true/false})`.
  Координаты: квадранты ~ (x<640 — левые, y<360 — верхние). Правильный ответ
  зависит от задания (см. current_item: isVowel/isEven).
- Отладка: F3 debug-меню (без прогресса), F4 пауза.

## Управление сессией
```js
await g.godot_runtime_play_scene({ scene_path: "res://scenes/Main.tscn" });
await g.godot_runtime_is_playing();
await g.godot_runtime_stop_scene();
```
После правки скриптов — `rescan_filesystem`, затем стоп+плей (autoplay-скрипты
перечитываются только на новом старте сцены).

## Ловушки (уже наступали)
- `await new Promise(r => null)` внутри execute вешает вызов намертво (промпис
  никогда не резолвится). Никаких «no-op await» — только реальные вызовы.
- Инверсная плашка меню: `set_inverted` обязан ставить Label'у
  `size_flags_horizontal = SIZE_SHRINK_BEGIN`, иначе белая плашка растягивается
  на всю ширину VBox.
- Курсорный `Timer` в TerminalScreen надо глушить в `clear_animated()` и
  `_exit_tree()`, иначе мигание бьёт по freed-лейблам при смене экрана
  (ловилось как «Invalid assignment ... previously freed»).
- Сентинелы `MOUSE_BUTTON_MAX`/`KEY_MAX` в Godot 4.7 удалены — не использовать.
- `--check-only` не грузит autoloads → ссылки на `SFX` легальны; smoke.sh их
  whitelist'ит.
