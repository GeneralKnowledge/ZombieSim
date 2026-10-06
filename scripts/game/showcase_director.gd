extends Node
## Showcase bootstrap tweaks for "100,000 Zombies" demo.
## Attached optionally; main.gd already city-bootstraps when city_mode is on.

func _ready() -> void:
	SimConfig.attract_active = false
	SimConfig.city_mode = true
	SimConfig.show_population_fields = true
	SimConfig.show_simulation_levels = true
	print("SHOWCASE 100k Zombies — press Space / Toggle Attract to start the city response.")
