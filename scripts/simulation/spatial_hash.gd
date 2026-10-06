class_name SpatialHash
extends RefCounted
## Sparse 3D spatial hash. Empty regions cost nothing.
## Keys are packed cell coordinates; values are agent index lists or population refs.

var cell_size: float = 16.0
var inv_cell: float = 1.0 / 16.0

## cell_key -> PackedInt32Array of agent indices
var agent_cells: Dictionary = {}
## Scratch for rebuild
var _scratch_keys: PackedInt32Array = PackedInt32Array()


func configure(size: float) -> void:
	cell_size = size
	inv_cell = 1.0 / size


func clear() -> void:
	agent_cells.clear()


static func pack_key(cx: int, cy: int, cz: int) -> int:
	# 21 bits per axis, signed via bias
	return ((cx + 1048576) & 0x1FFFFF) | (((cy + 1048576) & 0x1FFFFF) << 21) | (((cz + 1048576) & 0x1FFFFF) << 42)


static func unpack_key(key: int) -> Vector3i:
	var cx := (key & 0x1FFFFF) - 1048576
	var cy := ((key >> 21) & 0x1FFFFF) - 1048576
	var cz := ((key >> 42) & 0x1FFFFF) - 1048576
	return Vector3i(cx, cy, cz)


func cell_coords(p: Vector3) -> Vector3i:
	return Vector3i(
		int(floor(p.x * inv_cell)),
		int(floor(p.y * inv_cell)),
		int(floor(p.z * inv_cell))
	)


func key_for_position(p: Vector3) -> int:
	var c := cell_coords(p)
	return pack_key(c.x, c.y, c.z)


func rebuild_from_agents(store: AgentStore) -> void:
	agent_cells.clear()
	for i in store.count:
		if store.alive[i] == 0:
			continue
		var key := pack_key(
			int(floor(store.pos_x[i] * inv_cell)),
			int(floor(store.pos_y[i] * inv_cell)),
			int(floor(store.pos_z[i] * inv_cell))
		)
		if not agent_cells.has(key):
			agent_cells[key] = PackedInt32Array()
		var arr: PackedInt32Array = agent_cells[key]
		arr.append(i)
		agent_cells[key] = arr


func query_radius(center: Vector3, radius: float) -> PackedInt32Array:
	var result := PackedInt32Array()
	var r := radius
	var min_c := cell_coords(center - Vector3(r, r, r))
	var max_c := cell_coords(center + Vector3(r, r, r))
	var r2 := r * r
	for cx in range(min_c.x, max_c.x + 1):
		for cy in range(min_c.y, max_c.y + 1):
			for cz in range(min_c.z, max_c.z + 1):
				var key := pack_key(cx, cy, cz)
				if not agent_cells.has(key):
					continue
				var arr: PackedInt32Array = agent_cells[key]
				for idx in arr:
					result.append(idx)
	# Optional distance filter left to caller for budget reasons
	return result


func active_cell_count() -> int:
	return agent_cells.size()


func cell_world_center(key: int) -> Vector3:
	var c := unpack_key(key)
	var hs := cell_size * 0.5
	return Vector3(
		float(c.x) * cell_size + hs,
		float(c.y) * cell_size + hs,
		float(c.z) * cell_size + hs
	)
