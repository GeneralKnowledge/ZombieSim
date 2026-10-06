extends Node
## Open a real window briefly and report average FPS with rendering enabled.
## godot --display-driver x11 --rendering-driver opengl3 --path . res://tools/fps_probe.tscn

@export var population: int = 10000
@export var warmup_sec: float = 1.0
@export var sample_sec: float = 3.0

var _world: SimulationWorld = SimulationWorld.new()
var _elapsed: float = 0.0
var _sample_frames: int = 0
var _sample_time: float = 0.0
var _sum_frame_ms: float = 0.0
var _sum_sim_ms: float = 0.0
var _sum_render_ms: float = 0.0
var _max_frame_ms: float = 0.0
var _phase: String = "warmup"
var _renderer: Node3D


func _ready() -> void:
	Engine.max_fps = 0
	_world.bootstrap(population)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.14, 0.16)
	env.environment = e
	add_child(env)
	var cam_host := Node3D.new()
	cam_host.position = Vector3(0, 40, 80)
	var cam := Camera3D.new()
	cam.current = true
	cam.far = 2000
	cam_host.add_child(cam)
	add_child(cam_host)
	cam_host.look_at(Vector3.ZERO)
	_renderer = load("res://scripts/rendering/agent_renderer.gd").new()
	add_child(_renderer)
	# Bind via tiny shim
	var shim := Node.new()
	shim.set_script(load("res://tools/fps_probe_shim.gd"))
	shim.set("world", _world)
	add_child(shim)
	_renderer.call("bind_simulation", shim)
	print("FPS_PROBE_START pop=%d" % _world.total_population())


var _sim_accum: float = 0.0


func _process(delta: float) -> void:
	_elapsed += delta
	_world.player_position = Vector3(0, 40, 80)
	# Match main scene: fixed 20 Hz simulation, render every frame.
	_sim_accum += delta
	var step := 1.0 / 20.0
	var t0 := Telemetry.begin_sim()
	var steps := 0
	while _sim_accum >= step and steps < 2:
		_world.tick(step)
		_sim_accum -= step
		steps += 1
	Telemetry.end_sim(t0)
	if _phase == "warmup":
		if _elapsed >= warmup_sec:
			_phase = "sample"
			_elapsed = 0.0
			Telemetry.reset_stats()
		return
	_sample_frames += 1
	_sample_time += delta
	_sum_frame_ms += delta * 1000.0
	_sum_sim_ms += Telemetry.sim_time_ms
	_sum_render_ms += Telemetry.render_time_ms
	_max_frame_ms = maxf(_max_frame_ms, delta * 1000.0)
	if _sample_time >= sample_sec:
		var avg_ft := _sum_frame_ms / float(_sample_frames)
		var avg_fps := 1000.0 / maxf(avg_ft, 0.001)
		var result := {
			"population": _world.total_population(),
			"agents": _world.agents.living_count(),
			"avg_fps": avg_fps,
			"avg_frame_ms": avg_ft,
			"max_frame_ms": _max_frame_ms,
			"avg_sim_ms": _sum_sim_ms / float(_sample_frames),
			"avg_render_ms": _sum_render_ms / float(_sample_frames),
			"visible_dots": Telemetry.visible_dots,
			"frames": _sample_frames,
			"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method")),
			"display": DisplayServer.get_name(),
			"gpu": RenderingServer.get_video_adapter_name(),
		}
		print("FPS_PROBE_RESULT ", JSON.stringify(result))
		get_tree().quit(0)
