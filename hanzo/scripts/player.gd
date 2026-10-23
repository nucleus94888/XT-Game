extends CharacterBody3D
## 半藏：移動、三段連斬、閃步、受擊。
## 所有時間與力道從 Feel 讀取；COMBO 表只放「相對倍率」與角度。

signal hit_landed(info: Dictionary)
signal hp_changed(hp: int)
signal died
signal parried
## 實際扣血時發出（格擋成功不算）
signal damaged(amount: int)

enum State { FREE, ATTACK, DASH, HURT, BLOCK }

const SPEED := 6.2
const ACCEL := 34.0
const DASH_SPEED := 17.0
const DASH_TIME := 0.17
const MAX_HP := 100
const PIVOT_HOME := Vector3(0.0, 1.15, 0.0)
## 格擋姿勢（隻狼式）：刀身豎直在身前、略向內收
const GUARD_ROT := Vector3(-82.0, 18.0, -10.0)
const GUARD_POS := Vector3(-0.18, 1.1, 0.12)

## 三段連斬：from/to 為刀的水平掃角（度），tilt 為第三段的下劈抬刀角；
## tmul 乘在前置/有效/收刀三段時間上，stop/shake/kb 乘在頓幀/震動/擊退上。
const COMBO := [
	{"from": 95.0, "to": -75.0, "dmg": 12, "kb": 1.0, "stop": 1.0, "shake": 1.0, "tmul": 1.0, "tilt": 0.0, "heavy": false},
	{"from": -105.0, "to": 85.0, "dmg": 14, "kb": 1.15, "stop": 1.0, "shake": 1.1, "tmul": 0.95, "tilt": 0.0, "heavy": false},
	{"from": 40.0, "to": -130.0, "dmg": 28, "kb": 2.3, "stop": 1.7, "shake": 1.9, "tmul": 1.35, "tilt": 75.0, "heavy": true},
]

var state := State.FREE
var touch: Node = null
var hp := MAX_HP

var _facing := 0.0
var _combo_idx := 0
var _combo_window := 0.0
var _phase := 0
var _phase_t := 0.0
var _phase_len := 0.1
var _queued := false
var _hit_targets := {}
var _dash_t := 0.0
var _dash_dir := Vector3.FORWARD
var _invuln := false
var _hurt_t := 0.0
var _trail_mat: StandardMaterial3D
var _jolt_tw: Tween
var _block_held := false
var _block_start_ms := 0
var _sfx_block: AudioStreamPlayer
var _sfx_deflect: AudioStreamPlayer
var _guard_tw: Tween
var _spark: CPUParticles3D

@onready var visual: Node3D = $Visual
@onready var body: MeshInstance3D = $Visual/Body
@onready var sword_pivot: Node3D = $Visual/SwordPivot
@onready var hitbox: Area3D = $Visual/SwordPivot/Hitbox
@onready var trail: MeshInstance3D = $Visual/Trail
@onready var sfx_swing: AudioStreamPlayer = $SfxSwing
@onready var sfx_hit: AudioStreamPlayer = $SfxHit
@onready var sfx_heavy: AudioStreamPlayer = $SfxHeavy
@onready var sfx_dash: AudioStreamPlayer = $SfxDash
@onready var sfx_hurt: AudioStreamPlayer = $SfxHurt


var _sfx_heavy_wood: AudioStreamPlayer


func _ready() -> void:
	# 音效：Kenney CC0，各組隨機變化（見 sfx.gd）
	Sfx.bind(sfx_swing, "swing", 1.12)
	Sfx.bind(sfx_hit, "hit", 1.08)
	Sfx.bind(sfx_heavy, "heavy", 1.05, 0.95)
	Sfx.bind(sfx_dash, "dash", 1.15)
	Sfx.bind(sfx_hurt, "hurt", 1.08)
	_sfx_heavy_wood = Sfx.player(self, "heavy_wood", -9.0, 0.9)
	_sfx_block = Sfx.player(self, "block", -6.0, 1.0, 1.1)
	_sfx_deflect = Sfx.player(self, "deflect", -2.0, 1.05, 1.08)
	add_to_group("player")
	_build_spark()
	_trail_mat = StandardMaterial3D.new()
	_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_mat.vertex_color_use_as_albedo = true
	_trail_mat.no_depth_test = true
	_trail_mat.albedo_color = Color(1, 1, 1, 1)
	trail.material_override = _trail_mat
	trail.visible = false


func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("attack"):
		request_attack()
	elif ev.is_action_pressed("dash"):
		request_dash()
	elif ev.is_action_pressed("block"):
		set_block(true)
	elif ev.is_action_released("block"):
		set_block(false)


## 攻擊鍵：空閒/閃步中立刻出刀；攻擊中則排隊，收刀到一半自動接下一段。
func request_attack() -> void:
	match state:
		State.ATTACK:
			_queued = true
		State.FREE, State.DASH, State.BLOCK:
			_start_attack()


## 格擋鍵：按住生效。空閒時立刻舉刀；攻擊收刀/閃步結束後若仍按著會自動回到格擋。
## 對方的攻擊在舉刀後 160ms 內打到 = 彈反（對方硬直）。
func set_block(on: bool) -> void:
	_block_held = on
	if on:
		if state == State.FREE or (state == State.ATTACK and _phase == 2):
			_start_block()
	elif state == State.BLOCK:
		state = State.FREE


func _start_block() -> void:
	state = State.BLOCK
	_block_start_ms = Time.get_ticks_msec()
	_queued = false
	trail.visible = false


func _after_action() -> State:
	if _block_held:
		_start_block()
		return State.BLOCK
	return State.FREE


func _tick_block(delta: float, input: Vector2) -> void:
	var dir := Vector3(input.x, 0.0, input.y)
	velocity.x = move_toward(velocity.x, dir.x * SPEED * 0.3, ACCEL * delta)
	velocity.z = move_toward(velocity.z, dir.z * SPEED * 0.3, ACCEL * delta)
	_face_input(input, false)
	visual.rotation.y = lerp_angle(visual.rotation.y, _facing, 1.0 - exp(-16.0 * delta))
	# 架刀：身體前傾壓低、刀豎直擋在身前（快速到位，不拖泥帶水）
	body.rotation.x = lerpf(body.rotation.x, 0.18, 1.0 - exp(-14.0 * delta))
	visual.position.y = lerpf(visual.position.y, -0.06, 1.0 - exp(-14.0 * delta))
	if _guard_tw == null or not _guard_tw.is_valid():
		sword_pivot.rotation_degrees = sword_pivot.rotation_degrees.lerp(GUARD_ROT, 1.0 - exp(-40.0 * delta))
	sword_pivot.position = sword_pivot.position.lerp(GUARD_POS, 1.0 - exp(-30.0 * delta))


## 閃步鍵：空閒可閃；出刀「前置」與「收刀」階段可取消成閃步（有效幀不可）。
func request_dash() -> void:
	if state == State.FREE or state == State.BLOCK or (state == State.ATTACK and _phase != 1):
		_start_dash()


func _physics_process(delta: float) -> void:
	var input := _read_input()
	match state:
		State.FREE:
			_tick_free(delta, input)
		State.ATTACK:
			_tick_attack(delta, input)
		State.DASH:
			_tick_dash(delta)
		State.HURT:
			_tick_hurt(delta)
		State.BLOCK:
			_tick_block(delta, input)
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = 0.0
	move_and_slide()
	if state != State.ATTACK and _combo_window > 0.0:
		_combo_window -= delta
		if _combo_window <= 0.0:
			_combo_idx = 0


func _read_input() -> Vector2:
	var v := Vector2.ZERO
	if touch != null:
		v = touch.move_vector
	var kb := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if kb.length_squared() > v.length_squared():
		v = kb
	return v.limit_length(1.0)


func _forward() -> Vector3:
	return Vector3(-sin(_facing), 0.0, -cos(_facing))


func _face_input(input: Vector2, snap: bool) -> void:
	if input.length() > 0.2:
		_facing = atan2(-input.x, -input.y)
		if snap:
			visual.rotation.y = _facing


func _tick_free(delta: float, input: Vector2) -> void:
	var dir := Vector3(input.x, 0.0, input.y)
	velocity.x = move_toward(velocity.x, dir.x * SPEED, ACCEL * delta)
	velocity.z = move_toward(velocity.z, dir.z * SPEED, ACCEL * delta)
	_face_input(input, false)
	visual.rotation.y = lerp_angle(visual.rotation.y, _facing, 1.0 - exp(-16.0 * delta))
	var spd := Vector2(velocity.x, velocity.z).length() / SPEED
	body.rotation.x = lerpf(body.rotation.x, -0.14 * spd, 1.0 - exp(-10.0 * delta))
	visual.position.y = sin(Time.get_ticks_msec() * 0.006) * 0.025 * (1.0 + spd * 2.0)
	sword_pivot.rotation_degrees = sword_pivot.rotation_degrees.lerp(Vector3.ZERO, 1.0 - exp(-14.0 * delta))
	sword_pivot.position = sword_pivot.position.lerp(PIVOT_HOME, 1.0 - exp(-14.0 * delta))


func _start_attack() -> void:
	state = State.ATTACK
	_phase = 0
	_phase_t = 0.0
	_queued = false
	_hit_targets.clear()
	_invuln = false
	var c: Dictionary = COMBO[_combo_idx]
	_phase_len = Feel.sec("windup_ms") * float(c.tmul)
	_face_input(_read_input(), true)
	velocity.x *= 0.3
	velocity.z *= 0.3
	trail.visible = false
	sword_pivot.position = PIVOT_HOME
	if _guard_tw and _guard_tw.is_valid():
		_guard_tw.kill()
	# 出刀有聲音：附近未察覺的敵人會起疑
	get_tree().call_group("enemies", "hear_noise", global_position, 5.0)
	# 揮刀音在「按下」的瞬間就播（而不是等前置蓄力結束），抵銷手機音訊輸出延遲
	sfx_swing.set_meta("sfx_base", 0.8 if c.heavy else 1.0)
	Sfx.play(sfx_swing)


func _tick_attack(delta: float, _input: Vector2) -> void:
	var c: Dictionary = COMBO[_combo_idx]
	_phase_t += delta
	var k := clampf(_phase_t / maxf(_phase_len, 0.001), 0.0, 1.0)
	var from_deg: float = c.from
	var to_deg: float = c.to
	var tilt: float = c.tilt
	match _phase:
		0:
			# 前置：刀往後拉、身體後仰、腳步剎停
			var e := ease(k, 0.45)
			sword_pivot.rotation_degrees.y = lerpf(0.0, from_deg, e)
			sword_pivot.rotation_degrees.x = lerpf(0.0, -tilt, e)
			body.rotation.x = lerpf(body.rotation.x, 0.12, 1.0 - exp(-20.0 * delta))
			visual.rotation.y = lerp_angle(visual.rotation.y, _facing, 1.0 - exp(-30.0 * delta))
			velocity.x = move_toward(velocity.x, 0.0, 40.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 40.0 * delta)
			if k >= 1.0:
				_phase = 1
				_phase_t = 0.0
				_phase_len = Feel.sec("active_ms") * float(c.tmul)
				_build_trail(from_deg, to_deg, tilt)
				trail.visible = true
		1:
			# 有效：刀快速掃過（先快後慢）、前衝、每個物理幀檢查命中
			var e := 1.0 - pow(1.0 - k, 2.2)
			sword_pivot.rotation_degrees.y = lerpf(from_deg, to_deg, e)
			sword_pivot.rotation_degrees.x = lerpf(-tilt, tilt * 0.35, e)
			body.rotation.x = lerpf(0.12, -0.22, e)
			var fwd := _forward()
			var lunge := Feel.get_p("lunge") * 2.4 * (1.0 - k)
			velocity.x = fwd.x * lunge
			velocity.z = fwd.z * lunge
			_set_trail_alpha(Feel.get_p("trail_alpha"))
			_check_hits(c)
			if k >= 1.0:
				_phase = 2
				_phase_t = 0.0
				_phase_len = Feel.sec("recovery_ms") * float(c.tmul)
		2:
			# 收刀：刀回位、刀光淡出；過半可接下一段
			var e := ease(k, 0.4)
			sword_pivot.rotation_degrees.y = lerpf(to_deg, 0.0, e)
			sword_pivot.rotation_degrees.x = lerpf(tilt * 0.35, 0.0, e)
			body.rotation.x = lerpf(-0.22, 0.0, e)
			_set_trail_alpha(Feel.get_p("trail_alpha") * (1.0 - e))
			velocity.x = move_toward(velocity.x, 0.0, 22.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 22.0 * delta)
			if _queued and k >= 0.5:
				_combo_idx = (_combo_idx + 1) % COMBO.size()
				_start_attack()
				return
			if k >= 1.0:
				trail.visible = false
				_combo_idx = (_combo_idx + 1) % COMBO.size()
				_combo_window = 0.8
				state = _after_action()


func _check_hits(c: Dictionary) -> void:
	for a in hitbox.get_overlapping_areas():
		var tgt := a.get_parent()
		if tgt == null or tgt == self or not tgt.has_method("take_hit"):
			continue
		if _hit_targets.has(tgt):
			continue
		_hit_targets[tgt] = true
		var info := {
			"dmg": c.dmg,
			"dir": _forward(),
			"kb": Feel.get_p("knockback") * float(c.kb),
			"heavy": c.heavy,
			"pos": hitbox.to_global(Vector3(0.38, 0.0, -0.9)),
			"src": self,
		}
		# 未察覺的敵人從背後砍 = 暗殺（一擊必殺、無聲）
		if tgt.has_method("can_be_assassinated") and tgt.can_be_assassinated(self):
			tgt.assassinate(info)
			Feel.shake(0.6)
			hit_landed.emit(info)
			continue
		tgt.take_hit(info)
		_on_landed(info, c)


func _on_landed(info: Dictionary, c: Dictionary) -> void:
	Feel.hitstop(float(c.stop))
	Feel.shake(float(c.shake))
	# 刀撞上東西的反作用：鏡頭往砍的方向踢一下、身體一震（真實時間，頓幀中可見）
	Feel.kick(_forward(), 0.35 * float(c.shake))
	body.scale = Vector3(1.14, 0.9, 1.14) if c.heavy else Vector3(1.08, 0.95, 1.08)
	if _jolt_tw and _jolt_tw.is_valid():
		_jolt_tw.kill()
	_jolt_tw = create_tween()
	_jolt_tw.set_ignore_time_scale(true)
	_jolt_tw.tween_property(body, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var sp := sfx_heavy if c.heavy else sfx_hit
	var d := Feel.sec("sfx_delay_ms")
	if d > 0.0:
		get_tree().create_timer(d, true, false, true).timeout.connect(Sfx.play.bind(sp))
		if c.heavy:
			get_tree().create_timer(d, true, false, true).timeout.connect(Sfx.play.bind(_sfx_heavy_wood))
	else:
		Sfx.play(sp)
		if c.heavy:
			Sfx.play(_sfx_heavy_wood)
	hit_landed.emit(info)


func _start_dash() -> void:
	state = State.DASH
	_dash_t = 0.0
	var input := _read_input()
	if input.length() > 0.2:
		_dash_dir = Vector3(input.x, 0.0, input.y).normalized()
		_facing = atan2(-_dash_dir.x, -_dash_dir.z)
	else:
		_dash_dir = _forward()
	visual.rotation.y = _facing
	_invuln = true
	_queued = false
	trail.visible = false
	sword_pivot.rotation_degrees = Vector3.ZERO
	Sfx.play(sfx_dash)
	Fx.afterimage(body, Color(0.6, 0.7, 1.0, 0.45), 0.22)


func _tick_dash(delta: float) -> void:
	_dash_t += delta
	var k := _dash_t / DASH_TIME
	var s := DASH_SPEED * (1.0 - 0.55 * k)
	velocity.x = _dash_dir.x * s
	velocity.z = _dash_dir.z * s
	body.rotation.x = -0.35
	if fmod(_dash_t, 0.05) < delta:
		Fx.afterimage(body, Color(0.6, 0.7, 1.0, 0.3), 0.2)
	if _dash_t >= DASH_TIME:
		_invuln = false
		state = _after_action()
		velocity.x *= 0.35
		velocity.z *= 0.35


## 被稻草人反擊打到（閃步中無敵）
func take_hit(info: Dictionary) -> void:
	if _invuln or state == State.HURT:
		return
	if state == State.BLOCK and _forward().dot(-(info.dir as Vector3)) > 0.2:
		_blocked_hit(info)
		return
	hp = maxi(hp - int(info.dmg), 0)
	hp_changed.emit(hp)
	damaged.emit(int(info.dmg))
	state = State.HURT
	_hurt_t = 0.0
	_queued = false
	trail.visible = false
	var dir: Vector3 = info.dir
	velocity.x = dir.x * 7.0
	velocity.z = dir.z * 7.0
	body.scale = Vector3(1.2, 0.82, 1.2)
	if _jolt_tw and _jolt_tw.is_valid():
		_jolt_tw.kill()
	_jolt_tw = create_tween()
	_jolt_tw.set_ignore_time_scale(true)
	_jolt_tw.tween_property(body, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	Feel.kick(dir, 0.5)
	Sfx.play(sfx_hurt)
	Feel.hitstop(0.8)
	Feel.shake(1.6)
	Feel.flash(Color(0.8, 0.1, 0.1, 0.35), 0.25)
	if hp <= 0:
		died.emit()
		hp = MAX_HP
		hp_changed.emit(hp)


## 格擋（隻狼式）
## 一般格擋：刀被震開一下、小火花、小後退，不扣血。
## 彈反：舉刀後 parry_ms 內擋下 → 刀向外一撥、大片火花、閃白、長頓幀，對方後仰並累積「體幹」。
func _blocked_hit(info: Dictionary) -> void:
	var dir: Vector3 = info.dir
	var ranged: bool = info.get("ranged", false)
	var perfect: bool = (not ranged) and Time.get_ticks_msec() - _block_start_ms <= int(Feel.get_p("parry_ms"))
	var src = info.get("src")
	body.scale = Vector3(1.1, 0.92, 1.1)
	if _jolt_tw and _jolt_tw.is_valid():
		_jolt_tw.kill()
	_jolt_tw = create_tween()
	_jolt_tw.set_ignore_time_scale(true)
	_jolt_tw.tween_property(body, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if _guard_tw and _guard_tw.is_valid():
		_guard_tw.kill()
	_guard_tw = create_tween()
	_guard_tw.set_ignore_time_scale(true)
	var tip := sword_pivot.to_global(Vector3(0.38, 0.0, -1.3))
	if perfect:
		# 刀向外一撥（70ms）再回到架刀位
		_guard_tw.tween_property(sword_pivot, "rotation_degrees", Vector3(-70.0, -85.0, 30.0), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_guard_tw.tween_property(sword_pivot, "rotation_degrees", GUARD_ROT, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_burst_spark(tip, -dir, 2.0)
		Sfx.play(_sfx_deflect)
		Sfx.play(sfx_swing)
		velocity.x = dir.x * 1.0
		velocity.z = dir.z * 1.0
		Feel.hitstop(1.6)
		Feel.shake(1.0)
		Feel.kick(-dir, 0.45)
		Feel.flash(Color(1.0, 0.97, 0.85, 0.3), 0.14)
		if src and src.has_method("deflected"):
			src.deflected(-dir)
		parried.emit()
	else:
		# 刀被震開（50ms）再回位
		_guard_tw.tween_property(sword_pivot, "rotation_degrees", Vector3(-70.0, 58.0, -20.0), 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_guard_tw.tween_property(sword_pivot, "rotation_degrees", GUARD_ROT, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_burst_spark(tip, -dir, 0.9)
		Sfx.play(_sfx_block)
		velocity.x = dir.x * 4.0
		velocity.z = dir.z * 4.0
		Feel.hitstop(0.45)
		Feel.shake(0.45)
		Feel.kick(dir, 0.2)


func _build_spark() -> void:
	_spark = CPUParticles3D.new()
	_spark.top_level = true
	_spark.emitting = false
	_spark.one_shot = true
	_spark.explosiveness = 1.0
	_spark.amount = 36
	_spark.lifetime = 0.32
	_spark.spread = 55.0
	_spark.gravity = Vector3(0.0, -18.0, 0.0)
	_spark.initial_velocity_min = 5.0
	_spark.initial_velocity_max = 11.0
	_spark.scale_amount_min = 0.4
	_spark.scale_amount_max = 1.0
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.05)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.95, 0.7)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = m
	_spark.mesh = q
	add_child(_spark)
	Feel.time_scale_changed.connect(func(ts: float) -> void:
		_spark.speed_scale = 1.0 / maxf(ts, 0.01))


func _burst_spark(pos: Vector3, dir: Vector3, power: float) -> void:
	_spark.global_position = pos
	_spark.direction = (dir + Vector3(0.0, 0.8, 0.0)).normalized()
	_spark.initial_velocity_max = 6.0 * power + 4.0
	_spark.scale_amount_max = 0.6 * power + 0.3
	_spark.restart()


func _tick_hurt(delta: float) -> void:
	_hurt_t += delta
	velocity.x = move_toward(velocity.x, 0.0, 24.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 24.0 * delta)
	body.rotation.x = lerpf(body.rotation.x, 0.3, 1.0 - exp(-20.0 * delta))
	sword_pivot.rotation_degrees = sword_pivot.rotation_degrees.lerp(Vector3.ZERO, 1.0 - exp(-10.0 * delta))
	if _hurt_t > 0.4:
		state = _after_action()


## 刀光：扇形網格，尾端透明、刀頭亮；第三段下劈時整片前傾。
func _build_trail(from_deg: float, to_deg: float, tilt: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 18
	var r_in := 0.45
	var r_out := 1.95
	var h := 1.15
	var a0 := deg_to_rad(from_deg)
	var a1 := deg_to_rad(to_deg)
	for i in range(segs):
		var t0 := float(i) / segs
		var t1 := float(i + 1) / segs
		var ang0 := lerpf(a0, a1, t0)
		var ang1 := lerpf(a0, a1, t1)
		var c_out0 := Color(1.0, 0.97, 0.9, 0.9 * t0)
		var c_out1 := Color(1.0, 0.97, 0.9, 0.9 * t1)
		var c_in0 := Color(1.0, 0.85, 0.6, 0.15 * t0)
		var c_in1 := Color(1.0, 0.85, 0.6, 0.15 * t1)
		var d0 := Vector3(-sin(ang0), 0.0, -cos(ang0))
		var d1 := Vector3(-sin(ang1), 0.0, -cos(ang1))
		var up := Vector3(0.0, h, 0.0)
		var p_in0 := d0 * r_in + up
		var p_in1 := d1 * r_in + up
		var p_out0 := d0 * r_out + up
		var p_out1 := d1 * r_out + up
		st.set_color(c_in0)
		st.add_vertex(p_in0)
		st.set_color(c_out0)
		st.add_vertex(p_out0)
		st.set_color(c_out1)
		st.add_vertex(p_out1)
		st.set_color(c_in0)
		st.add_vertex(p_in0)
		st.set_color(c_out1)
		st.add_vertex(p_out1)
		st.set_color(c_in1)
		st.add_vertex(p_in1)
	trail.mesh = st.commit()
	trail.rotation_degrees = Vector3(-tilt * 0.45, 0.0, 0.0)
	trail.position = Vector3.ZERO
	_set_trail_alpha(Feel.get_p("trail_alpha"))


func _set_trail_alpha(a: float) -> void:
	_trail_mat.albedo_color.a = clampf(a, 0.0, 1.0)


## 開場預熱：刀光網格與材質先畫幾幀（幾乎透明）
func warmup() -> void:
	_build_trail(95.0, -75.0, 0.0)
	_set_trail_alpha(0.02)
	trail.visible = true
	_burst_spark(global_position + Vector3(0.0, 1.2, 0.0), Vector3.UP, 0.1)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if state != State.ATTACK:
		trail.visible = false
