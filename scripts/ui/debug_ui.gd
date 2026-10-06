extends CanvasLayer
## Developer stress-test UI. Not beautiful — intentional.

signal command(cmd: String, amount: int)

@onready var telemetry_label: Label = %TelemetryLabel
@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	Telemetry.updated.connect(_on_telemetry)
	_wire_buttons()


func _wire_buttons() -> void:
	_bind("%Btn1k", "add", 1000)
	_bind("%Btn10k", "add", 10000)
	_bind("%Btn100k", "add", 100000)
	_bind("%Btn1m", "add", 1000000)
	_bind("%BtnHorde", "horde", 100000)
	_bind("%BtnSplit", "split", 0)
	_bind("%BtnMerge", "merge", 0)
	_bind("%BtnAttract", "attract_toggle", 0)
	_bind("%BtnRelease", "release", 0)
	_bind("%BtnFields", "toggle_fields", 0)
	_bind("%BtnLevels", "toggle_levels", 0)
	_bind("%BtnGrid", "toggle_grid", 0)
	_bind("%BtnPause", "pause", 0)
	_bind("%BtnStep", "step", 0)
	_bind("%BtnDensity", "density", 100000)
	_bind("%BtnResetStats", "reset_stats", 0)


func _bind(path: String, cmd: String, amount: int) -> void:
	var btn := get_node_or_null(path)
	if btn:
		btn.pressed.connect(func() -> void: command.emit(cmd, amount))


func _on_telemetry(_s: Dictionary) -> void:
	telemetry_label.text = Telemetry.format_hud()
	status_label.text = (
		"Attract: %s | Paused: %s | Fields: %s | Levels: %s\n" % [
			str(SimConfig.attract_active),
			str(SimConfig.simulation_paused),
			str(SimConfig.show_population_fields),
			str(SimConfig.show_simulation_levels),
		]
		+ "WASD+QE fly | Shift sprint | Space attract | Esc mouse | P pause | . step"
	)
