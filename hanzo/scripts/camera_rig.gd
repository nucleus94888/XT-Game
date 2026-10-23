extends Node3D
## 跟隨鏡頭：可旋轉（yaw）與微調俯角（pitch），創傷式震動（trauma²）與方向性踢擊。
## 震動與踢擊以「真實時間」推進，頓幀期間畫面仍會動。

@export var distance := 12.5
@export var follow_speed := 7.0
@export var look_height := 1.0

@onready var cam: Camera3D = $Camera3D

## 水平旋轉角（弧度）。0 = 從 +Z 往 -Z 看（北）
var yaw := 0.0
## 俯角（弧度，從水平面算）
var pitch := deg_to_rad(49.0)

var _target: Node3D
var _trauma := 0.0
var _decay := 0.0
var _kick := Vector3.ZERO
var _last_ms := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Feel.shake_requested.connect(_on_shake)
	Feel.kick_requested.connect(_on_kick)
	Feel.params_changed.connect(_apply_params)
	_apply_params()
	_last_ms = Time.get_ticks_msec()


func set_target(t: Node3D) -> void:
	_target = t
	if _target:
		global_position = _target.global_position


## 滑動視角：delta 為螢幕像素位移
func look(delta: Vector2) -> void:
	yaw -= delta.x * 0.0045
	pitch = clampf(pitch + delta.y * 0.0025, deg_to_rad(28.0), deg_to_rad(72.0))


## 鏡頭正前方（水平）的世界方向
func forward() -> Vector3:
	return Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, yaw)


func _apply_params() -> void:
	cam.fov = Feel.get_p("cam_fov")


func _on_shake(amp: float, dur: float) -> void:
	_trauma = minf(maxf(_trauma, amp), 1.0)
	_decay = amp / maxf(dur, 0.02)


func _on_kick(dir: Vector3, amount: float) -> void:
	_kick += Vector3(dir.x, 0.0, dir.z) * amount


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	var real_dt := clampf(float(now - _last_ms) / 1000.0, 0.0, 0.1)
	_last_ms = now
	if _target:
		var w := 1.0 - exp(-follow_speed * delta)
		global_position = global_position.lerp(_target.global_position, w)
	var t := float(now) * 0.06
	var sh := _trauma * _trauma
	var off := Vector3(
		sin(t * 1.9) * 0.6 + sin(t * 3.7) * 0.4,
		cos(t * 2.3) * 0.6 + sin(t * 4.1) * 0.4,
		0.0
	) * sh * 1.6
	var roll := sin(t * 2.9) * sh * 0.09
	var base := Vector3(0.0, sin(pitch) * distance, cos(pitch) * distance).rotated(Vector3.UP, yaw)
	cam.position = base + off.rotated(Vector3.UP, yaw) + _kick
	cam.look_at(global_position + Vector3(0.0, look_height, 0.0) + _kick * 0.5, Vector3.UP)
	cam.rotate_object_local(Vector3(0.0, 0.0, 1.0), roll)
	_trauma = maxf(_trauma - _decay * real_dt, 0.0)
	_kick = _kick.lerp(Vector3.ZERO, 1.0 - exp(-14.0 * real_dt))
