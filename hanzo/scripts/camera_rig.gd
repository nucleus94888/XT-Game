extends Node3D
## 跟隨鏡頭：平時俯視環繞（可旋轉 yaw、微調俯角）；瞄準時切到「過肩鏡頭」（像射擊遊戲），
## 拖曳視角＝瞄準，畫面中心就是準心。創傷式震動與方向性踢擊以真實時間推進。

@export var distance := 12.5
@export var follow_speed := 7.0
@export var look_height := 1.0

@onready var cam: Camera3D = $Camera3D

## 水平旋轉角（弧度）。0 = 從 +Z 往 -Z 看（北）
var yaw := 0.0
## 俯視環繞的俯角（弧度，從水平面算）
var pitch := deg_to_rad(49.0)
## 瞄準中：過肩鏡頭
var aiming := false
## 瞄準時的抬頭／低頭（弧度，正 = 向下看）
var aim_pitch := 0.15

var _target: Node3D
var _trauma := 0.0
var _decay := 0.0
var _kick := Vector3.ZERO
var _last_ms := 0
var _blend := 0.0
var _base_fov := 55.0


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


## 滑動視角：delta 為螢幕像素位移。瞄準中靈敏度較低、可上下抬頭低頭。
func look(delta: Vector2) -> void:
	if aiming:
		yaw -= delta.x * 0.0032
		aim_pitch = clampf(aim_pitch + delta.y * 0.0024, -0.75, 0.8)
	else:
		yaw -= delta.x * 0.0045
		pitch = clampf(pitch + delta.y * 0.0025, deg_to_rad(28.0), deg_to_rad(72.0))


## 鏡頭正前方（水平）的世界方向
func forward() -> Vector3:
	return Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, yaw)


## 瞄準射線：從鏡頭中心往畫面正中央
func aim_ray() -> Array:
	return [cam.global_position, -cam.global_transform.basis.z]


func _apply_params() -> void:
	_base_fov = Feel.get_p("cam_fov")


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
	_blend = move_toward(_blend, 1.0 if aiming else 0.0, real_dt * 6.0)
	var t := float(now) * 0.06
	var sh := _trauma * _trauma
	var off := Vector3(
		sin(t * 1.9) * 0.6 + sin(t * 3.7) * 0.4,
		cos(t * 2.3) * 0.6 + sin(t * 4.1) * 0.4,
		0.0
	) * sh * 1.6
	var roll := sin(t * 2.9) * sh * 0.09
	# 俯視環繞
	var orbit_pos := Vector3(0.0, sin(pitch) * distance, cos(pitch) * distance).rotated(Vector3.UP, yaw)
	var orbit_look := Vector3(0.0, look_height, 0.0)
	# 過肩
	var f := forward()
	var right := Vector3(1.0, 0.0, 0.0).rotated(Vector3.UP, yaw)
	# 過肩：偏右上，避免半藏的頭擋住準心
	var shoulder_pos := Vector3(0.0, 2.05, 0.0) - f * 3.0 + right * 1.05
	var aim_f := (f * cos(aim_pitch) + Vector3(0.0, -sin(aim_pitch), 0.0)).normalized()
	var shoulder_look := shoulder_pos + aim_f * 12.0
	var k := smoothstep(0.0, 1.0, _blend)
	cam.position = orbit_pos.lerp(shoulder_pos, k) + off.rotated(Vector3.UP, yaw) + _kick
	var look_at_p := global_position + orbit_look.lerp(shoulder_look, k) + _kick * 0.5
	cam.look_at(look_at_p, Vector3.UP)
	cam.rotate_object_local(Vector3(0.0, 0.0, 1.0), roll)
	cam.fov = lerpf(_base_fov, 42.0, k)
	_trauma = maxf(_trauma - _decay * real_dt, 0.0)
	_kick = _kick.lerp(Vector3.ZERO, 1.0 - exp(-14.0 * real_dt))
