extends CharacterBody3D
class_name Enemy
## 第一關敵人：足輕（長槍）、弓兵（遠距）、武士（會架刀）、武將（暗殺目標）。
## 感知：視野錐 + 視線遮蔽 + 聽覺；警覺度累積到滿才進入戰鬥，並呼叫附近同伴。
## 未察覺時從背後攻擊 = 暗殺（一擊必殺、無聲）。
## 戰鬥：預告「！」→ 出手（可閃、可格擋、可彈反）；體幹累積滿 → 崩壞 → 忍殺。
## 整個敵人都用程式建構，關卡只要 new() + 設定 kind / patrol。

signal died(enemy: Enemy, stealth: bool)
signal alerted(enemy: Enemy)
## 大將逃到路線終點（故事用）
signal escaped(enemy: Enemy)
signal flee_started(enemy: Enemy)

enum Kind { ASHIGARU, ARCHER, SAMURAI, TARGET, LORD }
enum State { IDLE, PATROL, SUSPICIOUS, ALERT, ATTACK, STAGGER, BROKEN, DEAD, SEARCH, FLEE }

## speed：走路基準（巡邏 ×0.55、搜索 ×0.75、起疑逼近 ×0.5）；run：追擊／逃跑用的跑速。
## 玩家走速 5.4、閃步 17。追擊一定要快過走速，被發現才等於「必須閃步或戰鬥」（第七次議會）。
const SPEC := {
	Kind.ASHIGARU: {"name": "足輕", "hp": 40, "posture": 60.0, "speed": 4.0, "run": 6.0, "color": Color(0.36, 0.42, 0.55), "reach": 2.1, "dmg": 12, "windup": 0.45, "strike": 0.14, "cd": 1.5, "weapon": "spear", "view": 7.0},
	Kind.ARCHER: {"name": "弓兵", "hp": 30, "posture": 50.0, "speed": 3.6, "run": 4.6, "color": Color(0.3, 0.5, 0.35), "reach": 9.5, "dmg": 10, "windup": 0.75, "strike": 0.1, "cd": 2.3, "weapon": "bow", "view": 9.0},
	Kind.SAMURAI: {"name": "武士", "hp": 90, "posture": 100.0, "speed": 4.5, "run": 6.3, "color": Color(0.6, 0.16, 0.14), "reach": 2.3, "dmg": 18, "windup": 0.5, "strike": 0.14, "cd": 1.4, "weapon": "katana", "view": 8.0},
	Kind.TARGET: {"name": "武將", "hp": 120, "posture": 110.0, "speed": 4.3, "run": 6.1, "color": Color(0.78, 0.62, 0.2), "reach": 2.4, "dmg": 22, "windup": 0.55, "strike": 0.14, "cd": 1.3, "weapon": "katana", "view": 8.0},
	# 大將：不打架，一察覺就逃（故事用，打不死）
	Kind.LORD: {"name": "大將", "hp": 9999, "posture": 9999.0, "speed": 4.5, "run": 6.5, "color": Color(0.45, 0.12, 0.5), "reach": 0.0, "dmg": 0, "windup": 1.0, "strike": 0.1, "cd": 99.0, "weapon": "katana", "view": 9.0},
}
## 起疑：先站住一拍盯著（可讀），再慢走過去（壓力）
## 起疑當下就轉頭朝你走（第十次議會：原地站著讓敵人顯得瞎）
const SUSPICIOUS_HOLD := 0.0
## 移動加速度（公尺/秒²）：0 → 6 公尺/秒約 0.45 秒
const MOVE_ACCEL := 13.0
const VIEW_COS := 0.42
const SHOUT_RANGE := 10.0

var kind: Kind = Kind.ASHIGARU
var patrol: Array = []
var face_dir := Vector3.FORWARD
## 大將逃跑路線（最後一點到達就消失）
var flee_route: Array = []
var _flee_i := 0

var spec: Dictionary
var hp := 0
## 血條分母：取生成後看過的最高 hp（關卡可能在生成後調高 hp）
var _max_hp := 1
var posture := 0.0
var state := State.IDLE
var alerted_once := false
## 體力（不可見）：連續出手 6 刀會喘 0.8 秒（破綻）；武將不喘。4 秒沒出手就恢復
const SWINGS_BEFORE_PANT := 6
var _swings := 0
var _swing_rest_t := 0.0
## 連續格擋玩家幾刀（武士／武將格擋第三刀必反擊）
var _blocked_streak := 0
var _blocked_streak_t := 0.0
## 連續被玩家打中幾下（被連打 2 下，下一刀變成不可格擋的「危」技）
var _hit_streak := 0
var _hit_streak_t := 0.0
var _perilous := false
var _counter := false
## 被鉤繩拉過後 6 秒內不能再被拉
var _hook_immune_t := 0.0

var _player: Node3D
var _facing := 0.0
var _detect := 0.0
var _lost_t := 0.0
## 搜索：最後看到／聽到的位置
var _last_known := Vector3.ZERO
var _search_t := 0.0
var _search_look := 0.0
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
var _sfx_hm: AudioStreamPlayer
var _sfx_shout: AudioStreamPlayer
var _sfx_step: AudioStreamPlayer
## 起疑：站住計時、要走去查看的點
var _sus_t := 0.0
var _sus_pos := Vector3.ZERO
## 程序式走姿：前傾量（0～1）、步伐相位、下一步腳步聲剩餘距離
var _lean := 0.0
var _stride := 0.0
var _step_left := 0.6
var _blink_t := 2.0
## 喘氣（取代「喘」字）、被壓頂後抬頭警覺（6 秒內再下劈會側步）、血條受擊閃光
var _pant_t := 0.0
var _heads_up_t := 0.0
var _bar_flash_t := 0.0
var _bar_flash_color := Color(1, 1, 1)
var _body_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D

var visual: Node3D
var body: MeshInstance3D
var head: MeshInstance3D
var eye_l: MeshInstance3D
var eye_r: MeshInstance3D
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
	_sfx_hm = Sfx.player(self, "hm", -6.0, randf_range(0.9, 1.1), 1.04)
	_sfx_shout = Sfx.player(self, "shout", -3.0, randf_range(0.92, 1.08), 1.04)
	_sfx_step = Sfx.player(self, "step", -18.0, 1.0, 1.15)
	_blink_t = randf_range(1.5, 4.0)
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
	_body_mat = body.material_override
	visual.add_child(body)
	var hm := SphereMesh.new()
	hm.radius = 0.25
	hm.height = 0.5
	head = _mesh(hm, Color(0.82, 0.68, 0.58), Vector3(0, 1.68, 0))
	visual.add_child(head)
	# 頭盔/頭巾顏色帶：讓種類一眼可辨（掛在頭下，跟著頭晃）
	var band := BoxMesh.new()
	band.size = Vector3(0.56, 0.1, 0.56)
	head.add_child(_mesh(band, spec.color.darkened(0.3), Vector3(0, 0.13, 0)))
	# 眼睛：兩個發亮的小方塊，靠形狀與顏色讀狀態（平常細長、起疑瞇、警戒瞪大、崩壞打叉、死掉一條線）
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_mat.albedo_color = Color(0.95, 0.95, 1.0)
	var em := BoxMesh.new()
	em.size = Vector3(0.09, 0.055, 0.03)
	eye_l = MeshInstance3D.new()
	eye_l.mesh = em
	eye_l.material_override = _eye_mat
	eye_l.position = Vector3(-0.09, 0.03, -0.225)
	head.add_child(eye_l)
	eye_r = MeshInstance3D.new()
	eye_r.mesh = em
	eye_r.material_override = _eye_mat
	eye_r.position = Vector3(0.09, 0.03, -0.225)
	head.add_child(eye_r)
	# 鼻子：小三角錐朝前，俯視時一眼看出敵人臉朝哪邊
	var nose := MeshInstance3D.new()
	var nm := CylinderMesh.new()
	nm.top_radius = 0.0
	nm.bottom_radius = 0.07
	nm.height = 0.18
	nose.mesh = nm
	nose.material_override = _eye_mat.duplicate()
	(nose.material_override as StandardMaterial3D).albedo_color = Color(0.7, 0.55, 0.45)
	nose.rotation.x = -PI / 2.0
	nose.position = Vector3(0.0, -0.05, -0.28)
	head.add_child(nose)
	_build_vision()

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
	_hook_immune_t -= delta
	_pant_t -= delta
	_heads_up_t -= delta
	_wary_t -= delta
	_bar_flash_t -= delta
	_swing_rest_t -= delta
	if _swing_rest_t <= 0.0:
		_swings = 0
	_blocked_streak_t -= delta
	if _blocked_streak_t <= 0.0:
		_blocked_streak = 0
	_hit_streak_t -= delta
	if _hit_streak_t <= 0.0:
		_hit_streak = 0
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
			_do_suspicious(delta)
		State.SEARCH:
			_do_search(delta)
		State.FLEE:
			_do_flee(delta)
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
		# 起步有加速（約半秒到全速），不會一察覺就瞬間滿速衝出來；停下仍是立刻停（戰鬥站位要準）
		var cur := Vector2(velocity.x, velocity.z)
		var want := Vector2(d.x, d.z) * speed
		var nv := cur.move_toward(want, MOVE_ACCEL * delta)
		velocity.x = nv.x
		velocity.z = nv.y
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
	# 透明牆（只擋人和鉤繩）、被遮蔽層隱藏的屋頂／樓板：敵人的視線要穿過去
	# （以前會被柵欄上方的透明牆擋住，造成「站在正前方也沒被發現」）
	var ex: Array = [get_rid(), _player.get_rid()]
	for i in range(4):
		var q := PhysicsRayQueryParameters3D.create(from, to, 1)
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return true
		var c: Node = hit.collider
		if c is Node3D and (c.has_meta("ghost") or not (c as Node3D).is_visible_in_tree()):
			ex.append(hit.rid)
			continue
		return false
	return true


func _perceive(delta: float) -> void:
	if _player == null or state in [State.ATTACK, State.STAGGER, State.BROKEN, State.FLEE]:
		return
	var to := _player.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	# 光與暗（第十次議會）：在光裡視野全長、警覺累積 ×1.5、正面 4 公尺內立刻發現；
	# 暗處視野 ×0.5、累積 ×0.6、正面 2 公尺內才立刻發現。地上的視野錐跟著這個長度變
	var lit := _player_lit()
	var view := effective_view()
	if state == State.ALERT:
		# 甩掉追兵：切斷視線（牆、屋頂、轉角）或拉開距離。躲進暗處追蹤距離也縮短
		if dist < view * 1.6 and _los():
			_lost_t = 0.0
			_last_known = _player.global_position
			_share_sighting(delta)
		else:
			_lost_t += delta
			if _lost_t > (LOSE_TIME_LIT if lit else LOSE_TIME_DARK) + 2.0:
				_lost_t = 0.0
				_guard = false
				_start_search(_last_known)
		return
	var sees := false
	if dist < view:
		if _forward().dot(to.normalized()) > VIEW_COS or dist < 1.6:
			sees = _los()
	if sees:
		var rate := 2.4 if dist < 3.5 else 1.1
		rate *= 1.5 if lit else 0.5
		if _wary_t > 0.0:
			rate *= 1.3
		if state == State.SEARCH:
			rate *= 2.0
		_detect = minf(_detect + delta * rate, 1.0)
		# 正面近距離：不經起疑，直接發現（規則一句話說得完：正前方太近就被看到）
		if dist < instant_range() and _forward().dot(to.normalized()) > INSTANT_COS:
			_detect = 1.0
		_facing = lerp_angle(_facing, _yaw_to(to), 1.0 - exp(-6.0 * delta))
		if _detect >= 1.0:
			_go_alert()
		elif state == State.SUSPICIOUS:
			_sus_pos = _player.global_position
		elif state != State.SEARCH:
			_go_suspicious(_player.global_position)
	else:
		_detect = maxf(_detect - delta * 0.5, 0.0)
		if state == State.SUSPICIOUS and _detect <= 0.0:
			state = State.PATROL if patrol.size() > 0 else State.IDLE


## 甩掉追兵：看不到你超過這個時間就只追「最後看到的位置」（_lost_t > 0 起就已經不知道你真正在哪）
const LOSE_TIME_LIT := 1.5
const LOSE_TIME_DARK := 0.8
## 搜索結束回巡邏後的「提高警覺」：視野 ×1.25、警覺累積 ×1.3，持續 20 秒
const WARY_TIME := 20.0
var _wary_t := 0.0
var _share_t := 0.0
## 搜索：到最後位置張望後，再去附近兩個點看看
var _search_pts: Array = []


## 看到你的守衛會告訴附近 12 公尺內正在追你或搜索的同伴「人在這裡」
func _share_sighting(delta: float) -> void:
	_share_t -= delta
	if _share_t > 0.0:
		return
	_share_t = 0.3
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != self and e is Node3D and e.has_method("hear_sighting") and (e as Node3D).global_position.distance_to(global_position) < 12.0:
			e.hear_sighting(_player.global_position)


func hear_sighting(pos: Vector3) -> void:
	if state == State.ALERT:
		_last_known = pos
		_lost_t = minf(_lost_t, 0.01) if _lost_t > 0.0 else 0.0
	elif state == State.SEARCH:
		_last_known = pos
		_search_t = 0.0
		_search_look = 0.0
		_search_pts.clear()


## 給關卡畫「敵人以為你在哪」的殘影：追丟中或搜索中才回傳位置
func hunt_marker() -> Variant:
	if state == State.ALERT and _lost_t > 0.15:
		return _last_known
	if state == State.SEARCH:
		return _last_known
	return null


const INSTANT_COS := 0.766   # 正面 ±40 度
const INSTANT_LIT := 3.0
const INSTANT_DARK := 1.5


func effective_view() -> float:
	return float(spec.view) * (1.0 if _player_lit() else 0.5) * (1.25 if _wary_t > 0.0 else 1.0) * height_factor()


func instant_range() -> float:
	return (INSTANT_LIT if _player_lit() else INSTANT_DARK) * minf(height_factor(), 1.3)


## 居高臨下：站得比你高的敵人看得更遠（每高 1 公尺 +20%，最多 ×1.8）；你站得比他高時他看得較近（×0.8）
func height_factor() -> float:
	if _player == null:
		return 1.0
	var hd := global_position.y - _player.global_position.y
	if hd > 0.8:
		return minf(1.0 + hd * 0.2, 1.8)
	if hd < -1.5:
		return 0.8
	return 1.0


func _player_lit() -> bool:
	if _player == null:
		return true
	var v = _player.get("in_light")
	return true if v == null else bool(v)


## 搜索：走到最後看到／聽到的位置，左右張望幾秒，沒發現就回巡邏
func _start_search(pos: Vector3) -> void:
	if state in [State.DEAD, State.ATTACK, State.STAGGER, State.BROKEN]:
		return
	var was_calm := state in [State.IDLE, State.PATROL]
	state = State.SEARCH
	_last_known = pos
	_search_t = 0.0
	_search_look = 0.0
	_search_pts.clear()
	_detect = maxf(_detect, 0.5)
	_guard = false
	_show_mark("？", Color(1.0, 0.85, 0.3), 0.0)
	if was_calm:
		Sfx.play(_sfx_hm)


## 起疑：「嗯？」＋站住盯 0.5 秒（玩家讀得出），然後慢走到看到你的位置（躲著不動不再安全）
func _go_suspicious(pos: Vector3) -> void:
	if state in [State.SUSPICIOUS, State.ALERT, State.ATTACK, State.STAGGER, State.BROKEN, State.DEAD, State.FLEE]:
		return
	state = State.SUSPICIOUS
	_sus_t = 0.0
	_sus_pos = pos
	_stop()
	Sfx.play(_sfx_hm)
	if _player and global_position.distance_to(_player.global_position) < 14.0:
		Feel.haptic(25)


func _do_suspicious(delta: float) -> void:
	_sus_t += delta
	# 大將只轉頭不過去（看到你才逃）
	if _sus_t < SUSPICIOUS_HOLD or kind == Kind.LORD:
		_stop()
		return
	var d := _sus_pos - global_position
	d.y = 0.0
	if d.length() > 1.5:
		_move_to(_sus_pos, float(spec.speed) * 0.5, delta)
	else:
		_stop()


## 搜索：走到最後位置 → 張望 2.5 秒 → 再去附近兩個點各看 1.5 秒 → 回巡邏（之後 20 秒提高警覺）
func _do_search(delta: float) -> void:
	_search_t += delta
	var goal: Vector3 = _last_known if _search_pts.is_empty() or _search_look < 2.5 else _search_pts[0]
	var d := goal - global_position
	d.y = 0.0
	if d.length() > 1.2 and _search_t < 14.0:
		_move_to(goal, float(spec.speed) * 0.8, delta)
		return
	_stop()
	_search_look += delta
	_facing += sin(_search_look * 1.6) * delta * 1.4
	if _search_look >= 2.5 and _search_pts.is_empty() and _search_t < 14.0:
		_search_pts = _pick_search_points(_last_known)
		if _search_pts.is_empty():
			_search_pts = [_last_known]
		_search_look = 2.5
		return
	if _search_look > 4.0 and not _search_pts.is_empty():
		_search_pts.pop_front()
		_search_look = 2.5
		if not _search_pts.is_empty():
			return
	if _search_look > 2.5 and (_search_pts.is_empty() or _search_t >= 14.0):
		_detect = 0.0
		mark.visible = false
		_search_pts.clear()
		_wary_t = WARY_TIME
		state = State.PATROL if patrol.size() > 0 else State.IDLE


## 附近兩個可走到的點（導航網格上最近點），用來「去轉角看看」
func _pick_search_points(center: Vector3) -> Array:
	var out: Array = []
	var map := get_world_3d().navigation_map
	for i in range(2):
		var a := randf() * TAU
		var p := center + Vector3(cos(a), 0.0, sin(a)) * randf_range(3.0, 6.0)
		var q := NavigationServer3D.map_get_closest_point(map, p)
		if q.distance_to(center) > 1.5:
			out.append(q)
	return out


## 大將：沿逃跑路線跑，到終點就消失
func start_flee() -> void:
	if state in [State.FLEE, State.DEAD] or flee_route.is_empty():
		return
	state = State.FLEE
	_flee_i = 0
	alerted_once = true
	flee_started.emit(self)
	get_tree().call_group("enemies", "hear_shout", global_position)


## 逃跑路線是手擺的直線，不靠導航網格（陣屋高床往下 0.6 公尺導航走不過去，大將會在原地晃）。
## 直接朝下一個點跑、跳下台階；1.2 秒沒前進就直接跳到下一個點，跑出門就消失。
var _flee_stuck_t := 0.0
var _flee_last_d := INF


func _do_flee(delta: float) -> void:
	var p: Vector3 = flee_route[_flee_i]
	var d := p - global_position
	d.y = 0.0
	var dist := d.length()
	if dist < 0.8:
		_next_flee_point()
		return
	if dist < _flee_last_d - 0.05:
		_flee_last_d = dist
		_flee_stuck_t = 0.0
	else:
		_flee_stuck_t += delta
		if _flee_stuck_t > 1.2:
			global_position = Vector3(p.x, maxf(p.y, global_position.y), p.z)
			_next_flee_point()
			return
	var dir := d / dist
	var speed: float = spec.run
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	_facing = _yaw_to(dir)


func _next_flee_point() -> void:
	_flee_i += 1
	_flee_stuck_t = 0.0
	_flee_last_d = INF
	if _flee_i >= flee_route.size():
		state = State.DEAD
		escaped.emit(self)
		queue_free()


func _go_alert() -> void:
	if kind == Kind.LORD:
		start_flee()
		return
	if state in [State.ALERT, State.ATTACK, State.DEAD, State.STAGGER, State.BROKEN]:
		return
	state = State.ALERT
	_detect = 1.0
	alerted_once = true
	_lost_t = 0.0
	_attack_cd = maxf(_attack_cd, 0.5)
	_show_mark("！", Color(1.0, 0.25, 0.2), 0.9)
	Sfx.play(_sfx_shout)
	if _player and global_position.distance_to(_player.global_position) < 20.0:
		Feel.haptic(70)
	alerted.emit(self)
	get_tree().call_group("enemies", "hear_shout", global_position)


func hear_shout(pos: Vector3) -> void:
	if state in [State.IDLE, State.PATROL, State.SUSPICIOUS, State.SEARCH] and global_position.distance_to(pos) < (SHOUT_RANGE * 1.5 if kind == Kind.LORD else SHOUT_RANGE):
		_go_alert()


## 聽到聲響：未警戒 → 走過去查看（引開用）；警戒中 → 更新最後已知位置
func hear_noise(pos: Vector3, radius: float) -> void:
	if global_position.distance_to(pos) >= radius:
		return
	if kind == Kind.LORD:
		# 大將不會過去查看，只是起疑、轉頭（看到你才逃）
		if state in [State.IDLE, State.SUSPICIOUS]:
			_detect = maxf(_detect, 0.5)
			_go_suspicious(pos)
			_facing = _yaw_to(pos - global_position)
		return
	if state in [State.IDLE, State.PATROL, State.SUSPICIOUS, State.SEARCH]:
		_start_search(pos)
	elif state == State.ALERT:
		_last_known = pos


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
	# 看不到你的時候：只追到「最後看到你的地方」，不是你的真實位置（以前會隔牆鎖定你）
	if _lost_t > 0.0:
		var dl := _last_known - global_position
		dl.y = 0.0
		if dl.length() > 1.2:
			_move_to(_last_known, float(spec.run), delta)
		else:
			# 追到了還是不見人：直接開始搜索
			_lost_t = 0.0
			_guard = false
			_start_search(_last_known)
		return
	var to := _player.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var speed: float = spec.run
	# 被壓頂過的敵人：玩家又從上方下劈時側步閃開
	if _heads_up_t > 0.0 and _player.get("state") == _player.State.PLUNGE and _player.global_position.y - global_position.y > 1.0 and dist < 2.5:
		var side := Vector3(-to.z, 0.0, to.x).normalized() * 2.6
		_move_to(global_position + side, speed, delta)
		return
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
		# 武士／武將戰鬥中一律架刀（出手時才放下）
		_guard = (kind == Kind.SAMURAI or kind == Kind.TARGET) and dist < 4.5
		# 玩家體幹崩壞跪著：不客氣，立刻追擊
		if _player.get("state") == _player.State.BROKEN:
			_attack_cd = minf(_attack_cd, 0.15)
		if _attack_cd <= 0.0 and dist < float(spec.reach) * 1.05 and _forward().dot(to.normalized()) > 0.5:
			_try_attack()


## 連續出手 6 刀就喘氣停手 0.8 秒（頭上「喘」），這是玩家的破綻機會；武將不喘
func _try_attack() -> void:
	if kind != Kind.TARGET and _swings >= SWINGS_BEFORE_PANT:
		_swings = 0
		state = State.STAGGER
		_stun_t = 0.8
		_attack_cd = 0.8
		_guard = false
		# 不跳「喘」字：身體褪色、低頭、眼睛瞇成線（_update_face）
		_pant_t = 0.8
		return
	_swings += 1
	_swing_rest_t = 4.0
	_start_attack()


## counter = 格擋第三刀後的反擊（前置只有 220ms）
func _start_attack(counter: bool = false) -> void:
	state = State.ATTACK
	_atk_t = 0.0
	_struck = false
	_guard = false
	_counter = counter
	# 被連打 2 下 → 這一刀是「危」：不可格擋，只能閃或拉開距離
	_perilous = _hit_streak >= 2 and kind != Kind.ARCHER
	_stop()
	_set_emission(Color(1.0, 0.2, 0.15), 0.8)
	_flash_t = 0.0
	if _perilous:
		_show_mark("危", Color(1.0, 0.2, 0.15), _windup() + 0.1)
		_hit_streak = 0


func _windup() -> float:
	if _counter:
		return 0.22
	return float(spec.windup) * (1.25 if _perilous else 1.0)


func _do_attack(delta: float) -> void:
	# 出手中不自己走動；速度只來自 _kb（前衝半步）。不歸零的話 _kb 會逐幀累加，整個人飛出去
	_stop()
	_atk_t += delta
	var w: float = _windup()
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
		_perilous = false
		_counter = false
		_attack_cd = float(spec.cd) * randf_range(0.85, 1.25)


func _strike() -> void:
	Sfx.play(_sfx_swing)
	weapon.rotation.x = -0.8
	weapon.rotation.y = -1.4
	# 前衝半步（危技衝更遠）
	var f := _forward()
	_kb = f * (4.5 if _perilous else 3.0)
	for a in _strike_area.get_overlapping_areas():
		var t := a.get_parent()
		if t and t != self and t.is_in_group("player") and t.has_method("take_hit"):
			var dir: Vector3 = (t as Node3D).global_position - global_position
			dir.y = 0.0
			dir = dir.normalized()
			var dmg := int(spec.dmg)
			if _perilous:
				dmg = int(dmg * 1.3)
			t.take_hit({"dmg": dmg, "dir": dir, "kb": 5.0, "heavy": _perilous, "pos": t.global_position + Vector3(0, 1.2, 0), "src": self, "unblockable": _perilous})


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

## 暗殺條件：未警戒（巡邏／起疑／搜索中）且在背後，或從上方落下
func can_be_assassinated(by: Node3D) -> bool:
	if kind == Kind.LORD or state in [State.DEAD, State.ALERT, State.ATTACK, State.STAGGER, State.BROKEN, State.FLEE]:
		return false
	if by.global_position.y - global_position.y > 1.0:
		return true
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
	particles.global_position = info.pos
	particles.restart()
	_die(true)


func _hit_dir_set(info: Dictionary) -> Vector3:
	var dir := (info.dir as Vector3)
	dir.y = 0.0
	return dir.normalized()


## 被鉤繩拉過來：拖到 dest、小傷害、短硬直（0.45 秒）；會驚動；之後 6 秒不能再被拉
func can_be_hooked() -> bool:
	return state != State.DEAD and _hook_immune_t <= 0.0


func hooked(dest: Vector3, dmg: int, headshot: bool, by: Node3D, pull_dur: float = 0.45) -> void:
	if state == State.DEAD:
		return
	if kind == Kind.LORD:
		start_flee()
		return
	_hook_immune_t = 6.0
	var dir: Vector3 = dest - global_position
	dir.y = 0.0
	dir = dir.normalized()
	state = State.STAGGER
	_stun_t = pull_dur + 0.45
	_guard = false
	weapon.rotation = Vector3.ZERO
	take_hit({"dmg": dmg, "dir": -dir, "kb": 0.0, "heavy": false, "pos": global_position + Vector3(0.0, 1.5 if headshot else 1.1, 0.0), "src": by, "headshot": headshot, "hook": true})
	if state == State.DEAD:
		return
	# 被拖過來：身體往後仰、腳在地上拖，拖到面前才站穩
	_kb = Vector3.ZERO
	if _react_tw and _react_tw.is_valid():
		_react_tw.kill()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "global_position", Vector3(dest.x, global_position.y, dest.z), pull_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(visual, "rotation:x", -0.5, 0.1)
	tw.tween_property(visual, "scale", Vector3(0.95, 1.08, 0.95), 0.1)
	tw.chain().tween_property(visual, "rotation:x", 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(visual, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if state != State.BROKEN:
		state = State.STAGGER
		_stun_t = pull_dur + 0.45
		_facing = _yaw_to(-dir)


func take_hit(info: Dictionary) -> void:
	if state == State.DEAD:
		return
	if kind == Kind.LORD:
		# 大將打不死：被碰到就逃
		start_flee()
		return
	var dir := _hit_dir_set(info)
	var heavy: bool = info.get("heavy", false)
	var headshot: bool = info.get("headshot", false)
	if state == State.BROKEN:
		_execute(info, dir)
		return
	# 武士架刀（隻狼式）：正面的刀全部擋下，輕重都一樣，只累積體幹（重擊累積較多）。
	# 要傷到他：彈反他的攻擊讓他硬直、手裡劍／鉤繩、或把體幹打滿。
	# 連擋第三刀立刻反擊（連按攻擊的下場）。
	var sword_hit: bool = not info.get("shuriken", false) and not info.get("hook", false)
	var from_above: bool = info.get("from_above", false)
	# 下劈：刀架不住頭頂。武士／武將架刀中有三分之一機率舉刀上頂，把你彈開
	if from_above and _guard and (kind == Kind.SAMURAI or kind == Kind.TARGET) and randf() < 0.33:
		Sfx.play(_sfx_block)
		Feel.hitstop(0.6)
		weapon.rotation.x = -1.6
		var tw0 := weapon.create_tween()
		tw0.set_ignore_time_scale(true)
		tw0.tween_property(weapon, "rotation:x", 0.0, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		var src0 = info.get("src")
		if src0 and src0.has_method("plunge_parried"):
			src0.plunge_parried(self)
		return
	if _guard and sword_hit and not from_above and _forward().dot(-dir) > 0.3:
		Sfx.play(_sfx_block)
		_blocked_streak += 1
		_blocked_streak_t = 2.5
		# 砍架刀只累積少量體幹（彈反他才是大量）；用砍的硬磕不划算
		posture += 10.0 if heavy else 6.0
		_posture_t = 1.0
		_kb = dir * 1.5
		weapon.rotation.y = 0.9
		var tw := weapon.create_tween()
		tw.set_ignore_time_scale(true)
		tw.tween_property(weapon, "rotation:y", 0.0, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		Feel.hitstop(0.5)
		var src = info.get("src")
		if src and src.has_method("on_attack_blocked"):
			src.on_attack_blocked(self)
		if posture >= float(spec.posture):
			_break_posture()
		elif _blocked_streak >= 3 and (kind == Kind.SAMURAI or kind == Kind.TARGET):
			_blocked_streak = 0
			_show_mark("反", Color(1.0, 0.35, 0.2), 0.4)
			_start_attack(true)
		return
	_blocked_streak = 0
	# 手裡劍打斷弓兵拉弓
	if info.get("shuriken", false) and state == State.ATTACK and kind == Kind.ARCHER and not _struck:
		state = State.STAGGER
		_stun_t = 0.6
		weapon.rotation = Vector3.ZERO
		_set_emission(Color(1, 1, 1), 0.0)
	if not alerted_once or state in [State.IDLE, State.PATROL, State.SUSPICIOUS, State.SEARCH]:
		_go_alert()
	# 背後砍（隻狼式）：已警戒的敵人從背後砍不算暗殺，但傷害 1.6 倍、體幹 2 倍，而且無視霸體。
	# 繞背是閃步與鉤繩拉過來之後的獎勵
	var backstab: bool = sword_hit and _forward().dot(dir) > 0.4
	# 武士／武將出手前置中有「霸體」：硬吃刀只受六成傷害，攻擊照樣揮出（跟他對砍是划不來的）
	var dmg := int(info.dmg)
	if backstab:
		dmg = int(ceil(dmg * 1.6))
		info = info.duplicate()
		info.dmg = dmg
	elif state == State.ATTACK and not _struck and (kind == Kind.SAMURAI or kind == Kind.TARGET) and sword_hit:
		dmg = int(ceil(dmg * 0.6))
		info = info.duplicate()
		info.dmg = dmg
	hp -= dmg
	posture += (16.0 if heavy else 8.0) * (2.0 if (backstab or from_above) else 1.0)
	if from_above:
		# 被壓頂過：6 秒內會抬頭盯著上方，再被下劈會側步閃開（打地鼠無效）
		_heads_up_t = 6.0
		_guard = false
		if state != State.BROKEN:
			state = State.STAGGER
			_stun_t = maxf(_stun_t, 0.6)
	_posture_t = 1.5
	_hit_streak += 1
	_hit_streak_t = 2.0
	_kb = dir * float(info.kb) * 0.7
	_guard = false
	_flash_t = Feel.sec("hit_flash_ms")
	_set_emission(Color(1, 1, 1), 2.5)
	Sfx.play(_sfx_hit)
	particles.global_position = info.pos
	particles.direction = dir + Vector3(0, 0.6, 0)
	particles.restart()
	# 不跳傷害數字：血條受擊段閃白（爆頭閃橘）、立刻縮、彈一下（不等頓幀結束）
	_bar_flash_t = 0.18
	_bar_flash_color = Color(1.0, 0.6, 0.2) if headshot else Color(1, 1, 1)
	_refresh_bar(true)
	_react(dir, heavy)
	if hp <= 0:
		_die(false)
	elif posture >= float(spec.posture):
		_break_posture()
	elif heavy and state != State.ATTACK:
		state = State.STAGGER
		_stun_t = 0.45


## 我的刀被玩家普通格擋：刀彈回來、人被頂退半步、身體一震（不算硬直，攻擊照常收刀）
func on_guarded(dir_to_player: Vector3) -> void:
	if state == State.DEAD:
		return
	var back := -dir_to_player
	back.y = 0.0
	back = back.normalized() if back.length() > 0.01 else -_forward()
	_kb = back * 2.2
	weapon.rotation = Vector3(0.6, 0.9, 0.0)
	var tw := weapon.create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(weapon, "rotation", Vector3.ZERO, 0.28).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_react(back, false)
	posture += 4.0
	_posture_t = 1.0


func deflected(push_dir: Vector3) -> void:
	if state == State.DEAD:
		return
	var dir := push_dir
	dir.y = 0.0
	dir = dir.normalized()
	state = State.STAGGER
	_stun_t = 0.75
	_attack_cd = float(spec.cd)
	_perilous = false
	_counter = false
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
	_hit_streak = 0
	_blocked_streak = 0
	_perilous = false
	mark.visible = false
	weapon.rotation = Vector3.ZERO
	# 不跳「崩」字：「><」眼＋身體褪色＋血條閃紅白（_update_face／_update_visual）
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
	_cone.visible = false
	_cone_inner.visible = false
	_arc_mesh.clear_surfaces()
	# 死後不再跑 _update_face，眼睛直接定成一條線
	eye_l.scale = Vector3(1.3, 0.18, 1.0)
	eye_r.scale = Vector3(1.3, 0.18, 1.0)
	eye_l.rotation.z = 0.0
	eye_r.rotation.z = 0.0
	_eye_mat.albedo_color = Color(0.55, 0.55, 0.6)
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

## 地上的視野錐（第十次議會：看不見的規則等於不存在）：外圈＝會起疑的範圍（長度隨玩家在光裡／暗處變）、
## 內圈＝正面立刻發現的範圍。平常淡白、起疑黃、警戒時隱藏。頭上一段弧＝離被發現還差多少。
var _cone: MeshInstance3D
var _cone_mat: StandardMaterial3D
var _cone_inner: MeshInstance3D
var _arc: MeshInstance3D
var _arc_mesh: ImmediateMesh
var _arc_mat: StandardMaterial3D
var _arc_last := -1.0


func _fan(half_angle: float, segs: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segs):
		var a0 := -half_angle + 2.0 * half_angle * float(i) / segs
		var a1 := -half_angle + 2.0 * half_angle * float(i + 1) / segs
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(sin(a1), 0.0, -cos(a1)))
		st.add_vertex(Vector3(sin(a0), 0.0, -cos(a0)))
	return st.commit()


func _build_vision() -> void:
	_cone_mat = StandardMaterial3D.new()
	_cone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cone_mat.albedo_color = Color(1, 1, 1, 0.1)
	_cone = MeshInstance3D.new()
	_cone.mesh = _fan(acos(VIEW_COS), 20)
	_cone.material_override = _cone_mat
	_cone.position = Vector3(0, 0.27, 0)
	_cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cone)
	var inner_mat := _cone_mat.duplicate() as StandardMaterial3D
	inner_mat.albedo_color = Color(1.0, 0.35, 0.25, 0.28)
	_cone_inner = MeshInstance3D.new()
	_cone_inner.mesh = _fan(acos(INSTANT_COS), 10)
	_cone_inner.material_override = inner_mat
	_cone_inner.position = Vector3(0, 0.28, 0)
	_cone_inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cone_inner)
	_arc_mesh = ImmediateMesh.new()
	_arc_mat = StandardMaterial3D.new()
	_arc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arc_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_arc_mat.no_depth_test = true
	_arc_mat.vertex_color_use_as_albedo = true
	_arc = MeshInstance3D.new()
	_arc.mesh = _arc_mesh
	_arc.material_override = _arc_mat
	_arc.position = Vector3(0, 2.75, 0)
	add_child(_arc)


## 視野錐被牆擋住的地方要切掉（以前錐一路畫穿柵欄，看起來像隔牆也看得到你）：
## 每 0.15 秒從眼睛高度沿錐內 18 個方向打射線，每條長度取「視野」與「撞到牆」的較小者，重建扇形。
## 偵測用的是同一種射線（_los），所以畫面上錐碰不到的地方，敵人就真的看不到
var _cone_t := 0.0
var _cone_im: ImmediateMesh
var _cone_inner_im: ImmediateMesh


func _rebuild_cone(r: float, ir: float, ground_y: float) -> void:
	if _cone_im == null:
		_cone_im = ImmediateMesh.new()
		_cone.mesh = _cone_im
		_cone_inner_im = ImmediateMesh.new()
		_cone_inner.mesh = _cone_inner_im
	_cone.scale = Vector3.ONE
	_cone_inner.scale = Vector3.ONE
	_cone.rotation.y = 0.0
	_cone_inner.rotation.y = 0.0
	_cone.global_position = Vector3(global_position.x, ground_y + 0.27, global_position.z)
	_cone_inner.global_position = _cone.global_position + Vector3(0, 0.01, 0)
	var space := get_world_3d().direct_space_state
	var eye := global_position + Vector3(0, 1.5, 0)
	var half := acos(VIEW_COS)
	if global_position.y - ground_y > 0.8:
		_rebuild_cone_from_above(r, ir, ground_y, space, eye, half)
		return
	var segs := 18
	var pts: Array = []
	var ipts: Array = []
	var yaw := visual.rotation.y
	for i in range(segs + 1):
		var a := yaw - half + 2.0 * half * float(i) / segs
		var dir := Vector3(-sin(a), 0.0, -cos(a))
		var reach := r
		var ex: Array = [get_rid()]
		if _player is CollisionObject3D:
			ex.append((_player as CollisionObject3D).get_rid())
		for k in range(3):
			var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * r, 1)
			q.exclude = ex
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				break
			var c: Node = hit.collider
			if c is Node3D and (c.has_meta("ghost") or not (c as Node3D).is_visible_in_tree()):
				ex.append(hit.rid)
				continue
			reach = Vector2(hit.position.x - eye.x, hit.position.z - eye.z).length()
			break
		pts.append(dir * reach)
		ipts.append(dir * minf(reach, ir))
	for pair in [[_cone_im, pts], [_cone_inner_im, ipts]]:
		var im: ImmediateMesh = pair[0]
		var arr: Array = pair[1]
		im.clear_surfaces()
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(segs):
			im.surface_add_vertex(Vector3.ZERO)
			im.surface_add_vertex(arr[i + 1])
			im.surface_add_vertex(arr[i])
		im.surface_end()


## 高處敵人的視野錐：他的視線是斜往下看，所以不用水平射線，而是對你所在高度的地面
## 打一格一格的點（12 個方向 × 每 1 公尺），每一格都從他眼睛拉一條視線到「人站在那裡時的胸口」，
## 看得到的格子才畫。櫓／屋簷正下方會因為平台擋住而空一塊，房子後面被屋頂擋住的地方也會空掉。
## 偵測用的也是從眼睛到你胸口的同一種視線，所以畫出來的就是他真正看得到的地方
func _sees_point(space: PhysicsDirectSpaceState3D, eye: Vector3, p: Vector3) -> bool:
	var ex: Array = [get_rid()]
	if _player is CollisionObject3D:
		ex.append((_player as CollisionObject3D).get_rid())
	for k in range(3):
		var q := PhysicsRayQueryParameters3D.create(eye, p, 1)
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return true
		var c: Node = hit.collider
		if c is Node3D and (c.has_meta("ghost") or not (c as Node3D).is_visible_in_tree()):
			ex.append(hit.rid)
			continue
		return false
	return true


func _rebuild_cone_from_above(r: float, ir: float, ground_y: float, space: PhysicsDirectSpaceState3D, eye: Vector3, half: float) -> void:
	var dirs := 12
	var step := 1.0
	var rings := int(ceil(r / step))
	var yaw := visual.rotation.y
	var chest := ground_y + 1.0
	var vis: Array = []
	for i in range(dirs + 1):
		var a := yaw - half + 2.0 * half * float(i) / dirs
		var dir := Vector3(-sin(a), 0.0, -cos(a))
		var row: Array = []
		for j in range(rings):
			var d := (float(j) + 0.5) * step
			var p := Vector3(global_position.x, chest, global_position.z) + dir * d
			row.append(_sees_point(space, eye, p))
		vis.append(row)
	var y_off := 0.0
	for pair in [[_cone_im, r], [_cone_inner_im, ir]]:
		var im: ImmediateMesh = pair[0]
		var lim: float = pair[1]
		im.clear_surfaces()
		var any := false
		for i in range(dirs):
			var a0 := yaw - half + 2.0 * half * float(i) / dirs
			var a1 := yaw - half + 2.0 * half * float(i + 1) / dirs
			var d0 := Vector3(-sin(a0), 0.0, -cos(a0))
			var d1 := Vector3(-sin(a1), 0.0, -cos(a1))
			for j in range(rings):
				var n0 := float(j) * step
				if n0 >= lim:
					break
				var n1 := minf(float(j + 1) * step, lim)
				if not (vis[i][j] and vis[i + 1][j]):
					continue
				if not any:
					im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
					any = true
				var p00 := d0 * n0 + Vector3(0, y_off, 0)
				var p01 := d0 * n1 + Vector3(0, y_off, 0)
				var p10 := d1 * n0 + Vector3(0, y_off, 0)
				var p11 := d1 * n1 + Vector3(0, y_off, 0)
				for v in [p00, p11, p01, p00, p10, p11]:
					im.surface_add_vertex(v)
		if any:
			im.surface_end()


func _update_vision() -> void:
	var show := kind != Kind.LORD and state in [State.IDLE, State.PATROL, State.SUSPICIOUS, State.SEARCH]
	var hd := global_position.y - _player.global_position.y if _player else 0.0
	# 比你低很多的敵人不畫（看不到上面）；比你高的照畫，錐落在你所在的高度
	var near := _player != null and global_position.distance_to(_player.global_position) < 26.0 and hd > -2.5
	_cone.visible = show and near
	_cone_inner.visible = _cone.visible
	if _cone.visible:
		_cone_t -= get_physics_process_delta_time()
		if _cone_t <= 0.0:
			# 高處的錐要打比較多射線，0.3 秒更新一次就好
			_cone_t = 0.3 if hd > 0.8 else 0.15
			var ground_y := _player.global_position.y if hd > 0.8 else global_position.y
			_rebuild_cone(effective_view(), instant_range(), ground_y)
		_cone_mat.albedo_color = Color(1.0, 0.85, 0.3, 0.3) if state in [State.SUSPICIOUS, State.SEARCH] else Color(1, 1, 1, 0.17)
	# 偵測進度弧：0 時不畫；黃→紅
	var k := _detect if show else 0.0
	if absf(k - _arc_last) < 0.02:
		return
	_arc_last = k
	_arc_mesh.clear_surfaces()
	if k <= 0.02:
		return
	var col := Color(1.0, 0.85, 0.3).lerp(Color(1.0, 0.25, 0.2), k)
	_arc_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 24
	var n := maxi(1, int(segs * k))
	for i in range(n):
		var a0 := PI / 2.0 - TAU * float(i) / segs
		var a1 := PI / 2.0 - TAU * float(i + 1) / segs
		var r0 := 0.34
		var r1 := 0.44
		var p0 := Vector3(cos(a0) * r0, sin(a0) * r0, 0)
		var p1 := Vector3(cos(a0) * r1, sin(a0) * r1, 0)
		var p2 := Vector3(cos(a1) * r1, sin(a1) * r1, 0)
		var p3 := Vector3(cos(a1) * r0, sin(a1) * r0, 0)
		for v in [p0, p1, p2, p0, p2, p3]:
			_arc_mesh.surface_set_color(col)
			_arc_mesh.surface_add_vertex(v)
	_arc_mesh.surface_end()


## 程序式走姿（沒有動畫資源）：越快越前傾（跑步約 17 度）、身體隨步伐上下、腳步聲跟步頻走。
## 用 body／head 的局部位移，不碰 visual 的旋轉（受擊反應與倒地在用）。
func _update_gait(delta: float) -> void:
	var hv := Vector2(velocity.x, velocity.z).length()
	var ratio := clampf(hv / float(spec.run), 0.0, 1.0)
	_lean = lerpf(_lean, ratio, 1.0 - exp(-9.0 * delta))
	_stride += delta * hv * 3.4
	var bob := sin(_stride) * 0.045 * _lean
	body.rotation.x = -_lean * 0.3
	body.position = Vector3(0.0, 0.85 + bob, -_lean * 0.1)
	head.position = Vector3(0.0, 1.68 + bob * 1.3, -_lean * 0.28)
	# 腳步聲只給「快走／跑」（搜索、逼近、追擊），巡邏慢走不出聲；離玩家越遠越小，12 公尺外不播
	if hv > 0.4:
		_step_left -= hv * delta
		if _step_left <= 0.0:
			_step_left = 1.6
			var d := global_position.distance_to(_player.global_position) if _player else 99.0
			if ratio >= 0.5 and d < 12.0:
				var falloff := clampf((d - 3.0) / 9.0, 0.0, 1.0)
				_sfx_step.volume_db = lerpf(-18.0, -10.0, ratio) - falloff * 16.0
				Sfx.play(_sfx_step)
	else:
		_step_left = minf(_step_left, 0.4)


## 眼睛＋身體色調：狀態一眼可讀。
##   平常：白色細眼，偶爾眨眼　起疑／搜索：黃色瞇眼、身體偏黃　警戒／攻擊：紅色瞪大、身體偏紅
##   硬直：小點　崩壞：「><」　死：一條線
func _update_face(delta: float) -> void:
	var base: Color = spec.color
	var eye := Color(0.95, 0.95, 1.0)
	var sc := Vector3(1.0, 1.0, 1.0)
	var tilt := 0.0
	var tint := base
	var head_rot_x := 0.0
	match state:
		State.SUSPICIOUS, State.SEARCH:
			eye = Color(1.0, 0.85, 0.3)
			sc = Vector3(1.35, 0.45, 1.0)
			tint = base.lerp(Color(1.0, 0.8, 0.25), 0.3)
		State.ALERT, State.ATTACK:
			eye = Color(1.0, 0.3, 0.25)
			sc = Vector3(1.4, 1.7, 1.0)
			tint = base.lerp(Color(1.0, 0.2, 0.1), 0.45)
			if state == State.ALERT and _lost_t > 0.15:
				# 追丟了：眼睛轉橘、東張西望（玩家看得出「他不知道我在哪」）
				eye = Color(1.0, 0.6, 0.2)
				sc = Vector3(1.4, 1.0, 1.0)
				tint = base.lerp(Color(1.0, 0.55, 0.2), 0.35)
		State.STAGGER:
			eye = Color(0.9, 0.9, 0.95)
			sc = Vector3(0.6, 0.6, 1.0)
			if _pant_t > 0.0:
				# 喘氣：眼睛瞇成線、身體褪色、低頭
				eye = Color(0.8, 0.85, 0.9)
				sc = Vector3(1.2, 0.25, 1.0)
				tint = base.lerp(Color(0.55, 0.55, 0.6), 0.55)
				head_rot_x = 0.5
		State.BROKEN:
			eye = Color(1.0, 0.75, 0.4)
			sc = Vector3(1.3, 0.3, 1.0)
			tilt = 0.7
			tint = base.lerp(Color(0.6, 0.6, 0.62), 0.5)
		State.DEAD:
			eye = Color(0.55, 0.55, 0.6)
			sc = Vector3(1.3, 0.18, 1.0)
		State.FLEE:
			eye = Color(1.0, 0.9, 0.9)
			sc = Vector3(1.3, 1.5, 1.0)
		_:
			_blink_t -= delta
			if _blink_t < 0.0:
				_blink_t = randf_range(2.0, 5.0)
			elif _blink_t < 0.12:
				sc = Vector3(1.0, 0.1, 1.0)
	# 被壓頂過（或玩家正在上方下劈）：抬頭、眼睛睜大成圓
	if state in [State.ALERT, State.ATTACK, State.STAGGER] and _player and (_heads_up_t > 0.0 or (_player.get("state") == _player.State.PLUNGE and _player.global_position.y - global_position.y > 1.0)):
		sc = Vector3(1.6, 2.0, 1.0)
		head_rot_x = -0.45
	if state != State.STAGGER or _pant_t > 0.0 or head_rot_x != 0.0:
		# 受擊反應的 tween 也會動 head.rotation，只在沒有 tween 跑時才接手
		if not (_react_tw and _react_tw.is_valid() and _react_tw.is_running()):
			head.rotation.x = lerpf(head.rotation.x, head_rot_x, 1.0 - exp(-10.0 * delta))
	var k := 1.0 - exp(-16.0 * delta)
	eye_l.scale = eye_l.scale.lerp(sc, k)
	eye_r.scale = eye_r.scale.lerp(sc, k)
	eye_l.rotation.z = lerpf(eye_l.rotation.z, tilt, k)
	eye_r.rotation.z = lerpf(eye_r.rotation.z, -tilt, k)
	_eye_mat.albedo_color = _eye_mat.albedo_color.lerp(eye, k)
	_body_mat.albedo_color = _body_mat.albedo_color.lerp(tint, 1.0 - exp(-8.0 * delta))


## 頭上血條：受過傷或戰鬥中才出現；體幹崩壞時閃紅白；受擊時閃白並彈一下。
## 受擊當下直接呼叫（punch=true），不等物理幀——命中有頓幀（時間流速 0.05），等物理幀血條會慢半拍
## 關卡可能生成後把 hp 調高（第二關大將 150、第三關隊長 130），滿血以實際最高值算
var _bar_tw: Tween


func _refresh_bar(punch: bool = false) -> void:
	_max_hp = maxi(_max_hp, hp)
	var ratio := clampf(float(hp) / float(_max_hp), 0.0, 1.0)
	bar.visible = kind != Kind.LORD and (hp < _max_hp or state in [State.ALERT, State.ATTACK, State.STAGGER, State.BROKEN])
	bar_fill.scale.x = maxf(ratio, 0.001)
	bar_fill.position.x = -0.62 * (1.0 - ratio)
	bar_fill.visible = ratio > 0.001
	var blink := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.02)
	if _bar_flash_t > 0.0:
		bar_mat.albedo_color = _bar_flash_color
	else:
		bar_mat.albedo_color = Color(1.0, 0.3 + 0.7 * blink, 0.3 + 0.7 * blink) if state == State.BROKEN else Color(0.9, 0.2, 0.18)
	if punch:
		if _bar_tw and _bar_tw.is_valid():
			_bar_tw.kill()
		bar.scale = Vector3(1.0, 1.9, 1.0)
		_bar_tw = bar.create_tween()
		_bar_tw.set_ignore_time_scale(true)
		_bar_tw.tween_property(bar, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _set_emission(color: Color, energy: float) -> void:
	for m in _mats:
		m.emission = color
		m.emission_energy_multiplier = energy


func _update_visual(delta: float) -> void:
	visual.rotation.y = lerp_angle(visual.rotation.y, _facing, 1.0 - exp(-14.0 * delta))
	_update_gait(delta)
	_update_face(delta)
	_update_vision()
	# 架刀姿勢
	if state in [State.ALERT] and kind != Kind.ARCHER:
		var target_rot := Vector3(-1.3, 0.3, -0.2) if _guard else Vector3.ZERO
		weapon.rotation = weapon.rotation.lerp(target_rot, 1.0 - exp(-18.0 * delta))
	_refresh_bar()
	if state in [State.SUSPICIOUS, State.SEARCH] and not mark.visible:
		_show_mark("？", Color(1.0, 0.85, 0.3), 0.0)
	elif not state in [State.SUSPICIOUS, State.SEARCH] and mark.text == "？":
		mark.visible = false
