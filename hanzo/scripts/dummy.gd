extends CharacterBody3D
## 稻草人：受擊閃白、擊退、彈簧式搖晃、傷害數字、粒子；
## 1.5 秒內連吃三刀會「！」預告後橫掃反擊（閃步可躲）。HP 歸零倒下，1.2 秒後重生。

signal destroyed
signal hit_taken(info: Dictionary)
signal posture_broken
signal executed

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
var _stun_t := 0.0
var _sfx_sweep: AudioStreamPlayer
## 體幹（隻狼式）：被打、被彈反都會累積；滿了就「崩壞」，下一刀是忍殺
var posture := 0.0
var _posture_t := 0.0
var _broken := false
var _bar: Node3D
var _bar_fill: MeshInstance3D
var _bar_mat: StandardMaterial3D
var _attack_cd := 1.5
var _player: Node3D


func _ready() -> void:
	_spawn = global_position
	mark.visible = false
	Sfx.bind(sfx_break, "break", 1.06)
	_sfx_crack = Sfx.player(self, "hit", -5.0, 0.9)
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
	_build_bar()
	_player = get_tree().get_first_node_in_group("player")


## 頭上的體幹條（不隨搖晃傾斜）
func _build_bar() -> void:
	_bar = Node3D.new()
	add_child(_bar)
	_bar.position = Vector3(0.0, 2.75, 0.0)
	var bg := MeshInstance3D.new()
	var qbg := QuadMesh.new()
	qbg.size = Vector2(1.5, 0.14)
	var mbg := StandardMaterial3D.new()
	mbg.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mbg.albedo_color = Color(0.05, 0.05, 0.06, 0.8)
	mbg.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mbg.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mbg.no_depth_test = true
	qbg.material = mbg
	bg.mesh = qbg
	_bar.add_child(bg)
	_bar_fill = MeshInstance3D.new()
	var qf := QuadMesh.new()
	qf.size = Vector2(1.44, 0.1)
	_bar_mat = StandardMaterial3D.new()
	_bar_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bar_mat.albedo_color = Color(1.0, 0.75, 0.2)
	_bar_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_bar_mat.no_depth_test = true
	_bar_mat.render_priority = 1
	qf.material = _bar_mat
	_bar_fill.mesh = qf
	_bar_fill.position = Vector3(0.0, 0.0, 0.01)
	_bar.add_child(_bar_fill)
	_update_bar()


func _update_bar() -> void:
	var r := clampf(posture / 100.0, 0.0, 1.0)
	_bar_fill.scale.x = maxf(r, 0.001)
	_bar_fill.position.x = -0.72 * (1.0 - r)
	_bar_fill.visible = r > 0.0
	_bar_mat.albedo_color = Color(1.0, 0.2, 0.15) if _broken else Color(1.0, 0.75 - 0.5 * r, 0.2)


func add_posture(v: float) -> void:
	if _broken or _dead:
		return
	posture = minf(posture + v, 100.0)
	_posture_t = 1.5
	_update_bar()
	if posture >= 100.0:
		_break_posture()


## 體幹崩壞：長硬直 2.5 秒、紅條閃爍，期間任何一刀都是忍殺
func _break_posture() -> void:
	_broken = true
	_stun_t = 2.5
	_counter_t = -1.0
	_attack_cd = 3.0
	mark.visible = false
	_wob_v += 3.5
	_flash_t = 0.3
	_set_flash(true)
	_update_bar()
	posture_broken.emit()
	get_tree().create_timer(2.5).timeout.connect(func() -> void:
		if _broken and not _dead:
			_broken = false
			posture = 35.0
			_update_bar())


## 忍殺：體幹崩壞中被砍 → 一刀致命
func _execute(info: Dictionary) -> void:
	_broken = false
	posture = 0.0
	_update_bar()
	_hit_dir = (info.dir as Vector3).normalized()
	_kb = _hit_dir * 3.0
	Fx.damage_number(info.pos, hp, true)
	hp = 0
	Feel.hitstop(2.4)
	Feel.shake(1.6)
	Feel.kick(_hit_dir, 0.5)
	Feel.flash(Color(0.75, 0.05, 0.05, 0.45), 0.5)
	particles.global_position = info.pos
	particles.direction = _hit_dir + Vector3(0.0, 0.8, 0.0)
	particles.scale_amount_max = 2.0
	particles.initial_velocity_max = 14.0
	particles.restart()
	executed.emit()
	_die()


func _start_counter() -> void:
	_counter_t = 0.0
	_sweep_done = false
	_recent_hits = 0
	mark.visible = true


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
	_stun_t -= delta
	if _counter_t >= 0.0:
		_tick_counter(delta)
	# 體幹：1.5 秒沒被打就慢慢回復
	_posture_t -= delta
	if _posture_t <= 0.0 and not _broken and posture > 0.0:
		posture = maxf(posture - 12.0 * delta, 0.0)
		_update_bar()
	# 玩家靠近時會主動橫掃（練彈反用）
	_attack_cd -= delta
	if not _dead and not _broken and _stun_t <= 0.0 and _counter_t < 0.0 and _attack_cd <= 0.0 and _player \
			and global_position.distance_to(_player.global_position) < 3.2:
		_start_counter()
		_attack_cd = 2.8


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
	if _broken:
		_execute(info)
		return
	add_posture(16.0 if info.heavy else 8.0)
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
	elif _recent_hits >= 3 and _counter_t < 0.0 and _counter_cd <= 0.0 and _stun_t <= 0.0:
		_start_counter()


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
			Sfx.play(_sfx_sweep)
			Feel.shake(0.6)
			for a in sweep.get_overlapping_areas():
				var t := a.get_parent()
				if t and t != self and t.has_method("take_hit"):
					var dir: Vector3 = t.global_position - global_position
					dir.y = 0.0
					dir = dir.normalized()
					t.take_hit({"dmg": 15, "dir": dir, "kb": 6.0, "heavy": false, "pos": t.global_position + Vector3(0.0, 1.2, 0.0), "src": self})
	elif _counter_t < 1.0:
		arms.rotation.y = lerpf(2.4, 0.0, (_counter_t - 0.68) / 0.32)
		_set_flash(false)
	else:
		_counter_t = -1.0
		_counter_cd = 2.5
		arms.rotation.y = 0.0


## 被彈反（隻狼式）：手臂被彈回、整個往後仰、閃白、短暫不能再攻，體幹 +35
func deflected(push_dir: Vector3) -> void:
	if _dead:
		return
	_counter_t = 0.72
	_counter_cd = 1.2
	_attack_cd = 1.6
	_stun_t = 0.6
	mark.visible = false
	_hit_dir = push_dir.normalized()
	_kb = _hit_dir * 2.5
	_wob_v += 2.6
	_flash_t = 0.18
	_set_flash(true)
	if _react_tw and _react_tw.is_valid():
		_react_tw.kill()
	visual.scale = Vector3(1.12, 0.9, 1.12)
	head.rotation = Vector3(_hit_dir.z * 0.7, 0.0, -_hit_dir.x * 0.7)
	arms.rotation.y = -1.2
	_react_tw = create_tween()
	_react_tw.set_ignore_time_scale(true)
	_react_tw.set_parallel(true)
	_react_tw.tween_property(visual, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_react_tw.tween_property(head, "rotation", Vector3.ZERO, 0.7).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_react_tw.tween_property(arms, "rotation:y", 0.0, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	add_posture(35.0)


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
	Sfx.play(sfx_break)
	Sfx.play(_sfx_crack)
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
	_broken = false
	posture = 0.0
	_attack_cd = 1.5
	_update_bar()
