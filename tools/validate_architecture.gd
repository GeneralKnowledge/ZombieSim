extends Node
## Headless architecture assertions (no 100k nodes for 100k population).
## Run: godot --headless --path . res://tools/validate_architecture.tscn

func _ready() -> void:
	var ok := true
	var world := SimulationWorld.new()
	world.bootstrap(10000)
	if world.total_population() != 10000:
		push_error("Expected 10k population, got %d" % world.total_population())
		ok = false
	if world.agents.living_count() != 10000:
		push_error("Expected 10k individual agents for M1-scale spawn")
		ok = false

	world.clear()
	var horde_id := world.create_horde(100000)
	if horde_id < 0:
		push_error("Horde creation failed")
		ok = false
	if world.total_population() != 100000:
		push_error("Horde population mismatch: %d" % world.total_population())
		ok = false
	if world.agents.living_count() != 0:
		push_error("100k horde must not create individual agents; got %d" % world.agents.living_count())
		ok = false
	if world.fields.living_count() < 1:
		push_error("Horde should create population fields")
		ok = false
	if world.hordes.living_count() != 1:
		push_error("Expected 1 horde entity")
		ok = false

	world.player_position = Vector3.ZERO
	SimConfig.attract_active = true
	for _i in 30:
		world.tick(1.0 / 60.0)
	if world.agents.living_count() > SimConfig.MAX_MATERIALISATIONS_PER_FRAME * 40:
		push_error("Materialisation grew too fast: %d agents" % world.agents.living_count())
		ok = false
	if world.agents.count_by_level(SimConfig.LEVEL_DETAILED) > SimConfig.MAX_DETAILED_AGENTS:
		push_error("Detailed cap violated")
		ok = false
	if world.agents.count_by_level(SimConfig.LEVEL_ACTIVE) > SimConfig.MAX_ACTIVE_AGENTS:
		push_error("Active cap violated")
		ok = false

	world.split_horde()
	world.merge_hordes()

	world.clear()
	world.bootstrap(1000000)
	if world.total_population() != 1000000:
		push_error("1M bootstrap failed: %d" % world.total_population())
		ok = false
	if world.agents.living_count() > 50000:
		push_error("1M should be field-heavy; agents=%d" % world.agents.living_count())
		ok = false
	if world.fields.total_population() < 500000:
		push_error("1M should keep most pop in fields")
		ok = false

	if ok:
		print("VALIDATE_OK architecture assertions passed")
		print("  million_dot agents=%d field_pop=%d fields=%d" % [
			world.agents.living_count(),
			world.fields.total_population(),
			world.fields.living_count(),
		])
		get_tree().quit(0)
	else:
		print("VALIDATE_FAIL")
		get_tree().quit(1)
