class_name RelevanceSystem
extends RefCounted
## Relevance determines simulation detail, not population count.

func score_agent(store: AgentStore, idx: int, player_pos: Vector3, attract: bool) -> float:
	if store.alive[idx] == 0:
		return 0.0
	var p := store.get_position(idx)
	var dist := p.distance_to(player_pos)
	var s := 1.0 / (1.0 + dist * 0.05)
	# Prefer agents already more detailed (hysteresis)
	s += float(store.level[idx]) * 0.05
	if attract:
		s += 0.25
	# Density proxy: closer agents in front of camera would score higher later
	return s


func desired_level(distance: float) -> int:
	if distance <= SimConfig.RADIUS_DETAILED:
		return SimConfig.LEVEL_DETAILED
	if distance <= SimConfig.RADIUS_ACTIVE:
		return SimConfig.LEVEL_ACTIVE
	if distance <= SimConfig.RADIUS_LIGHTWEIGHT:
		return SimConfig.LEVEL_LIGHTWEIGHT
	return SimConfig.LEVEL_FIELD


var _cursor: int = 0


func apply_levels(store: AgentStore, player_pos: Vector3, budget_up: int, budget_down: int) -> Vector2i:
	var up := 0
	var down := 0
	if store.count == 0:
		return Vector2i.ZERO
	# Approximate caps from telemetry to avoid a full scan every frame.
	var detailed: int = Telemetry.detailed_agents
	var active: int = Telemetry.active_agents
	var scan_budget: int = mini(store.count, maxi(budget_up + budget_down, 256) * 4)
	var i: int = _cursor
	var scanned := 0
	while scanned < scan_budget and (up < budget_up or down < budget_down):
		if store.alive[i] != 0:
			var dx: float = store.pos_x[i] - player_pos.x
			var dy: float = store.pos_y[i] - player_pos.y
			var dz: float = store.pos_z[i] - player_pos.z
			var dist: float = sqrt(dx * dx + dy * dy + dz * dz)
			var want: int = desired_level(dist)
			var cur: int = store.level[i]
			if want > cur and up < budget_up:
				if want == SimConfig.LEVEL_DETAILED and detailed >= SimConfig.MAX_DETAILED_AGENTS:
					want = SimConfig.LEVEL_ACTIVE
				if want == SimConfig.LEVEL_ACTIVE and active >= SimConfig.MAX_ACTIVE_AGENTS:
					want = SimConfig.LEVEL_LIGHTWEIGHT
				if want > cur:
					if cur == SimConfig.LEVEL_ACTIVE:
						active -= 1
					elif cur == SimConfig.LEVEL_DETAILED:
						detailed -= 1
					store.level[i] = want
					if want == SimConfig.LEVEL_ACTIVE:
						active += 1
					elif want == SimConfig.LEVEL_DETAILED:
						detailed += 1
					up += 1
			elif want < cur and down < budget_down:
				if cur == SimConfig.LEVEL_ACTIVE:
					active -= 1
				elif cur == SimConfig.LEVEL_DETAILED:
					detailed -= 1
				store.level[i] = want
				if want == SimConfig.LEVEL_ACTIVE:
					active += 1
				elif want == SimConfig.LEVEL_DETAILED:
					detailed += 1
				down += 1
		i += 1
		if i >= store.count:
			i = 0
		scanned += 1
		if i == _cursor and scanned > 0:
			break
	_cursor = i
	return Vector2i(up, down)
