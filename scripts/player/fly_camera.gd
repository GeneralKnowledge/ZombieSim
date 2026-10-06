extends Node3D
## Free-fly camera for the Million Dot benchmark world.
## Node3D (not CharacterBody3D) — no physics body cost.

@export var move_speed: float = 40.0
@export var fast_multiplier: float = 4.0
@export var look_sensitivity: float = 0.0025

@onready var camera: Camera3D = $Camera3D

var _yaw: float = 0.0
var _pitch: float = -0.4
var mouse_captured: bool = true


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	rotation = Vector3.ZERO
	camera.rotation = Vector3(_pitch, 0.0, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_mouse"):
		mouse_captured = not mouse_captured
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mouse_captured else Input.MOUSE_MODE_VISIBLE
	if mouse_captured and event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * look_sensitivity
		_pitch -= mm.relative.y * look_sensitivity
		_pitch = clampf(_pitch, -1.4, 1.4)
		rotation.y = _yaw
		camera.rotation.x = _pitch


func _process(delta: float) -> void:
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
	var speed := move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= fast_multiplier
	if input_dir.length_squared() > 0.0001:
		global_position += input_dir.normalized() * speed * delta
	SimConfig.attract_active = Input.is_action_pressed("attract")
