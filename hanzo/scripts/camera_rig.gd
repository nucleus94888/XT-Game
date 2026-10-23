extends Node3D
## 跟隨鏡頭 + 創傷式震動（trauma²）。
## 震動以「真實時間」推進，所以頓幀期間畫面仍會顫動，撞擊感不會被凍住。

@export var offset := Vector3(0.0, 7.2, 6.2)
@export var follow_speed := 7.0
@export var look_height := 1.0

@onready var cam: Camera3D = $Camera3D

var _target: Node3D
var _trauma := 0.0
var _decay := 0.0
var _last_ms := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Feel.shake_requested.connect(_on_shake)
	Feel.params_changed.connect(_apply_params)
	_apply_params()
	_last_ms = Time.get_ticks_msec()


func set_target(t: Node3D) -> void:
	_target = t
	if _target:
		global_position = _target.global_position


func _apply_params() -> void:
	cam.fov = Feel.get_p("cam_fov")


func _on_shake(amp: float, dur: float) -> void:
	_trauma = minf(maxf(_trauma, amp), 1.0)
	_decay = amp / maxf(dur, 0.02)


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
	cam.position = offset + off
	cam.look_at(global_position + Vector3(0.0, look_height, 0.0), Vector3.UP)
	cam.rotate_object_local(Vector3(0.0, 0.0, 1.0), roll)
	_trauma = maxf(_trauma - _decay * real_dt, 0.0)
