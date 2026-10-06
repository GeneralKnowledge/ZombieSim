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
	# Prefer uncapped FPS for benchmarking.
	Engine.max_fps = 0
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


func _process(delta: float) -> void:
	world.player_position = player.global_position
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
	# Avoid spiral of death — at most 2 sim steps per rendered frame.
	var steps := 0
	var t0 := Telemetry.begin_sim()
	while _sim_accum >= step and steps < 2:
		world.tick(step)
		_sim_accum -= step
		steps += 1
	if steps == 0:
		# Still publish player-facing telemetry cadence when sim is ahead.
		pass
	Telemetry.end_sim(t0)
	# If we were heavily behind, drop backlog.
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
		"pause":
			SimConfig.simulation_paused = not SimConfig.simulation_paused
		"step":
			_step_once = true
		"density":
			world.extreme_density_building(amount)
		"reset_stats":
			Telemetry.reset_stats()
		_:
			push_warning("Unknown debug command: %s" % cmd)
	print("CMD %s(%d) → population=%d fields=%d hordes=%d agents=%d" % [
		cmd, amount, world.total_population(), world.fields.living_count(),
		world.hordes.living_count(), world.agents.living_count()
	])
