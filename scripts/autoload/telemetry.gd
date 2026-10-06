extends Node
## First-class profiling. Every optimisation must be based on measurements.

signal updated(snapshot: Dictionary)

var fps: float = 0.0
var frame_time_ms: float = 0.0
var sim_time_ms: float = 0.0
var render_time_ms: float = 0.0
var population_update_ms: float = 0.0
var agent_update_ms: float = 0.0
var materialisation_ms: float = 0.0
var horde_update_ms: float = 0.0
var journey_update_ms: float = 0.0

var population: int = 0
var lightweight_agents: int = 0
var active_agents: int = 0
var detailed_agents: int = 0
var individual_agents: int = 0
var expensive_sim_agents: int = 0
var visible_dots: int = 0
var population_fields: int = 0
var horde_count: int = 0
var materialisations_this_frame: int = 0
var dematerialisations_this_frame: int = 0
var fire_volumes: int = 0
var combat_ring_agents: int = 0
var shots_fired: int = 0
var kills_individual: int = 0
var kills_field: int = 0
var agent_updates: int = 0
var nav_regions: int = 0
var nav_connections: int = 0
var nav_flow_rebuilds: int = 0
var path_requests: int = 0
var population_transfers: int = 0
var transfer_population: int = 0
var horde_splits: int = 0
var horde_merges: int = 0
var journey_count: int = 0
var journey_population: int = 0
var journey_arrivals: int = 0
var sim_cost_per_pop: float = 0.0
var expensive_fraction: float = 0.0

var _frame_times: PackedFloat32Array = PackedFloat32Array()
var _sim_times: PackedFloat32Array = PackedFloat32Array()
var _history_cap: int = 240

var min_fps: float = 9999.0
var max_frame_time_ms: float = 0.0
var avg_fps: float = 0.0
var avg_frame_time_ms: float = 0.0
var avg_sim_time_ms: float = 0.0

var _accum_ui: float = 0.0


func _process(delta: float) -> void:
	fps = Engine.get_frames_per_second()
	frame_time_ms = delta * 1000.0
	_record_sample(frame_time_ms, sim_time_ms)
	_accum_ui += delta
	if _accum_ui >= 0.25:
		_accum_ui = 0.0
		updated.emit(snapshot())


func begin_sim() -> int:
	return Time.get_ticks_usec()


func end_sim(t0: int) -> void:
	sim_time_ms = float(Time.get_ticks_usec() - t0) / 1000.0


func mark_section(t0: int) -> float:
	return float(Time.get_ticks_usec() - t0) / 1000.0


func reset_stats() -> void:
	_frame_times.clear()
	_sim_times.clear()
	min_fps = 9999.0
	max_frame_time_ms = 0.0
	avg_fps = 0.0
	avg_frame_time_ms = 0.0
	avg_sim_time_ms = 0.0


func _record_sample(ft: float, st: float) -> void:
	_frame_times.append(ft)
	_sim_times.append(st)
	if _frame_times.size() > _history_cap:
		_frame_times = _frame_times.slice(_frame_times.size() - _history_cap)
		_sim_times = _sim_times.slice(_sim_times.size() - _history_cap)
	if fps > 0.0:
		min_fps = minf(min_fps, fps)
	max_frame_time_ms = maxf(max_frame_time_ms, ft)
	var sum_ft := 0.0
	var sum_st := 0.0
	for i in _frame_times.size():
		sum_ft += _frame_times[i]
		sum_st += _sim_times[i]
	var n := float(_frame_times.size())
	avg_frame_time_ms = sum_ft / n
	avg_sim_time_ms = sum_st / n
	avg_fps = 1000.0 / maxf(avg_frame_time_ms, 0.001)


func snapshot() -> Dictionary:
	return {
		"fps": fps,
		"min_fps": min_fps,
		"avg_fps": avg_fps,
		"frame_time_ms": frame_time_ms,
		"max_frame_time_ms": max_frame_time_ms,
		"avg_frame_time_ms": avg_frame_time_ms,
		"sim_time_ms": sim_time_ms,
		"avg_sim_time_ms": avg_sim_time_ms,
		"render_time_ms": render_time_ms,
		"population_update_ms": population_update_ms,
		"agent_update_ms": agent_update_ms,
		"materialisation_ms": materialisation_ms,
		"horde_update_ms": horde_update_ms,
		"journey_update_ms": journey_update_ms,
		"population": population,
		"lightweight_agents": lightweight_agents,
		"active_agents": active_agents,
		"detailed_agents": detailed_agents,
		"individual_agents": individual_agents,
		"expensive_sim_agents": expensive_sim_agents,
		"visible_dots": visible_dots,
		"population_fields": population_fields,
		"horde_count": horde_count,
		"materialisations_this_frame": materialisations_this_frame,
		"dematerialisations_this_frame": dematerialisations_this_frame,
		"fire_volumes": fire_volumes,
		"combat_ring_agents": combat_ring_agents,
		"shots_fired": shots_fired,
		"kills_individual": kills_individual,
		"kills_field": kills_field,
		"agent_updates": agent_updates,
		"nav_regions": nav_regions,
		"nav_connections": nav_connections,
		"nav_flow_rebuilds": nav_flow_rebuilds,
		"path_requests": path_requests,
		"population_transfers": population_transfers,
		"transfer_population": transfer_population,
		"horde_splits": horde_splits,
		"horde_merges": horde_merges,
		"journey_count": journey_count,
		"journey_population": journey_population,
		"journey_arrivals": journey_arrivals,
		"sim_cost_per_pop": sim_cost_per_pop,
		"expensive_fraction": expensive_fraction,
		"static_memory_mb": float(OS.get_static_memory_usage()) / (1024.0 * 1024.0),
	}


func format_hud() -> String:
	var s := snapshot()
	var gpu := RenderingServer.get_video_adapter_name()
	return (
		"FPS %d  (min %d avg %.0f)\n" % [int(s.fps), int(s.min_fps) if s.min_fps < 9000 else 0, s.avg_fps]
		+ "Frame %.2f ms  (max %.2f avg %.2f)\n" % [s.frame_time_ms, s.max_frame_time_ms, s.avg_frame_time_ms]
		+ "Sim %.2f ms  RenderCPU %.2f ms\n" % [s.sim_time_ms, s.render_time_ms]
		+ "  field %.2f agent %.2f horde %.2f mat %.2f journey %.2f\n" % [
			s.population_update_ms, s.agent_update_ms, s.horde_update_ms, s.materialisation_ms, s.journey_update_ms
		]
		+ "TOTAL POPULATION %d\n" % s.population
		+ "  fields %d  hordes %d  journeys %d (%d)\n" % [
			s.population_fields, s.horde_count, s.journey_count, s.journey_population
		]
		+ "  light %d  active %d  detailed %d\n" % [s.lightweight_agents, s.active_agents, s.detailed_agents]
		+ "Visible dots %d | agent updates %d\n" % [s.visible_dots, s.agent_updates]
		+ "Nav regions %d conn %d | flow rebuilds %d | paths %d\n" % [
			s.nav_regions, s.nav_connections, s.nav_flow_rebuilds, s.path_requests
		]
		+ "Transfers %d (%d pop) | splits %d merges %d\n" % [
			s.population_transfers, s.transfer_population, s.horde_splits, s.horde_merges
		]
		+ "SIM COST / POP %.6f ms | expensive frac %.4f\n" % [s.sim_cost_per_pop, s.expensive_fraction]
		+ "Combat ring %d | fires %d | shots %d | kills %d/%d\n" % [
			s.combat_ring_agents, s.fire_volumes, s.shots_fired, s.kills_individual, s.kills_field
		]
		+ "Mat/demat %d / %d | Memory %.1f MB\n" % [
			s.materialisations_this_frame, s.dematerialisations_this_frame, s.static_memory_mb
		]
		+ "GPU %s\n" % gpu
	)
