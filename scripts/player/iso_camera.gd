extends Node3D
## Follows the grounded player. Iso by default; F5 toggles free debug orbit.

@export var target_path: NodePath
@export var iso_height: float = 42.0
@export var iso_distance: float = 48.0
@export var follow_speed: float = 12.0
@export var ortho_size: float = 36.0

@onready var camera: Camera3D = $Camera3D

var _target: Node3D
var _debug_fly: bool = false
var _yaw: float = 0.0
var _pitch: float = -0.5


func _ready() -> void:
	if target_path != NodePath(""):
		_target = get_node_or_null(target_path) as Node3D
	SimConfig.isometric_mode = true
	_apply_mode()


func set_target(node: Node3D) -> void:
	_target = node


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_iso"):
		_debug_fly = not _debug_fly
		SimConfig.isometric_mode = not _debug_fly
		_apply_mode()
	if _debug_fly and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.003
		_pitch = clampf(_pitch - mm.relative.y * 0.003, -1.3, -0.1)


func _apply_mode() -> void:
	if SimConfig.isometric_mode:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = ortho_size
		camera.near = 0.1
		camera.far = 2000.0
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = 70.0
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if _target == null:
		return
	var focus := _target.global_position
	focus.y = 0.0
	if SimConfig.isometric_mode:
		var back := Vector3(1, 0, 1).normalized()
		var desired := focus + Vector3(0, iso_height, 0) + back * iso_distance
		global_position = global_position.lerp(desired, clampf(follow_speed * delta, 0.0, 1.0))
		camera.position = Vector3.ZERO
		look_at(focus, Vector3.UP)
		# Stabilize classic iso tilt
		rotation_degrees.x = -35.264
		rotation_degrees.y = 45.0
		rotation_degrees.z = 0.0
	else:
		var offset := Vector3(0, 8, 14).rotated(Vector3.UP, _yaw)
		global_position = focus + offset
		camera.position = Vector3.ZERO
		look_at(focus + Vector3(0, 1.2, 0), Vector3.UP)
