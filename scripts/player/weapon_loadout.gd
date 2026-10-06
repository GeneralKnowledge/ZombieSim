class_name WeaponLoadout
extends RefCounted
## Sandbox weapons: pistol + molotovs. No inventory UI grid yet.

signal changed

var pistol_ammo: int = 60
var pistol_reserve: int = 120
var pistol_mag_size: int = 12
var pistol_cooldown: float = 0.0
var pistol_fire_interval: float = 0.18
var pistol_reload_time: float = 1.2
var reloading: bool = false
var reload_left: float = 0.0

var molotovs: int = 3
var molotov_cooldown: float = 0.0
var molotov_interval: float = 0.8


func _init() -> void:
	pistol_ammo = pistol_mag_size


func tick(delta: float) -> void:
	pistol_cooldown = maxf(0.0, pistol_cooldown - delta)
	molotov_cooldown = maxf(0.0, molotov_cooldown - delta)
	if reloading:
		reload_left -= delta
		if reload_left <= 0.0:
			var need := pistol_mag_size - pistol_ammo
			var take := mini(need, pistol_reserve)
			pistol_ammo += take
			pistol_reserve -= take
			reloading = false
			changed.emit()


func can_shoot() -> bool:
	return not reloading and pistol_cooldown <= 0.0 and pistol_ammo > 0


func try_shoot() -> bool:
	if not can_shoot():
		if pistol_ammo <= 0 and pistol_reserve > 0 and not reloading:
			start_reload()
		return false
	pistol_ammo -= 1
	pistol_cooldown = pistol_fire_interval
	changed.emit()
	return true


func start_reload() -> void:
	if reloading or pistol_ammo >= pistol_mag_size or pistol_reserve <= 0:
		return
	reloading = true
	reload_left = pistol_reload_time
	changed.emit()


func can_molotov() -> bool:
	return molotovs > 0 and molotov_cooldown <= 0.0


func try_molotov() -> bool:
	if not can_molotov():
		return false
	molotovs -= 1
	molotov_cooldown = molotov_interval
	changed.emit()
	return true


func add_ammo(mag_fills: int = 2) -> void:
	pistol_reserve += mag_fills * pistol_mag_size
	changed.emit()


func add_molotovs(n: int = 1) -> void:
	molotovs += n
	changed.emit()


func status_line() -> String:
	var reload_s := " RELOADING" if reloading else ""
	return "Pistol %d/%d%s | Molotovs %d" % [pistol_ammo, pistol_reserve, reload_s, molotovs]
