extends Node
## Combat sandbox loop: waves of horde pressure, melee threat, scoring.

signal wave_changed(wave: int, horde_size: int)
signal player_killed
signal score_changed(score: int)

@export var player_path: NodePath
@export var main_path: NodePath
@export var auto_start: bool = true
@export var base_horde: int = 8000
@export var horde_growth: float = 1.35
@export var wave_duration: float = 45.0
@export var melee_range: float = 1.6
@export var melee_dps: float = 22.0

var wave: int = 0
var score: int = 0
var _wave_timer: float = 0.0
var _active: bool = false
var _player: CharacterBody3D
var _main: Node

var kills_at_wave_start: int = 0


func _ready() -> void:
	_player = get_node_or_null(player_path) as CharacterBody3D
	_main = get_node_or_null(main_path)
	if _player and _player.has_signal("died"):
		_player.died.connect(_on_player_died)
	if auto_start:
		call_deferred("start_sandbox")


func start_sandbox() -> void:
	_active = true
	wave = 0
	score = 0
	_next_wave()


func _next_wave() -> void:
	wave += 1
	_wave_timer = wave_duration
	var size := int(float(base_horde) * pow(horde_growth, float(wave - 1)))
	size = mini(size, 250000)
	var world: SimulationWorld = _get_world()
	if world == null:
		return
	# Clear far soft pressure, spawn a fresh horde near the player.
	var center := _player.global_position + Vector3(35, 0, 35) if _player else Vector3(40, 0, 40)
	world.hordes.create_horde(world.fields, size, center, SimConfig.FACTION_ZOMBIE)
	SimConfig.attract_active = true
	kills_at_wave_start = _total_kills(world)
	wave_changed.emit(wave, size)
	score_changed.emit(score)
	print("WAVE %d horde=%d" % [wave, size])


func _process(delta: float) -> void:
	if not _active or _player == null or not _player.alive:
		return
	var world := _get_world()
	if world == null:
		return
	_wave_timer -= delta
	_apply_melee(delta, world)
	# Score from new kills
	var kills_now := _total_kills(world)
	var gained := kills_now - kills_at_wave_start
	if gained > 0:
		score += gained
		kills_at_wave_start = kills_now
		score_changed.emit(score)
	if _wave_timer <= 0.0:
		_next_wave()


func _apply_melee(delta: float, world: SimulationWorld) -> void:
	var p := _player.global_position
	var r2 := melee_range * melee_range
	var hits := 0
	var store := world.agents
	for i in store.count:
		if store.alive[i] == 0:
			continue
		if store.level[i] < SimConfig.LEVEL_ACTIVE:
			continue
		var dx := store.pos_x[i] - p.x
		var dz := store.pos_z[i] - p.z
		if dx * dx + dz * dz <= r2:
			hits += 1
			if hits >= 6:
				break
	if hits > 0 and _player.has_method("apply_damage"):
		_player.apply_damage(melee_dps * float(hits) * delta)


func _total_kills(world: SimulationWorld) -> int:
	return world.combat.individual_kills + world.combat.field_kills + world.fire.total_agent_kills + world.fire.total_field_kills


func _get_world() -> SimulationWorld:
	if _main and _main.has_method("get_simulation"):
		return _main.get_simulation()
	return null


func _on_player_died() -> void:
	_active = false
	SimConfig.attract_active = false
	player_killed.emit()
	print("PLAYER DOWN wave=%d score=%d" % [wave, score])


func status_line() -> String:
	return "Wave %d (%.0fs) | Score %d" % [wave, maxf(_wave_timer, 0.0), score]
