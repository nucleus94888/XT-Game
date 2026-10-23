extends CharacterBody3D
class_name Enemy
## 第一關敵人：足輕（長槍）、弓兵（遠距）、武士（會架刀）、武將（暗殺目標）。
## 感知：視野錐 + 視線遮蔽 + 聽覺；警覺度累積到滿才進入戰鬥，並呼叫附近同伴。
## 未察覺時從背後攻擊 = 暗殺（一擊必殺、無聲）。
## 戰鬥：預告「！」→ 出手（可閃、可格擋、可彈反）；體幹累積滿 → 崩壞 → 忍殺。
## 整個敵人都用程式建構，關卡只要 new() + 設定 kind / patrol。

signal died(enemy: Enemy, stealth: bool)
signal alerted(enemy: Enemy)

enum Kind { ASHIGARU, ARCHER, SAMURAI, TARGET }
enum State { IDLE, PATROL, SUSPICIOUS, ALERT, ATTACK, STAGGER, BROKEN, DEAD }

const SPEC := {
	Kind.ASHIGARU: {"name": "足輕", "hp": 40, "posture": 60.0, "speed": 4.0, "color": Color(0.36, 0.42, 0.55), "reach": 2.1, "dmg": 12, "windup": 0.45, "strike": 0.14, "cd": 1.5, "weapon": "spear", "view": 7.0},
	Kind.ARCHER: {"name": "弓兵", "hp": 30, "posture": 50.0, "speed": 3.6, "color": Color(0.3, 0.5, 0.35), "reach": 9.5, "dmg": 10, "windup": 0.75, "strike": 0.1, "cd": 2.3, "weapon": "bow", "view": 9.0},
	Kind.SAMURAI: {"name": "武士", "hp": 90, "posture": 100.0, "speed": 4.5, "color": Color(0.6, 0.16, 0.14), "reach": 2.3, "dmg": 18, "windup": 0.5, "strike": 0.14, "cd": 1.8, "weapon": "katana", "view": 8.0},
	Kind.TARGET: {"name": "武將", "hp": 120, "posture": 110.0, "speed": 4.3, "color": Color(0.78, 0.62, 0.2), "reach": 2.4, "dmg": 22, "windup": 0.55, "strike": 0.14, "cd": 1.6, "weapon": "katana", "view": 8.0},
}
const VIEW_COS := 0.42
const SHOUT_RANGE := 10.0

var kind: Kind = Kind.ASHIGARU
var patrol: Array = []
var face_dir := Vector3.FORWARD

var spec: Dictionary
var hp := 0
var posture := 0.0
var state := State.IDLE
var alerted_once := false
## 體力：出手要花，耗盡會喘氣停手（破綻）
var stamina := 100.0
const STAM_ATTACK := 25.0
var stam_fill: MeshInstance3D

var _player: Node3D
var _facing := 0.0
var _detect := 0.0
var _lost_t := 0.0
var _patrol_i := 0
var _wait_t := 0.0
var _attack_cd := 1.0
var _atk_t := 0.0
var _struck := false
var _stun_t := 0.0
var _guard := false
var _kb := Vector3.ZERO
var _flash_t := 0.0
var _posture_t := 0.0
var _nav_t := 0.0
var _hurtbox: Area3D
var _strike_area: Area3D
var _nav: NavigationAgent3D
var _mats: Array[StandardMaterial3D] = []
var _react_tw: Tween
var _sfx_swing: AudioStreamPlayer
var _sfx_hit: AudioStreamPlayer
var _sfx_block: AudioStreamPlayer
var _sfx_die: AudioStreamPlayer

var visual: Node3D
var body: MeshInstance3D
var head: MeshInstance3D
var weapon: MeshInstance3D
var mark: Label3D
var bar: Node3D
var bar_fill: MeshInstance3D
var bar_mat: StandardMaterial3D
var particles: CPUParticles3D


func _ready() -> void:
	spec = SPEC[kind]
	hp = int(spec.hp)
	collision_layer = 2
	collision_mask = 3
	add_to_group("enemies")
	_player = get_tree().get_first_node_in_group("player")
	_build()
	if patrol.size() > 0:
		state = State.PATROL
		_facing = _yaw_to(patrol[0] - global_position)
	else:
		state = State.IDLE
		_facing = _yaw_to(face_dir)
	visual.rotation.y = _facing
	_sfx_swing = Sfx.player(self, "swing", -9.0, 0.85)
	_sfx_hit = Sfx.player(self, "hit", -4.0)
	_sfx_block = Sfx.player(self, "block", -7.0, 0.9)
	_sfx_die = Sfx.player(self, "hurt", -3.0, 0.8)
	Feel.time_scale_changed.connect(func(ts: float) -> void:
		particles.speed_scale = 1.0 / maxf(ts, 0.01))


func _yaw_to(v: Vector3) -> float:
	if v.length() < 0.001:
		return _facing
	return atan2(-v.x, -v.z)


func _forward() -> Vector3:
	return Vector3(-sin(_facing), 0.0, -cos(_facing))


func _mesh(m: Mesh, color: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 1)
	mat.emission_energy_multiplier = 0.0
	mi.material_override = mat
	mi.position = pos
	_mats.append(mat)
	return mi


func _build() -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.4
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)

	_hurtbox = Area3D.new()
	_hurtbox.collision_layer = 4
	_hurtbox.collision_mask = 0
	_hurtbox.monitoring = false
	var hs := CollisionShape3D.new()
	var hcap := CapsuleShape3D.new()
	hcap.radius = 0.55
	hcap.height = 1.9
	hs.shape = hcap
	hs.position = Vector3(0, 1.0, 0)
	_hurtbox.add_child(hs)
	add_child(_hurtbox)

	visual = Node3D.new()
	add_child(visual)

	_strike_area = Area3D.new()
	_strike_area.collision_layer = 0
	_strike_area.collision_mask = 8
	_strike_area.monitorable = false
	var ss := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.15
	ss.shape = sph
	ss.position = Vector3(0, 1.0, -1.35)
	_strike_area.add_child(ss)
	visual.add_child(_strike_area)

	var bm := CapsuleMesh.new()
	bm.radius = 0.36
	bm.height = 1.35
	body = _mesh(bm, spec.color, Vector3(0, 0.85, 0))
	visual.add_child(body)
	var hm := SphereMesh.new()
	hm.radius = 0.25
	hm.height = 0.5
	head = _mesh(hm, Color(0.82, 0.68, 0.58), Vector3(0, 1.68, 0))
	visual.add_child(head)
	# 頭盔/頭巾顏色帶：讓種類一眼可辨
	var band := BoxMesh.new()
	band.size = Vector3(0.56, 0.1, 0.56)
	visual.add_child(_mesh(band, spec.color.darkened(0.3), Vector3(0, 1.78, 0)))

	var wm := BoxMesh.new()
	var wcolor := Color(0.85, 0.88, 0.95)
	var wpos := Vector3(0.38, 1.15, -0.65)
	match spec.weapon:
		"spear":
			wm.size = Vector3(0.06, 0.06, 2.3)
			wcolor = Color(0.5, 0.35, 0.2)
			wpos = Vector3(0.36, 1.0, -0.7)
		"bow":
			wm.size = Vector3(0.05, 1.3, 0.05)
			wcolor = Color(0.45, 0.3, 0.18)
			wpos = Vector3(0.36, 1.1, -0.35)
		_:
			wm.size = Vector3(0.07, 0.04, 1.3)
	weapon = _mesh(wm, wcolor, wpos)
	visual.add_child(weapon)

	mark = Label3D.new()
	mark.text = "？"
	mark.font = Fx.ui_font
	mark.font_size = 100
	mark.pixel_size = 0.012
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.no_depth_test = true
	mark.outline_size = 14
	mark.modulate = Color(1.0, 0.85, 0.3)
	mark.position = Vector3(0, 2.75, 0)
	mark.visible = false
	add_child(mark)

	# 頭上條：察覺中顯示白色警覺度，戰鬥中顯示體幹
	bar = Node3D.new()
	bar.position = Vector3(0, 2.45, 0)
	add_child(bar)
	var bg := MeshInstance3D.new()
	var qbg := QuadMesh.new()
	qbg.size = Vector2(1.3, 0.12)
	var mbg := StandardMaterial3D.new()
	mbg.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mbg.albedo_color = Color(0.05, 0.05, 0.06, 0.8)
	mbg.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mbg.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mbg.no_depth_test = true
	qbg.material = mbg
	bg.mesh = qbg
	bar.add_child(bg)
	bar_fill = MeshInstance3D.new()
	var qf := QuadMesh.new()
	qf.size = Vector2(1.24, 0.08)
	bar_mat = StandardMaterial3D.new()
	bar_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bar_mat.albedo_color = Color(1, 1, 1)
	bar_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bar_mat.no_depth_test = true
	bar_mat.render_priority = 1
	qf.material = bar_mat
	bar_fill.mesh = qf
	bar_fill.position = Vector3(0, 0, 0.01)
	bar.add_child(bar_fill)
	# 體力細條（綠）在體幹條下方
	stam_fill = MeshInstance3D.new()
	var qs := QuadMesh.new()
	qs.size = Vector2(1.24, 0.045)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(0.35, 0.85, 0.4)
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sm.no_depth_test = true
	sm.render_priority = 1
	qs.material = sm
	stam_fill.mesh = qs
	stam_fill.position = Vector3(0, -0.1, 0.01)
	bar.add_child(stam_fill)
	bar.visible = false

	particles = CPUParticles3D.new()
	particles.top_level = true
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 30
	particles.lifetime = 0.4
	particles.spread = 65.0
	particles.gravity = Vector3(0, -14, 0)
	particles.initial_velocity_min = 4.0
	particles.initial_velocity_max = 8.0
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.1
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.14)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.albedo_color = Color(0.9, 0.2, 0.15)
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = pm
	particles.mesh = q
	add_child(particles)

	_nav = NavigationAgent3D.new()
	_nav.path_desired_distance = 0.7
	_nav.target_desired_distance = 1.0
	_nav.avoidance_enabled = false
	add_child(_nav)


# ---------------------------------------------------------------- 主迴圈

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_attack_cd -= delta
	_stun_t -= delta
	_posture_t -= delta
	if state != State.ATTACK:
		stamina = minf(stamina + 18.0 * delta, 100.0)
	if _posture_t <= 0.0 and state != State.BROKEN and posture > 0.0:
		posture = maxf(posture - 10.0 * delta, 0.0)
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_set_emission(Color(1, 1, 1), 0.0)
	_perceive(delta)
	match state:
		State.IDLE:
			_stop()
			_facing = lerp_angle(_facing, _yaw_to(face_dir), 1.0 - exp(-3.0 * delta))
		State.PATROL:
			_do_patrol(delta)
		State.SUSPICIOUS:
			_stop()
		State.ALERT:
			_do_alert(delta)
		State.ATTACK:
			_do_attack(delta)
		State.STAGGER, State.BROKEN:
			_stop()
			if _stun_t <= 0.0:
				state = State.ALERT
				if posture >= float(spec.posture):
					posture = float(spec.posture) * 0.35
	velocity.x += _kb.x
	velocity.z += _kb.z
	_kb = _kb.move_toward(Vector3.ZERO, 14.0 * delta)
	velocity.y = -5.0 if not is_on_floor() else 0.0
	move_and_slide()
	_update_visual(delta)


func _stop() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func _move_to(p: Vector3, speed: float, delta: float) -> void:
	_nav_t -= delta
	if _nav_t <= 0.0 or _nav.target_position.distance_to(p) > 0.8:
		_nav.target_position = p
		_nav_t = 0.25
	var next := _nav.get_next_path_position()
	var d := next - global_position
	d.y = 0.0
	if d.length() < 0.05:
		d = p - global_position
		d.y = 0.0
	if d.length() > 0.05:
		d = d.normalized()
		velocity.x = d.x * speed
		velocity.z = d.z * speed
		_facing = _yaw_to(d)
	else:
		_stop()


func _face_player(delta: float, rate: float = 12.0) -> void:
	if _player:
		var to := _player.global_position - global_position
		to.y = 0.0
		_facing = lerp_angle(_facing, _yaw_to(to), 1.0 - exp(-rate * delta))


# ---------------------------------------------------------------- 感知

func _los() -> bool:
	if _player == null:
		return false
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 1.5, 0)
	var to := _player.global_position + Vector3(0, 1.0, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	q.exclude = [get_rid(), _player.get_rid()]
	return space.intersect_ray(q).is_empty()


func _perceive(delta: float) -> void:
	if _player == null or state in [State.ATTACK, State.STAGGER, State.BROKEN]:
		return
	var to := _player.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	if state == State.ALERT:
		if dist < float(spec.view) * 1.6 and _los():
			_lost_t = 0.0
		else:
			_lost_t += delta
			if _lost_t > 7.0:
				_lost_t = 0.0
				_detect = 0.3
				_guard = false
				state = State.PATROL if patrol.size() > 0 else State.IDLE
		return
	var sees := false
	if dist < float(spec.view):
		if _forward().dot(to.normalized()) > VIEW_COS or dist < 1.6:
			sees = _los()
	if sees:
		_detect = minf(_detect + delta * (2.4 if dist < 3.5 else 1.1), 1.0)
		_facing = lerp_angle(_facing, _yaw_to(to), 1.0 - exp(-6.0 * delta))
		if _detect >= 1.0:
			_go_alert()
		elif state != State.SUSPICIOUS:
			state = State.SUSPICIOUS
	else:
		_detect = maxf(_detect - delta * 0.5, 0.0)
		if state == State.SUSPICIOUS and _detect <= 0.0:
			state = State.PATROL if patrol.size() > 0 else State.IDLE


func _go_alert() -> void:
	if state in [State.ALERT, State.ATTACK, State.DEAD, State.STAGGER, State.BROKEN]:
		return
	state = State.ALERT
	_detect = 1.0
	alerted_once = true
	_lost_t = 0.0
	_attack_cd = maxf(_attack_cd, 0.5)
	_show_mark("！", Color(1.0, 0.25, 0.2), 0.9)
	alerted.emit(self)
	get_tree().call_group("enemies", "hear_shout", global_position)


func hear_shout(pos: Vector3) -> void:
	if state in [State.IDLE, State.PATROL, State.SUSPICIOUS] and global_position.distance_to(pos) < SHOUT_RANGE:
		_go_alert()


func hear_noise(pos: Vector3, radius: float) -> void:
	if state in [State.IDLE, State.PATROL] and global_position.distance_to(pos) < radius:
		_detect = maxf(_detect, 0.55)
		state = State.SUSPICIOUS
		var to := pos - global_position
		to.y = 0.0
		_facing = _yaw_to(to)


func _show_mark(text: String, color: Color, dur: float) -> void:
	mark.text = text
	mark.modulate = color
	mark.visible = true
	mark.scale = Vector3.ONE * 1.5
	var tw := mark.create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(mark, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if dur > 0.0:
		tw.tween_interval(dur)
		tw.tween_callback(func() -> void:
			if mark.text == text:
				mark.visible = false)


# ---------------------------------------------------------------- 行為

func _do_patrol(delta: float) -> void:
	if patrol.is_empty():
		state = State.IDLE
		return
	if _wait_t > 0.0:
		_wait_t -= delta
		_stop()
		return
	var p: Vector3 = patrol[_patrol_i]
	var d := p - global_position
	d.y = 0.0
	if d.length() < 0.6:
		_patrol_i = (_patrol_i + 1) % patrol.size()
		_wait_t = randf_range(0.8, 1.8)
		_stop()
		return
	_move_to(p, float(spec.speed) * 0.55, delta)


func _do_alert(delta: float) -> void:
	if _player == null:
		return
	var to := _player.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var speed: float = spec.speed
	if kind == Kind.ARCHER:
		if dist < 4.5:
			_move_to(global_position - to.normalized() * 5.0, speed, delta)
		elif dist > 9.0:
			_move_to(_player.global_position, speed, delta)
		else:
			_stop()
		_face_player(delta)
		if _attack_cd <= 0.0 and dist > 2.0 and dist < float(spec.reach) and _los():
			_try_attack()
	else:
		if dist > float(spec.reach) * 0.85:
			_move_to(_player.global_position, speed, delta)
		else:
			_stop()
			_face_player(delta)
		_guard = (kind == Kind.SAMURAI or kind == Kind.TARGET) and dist < 4.5 and _attack_cd > 0.35
		if _attack_cd <= 0.0 and dist < float(spec.reach) * 1.05 and _forward().dot(to.normalized()) > 0.5:
			_try_attack()


## 體力不夠就喘氣停手 1.1 秒（頭上「喘」），這是玩家的破綻機會
func _try_attack() -> void:
	if stamina < STAM_ATTACK:
		state = State.STAGGER
		_stun_t = 1.1
		_attack_cd = 1.0
		_guard = false
		_show_mark("喘", Color(0.75, 0.85, 1.0), 1.0)
		return
	stamina -= STAM_ATTACK
	_start_attack()


func _start_attack() -> void:
	state = State.ATTACK
	_atk_t = 0.0
	_struck = false
	_guard = false
	_stop()
	_set_emission(Color(1.0, 0.2, 0.15), 0.8)
	_flash_t = 0.0


func _do_attack(delta: float) -> void:
	_atk_t += delta
	var w: float = spec.windup
	var s: float = spec.strike
	if _atk_t < w:
		_face_player(delta, 6.0)
		var k := _atk_t / w
		var pulse := 0.5 + 0.5 * sin(_atk_t * 35.0)
		_set_emission(Color(1.0, 0.2, 0.15), 0.4 + 0.8 * pulse)
		if kind == Kind.ARCHER:
			weapon.rotation.z = lerpf(0.0, -0.4, k)
		else:
			weapon.rotation.x = lerpf(0.0, 0.9, k)
			weapon.rotation.y = lerpf(0.0, 0.8, k)
	elif not _struck:
		_struck = true
		_set_emission(Color(1, 1, 1), 0.0)
		if kind == Kind.ARCHER:
			_shoot()
		else:
			_strike()
	elif _atk_t < w + s + 0.4:
		var k := (_atk_t - w) / (s + 0.4)
		if kind != Kind.ARCHER:
			weapon.rotation.x = lerpf(-0.8, 0.0, k)
			weapon.rotation.y = lerpf(-1.4, 0.0, k)
		else:
			weapon.rotation.z = lerpf(0.3, 0.0, k)
	else:
		weapon.rotation = Vector3.ZERO
		state = State.ALERT
		_attack_cd = float(spec.cd) * randf_range(0.85, 1.25)


func _strike() -> void:
	Sfx.play(_sfx_swing)
	weapon.rotation.x = -0.8
	weapon.rotation.y = -1.4
	# 前衝半步
	var f := _forward()
	_kb = f * 3.0
	for a in _strike_area.get_overlapping_areas():
		var t := a.get_parent()
		if t and t != self and t.is_in_group("player") and t.has_method("take_hit"):
			var dir: Vector3 = (t as Node3D).global_position - global_position
			dir.y = 0.0
			dir = dir.normalized()
			t.take_hit({"dmg": spec.dmg, "dir": dir, "kb": 5.0, "heavy": false, "pos": t.global_position + Vector3(0, 1.2, 0), "src": self})


func _shoot() -> void:
	Sfx.play(_sfx_swing)
	var arrow := Arrow.new()
	arrow.dmg = int(spec.dmg)
	arrow.src = self
	get_tree().current_scene.add_child(arrow)
	var from := global_position + Vector3(0, 1.3, 0)
	var to := (_player.global_position + Vector3(0, 1.0, 0)) - from
	arrow.launch(from, to)


# ---------------------------------------------------------------- 受擊

func can_be_assassinated(by: Node3D) -> bool:
	if state in [State.DEAD, State.ALERT, State.ATTACK, State.STAGGER, State.BROKEN]:
		return false
	var to := by.global_position - global_position
	to.y = 0.0
	return _forward().dot(to.normalized()) < -0.15


func assassinate(info: Dictionary) -> void:
	if state == State.DEAD:
		return
	_hit_dir_set(info)
	hp = 0
	Feel.hitstop(2.0)
	Feel.shake(0.7)
	Feel.flash(Color(0.0, 0.0, 0.0, 0.5), 0.5)
	Fx.damage_number(info.pos, int(spec.hp), true)
	particles.global_position = info.pos
	particles.restart()
	_die(true)


func _hit_dir_set(info: Dictionary) -> Vector3:
	var dir := (info.dir as Vector3)
	dir.y = 0.0
	return dir.normalized()


func take_hit(info: Dictionary) -> void:
	if state == State.DEAD:
		return
	var dir := _hit_dir_set(info)
	var heavy: bool = info.get("heavy", false)
	if state == State.BROKEN:
		_execute(info, dir)
		return
	# 武士架刀：正面的輕攻擊被擋下（體幹仍會累積，重擊能破）
	if _guard and not heavy and _forward().dot(-dir) > 0.3:
		Sfx.play(_sfx_block)
		stamina = maxf(stamina - 10.0, 0.0)
		if stamina <= 0.0:
			_guard = false
			state = State.STAGGER
			_stun_t = 0.6
		posture += 12.0
		_posture_t = 1.5
		_kb = dir * 1.5
		weapon.rotation.y = 0.9
		var tw := weapon.create_tween()
		tw.set_ignore_time_scale(true)
		tw.tween_property(weapon, "rotation:y", 0.0, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		Feel.hitstop(0.5)
		if posture >= float(spec.posture):
			_break_posture()
		return
	if not alerted_once or state in [State.IDLE, State.PATROL, State.SUSPICIOUS]:
		_go_alert()
	hp -= int(info.dmg)
	posture += 16.0 if heavy else 8.0
	_posture_t = 1.5
	_kb = dir * float(info.kb) * 0.7
	_guard = false
	_flash_t = Feel.sec("hit_flash_ms")
	_set_emission(Color(1, 1, 1), 2.5)
	Sfx.play(_sfx_hit)
	particles.global_position = info.pos
	particles.direction = dir + Vector3(0, 0.6, 0)
	particles.restart()
	Fx.damage_number(info.pos, int(info.dmg), heavy)
	_react(dir, heavy)
	if hp <= 0:
		_die(false)
	elif posture >= float(spec.posture):
		_break_posture()
	elif heavy and state != State.ATTACK:
		state = State.STAGGER
		_stun_t = 0.45


func deflected(push_dir: Vector3) -> void:
	if state == State.DEAD:
		return
	var dir := push_dir
	dir.y = 0.0
	dir = dir.normalized()
	state = State.STAGGER
	_stun_t = 0.75
	_attack_cd = float(spec.cd)
	mark.visible = false
	weapon.rotation = Vector3.ZERO
	_kb = dir * 3.5
	posture += 35.0
	_posture_t = 1.5
	_flash_t = 0.18
	_set_emission(Color(1, 1, 1), 2.0)
	_react(dir, true)
	if posture >= float(spec.posture):
		_break_posture()


func _react(dir: Vector3, heavy: bool) -> void:
	if _react_tw and _react_tw.is_valid():
		_react_tw.kill()
	visual.scale = Vector3(1.25, 0.8, 1.25) if heavy else Vector3(1.12, 0.9, 1.12)
	visual.rotation.x = dir.z * (0.45 if heavy else 0.25)
	visual.rotation.z = -dir.x * (0.45 if heavy else 0.25)
	head.rotation = Vector3(dir.z * 0.6, 0.0, -dir.x * 0.6)
	_react_tw = create_tween()
	_react_tw.set_ignore_time_scale(true)
	_react_tw.set_parallel(true)
	_react_tw.tween_property(visual, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_react_tw.tween_property(visual, "rotation:x", 0.0, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_react_tw.tween_property(visual, "rotation:z", 0.0, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_react_tw.tween_property(head, "rotation", Vector3.ZERO, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _break_posture() -> void:
	state = State.BROKEN
	_stun_t = 2.5
	posture = float(spec.posture)
	_guard = false
	mark.visible = false
	weapon.rotation = Vector3.ZERO
	_show_mark("崩", Color(1.0, 0.55, 0.2), 2.3)
	Feel.shake(0.5)
	if _react_tw and _react_tw.is_valid():
		_react_tw.kill()
	visual.scale = Vector3(1.2, 0.85, 1.2)
	head.rotation = Vector3(0.0, 0.0, 0.8)
	_react_tw = create_tween()
	_react_tw.set_ignore_time_scale(true)
	_react_tw.set_parallel(true)
	_react_tw.tween_property(visual, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_react_tw.tween_property(head, "rotation", Vector3.ZERO, 2.0).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _execute(info: Dictionary, dir: Vector3) -> void:
	hp = 0
	Fx.damage_number(info.pos, int(spec.hp), true)
	Feel.hitstop(2.4)
	Feel.shake(1.5)
	Feel.kick(dir, 0.5)
	Feel.flash(Color(0.75, 0.05, 0.05, 0.45), 0.5)
	particles.global_position = info.pos
	particles.direction = dir + Vector3(0, 0.8, 0)
	particles.restart()
	_die(false, true)


func _die(stealth: bool, execution: bool = false) -> void:
	state = State.DEAD
	_hurtbox.monitorable = false
	collision_layer = 0
	collision_mask = 1
	mark.visible = false
	bar.visible = false
	_set_emission(Color(1, 1, 1), 0.0)
	weapon.rotation = Vector3.ZERO
	if _react_tw and _react_tw.is_valid():
		_react_tw.kill()
	visual.scale = Vector3.ONE
	if not stealth:
		Sfx.play(_sfx_die)
		get_tree().call_group("enemies", "hear_noise", global_position, 7.0)
	var fall := Vector3(_forward().z * -1.4, 0.0, _forward().x * 1.4) if stealth else Vector3(_kb.normalized().z * 1.5, 0.0, -_kb.normalized().x * 1.5)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(visual, "rotation", fall, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(2.5)
	tw.chain().tween_property(visual, "position:y", -1.6, 0.8)
	tw.chain().tween_callback(queue_free)
	died.emit(self, stealth)


# ---------------------------------------------------------------- 視覺

func _set_emission(color: Color, energy: float) -> void:
	for m in _mats:
		m.emission = color
		m.emission_energy_multiplier = energy


func _update_visual(delta: float) -> void:
	visual.rotation.y = lerp_angle(visual.rotation.y, _facing, 1.0 - exp(-14.0 * delta))
	# 架刀姿勢
	if state in [State.ALERT] and kind != Kind.ARCHER:
		var target_rot := Vector3(-1.3, 0.3, -0.2) if _guard else Vector3.ZERO
		weapon.rotation = weapon.rotation.lerp(target_rot, 1.0 - exp(-18.0 * delta))
	# 頭上條
	var ratio := 0.0
	var color := Color(1, 1, 1)
	match state:
		State.SUSPICIOUS:
			ratio = _detect
			color = Color(1.0, 1.0, 1.0)
		State.ALERT, State.ATTACK, State.STAGGER, State.BROKEN:
			ratio = posture / float(spec.posture)
			color = Color(1.0, 0.2, 0.15) if state == State.BROKEN else Color(1.0, 0.75 - 0.5 * ratio, 0.2)
		_:
			ratio = _detect
	bar.visible = ratio > 0.01 or state in [State.ALERT, State.ATTACK, State.STAGGER, State.BROKEN]
	bar_fill.scale.x = maxf(ratio, 0.001)
	bar_fill.position.x = -0.62 * (1.0 - ratio)
	bar_fill.visible = ratio > 0.001
	bar_mat.albedo_color = color
	var sr := stamina / 100.0
	stam_fill.visible = state in [State.ALERT, State.ATTACK, State.STAGGER, State.BROKEN]
	stam_fill.scale.x = maxf(sr, 0.001)
	stam_fill.position.x = -0.62 * (1.0 - sr)
	if state == State.SUSPICIOUS and not mark.visible:
		_show_mark("？", Color(1.0, 0.85, 0.3), 0.0)
	elif state != State.SUSPICIOUS and mark.text == "？":
		mark.visible = false
