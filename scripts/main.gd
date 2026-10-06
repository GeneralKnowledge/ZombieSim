extends Node3D
## Main orchestration node. Mass population lives in SimulationWorld (data), not SceneTree.

@export var initial_population: int = 10000
## Simulation tick rate. Render runs every frame; sim is fixed-step.
@export var sim_hz: float = 20.0

@onready var player: Node3D = $Player
@onready var renderer: Node3D = $AgentRenderer
@onready var debug_ui: CanvasLayer = $DebugUI

var world: SimulationWorld = SimulationWorld.new()
var _step_once: bool = false
var _sim_accum: float = 0.0


func _ready() -> void:
	Engine.max_fps = 0
	SimConfig.MAX_ACTIVE_AGENTS = 256
	if initial_population > 0:
		SimConfig.initial_population = initial_population
	world.half_extent = SimConfig.WORLD_HALF_EXTENT
	world.bootstrap(SimConfig.initial_population)
	if renderer.has_method("bind_simulation"):
		renderer.bind_simulation(self)
	debug_ui.command.connect(_on_debug_command)
	print("Million Dot ready. Population=%d" % world.total_population())


func get_simulation() -> SimulationWorld:
	return world


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("shoot"):
		_do_shoot()
	elif event.is_action_pressed("molotov"):
		_do_molotov()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var free_mouse := true
		if "mouse_captured" in player:
			free_mouse = not bool(player.mouse_captured)
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and free_mouse:
			_aim_from_screen(mb.position)
			_do_shoot()


func _aim_from_screen(screen_pos: Vector2) -> void:
	var cam: Camera3D = player.get_node_or_null("Camera3D") as Camera3D
	if cam == null:
		return
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return
	var t := -from.y / dir.y
	if t < 0.0:
		return
	var hit := from + dir * t
	var aim := hit - world.player_position
	aim.y = 0.0
	if aim.length_squared() > 0.0001:
		world.player_aim = aim.normalized()
		player.aim_direction = world.player_aim


func _do_shoot() -> void:
	_sync_player_pose()
	var result := world.shoot()
	print("SHOOT hit=%s field=%s kills=%s pop=%d ring=%d" % [
		str(result.get("hit", false)),
		str(result.get("field", false)),
		str(result.get("kills", int(result.get("killed", false)))),
		world.total_population(),
		world.combat.ring_agent_count,
	])


func _do_molotov() -> void:
	_sync_player_pose()
	var idx := world.throw_molotov()
	print("MOLOTOV idx=%d fires=%d pop=%d" % [idx, world.fire.living_count(), world.total_population()])


func _sync_player_pose() -> void:
	world.player_position = player.global_position
	world.player_aim = player.aim_direction


func _process(delta: float) -> void:
	_sync_player_pose()
	if Input.is_action_just_pressed("pause_sim"):
		SimConfig.simulation_paused = not SimConfig.simulation_paused
	if Input.is_action_just_pressed("step_sim"):
		_step_once = true

	if _step_once:
		var t0 := Telemetry.begin_sim()
		world.tick(1.0 / maxf(sim_hz, 1.0))
		Telemetry.end_sim(t0)
		_step_once = false
		return

	if SimConfig.simulation_paused:
		return

	var step := 1.0 / maxf(sim_hz, 1.0)
	_sim_accum += delta
	var steps := 0
	var t0 := Telemetry.begin_sim()
	while _sim_accum >= step and steps < 2:
		world.tick(step)
		_sim_accum -= step
		steps += 1
	Telemetry.end_sim(t0)
	if _sim_accum > step * 2.0:
		_sim_accum = 0.0


func _on_debug_command(cmd: String, amount: int) -> void:
	match cmd:
		"add":
			world.add_zombies(amount, amount >= 100000)
		"horde":
			world.create_horde(amount if amount > 0 else 100000)
		"split":
			world.split_horde()
		"merge":
			world.merge_hordes()
		"attract_toggle":
			SimConfig.attract_active = not SimConfig.attract_active
		"release":
			SimConfig.attract_active = false
		"toggle_fields":
			SimConfig.show_population_fields = not SimConfig.show_population_fields
		"toggle_levels":
			SimConfig.show_simulation_levels = not SimConfig.show_simulation_levels
		"toggle_grid":
			SimConfig.show_spatial_grid = not SimConfig.show_spatial_grid
		"toggle_ring":
			SimConfig.show_combat_ring = not SimConfig.show_combat_ring
		"toggle_iso":
			SimConfig.isometric_mode = not SimConfig.isometric_mode
			if player.has_method("_apply_camera_mode"):
				player._apply_camera_mode()
		"pause":
			SimConfig.simulation_paused = not SimConfig.simulation_paused
		"step":
			_step_once = true
		"density":
			world.extreme_density_building(amount)
		"molotov":
			_do_molotov()
		"shoot":
			_do_shoot()
		"reset_stats":
			Telemetry.reset_stats()
			world.combat.clear_stats()
		_:
			push_warning("Unknown debug command: %s" % cmd)
	print("CMD %s(%d) → population=%d fields=%d hordes=%d agents=%d fires=%d" % [
		cmd, amount, world.total_population(), world.fields.living_count(),
		world.hordes.living_count(), world.agents.living_count(), world.fire.living_count()
	])
