class_name RelevanceSystem
extends RefCounted
## Relevance determines simulation detail, not population count.
## Individual agent rows never use LEVEL_FIELD — that is population-cell territory.

var _cursor: int = 0


func score_agent(store: AgentStore, idx: int, player_pos: Vector3, attract: bool) -> float:
	if store.alive[idx] == 0:
		return 0.0
	var dx: float = store.pos_x[idx] - player_pos.x
	var dy: float = store.pos_y[idx] - player_pos.y
	var dz: float = store.pos_z[idx] - player_pos.z
	var dist := sqrt(dx * dx + dy * dy + dz * dz)
	var s := 1.0 / (1.0 + dist * 0.05)
	s += float(store.level[idx]) * 0.05
	if attract:
		s += 0.25
	return s


func desired_level(distance: float) -> int:
	if distance <= SimConfig.RADIUS_DETAILED:
		return SimConfig.LEVEL_DETAILED
	if distance <= SimConfig.RADIUS_ACTIVE:
		return SimConfig.LEVEL_ACTIVE
	return SimConfig.LEVEL_LIGHTWEIGHT


func apply_levels(store: AgentStore, player_pos: Vector3, budget_up: int, budget_down: int) -> Vector2i:
	var up := 0
	var down := 0
	if store.count == 0 or store.living == 0:
		return Vector2i.ZERO
	var detailed: int = store.count_detailed
	var active: int = store.count_active
	var scan_budget: int = mini(store.count, maxi(budget_up + budget_down, 64) * 2)
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
					store.set_level(i, want)
					detailed = store.count_detailed
					active = store.count_active
					up += 1
			elif want < cur and down < budget_down:
				store.set_level(i, want)
				detailed = store.count_detailed
				active = store.count_active
				down += 1
		i += 1
		if i >= store.count:
			i = 0
		scanned += 1
		if i == _cursor and scanned > 0:
			break
	_cursor = i
	return Vector2i(up, down)
