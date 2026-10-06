extends Node3D
## Free-fly / isometric camera. Exposes aim direction for shoot + Molotov.

@export var move_speed: float = 40.0
@export var fast_multiplier: float = 4.0
@export var look_sensitivity: float = 0.0025
@export var iso_height: float = 55.0
@export var iso_distance: float = 70.0

@onready var camera: Camera3D = $Camera3D

var _yaw: float = 0.0
var _pitch: float = -0.4
var mouse_captured: bool = true
var aim_direction: Vector3 = Vector3(0, 0, -1)
var _focus: Vector3 = Vector3.ZERO


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	rotation = Vector3.ZERO
	camera.rotation = Vector3(_pitch, 0.0, 0.0)
	_focus = global_position
	_apply_camera_mode()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_mouse"):
		mouse_captured = not mouse_captured
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mouse_captured else Input.MOUSE_MODE_VISIBLE
	if event.is_action_pressed("toggle_iso"):
		SimConfig.isometric_mode = not SimConfig.isometric_mode
		_apply_camera_mode()
	if mouse_captured and event is InputEventMouseMotion and not SimConfig.isometric_mode:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * look_sensitivity
		_pitch -= mm.relative.y * look_sensitivity
		_pitch = clampf(_pitch, -1.4, 1.4)
		rotation.y = _yaw
		camera.rotation.x = _pitch


func _apply_camera_mode() -> void:
	if SimConfig.isometric_mode:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 48.0
		camera.near = 0.1
		camera.far = 2000.0
		# Classic-ish isometric angle
		rotation = Vector3.ZERO
		camera.rotation_degrees = Vector3(-35.264, 45.0, 0.0)
		_focus = global_position
		_update_iso_rig()
	else:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = 70.0
		camera.rotation = Vector3(_pitch, 0.0, 0.0)
		rotation.y = _yaw
		camera.position = Vector3.ZERO


func _update_iso_rig() -> void:
	# Keep the Node3D at focus; offset the Camera3D along iso view.
	global_position = _focus
	var back := Vector3(1, 0, 1).normalized()
	camera.position = Vector3(0, iso_height, 0) + back * iso_distance
	camera.look_at(_focus)


func _process(delta: float) -> void:
	var speed := move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= fast_multiplier

	if SimConfig.isometric_mode:
		var flat := Vector3.ZERO
		if Input.is_action_pressed("move_forward"):
			flat += Vector3(-1, 0, -1)
		if Input.is_action_pressed("move_back"):
			flat += Vector3(1, 0, 1)
		if Input.is_action_pressed("move_left"):
			flat += Vector3(-1, 0, 1)
		if Input.is_action_pressed("move_right"):
			flat += Vector3(1, 0, -1)
		if flat.length_squared() > 0.0001:
			_focus += flat.normalized() * speed * delta
		_update_iso_rig()
		# Aim along ground from screen center forward-left of iso view.
		aim_direction = Vector3(-1, 0, -1).normalized()
	else:
		var input_dir := Vector3.ZERO
		var basis_cam := camera.global_transform.basis
		if Input.is_action_pressed("move_forward"):
			input_dir -= basis_cam.z
		if Input.is_action_pressed("move_back"):
			input_dir += basis_cam.z
		if Input.is_action_pressed("move_left"):
			input_dir -= basis_cam.x
		if Input.is_action_pressed("move_right"):
			input_dir += basis_cam.x
		if Input.is_action_pressed("move_up"):
			input_dir += Vector3.UP
		if Input.is_action_pressed("move_down"):
			input_dir -= Vector3.UP
		if input_dir.length_squared() > 0.0001:
			global_position += input_dir.normalized() * speed * delta
		aim_direction = -camera.global_transform.basis.z
		aim_direction.y = 0.0
		if aim_direction.length_squared() < 0.0001:
			aim_direction = Vector3(0, 0, -1)
		else:
			aim_direction = aim_direction.normalized()

	SimConfig.attract_active = Input.is_action_pressed("attract")
