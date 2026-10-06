extends Node
## Headless architecture assertions.
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

	# Fire on the horde aggregate (no 100k agents / flame nodes).
	var horde := world.hordes.get_horde(horde_id)
	var before := world.total_population()
	var fire_idx := world.fire.spawn_fire(horde.center, 14.0, 1.0, 14.0, 0)
	if fire_idx < 0:
		push_error("Fire spawn failed")
		ok = false
	SimConfig.attract_active = false
	for _i in 40:
		world.tick(1.0 / 20.0)
	if world.fire.total_field_kills <= 0 and world.total_population() >= before:
		push_error("Fire should reduce field population aggregately")
		ok = false
	world.player_position = horde.center
	world.player_aim = Vector3(1, 0, 0)
	var shoot_result := world.shoot()
	if not shoot_result.has("hit"):
		push_error("Shoot returned unexpected payload")
		ok = false

	world.clear()
	world.bootstrap(10000)
	world.player_position = Vector3.ZERO
	for _i in 10:
		world.tick(1.0 / 20.0)
	if world.combat.ring_agent_count <= 0 and world.agents.count_active <= 0:
		# Ring may be empty if all agents spawned far; force a nearby spawn.
		world.agents.spawn_batch(50, Vector3.ZERO, 10.0, SimConfig.LEVEL_LIGHTWEIGHT, SimConfig.FACTION_ZOMBIE, RandomNumberGenerator.new())
		world.tick(1.0 / 20.0)
	if world.agents.count_active + world.agents.count_detailed <= 0:
		push_error("Combat ring should promote nearby agents")
		ok = false

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
		print("VALIDATE_OK architecture + combat/fire assertions passed")
		print("  million_dot agents=%d field_pop=%d fields=%d" % [
			world.agents.living_count(),
			world.fields.total_population(),
			world.fields.living_count(),
		])
		get_tree().quit(0)
	else:
		print("VALIDATE_FAIL")
		get_tree().quit(1)
