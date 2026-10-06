extends Node3D
## Combat sandbox entry: grounded player + mass-NPC sim + wave director.

@export var initial_population: int = 2500
@export var sim_hz: float = 20.0

@onready var player: CharacterBody3D = $Player
@onready var camera_rig: Node3D = $CameraRig
@onready var renderer: Node3D = $AgentRenderer
@onready var world_node: Node3D = $World
@onready var debug_ui: CanvasLayer = $DebugUI
@onready var game_hud: CanvasLayer = $GameHUD
@onready var director: Node = $SandboxDirector

var world: SimulationWorld = SimulationWorld.new()
var _step_once: bool = false
var _sim_accum: float = 0.0


func _ready() -> void:
	Engine.max_fps = 0
	SimConfig.MAX_ACTIVE_AGENTS = 256
	SimConfig.isometric_mode = true
	SimConfig.initial_population = initial_population
	SimConfig.attract_active = true
	SimConfig.city_mode = true
	world.half_extent = SimConfig.WORLD_HALF_EXTENT
	# Bind city nav graph before population bootstrap.
	if world_node.has_method("get_nav"):
		world.nav = world_node.get_nav()
	if world_node.has_method("get_city_meta"):
		world.bind_city_meta(world_node.get_city_meta())
	if SimConfig.city_mode and world.city_meta.get("spawn_points", []).size() > 0:
		world.bootstrap_city(initial_population)
	else:
		world.bootstrap(initial_population)
	if renderer.has_method("bind_simulation"):
		renderer.bind_simulation(self)
	if camera_rig.has_method("set_target"):
		camera_rig.set_target(player)
	if world_node.has_method("setup_interactables"):
		world_node.setup_interactables(player)
	if game_hud.has_method("bind"):
		game_hud.bind(player, director)
	var interact := world_node.get_node_or_null("Interactables")
	if interact and interact.has_signal("loot_taken"):
		interact.loot_taken.connect(_on_loot)
	debug_ui.command.connect(_on_debug_command)
	print("M9 city sandbox ready. Population=%d regions=%d connections=%d" % [
		world.total_population(), world.nav.region_count(), world.nav.connection_count()
	])


func get_simulation() -> SimulationWorld:
	return world


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("shoot") or (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT
	):
		_do_shoot()
	elif event.is_action_pressed("molotov"):
		_do_molotov()


func _do_shoot() -> void:
	if player == null or not player.alive:
		return
	if not player.weapons.try_shoot():
		return
	_sync_player_pose()
	var result := world.shoot()
	print("SHOOT hit=%s field=%s ammo=%s" % [
		str(result.get("hit", false)),
		str(result.get("field", false)),
		player.weapons.status_line(),
	])


func _do_molotov() -> void:
	if player == null or not player.alive:
		return
	if not player.weapons.try_molotov():
		return
	_sync_player_pose()
	var idx := world.throw_molotov()
	print("MOLOTOV idx=%d left=%d" % [idx, player.weapons.molotovs])


func _sync_player_pose() -> void:
	world.player_position = player.global_position
	world.player_aim = player.aim_direction


func _on_loot(kind: String) -> void:
	match kind:
		"ammo":
			player.weapons.add_ammo(3)
		"molotov":
			player.weapons.add_molotovs(2)
		"medkit":
			player.heal(40.0)


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
		"toggle_nav":
			SimConfig.show_navigation = not SimConfig.show_navigation
		"toggle_flow":
			SimConfig.show_flow_fields = not SimConfig.show_flow_fields
		"toggle_ring":
			SimConfig.show_combat_ring = not SimConfig.show_combat_ring
		"toggle_iso":
			if camera_rig.has_method("_unhandled_input"):
				SimConfig.isometric_mode = not SimConfig.isometric_mode
				if camera_rig.has_method("_apply_mode"):
					camera_rig._apply_mode()
		"pause":
			SimConfig.simulation_paused = not SimConfig.simulation_paused
		"step":
			_step_once = true
		"density":
			world.extreme_density_building(amount if amount > 0 else 100000)
		"molotov":
			_do_molotov()
		"shoot":
			_do_shoot()
		"reset_stats":
			Telemetry.reset_stats()
			world.combat.clear_stats()
		"reset_benchmark":
			SimConfig.initial_population = amount if amount > 0 else SimConfig.initial_population
			world.reset_benchmark()
		"city_100k":
			SimConfig.initial_population = 100000
			world.bootstrap_city(100000)
		"bottleneck":
			world.bootstrap_bottleneck(amount if amount > 0 else 100000)
		"wave":
			if director.has_method("_next_wave"):
				director._next_wave()
		_:
			push_warning("Unknown debug command: %s" % cmd)
	print("CMD %s(%d) → population=%d agents=%d fields=%d hordes=%d fires=%d" % [
		cmd, amount, world.total_population(), world.agents.living_count(),
		world.fields.living_count(), world.hordes.living_count(), world.fire.living_count()
	])
