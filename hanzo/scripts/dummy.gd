extends CharacterBody3D
## 稻草人：受擊閃白、擊退、彈簧式搖晃、傷害數字、粒子；
## 1.5 秒內連吃三刀會「！」預告後橫掃反擊（閃步可躲）。HP 歸零倒下，1.2 秒後重生。

signal destroyed
signal hit_taken(info: Dictionary)

const MAX_HP := 70

var hp := MAX_HP
var _kb := Vector3.ZERO
var _wob := 0.0
var _wob_v := 0.0
var _hit_dir := Vector3.FORWARD
var _flash_t := 0.0
var _dead := false
var _recent_hits := 0
var _recent_t := 0.0
var _counter_t := -1.0
var _counter_cd := 0.0
var _sweep_done := false
var _spawn := Vector3.ZERO
var _mats: Array[StandardMaterial3D] = []

@onready var visual: Node3D = $Visual
@onready var hurtbox: Area3D = $Hurtbox
@onready var sweep: Area3D = $Visual/SweepBox
@onready var mark: Label3D = $Visual/Mark
@onready var arms: MeshInstance3D = $Visual/Arms
@onready var head: MeshInstance3D = $Visual/Head
var _react_tw: Tween
@onready var particles: CPUParticles3D = $HitParticles
@onready var sfx_break: AudioStreamPlayer = $SfxBreak


var _sfx_crack: AudioStreamPlayer
var _sfx_sweep: AudioStreamPlayer


func _ready() -> void:
	_spawn = global_position
	mark.visible = false
	sfx_break.stream = Sfx.make("break")
	_sfx_crack = Sfx.player(self, "break_wood", -4.0)
	_sfx_sweep = Sfx.player(self, "swing", -6.0, 0.7)
	for n in [$Visual/Straw, $Visual/Head, $Visual/Arms, $Visual/Post]:
		var mi := n as MeshInstance3D
		var src := mi.material_override as StandardMaterial3D
		var mat := src.duplicate() as StandardMaterial3D
		# 發光永遠開著、只調強度：切換 emission_enabled 會換著色器變體，
		# 第一次命中時當場編譯會卡一下（網頁版尤其明顯）
		mat.emission_enabled = true
		mat.emission = Color(1, 1, 1)
		mat.emission_energy_multiplier = 0.0
		mi.material_override = mat
		_mats.append(mat)
	# 粒子數固定（每次改 amount 會重新配置緩衝，命中瞬間會卡一下），輕重只差大小與速度
	particles.amount = 40
	particles.emitting = false
	# 頓幀期間火花改走真實時間，凍結的畫面裡仍有東西在飛
	Feel.time_scale_changed.connect(func(ts: float) -> void:
		particles.speed_scale = 1.0 / maxf(ts, 0.01))


func _physics_process(delta: float) -> void:
	velocity.x = _kb.x
	velocity.z = _kb.z
	velocity.y = -5.0 if not is_on_floor() else 0.0
	_kb = _kb.move_toward(Vector3.ZERO, 16.0 * delta)
	move_and_slide()

	if not _dead:
		# 彈簧搖晃：往受擊方向倒、彈回
		var acc := -_wob * 70.0 - _wob_v * 7.0
		_wob_v += acc * delta
		_wob += _wob_v * delta
		visual.rotation.x = _wob * _hit_dir.z
		visual.rotation.z = -_wob * _hit_dir.x

	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_set_flash(false)

	_recent_t -= delta
	if _recent_t <= 0.0:
		_recent_hits = 0
	_counter_cd -= delta
	if _counter_t >= 0.0:
		_tick_counter(delta)


func _set_flash(on: bool) -> void:
	for m in _mats:
		m.emission = Color(1, 1, 1)
		m.emission_energy_multiplier = 2.5 if on else 0.0


## 開場預熱：把命中時才會第一次出現的東西先各畫一幀，讓著色器提前編譯
func warmup() -> void:
	_set_flash(true)
	particles.global_position = global_position + Vector3(0.0, 1.2, 0.0)
	particles.scale_amount_max = 0.8
	particles.restart()
	await get_tree().process_frame
	await get_tree().process_frame
	_set_flash(false)


func take_hit(info: Dictionary) -> void:
	if _dead:
		return
	hp -= int(info.dmg)
	_hit_dir = (info.dir as Vector3).normalized()
	_kb = _hit_dir * float(info.kb)
	_wob_v += 2.4 if info.heavy else 1.3
	_flash_t = Feel.sec("hit_flash_ms")
	if _flash_t > 0.0:
		_set_flash(true)
	_react(info)
	particles.global_position = info.pos
	particles.direction = _hit_dir + Vector3(0.0, 0.6, 0.0)
	particles.scale_amount_max = 1.7 if info.heavy else 1.2
	particles.initial_velocity_max = 10.0 if info.heavy else 7.0
	particles.restart()
	Fx.damage_number(info.pos, int(info.dmg), bool(info.heavy))
	_recent_hits += 1
	_recent_t = 1.5
	hit_taken.emit(info)
	if hp <= 0:
		_die()
	elif _recent_hits >= 3 and _counter_t < 0.0 and _counter_cd <= 0.0:
		_counter_t = 0.0
		_sweep_done = false
		_recent_hits = 0
		mark.visible = true


## 受擊反應（真實時間，頓幀中可見）：整體擠扁再彈回、頭往受擊方向甩、手臂抖一下
func _react(info: Dictionary) -> void:
	if _react_tw and _react_tw.is_valid():
		_react_tw.kill()
	var heavy: bool = info.heavy
	visual.scale = Vector3(1.32, 0.72, 1.32) if heavy else Vector3(1.18, 0.86, 1.18)
	head.rotation = Vector3(_hit_dir.z * (0.9 if heavy else 0.5), 0.0, -_hit_dir.x * (0.9 if heavy else 0.5))
	arms.rotation.z = (0.5 if heavy else 0.25) * (1.0 if randf() > 0.5 else -1.0)
	_react_tw = create_tween()
	_react_tw.set_ignore_time_scale(true)
	_react_tw.set_parallel(true)
	_react_tw.tween_property(visual, "scale", Vector3.ONE, 0.32).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_react_tw.tween_property(head, "rotation", Vector3.ZERO, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_react_tw.tween_property(arms, "rotation:z", 0.0, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _tick_counter(delta: float) -> void:
	_counter_t += delta
	if _counter_t < 0.5:
		# 預告：紅光脈動 + 「！」，手臂往後拉
		var pulse := 0.5 + 0.5 * sin(_counter_t * 40.0)
		for m in _mats:
			m.emission = Color(1.0, 0.15, 0.1)
			m.emission_energy_multiplier = 0.4 + 0.8 * pulse
		arms.rotation.y = lerpf(0.0, -1.6, _counter_t / 0.5)
	elif _counter_t < 0.68:
		mark.visible = false
		arms.rotation.y = lerpf(-1.6, 2.4, (_counter_t - 0.5) / 0.18)
		if not _sweep_done:
			_sweep_done = true
			_sfx_sweep.play()
			Feel.shake(0.6)
			for a in sweep.get_overlapping_areas():
				var t := a.get_parent()
				if t and t != self and t.has_method("take_hit"):
					var dir: Vector3 = t.global_position - global_position
					dir.y = 0.0
					dir = dir.normalized()
					t.take_hit({"dmg": 15, "dir": dir, "kb": 6.0, "heavy": false, "pos": t.global_position + Vector3(0.0, 1.2, 0.0)})
	elif _counter_t < 1.0:
		arms.rotation.y = lerpf(2.4, 0.0, (_counter_t - 0.68) / 0.32)
		_set_flash(false)
	else:
		_counter_t = -1.0
		_counter_cd = 2.5
		arms.rotation.y = 0.0


func _die() -> void:
	_dead = true
	hurtbox.monitorable = false
	mark.visible = false
	_counter_t = -1.0
	_set_flash(false)
	if _react_tw and _react_tw.is_valid():
		_react_tw.kill()
	head.rotation = Vector3.ZERO
	arms.rotation = Vector3.ZERO
	sfx_break.play()
	_sfx_crack.play()
	Feel.shake(1.2)
	particles.scale_amount_max = 1.7
	particles.initial_velocity_max = 12.0
	particles.restart()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(visual, "rotation", Vector3(_hit_dir.z * 1.5, 0.0, -_hit_dir.x * 1.5), 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(visual, "scale", Vector3(1.15, 0.8, 1.15), 0.3).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_interval(0.9)
	tw.chain().tween_callback(_respawn)
	destroyed.emit()


func _respawn() -> void:
	hp = MAX_HP
	_kb = Vector3.ZERO
	_wob = 0.0
	_wob_v = 0.0
	global_position = _spawn
	visual.rotation = Vector3.ZERO
	head.rotation = Vector3.ZERO
	arms.rotation = Vector3.ZERO
	visual.scale = Vector3(0.2, 0.2, 0.2)
	var tw := create_tween()
	tw.tween_property(visual, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_dead = false
	hurtbox.monitorable = true
