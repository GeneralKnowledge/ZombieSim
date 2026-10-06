extends CanvasLayer
## Gameplay HUD for the combat sandbox (separate from debug telemetry).

@onready var hud_label: Label = %GameHudLabel
@onready var banner_label: Label = %BannerLabel

var _player: Node
var _director: Node
var _banner_time: float = 0.0


func bind(player: Node, director: Node) -> void:
	_player = player
	_director = director
	if _player and _player.has_signal("died"):
		_player.died.connect(func() -> void: _flash("YOU DIED — restart scene", 6.0))
	if _director and _director.has_signal("wave_changed"):
		_director.wave_changed.connect(
			func(wave: int, horde_size: int) -> void:
				_flash("WAVE %d — %d incoming" % [wave, horde_size], 2.5)
		)


func _flash(text: String, seconds: float) -> void:
	banner_label.text = text
	_banner_time = seconds


func _process(delta: float) -> void:
	if _banner_time > 0.0:
		_banner_time -= delta
		banner_label.visible = true
		if _banner_time <= 0.0:
			banner_label.visible = false
	var lines: PackedStringArray = PackedStringArray()
	if _player and "health" in _player:
		lines.append("HP %d/%d" % [int(_player.health), int(_player.max_health)])
	if _player and "weapons" in _player and _player.weapons != null:
		lines.append(_player.weapons.status_line())
	if _director and _director.has_method("status_line"):
		lines.append(_director.status_line())
	lines.append("LMB/C shoot | F molotov | R reload | G door/loot | I debug cam")
	hud_label.text = "\n".join(lines)
