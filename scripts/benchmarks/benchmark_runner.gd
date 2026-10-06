extends Node
## Headless / in-game benchmark harness.
## Modes: open | city | convergence | bottleneck | combat

@export var population: int = 10000
@export var duration_sec: float = 5.0
@export var label: String = "Benchmark"
@export_enum("open", "city", "convergence", "bottleneck", "combat") var mode: String = "open"

var _world: SimulationWorld = SimulationWorld.new()
var _elapsed: float = 0.0
var _frames: int = 0
var _done: bool = false
var _city_root: Node3D


func _ready() -> void:
	SimConfig.initial_population = population
	SimConfig.WORLD_SEED = 42
	if population >= 100000:
		SimConfig.spawn_as_fields_above = 20000
		SimConfig.MAX_AGENT_UPDATES_PER_FRAME = 20000
	_setup_world()
	Telemetry.reset_stats()
	print("BENCH_START %s mode=%s population=%d regions=%d" % [
		label, mode, _world.total_population(), _world.nav.region_count()
	])


func _setup_world() -> void:
	match mode:
		"city", "convergence", "bottleneck", "combat":
			_city_root = Node3D.new()
			add_child(_city_root)
			var meta := CityBuilder.build(_city_root, _world.nav, SimConfig.WORLD_SEED)
			_world.bind_city_meta(meta)
			if mode == "bottleneck":
				_world.bootstrap_bottleneck(population)
			elif mode == "city" or mode == "convergence" or mode == "combat":
				_world.bootstrap_city(population)
			else:
				_world.bootstrap(population)
		_:
			_world.bootstrap(population)


func _process(delta: float) -> void:
	if _done:
		return
	var t0 := Telemetry.begin_sim()
	# Player wanders slowly so attraction / materialisation stay meaningful.
	var t := _elapsed
	_world.player_position = Vector3(sin(t * 0.15) * 40.0, 1.0, cos(t * 0.12) * 40.0)
	_world.player_aim = Vector3(1, 0, 0)
	match mode:
		"convergence":
			SimConfig.attract_active = true
		"bottleneck":
			SimConfig.attract_active = true
			# Stand outside The Building exit to pull the crowd through the door.
			_world.player_position = Vector3(-90.0, 1.0, 130.0)
		"combat":
			SimConfig.attract_active = true
			if _frames % 8 == 0:
				_world.shoot()
			if _frames % 90 == 0:
				_world.throw_molotov()
		_:
			SimConfig.attract_active = (_frames % 120) < 60
	_world.tick(delta)
	Telemetry.end_sim(t0)
	_elapsed += delta
	_frames += 1
	if _elapsed >= duration_sec:
		_finish()


func _finish() -> void:
	_done = true
	var s := Telemetry.snapshot()
	s["label"] = label
	s["mode"] = mode
	s["requested_population"] = population
	s["frames"] = _frames
	s["duration_sec"] = _elapsed
	s["agents"] = _world.agents.living_count()
	s["fields"] = _world.fields.living_count()
	s["field_population"] = _world.fields.total_population()
	s["hordes"] = _world.hordes.living_count()
	s["journeys"] = _world.journeys.living_count()
	s["nav_regions"] = _world.nav.region_count()
	s["nav_connections"] = _world.nav.connection_count()
	print("BENCH_RESULT ", JSON.stringify(s))
	if DisplayServer.get_name() == "headless" or OS.has_feature("Server"):
		get_tree().quit(0)
