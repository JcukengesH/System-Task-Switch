extends SceneTree

# Инфраструктурный зонд для tools/check.ps1 (режим runtime).
# Печатает фактический корень user://, чтобы check.ps1 сверил его
# с изолирующим каталогом. При несовпадении runtime-тест прерывается —
# это защита реальных сохранений (%APPDATA%\Godot\app_userdata\...).
# Не принадлежит игровой логике: не подключать в autoload и сцены.

func _initialize() -> void:
	print("USER_DATA_DIR=" + OS.get_user_data_dir())
	print("CONFIG_DIR=" + OS.get_config_dir())
	quit(0)
