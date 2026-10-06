extends Node
## Headless / in-game benchmark harness.
## Runs a fixed duration and prints a JSON-ish summary to stdout.

@export var population: int = 10000
@export var duration_sec: float = 5.0
@export var label: String = "Benchmark"

var _world: SimulationWorld = SimulationWorld.new()
var _elapsed: float = 0.0
var _frames: int = 0
var _done: bool = false


func _ready() -> void:
	SimConfig.initial_population = population
	# For huge benches, prefer field-heavy spawn
	if population >= 100000:
		SimConfig.spawn_as_fields_above = 20000
		SimConfig.MAX_AGENT_UPDATES_PER_FRAME = 20000
	_world.bootstrap(population)
	Telemetry.reset_stats()
	print("BENCH_START %s population=%d" % [label, _world.total_population()])


func _process(delta: float) -> void:
	if _done:
		return
	var t0 := Telemetry.begin_sim()
	_world.player_position = Vector3(0, 20, 40)
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
	s["requested_population"] = population
	s["frames"] = _frames
	s["duration_sec"] = _elapsed
	s["agents"] = _world.agents.living_count()
	s["fields"] = _world.fields.living_count()
	s["field_population"] = _world.fields.total_population()
	s["hordes"] = _world.hordes.living_count()
	print("BENCH_RESULT ", JSON.stringify(s))
	# Exit when running headless CI-style
	if DisplayServer.get_name() == "headless" or OS.has_feature("Server"):
		get_tree().quit(0)
