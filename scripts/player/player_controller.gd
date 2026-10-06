extends CharacterBody3D
## Grounded sandbox player. Iso-friendly WASD, mouse-aim on ground plane.

signal died
signal health_changed(current: float, maximum: float)

@export var move_speed: float = 8.5
@export var sprint_multiplier: float = 1.55
@export var max_health: float = 100.0

var health: float = 100.0
var aim_direction: Vector3 = Vector3(0, 0, -1)
var weapons: WeaponLoadout = WeaponLoadout.new()
var alive: bool = true
## Kept for main.gd compatibility (mouse is free in sandbox).
var mouse_captured: bool = false

@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _facing: Node3D = $Facing


func _ready() -> void:
	health = max_health
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	floor_snap_length = 0.2
	if _mesh:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.55, 0.95)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mesh.material_override = mat
	health_changed.emit(health, max_health)


func _physics_process(delta: float) -> void:
	if not alive:
		return
	weapons.tick(delta)
	_update_aim_from_mouse()
	var input := Vector3.ZERO
	# Iso-aligned movement (screen-relative-ish for 45° camera).
	if Input.is_action_pressed("move_forward"):
		input += Vector3(-1, 0, -1)
	if Input.is_action_pressed("move_back"):
		input += Vector3(1, 0, 1)
	if Input.is_action_pressed("move_left"):
		input += Vector3(-1, 0, 1)
	if Input.is_action_pressed("move_right"):
		input += Vector3(1, 0, -1)
	var speed := move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= sprint_multiplier
	if input.length_squared() > 0.0001:
		velocity.x = input.normalized().x * speed
		velocity.z = input.normalized().z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)
	velocity.y = 0.0
	move_and_slide()
	# Stay on ground plane y=0 for sandbox.
	global_position.y = 0.9
	if _facing and aim_direction.length_squared() > 0.0001:
		_facing.look_at(global_position + aim_direction, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if not alive:
		return
	if event.is_action_pressed("reload"):
		weapons.start_reload()


func _update_aim_from_mouse() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var screen := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return
	var t := (0.0 - from.y) / dir.y
	if t < 0.0:
		return
	var hit := from + dir * t
	var aim := hit - global_position
	aim.y = 0.0
	if aim.length_squared() > 0.0001:
		aim_direction = aim.normalized()


func apply_damage(amount: float) -> void:
	if not alive:
		return
	health = maxf(0.0, health - amount)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		alive = false
		died.emit()


func heal(amount: float) -> void:
	if not alive:
		return
	health = minf(max_health, health + amount)
	health_changed.emit(health, max_health)
