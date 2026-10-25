extends CharacterBody3D
## 半藏：移動、三段連斬、閃步、受擊。
## 所有時間與力道從 Feel 讀取；COMBO 表只放「相對倍率」與角度。

signal hit_landed(info: Dictionary)
signal hp_changed(hp: int)
signal died
signal parried
## 實際扣血時發出（格擋成功不算）
signal damaged(amount: int)
## 體幹（隻狼式）：被格擋、被打、普通格擋都會累積；滿了崩壞 2.5 秒
signal posture_changed(v: float, max_v: float)
signal posture_broken
## 動作被拒（手裡劍沒了、閃步冷卻中、鉤繩冷卻中…）：HUD 用來給一個小提示
signal denied(what: String)
signal shuriken_changed(n: int)
signal rations_changed(n: int)
signal weapon_changed(mode: int)

enum State { FREE, ATTACK, DASH, HURT, BLOCK, DEAD, GRAPPLE, BROKEN, PLUNGE }

const SPEED := 5.4
## 鉤繩固定長度（公尺）；升級系統之後可加長
var hook_range := 22.0
const ACCEL := 34.0
const DASH_SPEED := 17.0
const DASH_TIME := 0.17
const MAX_HP := 100
## 體幹：被敵人格擋 +15、被打中 +25、普通格擋 +10、完美彈反 −10；1.5 秒未受擊後每秒回 20
const MAX_POSTURE := 100.0
const POSTURE_BLOCKED := 15.0
const POSTURE_HIT := 25.0
const POSTURE_GUARD := 10.0
const POSTURE_DEFLECT := -10.0
const POSTURE_REGEN := 20.0
const POSTURE_BREAK_TIME := 2.5
## 閃步：0.6 秒內最多兩次，之後 0.8 秒不可閃
const DASH_BURST := 2
const DASH_BURST_WINDOW := 0.6
const DASH_LOCKOUT := 0.8
## 手裡劍 5 枚；一次只能有一枚在空中；撿回或檢查點補充
const MAX_SHURIKEN := 5
## 鉤繩拉人冷卻
const HOOK_PULL_CD := 4.0
## 奔跑靴聲半徑（未警戒的敵人會過來查看）
const RUN_NOISE_RADIUS := 3.5
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
var cam_rig: Node = null
var hp := MAX_HP
var max_hp := MAX_HP
## 帶著的口糧（血滿時撿到會帶著，血量低於三成自動吃）
var rations := 0
var posture := 0.0
var _posture_delay := 0.0
var _broken_t := 0.0
## 崩壞後 3 秒免疫體幹傷害
var _posture_immune_t := 0.0
## 最近 1 秒內造成體幹傷害的敵人（多敵圍攻：第二個以上打 0.5 折）
var _posture_sources: Array = []
var _dash_times: Array = []
var _dash_lock_t := 0.0
## 暗殺後的短暫硬直（不能攻擊／閃步／瞄準）
var _lock_t := 0.0
var _run_noise_t := 0.0
var _hook_cd := 0.0
var _shuriken_in_flight: Node = null
## 手裡劍數量
var shuriken := MAX_SHURIKEN
## 武器模式與瞄準
const WEAPON_SWORD := 0
const WEAPON_SHURIKEN := 1
const AIM_NONE := 0
const AIM_SHURIKEN := 1
const AIM_HOOK := 2
var weapon_mode := WEAPON_SWORD
var aim_mode := AIM_NONE
var aim_dir := Vector3.FORWARD
## 準心狀態："" / "lock"（鎖定敵人）/ "ok"（可鉤）/ "bad"（不可鉤）
var aim_status := ""
var _aim_t := 0.0
var _aim_target: Node3D = null
var _hook_ok := false
var _hook_pos := Vector3.ZERO
var _aim_head := false
var _rope: MeshInstance3D
var _rope_to := Vector3.ZERO
var _rope_t := 0.0
## 是否站在燈光下（關卡每幀更新；敵人視野據此縮放）
var in_light := true
## 腳下光圈：在燈籠光裡亮起暖黃圓片（敵人看得更遠、更快發現）；暗處消失。走進光裡輕震一下
var _light_disc: MeshInstance3D
var _light_disc_mat: StandardMaterial3D
var _was_lit := false


func _update_light_disc(delta: float) -> void:
	if _light_disc == null:
		_light_disc = MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.75
		cm.bottom_radius = 0.75
		cm.height = 0.02
		cm.radial_segments = 24
		_light_disc.mesh = cm
		_light_disc_mat = StandardMaterial3D.new()
		_light_disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_light_disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_light_disc_mat.albedo_color = Color(1.0, 0.82, 0.4, 0.0)
		_light_disc.material_override = _light_disc_mat
		_light_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_light_disc.position = Vector3(0, 0.26, 0)
		add_child(_light_disc)
	var a := _light_disc_mat.albedo_color.a
	a = move_toward(a, 0.6 if in_light else 0.0, delta * 3.0)
	_light_disc_mat.albedo_color.a = a
	_light_disc.visible = a > 0.01
	if in_light and not _was_lit:
		Feel.haptic(15)
	_was_lit = in_light
## 鉤繩可到達的範圍（關卡設定；size 為零＝不限制）
var hook_bounds := AABB()
var _grapple_t := 0.0
var _grapple_from := Vector3.ZERO
var _grapple_to := Vector3.ZERO

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
	_build_rope()
	max_hp = Progress.max_hp()
	hp = max_hp
	shuriken = Progress.shuriken_max()
	_shuriken_cap = shuriken
	Progress.changed.connect(refresh_progress)
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
		on_attack_down()
	elif ev.is_action_released("attack"):
		on_attack_up()
	elif ev.is_action_pressed("dash"):
		request_dash()
	elif ev.is_action_pressed("throw"):
		on_hook_down()
	elif ev.is_action_released("throw"):
		on_hook_up()
	elif ev.is_action_pressed("weapon_toggle"):
		toggle_weapon()
	elif ev.is_action_pressed("block"):
		set_block(true)
	elif ev.is_action_released("block"):
		set_block(false)


## 攻擊鍵：刀模式按下即斬；手裡劍模式按住瞄準、放開射出
func on_attack_down() -> void:
	if submerged:
		return
	if weapon_mode == WEAPON_SHURIKEN:
		_begin_aim(AIM_SHURIKEN)
	elif weapon_mode == WEAPON_SMOKE:
		throw_smoke()
	else:
		request_attack()


# ---------------------------------------------------------------- 第十二次議會：煙玉、焙烙玉、情境鍵、水遁

const WEAPON_SMOKE := 2
const SMOKE_MAX := 2
const BREATH_MAX := 8.0
const SmokeScript := preload("res://scripts/smoke.gd")
const FireScript2 := preload("res://scripts/fire.gd")
signal smoke_changed(n: int)
signal ctx_changed(label: String)
var smoke := SMOKE_MAX
## 手上拿著焙烙玉（一次性；情境鍵變「丟出」）
var held_bomb := false
## 水遁
var submerged := false
var breath := BREATH_MAX
var _surface_lock := 0.0
var _ctx: Node = null
var _ctx_label := ""
var _ripple: MeshInstance3D


## 煙玉：腳下爆一團煙，7 秒擋住敵人視線（檢查點補滿 2 顆）
func throw_smoke() -> void:
	if smoke <= 0 or not state in [State.FREE, State.BLOCK]:
		denied.emit("smoke")
		return
	smoke -= 1
	smoke_changed.emit(smoke)
	# 腳下爆煙（忍者遁術）：人在煙裡＝看不到，追兵追丟，趁 7 秒溜走
	var s: Node3D = SmokeScript.new()
	get_tree().current_scene.add_child(s)
	s.global_position = global_position
	Sfx.play(sfx_dash)
	Feel.haptic(25)


func refill_smoke() -> void:
	smoke = SMOKE_MAX
	smoke_changed.emit(smoke)


func pickup_bomb() -> void:
	held_bomb = true
	Feel.haptic(30)
	_update_ctx(true)


## 丟焙烙玉：往前 6 公尺拋物線，落地爆炸（3 公尺內敵人重傷硬直、點著附近的稻草油壺、也會燙到太近的自己）
func throw_bomb() -> void:
	if not held_bomb or not state in [State.FREE, State.BLOCK]:
		return
	held_bomb = false
	var f: Vector3 = cam_rig.forward() if cam_rig != null and cam_rig.has_method("forward") else _forward()
	var from := global_position + Vector3(0, 1.4, 0)
	var to := global_position + f * 6.0
	# 落點：往下找地面
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(to + Vector3(0, 4, 0), to + Vector3(0, -8, 0), 1)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		to = hit.position
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.2
	sm.height = 0.4
	ball.mesh = sm
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.15, 0.13, 0.12)
	ball.material_override = bm
	get_tree().current_scene.add_child(ball)
	ball.global_position = from
	var tw := ball.create_tween()
	tw.tween_method(func(k: float) -> void:
		ball.global_position = from.lerp(to, k) + Vector3(0, sin(k * PI) * 2.5, 0), 0.0, 1.0, 0.6)
	tw.tween_callback(func() -> void:
		_explode(ball.global_position)
		ball.queue_free())
	Sfx.play(sfx_swing)
	_update_ctx(true)


func _explode(at: Vector3) -> void:
	Feel.shake(1.2)
	Feel.hitstop(0.8)
	Feel.flash(Color(1.0, 0.8, 0.4, 0.35), 0.25)
	Feel.haptic(80)
	get_tree().call_group("enemies", "hear_noise", at, 18.0)
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Node3D
		if en and en.global_position.distance_to(at) < 3.2 and e.has_method("take_hit") and e.get("state") != e.State.DEAD:
			var d := en.global_position - at
			d.y = 0.0
			e.take_hit({"dmg": 40, "dir": d.normalized() if d.length() > 0.01 else Vector3.FORWARD, "kb": 8.0, "heavy": true, "pos": en.global_position + Vector3(0, 1, 0), "src": self, "bomb": true})
	if global_position.distance_to(at) < 2.2:
		var dd := global_position - at
		dd.y = 0.0
		take_hit({"dmg": 25, "dir": dd.normalized() if dd.length() > 0.01 else Vector3.BACK, "kb": 6.0, "heavy": true, "pos": global_position + Vector3(0, 1, 0), "src": self, "unblockable": true})
	for n in get_tree().get_nodes_in_group("flammable"):
		if n is Node3D and (n as Node3D).global_position.distance_to(at) < 3.8 and n.has_method("ignite"):
			n.ignite()
	var f: Node3D = FireScript2.new()
	f.radius = 1.6
	f.duration = 4.0
	get_tree().current_scene.add_child(f)
	f.global_position = at
	_burst_spark(at + Vector3(0, 0.5, 0), Vector3.UP, 2.0)


## 情境鍵：手上有焙烙玉＝丟出；否則找身邊最近、可互動的東西
func _update_ctx(force: bool = false) -> void:
	var label := ""
	_ctx = null
	if held_bomb:
		label = "丟出"
	else:
		var best_d := 1e9
		for n in get_tree().get_nodes_in_group("interactable"):
			if not (n is Node3D) or not n.can_interact(self):
				continue
			var d := (n as Node3D).global_position - global_position
			if absf(d.y) > 1.5:
				continue
			d.y = 0.0
			var dist := d.length()
			if dist < float(n.interact_radius()) and dist < best_d:
				best_d = dist
				_ctx = n
		if _ctx:
			label = String(_ctx.interact_label())
	if label != _ctx_label or force:
		_ctx_label = label
		ctx_changed.emit(label)


func interact() -> void:
	if submerged:
		return
	if held_bomb:
		throw_bomb()
		return
	if _ctx and is_instance_valid(_ctx) and _ctx.can_interact(self):
		_ctx.interact(self)
		Feel.haptic(20)
	_update_ctx(true)


## 竹筒：潛下時從水面斜斜伸出一截青竹（有竹節），頂端偶爾冒一串小氣泡；人怎麼走竹筒就跟著滑
var _bamboo: Node3D
var _bubble_t := 0.0


func _update_bamboo(delta: float) -> void:
	if _bamboo == null:
		_bamboo = Node3D.new()
		var green := StandardMaterial3D.new()
		green.albedo_color = Color(0.55, 0.78, 0.3)
		var node_mat := StandardMaterial3D.new()
		node_mat.albedo_color = Color(0.35, 0.45, 0.18)
		var tube := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.045
		cm.bottom_radius = 0.05
		cm.height = 0.75
		cm.radial_segments = 8
		tube.mesh = cm
		tube.material_override = green
		tube.position = Vector3(0, 0.375, 0)
		_bamboo.add_child(tube)
		for y in [0.15, 0.45]:
			var ring := MeshInstance3D.new()
			var rm := CylinderMesh.new()
			rm.top_radius = 0.058
			rm.bottom_radius = 0.058
			rm.height = 0.035
			rm.radial_segments = 8
			ring.mesh = rm
			ring.material_override = node_mat
			ring.position = Vector3(0, y, 0)
			_bamboo.add_child(ring)
		# 斜口（竹筒頂端削斜）：深色小圓片
		var mouth := MeshInstance3D.new()
		var mm := CylinderMesh.new()
		mm.top_radius = 0.04
		mm.bottom_radius = 0.04
		mm.height = 0.01
		mouth.mesh = mm
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.1, 0.12, 0.06)
		mouth.material_override = dark
		mouth.position = Vector3(0, 0.755, 0)
		_bamboo.add_child(mouth)
		_bamboo.rotation_degrees = Vector3(18, 0, 0)
		add_child(_bamboo)
	_bamboo.visible = submerged
	if not submerged:
		return
	_bamboo.scale = Vector3(1.6, 1.4, 1.6)   # 手機小螢幕上要看得出是竹筒
	# 原點在地面下約 0.2 公尺：竹筒從水面往上伸；朝面向的反方向斜（像人仰躺在水裡含著）
	_bamboo.position = Vector3(0, 0.15, 0)
	# 往畫面左右斜（對著鏡頭斜會被透視壓扁，看不出長度）
	var side_yaw: float = (cam_rig.yaw if cam_rig != null else _facing) + PI / 2.0
	_bamboo.rotation = Vector3(deg_to_rad(25) + sin(Time.get_ticks_msec() * 0.002) * 0.04, side_yaw, 0)
	_bubble_t -= delta
	if _bubble_t <= 0.0:
		_bubble_t = randf_range(1.2, 2.2)
		var top := _bamboo.global_transform * Vector3(0, 0.78, 0)  # 已含縮放
		for i in range(3):
			var b := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.03
			sm.height = 0.06
			sm.radial_segments = 6
			sm.rings = 3
			b.mesh = sm
			var bm := StandardMaterial3D.new()
			bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			bm.albedo_color = Color(0.85, 0.95, 1.0, 0.7)
			b.material_override = bm
			get_tree().current_scene.add_child(b)
			b.global_position = top
			var tw := b.create_tween()
			tw.tween_interval(i * 0.12)
			tw.tween_property(b, "global_position", top + Vector3(randf_range(-0.05, 0.05), 0.35, randf_range(-0.05, 0.05)), 0.6)
			tw.parallel().tween_property(bm, "albedo_color:a", 0.0, 0.6)
			tw.tween_callback(b.queue_free)


## 水遁：站在深水區自動潛下，用竹筒呼吸（不限時間）
func _update_water(delta: float) -> void:
	var in_water := false
	for w in get_tree().get_nodes_in_group("water"):
		if w.contains(global_position):
			in_water = true
			break
	_surface_lock -= delta
	var want := in_water and _surface_lock <= 0.0 and state in [State.FREE, State.BLOCK, State.ATTACK, State.DASH]
	if want and not submerged:
		submerged = true
		visual.visible = false
		Sfx.play(sfx_dash)
	elif not want and submerged:
		submerged = false
		visual.visible = true
	# 竹筒呼吸（水遁之術）：潛著不限時間；代價是竹筒露出水面，守衛走到 1.6 公尺內看過來會發現（enemy._los）
	breath = BREATH_MAX
	_update_bamboo(delta)
	if _ripple == null:
		_ripple = MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.45
		tm.outer_radius = 0.55
		_ripple.mesh = tm
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.albedo_color = Color(0.8, 0.9, 1.0, 0.6)
		_ripple.material_override = rm
		_ripple.position = Vector3(0, 0.3, 0)
		add_child(_ripple)
	_ripple.visible = submerged
	if submerged:
		var k := fmod(Time.get_ticks_msec() * 0.0015, 1.0)
		_ripple.scale = Vector3.ONE * (0.6 + k * 0.9)
		(_ripple.material_override as StandardMaterial3D).albedo_color.a = 0.7 * (1.0 - k)


func on_attack_up() -> void:
	if aim_mode == AIM_SHURIKEN:
		_release_aim()


## 鉤繩鍵：按住瞄準牆頂／屋頂，放開射出
func on_hook_down() -> void:
	_begin_aim(AIM_HOOK)


func on_hook_up() -> void:
	if aim_mode == AIM_HOOK:
		_release_aim()


## 換武器：刀 → 手裡劍 → 煙玉 → 刀
func toggle_weapon() -> void:
	weapon_mode = (weapon_mode + 1) % 3
	weapon_changed.emit(weapon_mode)


## 刀：空閒/閃步中立刻出刀；攻擊中則排隊，收刀到一半自動接下一段。
func request_attack() -> void:
	if _lock_t > 0.0:
		return
	if state == State.FREE and not is_on_floor():
		# 空中按攻擊永遠有事發生：正下方有未察覺的敵人→落下忍殺；離地 1.5 公尺以上→下劈
		if _try_plunge():
			return
		if _can_plunge():
			_start_plunge()
			return
	match state:
		State.ATTACK:
			_queued = true
		State.FREE, State.DASH, State.BLOCK:
			_start_attack()


## 自動試玩用：快速丟手裡劍／快速鉤（瞄準鏡頭正前方）
func request_throw() -> void:
	_begin_aim(AIM_SHURIKEN)
	_release_aim()


func request_hook() -> void:
	_begin_aim(AIM_HOOK)
	_release_aim()


# ---------------------------------------------------------------- 瞄準

func _begin_aim(kind: int) -> void:
	if not state in [State.FREE, State.BLOCK] or _lock_t > 0.0:
		return
	if kind == AIM_SHURIKEN and shuriken <= 0:
		denied.emit("shuriken")
		return
	# 鉤繩冷卻中（按鍵在倒數）就整個不能用，鉤牆頂／屋頂也一樣：倒數＝不能放（使用者回報倒數中還放得出來）
	if kind == AIM_HOOK and _hook_cd > 0.0:
		denied.emit("hook")
		Feel.haptic(15)
		return
	if state == State.BLOCK:
		state = State.FREE
	aim_mode = kind
	_aim_t = 0.0
	_aim_target = null
	_hook_ok = false
	aim_status = ""
	if cam_rig != null:
		cam_rig.aiming = true
	_tick_aim(0.0)


## 瞄準中（過肩鏡頭）：拖視角＝瞄準，畫面中心是準心；左搖桿慢速移動；人物面向鏡頭方向
func _tick_aim(delta: float) -> void:
	_aim_t += delta
	var input := _read_input()
	velocity.x = move_toward(velocity.x, input.x * SPEED * 0.45, ACCEL * delta)
	velocity.z = move_toward(velocity.z, input.z * SPEED * 0.45, ACCEL * delta)
	var origin := global_position + Vector3(0.0, 1.5, 0.0)
	var dir := _forward()
	if cam_rig != null and cam_rig.has_method("aim_ray"):
		var r: Array = cam_rig.aim_ray()
		origin = r[0]
		dir = r[1]
		_facing = cam_rig.yaw
	aim_dir = dir
	visual.rotation.y = lerp_angle(visual.rotation.y, _facing, 1.0 - exp(-20.0 * delta))
	var pose := Vector3(-20.0, -60.0, 0.0) if aim_mode == AIM_SHURIKEN else Vector3(-70.0, 0.0, 0.0)
	sword_pivot.rotation_degrees = sword_pivot.rotation_degrees.lerp(pose, 1.0 - exp(-20.0 * delta))
	# 兩種瞄準共用：準心附近有敵人就默默鎖定（頭／身），畫面上不另外畫圈
	var lock := _pick_enemy_ray(origin, dir, 0.992, hook_range if aim_mode == AIM_HOOK else 22.0)
	_aim_target = lock.target
	_aim_head = lock.head
	aim_status = "lock" if _aim_target else ""
	if aim_mode == AIM_HOOK and _aim_target == null:
		var r := _hook_probe_ray(origin, dir)
		_hook_ok = r.ok
		_hook_pos = r.pos


func _release_aim() -> void:
	var kind := aim_mode
	aim_mode = AIM_NONE
	aim_status = ""
	if cam_rig != null:
		cam_rig.aiming = false
	if state != State.FREE:
		return
	if kind == AIM_SHURIKEN:
		_throw(aim_dir, _aim_target, _aim_head)
	elif kind == AIM_HOOK:
		if _aim_target:
			if _can_hook_pull(_aim_target):
				_hook_launch("pull", _aim_target.global_position + Vector3(0.0, 1.68 if _aim_head else 1.1, 0.0), _aim_target, _aim_head)
			else:
				_hook_launch("miss", _aim_target.global_position + Vector3(0.0, 1.1, 0.0))
		elif _hook_ok:
			_hook_launch("grapple", _hook_pos)
		else:
			_hook_launch("miss", _hook_pos)
	_aim_target = null


func _can_hook_pull(e: Node3D) -> bool:
	if _hook_cd > 0.0:
		return false
	if e.has_method("can_be_hooked") and not e.can_be_hooked():
		return false
	return true


## 準心附近的敵人（與射線夾角最小者）；準心更靠近頭部時回報 head=true
func _pick_enemy_ray(origin: Vector3, dir: Vector3, min_dot: float, max_dist: float) -> Dictionary:
	var best: Node3D = null
	var best_dot := min_dot
	var head := false
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node3D) or e.get("state") == null or e.state == e.State.DEAD:
			continue
		var chest: Vector3 = (e.global_position + Vector3(0.0, 1.1, 0.0)) - origin
		var dist := chest.length()
		if dist < 1.0 or dist > max_dist:
			continue
		var dot_c := dir.dot(chest / dist)
		var hv: Vector3 = (e.global_position + Vector3(0.0, 1.68, 0.0)) - origin
		var dot_h := dir.dot(hv / hv.length())
		var dot := maxf(dot_c, dot_h)
		if dot > best_dot:
			best = e
			best_dot = dot
			head = dot_h > dot_c and dot_h > 0.9975
	return {"target": best, "head": head}


## 瞄準用射線：跳過被遮蔽層隱藏的屋頂／樓板（它們隱藏時還有碰撞，不跳過的話準心會打在看不見的天花板上）
func _ray_visible(from: Vector3, to: Vector3, mask: int) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var ex: Array = [get_rid()]
	for i in range(4):
		var q := PhysicsRayQueryParameters3D.create(from, to, mask)
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return hit
		var c: Node = hit.collider
		if c is Node3D and not (c as Node3D).is_visible_in_tree():
			ex.append(hit.rid)
			continue
		return hit
	return {}


## 鉤繩落點（準心射線）：打到頂面直接落在那裡（可上可下，不能同高度平移）；打到牆面就往上找牆頂
func _hook_probe_ray(origin: Vector3, dir: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var hit := _ray_visible(origin, origin + dir * 30.0, 1)
	var fail := {"ok": false, "pos": origin + dir * 8.0}
	if hit.is_empty():
		return fail
	var p: Vector3 = hit.position
	var n: Vector3 = hit.normal
	var flat := Vector3(dir.x, 0.0, dir.z)
	flat = flat.normalized() if flat.length() > 0.01 else _forward()
	var top := p
	if n.y < 0.7:
		var top_from := p + flat * 0.7 + Vector3(0.0, 9.0, 0.0)
		var q2 := PhysicsRayQueryParameters3D.create(top_from, top_from + Vector3(0.0, -12.0, 0.0), 1)
		q2.exclude = [get_rid()]
		var h2 := space.intersect_ray(q2)
		if h2.is_empty() or (h2.normal as Vector3).y < 0.7:
			return fail
		top = h2.position
	var dy := top.y - global_position.y
	var flat_d := Vector2(top.x - global_position.x, top.z - global_position.z).length()
	# 鉤不到時繩子飛到實際打到的點再收回（不是飛去算出來的牆頂）
	fail.pos = p
	if absf(dy) < 0.8 or dy > 8.0 or dy < -10.0 or flat_d < 1.0 or global_position.distance_to(top) > hook_range:
		return fail
	# 關卡範圍外（外牆頂、牆外地面）不能鉤
	if hook_bounds.size != Vector3.ZERO and not hook_bounds.has_point(top):
		return fail
	return {"ok": true, "pos": top + Vector3(0.0, 0.05, 0.0)}


## 鉤繩：繩子先飛出去（看得到鉤頭飛行），到了再決定：
##   pull    → 鉤住敵人，把他拖過來（0.45 秒拖行，繩子一直連著）
##   grapple → 鉤住牆頂／屋頂，人飛過去
##   miss    → 鉤不到，繩子收回來
const HOOK_PULL_TIME := 0.45
var _hook_job := {}


func _hook_launch(kind: String, to: Vector3, target: Node3D = null, head: bool = false) -> void:
	var flat := to - global_position
	flat.y = 0.0
	if flat.length() > 0.01:
		_facing = atan2(-flat.x, -flat.z)
		visual.rotation.y = _facing
	var dist := global_position.distance_to(to)
	_hook_job = {"kind": kind, "t": 0.0, "dur": clampf(0.08 + dist * 0.008, 0.1, 0.26), "to": to, "target": target, "head": head}
	_lock_t = maxf(_lock_t, float(_hook_job.dur) + 0.05)
	Sfx.play(sfx_dash)
	# 甩繩姿勢
	if _guard_tw and _guard_tw.is_valid():
		_guard_tw.kill()
	sword_pivot.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	_guard_tw = create_tween()
	_guard_tw.set_ignore_time_scale(true)
	_guard_tw.tween_property(sword_pivot, "rotation_degrees", Vector3.ZERO, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _tick_hook_job(delta: float) -> void:
	if _hook_job.is_empty():
		return
	_hook_job.t += delta
	# 保險：任何鉤繩工作超過 1.5 秒（正常最長 0.26＋0.5 秒）一律收掉，繩子不准一直掛著
	if float(_hook_job.t) > 1.5:
		push_warning("hook job %s stuck, cleared" % String(_hook_job.get("kind", "?")))
		_hook_job = {}
		_rope_t = 0.0
		return
	var k := clampf(float(_hook_job.t) / float(_hook_job.dur), 0.0, 1.0)
	var hand := global_position + Vector3(0.0, 1.3, 0.0)
	var to: Vector3 = _hook_job.to
	match String(_hook_job.kind):
		"pull", "grapple", "miss":
			# 鉤頭飛出去
			_rope_show(hand.lerp(to, k), 0.05)
			if k < 1.0:
				return
			var kind := String(_hook_job.kind)
			var target: Node3D = _hook_job.target
			if kind == "grapple":
				_hook_job = {}
				_start_grapple_to(to)
			elif kind == "pull" and is_instance_valid(target) and target.has_method("hooked") and target.get("state") != target.State.DEAD:
				_hook_cd = HOOK_PULL_CD
				var dir := _forward()
				var head_hit := bool(_hook_job.head)
				var flat_d := Vector2(target.global_position.x - global_position.x, target.global_position.z - global_position.z).length()
				# 先把工作切到下一步，再去呼叫敵人：萬一敵人那邊出錯，這一步不會每幀重跑卡死
				if Progress.has_scroll("hook_fly") and flat_d > 6.0:
					# 飛鉤（卷軸）：對方太遠就是你飛過去，落地時他正硬直
					var to_me := global_position - target.global_position
					to_me.y = 0.0
					to_me = to_me.normalized() if to_me.length() > 0.01 else -dir
					var land := target.global_position + to_me * 1.5
					_hook_job = {}
					target.hooked(target.global_position, 15 if head_hit else 6, head_hit, self, 0.05)
					_start_grapple_to(land)
					return
				var dest := global_position + dir * 1.6
				_hook_job = {"kind": "pulling", "t": 0.0, "dur": HOOK_PULL_TIME + 0.05, "to": to, "target": target, "head": false}
				_lock_t = maxf(_lock_t, 0.25)
				target.hooked(dest, 15 if head_hit else 6, head_hit, self, HOOK_PULL_TIME)
				Feel.kick(dir, 0.3)
			else:
				# 鉤不到：收繩
				_hook_job = {"kind": "back", "t": 0.0, "dur": 0.2, "to": to, "target": null, "head": false}
		"pulling":
			# 繩子連在敵人身上，跟著他被拖過來
			var target: Node3D = _hook_job.target
			if is_instance_valid(target):
				_rope_show(target.global_position + Vector3(0.0, 1.2, 0.0), 0.05)
			if k >= 1.0:
				_hook_job = {}
		"back":
			_rope_show(to.lerp(hand, k), 0.05)
			if k >= 1.0:
				_hook_job = {}
				_rope_t = 0.0


func _rope_show(to: Vector3, dur: float) -> void:
	_rope_to = to
	_rope_t = dur


func _rope_update() -> void:
	if _rope_t <= 0.0:
		_rope.visible = false
		return
	_rope.visible = true
	var from := global_position + Vector3(0.0, 1.3, 0.0)
	var im: ImmediateMesh = _rope.mesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(from)
	im.surface_add_vertex(_rope_to)
	im.surface_end()


func _build_rope() -> void:
	_rope = MeshInstance3D.new()
	_rope.top_level = true
	_rope.mesh = ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.85, 0.8, 0.6)
	m.no_depth_test = true
	_rope.material_override = m
	_rope.visible = false
	add_child(_rope)


## 手裡劍：往瞄準方向射出；有鎖定目標就射向目標胸口。一次只能有一枚在空中。
func _throw(dir: Vector3, target: Node3D, head: bool = false) -> void:
	if shuriken <= 0:
		denied.emit("shuriken")
		return
	if is_instance_valid(_shuriken_in_flight) and _shuriken_in_flight.is_inside_tree() and not _shuriken_in_flight.get("stuck"):
		denied.emit("shuriken")
		return
	shuriken -= 1
	shuriken_changed.emit(shuriken)
	var from := global_position + Vector3(0.0, 1.3, 0.0)
	var d := dir
	if target:
		d = ((target.global_position + (Vector3(0.0, 1.68, 0.0) if head else Vector3(0.0, 1.1, 0.0))) - from).normalized()
	elif cam_rig != null and cam_rig.has_method("aim_ray"):
		# 準心射線打到的點（或 35 公尺外），手裡劍從手上飛向那一點
		var r: Array = cam_rig.aim_ray()
		var hit := _ray_visible(r[0], r[0] + r[1] * 35.0, 1 | 2)
		var aim_point: Vector3 = hit.position if not hit.is_empty() else r[0] + r[1] * 35.0
		d = (aim_point - from).normalized()
		# 快速點一下（鏡頭還沒切到過肩）、或準心打到的點離手太近／在身後：改朝鏡頭正前方平射，
		# 不然會射向俯視鏡頭中心打到的地面（看起來就是「準心和飛出去的位置不同」）
		var fwd: Vector3 = cam_rig.forward()
		if _aim_t < 0.2 or (aim_point - from).length() < 0.8 or d.dot(fwd) < 0.35:
			d = fwd
	var flat := Vector3(d.x, 0.0, d.z)
	if flat.length() > 0.01:
		_facing = atan2(-flat.x, -flat.z)
		visual.rotation.y = _facing
	var s := Shuriken.new()
	s.src = self
	get_tree().current_scene.add_child(s)
	s.launch(from + d * 0.6, d)
	_shuriken_in_flight = s
	sfx_swing.set_meta("sfx_base", 1.35)
	Sfx.play(sfx_swing)
	sfx_swing.set_meta("sfx_base", 1.0)
	# 投擲手勢：刀臂往前一甩再回位
	if _guard_tw and _guard_tw.is_valid():
		_guard_tw.kill()
	sword_pivot.rotation_degrees = Vector3(-30.0, -40.0, 0.0)
	_guard_tw = create_tween()
	_guard_tw.set_ignore_time_scale(true)
	_guard_tw.tween_property(sword_pivot, "rotation_degrees", Vector3.ZERO, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## 鉤繩：往落點飛一道弧線（0.5 秒，無敵）
func _start_grapple_to(dest: Vector3) -> void:
	state = State.GRAPPLE
	_grapple_t = 0.0
	_grapple_from = global_position
	_grapple_to = dest
	_invuln = true
	_queued = false
	trail.visible = false
	var flat := _grapple_to - _grapple_from
	flat.y = 0.0
	if flat.length() > 0.01:
		_facing = atan2(-flat.x, -flat.z)
		visual.rotation.y = _facing
	sword_pivot.rotation_degrees = Vector3.ZERO
	_rope_show(dest + Vector3(0.0, 0.5, 0.0), 0.5)
	Sfx.play(sfx_dash)
	Feel.kick(flat.normalized(), 0.25)


func _tick_grapple(delta: float) -> void:
	_grapple_t = minf(_grapple_t + delta / 0.5, 1.0)
	var k := _grapple_t
	var e := 1.0 - pow(1.0 - k, 2.0)
	var p := _grapple_from.lerp(_grapple_to, e)
	p.y += sin(k * PI) * 1.6
	global_position = p
	velocity = Vector3.ZERO
	body.rotation.x = -0.5
	if fmod(_grapple_t, 0.12) < delta / 0.5:
		Fx.afterimage(body, Color(0.6, 0.8, 1.0, 0.3), 0.2)
	if _grapple_t >= 1.0:
		global_position = _grapple_to
		_invuln = false
		body.rotation.x = 0.0
		state = _after_action()
		Feel.shake(0.25)


## 落下忍殺：空中按攻擊，對正下方附近未察覺的敵人一擊必殺
func _try_plunge() -> bool:
	var best: Node3D = null
	var best_d := 2.4
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node3D) or not e.has_method("can_be_assassinated"):
			continue
		var d: Vector3 = e.global_position - global_position
		var dy := -d.y
		d.y = 0.0
		if dy > 1.0 and d.length() < best_d and e.can_be_assassinated(self):
			best = e
			best_d = d.length()
	if best == null:
		return false
	var back: Vector3 = global_position - best.global_position
	back.y = 0.0
	back = back.normalized() if back.length() > 0.01 else -_forward()
	global_position = best.global_position + back * 0.8 + Vector3(0.0, 0.1, 0.0)
	velocity = Vector3.ZERO
	_facing = atan2(back.x, back.z)
	visual.rotation.y = _facing
	var info := {"dmg": 999, "dir": -back, "kb": 2.0, "heavy": true, "pos": best.global_position + Vector3(0.0, 1.4, 0.0), "src": self}
	best.assassinate(info)
	Feel.shake(0.9)
	Feel.kick(-back, 0.5)
	hit_landed.emit(info)
	sword_pivot.rotation_degrees = Vector3(70.0, 0.0, 0.0)
	_lock_t = 1.0
	return true


## 下劈（第九次議會）：離地 ≥1.5 公尺的空中按攻擊 → 鎖落點、加速下墜，落地對半徑 1.3 公尺內的敵人
## 固定 28 傷害、體幹兩倍、無視架刀（刀架不住頭頂；武士三分之一機率舉刀上頂把你彈開）。
## 落空硬直 0.5 秒，3 公尺內敵人全部警戒。落點畫地面環：壓到警戒敵人變紅。
const PLUNGE_MIN_HEIGHT := 1.5
const PLUNGE_DMG := 28
const PLUNGE_RADIUS := 1.3
const PLUNGE_LAND_LOCK := 0.5
var _plunge_target := Vector3.ZERO
var _plunge_landed := false
var _land_t := 0.0
var _plunge_ring: MeshInstance3D
var _plunge_ring_mat: StandardMaterial3D


func _ground_below() -> Dictionary:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0.0, 0.2, 0.0), global_position + Vector3(0.0, -40.0, 0.0), 1)
	q.exclude = [get_rid()]
	return space.intersect_ray(q)


func _can_plunge() -> bool:
	if velocity.y > 2.0:
		return false
	var hit := _ground_below()
	if hit.is_empty():
		return false
	if global_position.y - float(hit.position.y) < PLUNGE_MIN_HEIGHT:
		return false
	_plunge_target = hit.position
	return true


func _ensure_plunge_ring() -> void:
	if _plunge_ring:
		return
	_plunge_ring = MeshInstance3D.new()
	_plunge_ring.top_level = true
	var tm := TorusMesh.new()
	tm.inner_radius = PLUNGE_RADIUS - 0.18
	tm.outer_radius = PLUNGE_RADIUS
	tm.rings = 32
	tm.ring_segments = 6
	_plunge_ring.mesh = tm
	_plunge_ring_mat = StandardMaterial3D.new()
	_plunge_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_plunge_ring_mat.albedo_color = Color(1, 1, 1, 0.8)
	_plunge_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_plunge_ring.material_override = _plunge_ring_mat
	_plunge_ring.visible = false
	add_child(_plunge_ring)


func _start_plunge() -> void:
	state = State.PLUNGE
	_plunge_landed = false
	_land_t = 0.0
	_queued = false
	_invuln = false
	trail.visible = false
	velocity.x *= 0.3
	velocity.z *= 0.3
	if _guard_tw and _guard_tw.is_valid():
		_guard_tw.kill()
	sword_pivot.rotation_degrees = Vector3(-110.0, 0.0, 0.0)
	_ensure_plunge_ring()
	_plunge_ring.visible = true
	_plunge_ring.global_position = _plunge_target + Vector3(0.0, 0.06, 0.0)
	if cam_rig != null:
		cam_rig.set("extra_pitch", 0.26)
	Sfx.play(sfx_dash)


## 落點附近有沒有警戒中的敵人（地面環變紅）
func _plunge_victims() -> Array:
	var out: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node3D) or e.get("state") == null or e.state == e.State.DEAD:
			continue
		var d: Vector3 = e.global_position - _plunge_target
		if absf(d.y) > 1.6:
			continue
		d.y = 0.0
		if d.length() <= PLUNGE_RADIUS:
			out.append(e)
	return out


func _tick_plunge(delta: float) -> void:
	if not _plunge_landed:
		# 加速下墜（比自由落體快），水平微微修正到落點
		velocity.y = minf(velocity.y - 60.0 * delta, -6.0)
		velocity.y = maxf(velocity.y, -26.0)
		var to := _plunge_target - global_position
		to.y = 0.0
		velocity.x = to.x * 3.0
		velocity.z = to.z * 3.0
		body.rotation.x = lerpf(body.rotation.x, 0.6, 1.0 - exp(-12.0 * delta))
		_plunge_ring_mat.albedo_color = Color(1.0, 0.25, 0.2, 0.9) if _plunge_victims().size() > 0 else Color(1, 1, 1, 0.7)
		_plunge_ring.scale = Vector3.ONE * (1.0 + 0.08 * sin(Time.get_ticks_msec() * 0.02))
		if is_on_floor():
			_plunge_land()
		return
	_land_t += delta
	velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
	body.rotation.x = lerpf(body.rotation.x, 0.35, 1.0 - exp(-10.0 * delta))
	sword_pivot.rotation_degrees = sword_pivot.rotation_degrees.lerp(Vector3(40.0, 0.0, 0.0), 1.0 - exp(-14.0 * delta))
	if _land_t >= PLUNGE_LAND_LOCK:
		body.rotation.x = 0.0
		state = _after_action()


func _plunge_land() -> void:
	_plunge_landed = true
	_land_t = 0.0
	velocity = Vector3.ZERO
	_plunge_ring.visible = false
	if cam_rig != null:
		cam_rig.set("extra_pitch", 0.0)
	var victims := _plunge_victims()
	var hit_any := false
	for e in victims:
		var dir: Vector3 = e.global_position - global_position
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.01 else _forward()
		_facing = atan2(-dir.x, -dir.z)
		visual.rotation.y = _facing
		if e.has_method("can_be_assassinated") and e.can_be_assassinated(self):
			e.assassinate({"dmg": 999, "dir": dir, "kb": 2.0, "heavy": true, "pos": e.global_position + Vector3(0.0, 1.4, 0.0), "src": self})
			hit_any = true
			continue
		var info := {"dmg": PLUNGE_DMG, "dir": dir, "kb": Feel.get_p("knockback") * 1.2, "heavy": true, "pos": e.global_position + Vector3(0.0, 1.3, 0.0), "src": self, "from_above": true}
		e.take_hit(info)
		hit_landed.emit(info)
		hit_any = true
	if hit_any:
		Feel.hitstop(1.4)
		Feel.shake(0.9)
		Feel.kick(Vector3.DOWN, 0.4)
		Sfx.play(sfx_heavy)
		Feel.haptic(60)
	else:
		Feel.shake(0.35)
		Sfx.play(sfx_dash)
	# 落地的動靜：3 公尺內的敵人全部警戒，更遠的過來查看
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node3D and e.has_method("_go_alert") and e.global_position.distance_to(global_position) < 3.0:
			e._go_alert()
	get_tree().call_group("enemies", "hear_noise", global_position, 7.0)
	_burst_spark(global_position + Vector3(0.0, 0.2, 0.0), Vector3.UP, 0.8)


## 武士舉刀上頂把下劈彈開：人往後彈、硬直 0.6 秒、自己吃一段體幹
func plunge_parried(by: Node3D) -> void:
	var away := global_position - by.global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else -_forward()
	velocity = away * 7.0 + Vector3(0.0, 3.0, 0.0)
	_plunge_landed = true
	_land_t = -0.1
	_lock_t = maxf(_lock_t, 0.6)
	_add_posture(25.0, by)
	Feel.kick(away, 0.5)
	Feel.shake(0.6)


## 吃口糧：血快滿就帶著（上限看卷軸），血量低於三成自動吃。回傳 true＝直接回血、false＝帶著
func heal(v: int) -> bool:
	if hp >= max_hp - 5 and rations < Progress.ration_max():
		rations += 1
		rations_changed.emit(rations)
		return false
	hp = mini(hp + v, max_hp)
	hp_changed.emit(hp)
	_flash_hp(Color(0.6, 1.0, 0.6))
	return true


func _tick_rations() -> void:
	if rations <= 0 or hp >= int(max_hp * 0.3) or state in [State.HURT, State.DEAD, State.BROKEN]:
		return
	rations -= 1
	rations_changed.emit(rations)
	hp = mini(hp + 35, max_hp)
	hp_changed.emit(hp)
	_flash_hp(Color(0.6, 1.0, 0.6))


func _flash_hp(color: Color) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("flash_hp"):
		hud.flash_hp(color)


## 上次套用時的手裡劍上限：卷軸把上限拉高時，多出來的枚數當場發給玩家（不是等檢查點才補）
var _shuriken_cap := 5


## 進度（念珠、卷軸）套用到角色：最大 HP、手裡劍上限
func refresh_progress() -> void:
	var was_max := hp >= max_hp
	max_hp = Progress.max_hp()
	if was_max:
		hp = max_hp
	hp = mini(hp, max_hp)
	hp_changed.emit(hp)
	var cap := Progress.shuriken_max()
	if cap > _shuriken_cap:
		shuriken += cap - _shuriken_cap
	_shuriken_cap = cap
	shuriken = mini(shuriken, cap)
	shuriken_changed.emit(shuriken)


## 檢查點／復活：補滿手裡劍
func refill_shuriken() -> void:
	shuriken = Progress.shuriken_max()
	shuriken_changed.emit(shuriken)
	refill_smoke()


## 撿回射出的手裡劍
func pickup_shuriken() -> void:
	shuriken = mini(shuriken + 1, Progress.shuriken_max())
	shuriken_changed.emit(shuriken)


## 敵人格擋了我的刀（武士架刀）：體幹累積、刀被震開、鏡頭回踢
func on_attack_blocked(by: Node) -> void:
	_add_posture(POSTURE_BLOCKED, by)
	Feel.kick(-_forward(), 0.3)
	var tip := sword_pivot.to_global(Vector3(0.38, 0.0, -1.1))
	_burst_spark(tip, -_forward(), 0.7)
	body.scale = Vector3(1.08, 0.94, 1.08)
	if _jolt_tw and _jolt_tw.is_valid():
		_jolt_tw.kill()
	_jolt_tw = create_tween()
	_jolt_tw.set_ignore_time_scale(true)
	_jolt_tw.tween_property(body, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## 體幹累積。多敵圍攻：1 秒內第二個以上不同敵人造成的體幹傷害打 0.5 折；崩壞後 3 秒免疫。
func _add_posture(v: float, src: Node) -> void:
	if state == State.DEAD or state == State.BROKEN:
		return
	if v > 0.0:
		if _posture_immune_t > 0.0:
			return
		var now := Time.get_ticks_msec()
		_posture_sources = _posture_sources.filter(func(s: Array) -> bool: return now - int(s[1]) < 1000)
		var other := false
		for s in _posture_sources:
			if s[0] != src:
				other = true
		if other:
			v *= 0.5
		_posture_sources.append([src, now])
		_posture_delay = 1.5
	posture = clampf(posture + v, 0.0, MAX_POSTURE)
	posture_changed.emit(posture, MAX_POSTURE)
	if posture >= MAX_POSTURE:
		_break_posture()


func _tick_posture(delta: float) -> void:
	_posture_delay -= delta
	if _posture_immune_t > 0.0:
		_posture_immune_t -= delta
	if state == State.BROKEN or _posture_delay > 0.0 or posture <= 0.0:
		return
	posture = maxf(posture - POSTURE_REGEN * delta * (0.5 if state == State.BLOCK else 1.0), 0.0)
	posture_changed.emit(posture, MAX_POSTURE)


## 體幹崩壞：2.5 秒無法行動、無法格擋（敵人可以自由攻擊）
func _break_posture() -> void:
	state = State.BROKEN
	_broken_t = 0.0
	_queued = false
	_block_held = false
	trail.visible = false
	_invuln = false
	if aim_mode != AIM_NONE:
		_release_aim_silent()
	velocity.x *= 0.2
	velocity.z *= 0.2
	if _guard_tw and _guard_tw.is_valid():
		_guard_tw.kill()
	sword_pivot.rotation_degrees = Vector3(30.0, 60.0, 0.0)
	Sfx.play(sfx_hurt)
	Feel.hitstop(1.2)
	Feel.shake(1.2)
	Feel.flash(Color(1.0, 0.6, 0.2, 0.3), 0.3)
	posture_broken.emit()


func _tick_broken(delta: float) -> void:
	_broken_t += delta
	velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
	# 跪下喘氣：身體前傾、上下起伏
	body.rotation.x = lerpf(body.rotation.x, 0.55, 1.0 - exp(-10.0 * delta))
	visual.position.y = lerpf(visual.position.y, -0.35 + sin(_broken_t * 9.0) * 0.03, 1.0 - exp(-10.0 * delta))
	if _broken_t >= POSTURE_BREAK_TIME:
		posture = 0.0
		_posture_immune_t = 3.0
		_posture_delay = 0.0
		posture_changed.emit(posture, MAX_POSTURE)
		visual.position.y = 0.0
		state = _after_action()


func _release_aim_silent() -> void:
	aim_mode = AIM_NONE
	aim_status = ""
	_aim_target = null
	if cam_rig != null:
		cam_rig.aiming = false


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


func _tick_block(delta: float, input: Vector3) -> void:
	var dir := input * (0.5 if submerged else 1.0)
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
## 0.6 秒內最多兩次；第三次起 0.8 秒不可閃（連按閃步不是無限滾）。
func request_dash() -> void:
	if _lock_t > 0.0:
		return
	if state == State.FREE or state == State.BLOCK or (state == State.ATTACK and _phase != 1):
		if _dash_lock_t > 0.0:
			denied.emit("dash")
			return
		var now := Time.get_ticks_msec()
		_dash_times = _dash_times.filter(func(t: int) -> bool: return now - t < int(DASH_BURST_WINDOW * 1000.0))
		_dash_times.append(now)
		# 連閃第二次的瞬間就開始 0.8 秒冷卻（按鍵立刻顯示倒數；以前要等第三下被擋才出現倒數，看起來像「倒數中還能閃」）
		if _dash_times.size() >= DASH_BURST:
			_dash_times.clear()
			_dash_lock_t = DASH_LOCKOUT
		_start_dash()


## 看門狗：任何一個「應該幾秒內結束」的狀態卡太久（例：鉤繩目標被釋放、tween 被殺、事件遺失），
## 強制回到待機，寧可動作怪一下也不要整個人卡死要重新整理。
const STATE_LIMIT := {State.ATTACK: 3.0, State.DASH: 1.0, State.HURT: 2.0, State.GRAPPLE: 2.5, State.BROKEN: POSTURE_BREAK_TIME + 1.0, State.PLUNGE: 4.0}
var _state_t := 0.0
var _state_last := -1


func _watchdog(delta: float) -> void:
	if state != _state_last:
		_state_last = state
		_state_t = 0.0
	else:
		_state_t += delta
	_lock_t = minf(_lock_t, 2.0)
	# 瞄準按著超過 15 秒：手指事件大概掉了，放開
	if aim_mode != AIM_NONE and _aim_t > 15.0:
		_release_aim_silent()
	var stuck := STATE_LIMIT.has(state) and _state_t > float(STATE_LIMIT[state])
	if state == State.BLOCK and not _block_held and _state_t > 1.0:
		stuck = true
	if not stuck:
		return
	push_warning("player watchdog: state %s stuck %.1fs, reset" % [State.keys()[state], _state_t])
	state = State.FREE
	if _plunge_ring:
		_plunge_ring.visible = false
	if cam_rig != null:
		cam_rig.set("extra_pitch", 0.0)
	_invuln = false
	_lock_t = 0.0
	_hook_job = {}
	_rope_t = 0.0
	_queued = false
	body.rotation.x = 0.0
	visual.position.y = 0.0
	trail.visible = false
	if aim_mode != AIM_NONE:
		_release_aim_silent()


func _physics_process(delta: float) -> void:
	_watchdog(delta)
	_update_light_disc(delta)
	_update_water(delta)
	_update_ctx()
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
		State.DEAD:
			velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		State.GRAPPLE:
			_tick_grapple(delta)
		State.BROKEN:
			_tick_broken(delta)
		State.PLUNGE:
			_tick_plunge(delta)
	_tick_posture(delta)
	_tick_rations()
	_lock_t -= delta
	_dash_lock_t -= delta
	_hook_cd -= delta
	if state == State.GRAPPLE:
		velocity = Vector3.ZERO
	elif not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = 0.0
	# 先移動再處理鉤繩／繩子：這兩段會呼叫到敵人，萬一那邊出錯，至少這一幀的移動已經做完，人不會釘在原地
	move_and_slide()
	_tick_hook_job(delta)
	_rope_t -= delta
	_rope_update()
	if aim_mode != AIM_NONE and state != State.FREE:
		_release_aim_silent()
	if not _hook_job.is_empty() and state in [State.HURT, State.DEAD, State.BROKEN]:
		_hook_job = {}
		_rope_t = 0.0
	if state != State.ATTACK and _combo_window > 0.0:
		_combo_window -= delta
		if _combo_window <= 0.0:
			_combo_idx = 0


## 讀搖桿/鍵盤，轉成「相對鏡頭」的世界方向（搖桿往上 = 往畫面深處）
func _read_input() -> Vector3:
	var v := Vector2.ZERO
	if touch != null:
		v = touch.move_vector
	var kb := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if kb.length_squared() > v.length_squared():
		v = kb
	v = v.limit_length(1.0)
	var yaw: float = cam_rig.yaw if cam_rig != null else 0.0
	return Vector3(v.x, 0.0, v.y).rotated(Vector3.UP, yaw)


func _forward() -> Vector3:
	return Vector3(-sin(_facing), 0.0, -cos(_facing))


func _face_input(input: Vector3, snap: bool) -> void:
	if input.length() > 0.2:
		_facing = atan2(-input.x, -input.z)
		if snap:
			visual.rotation.y = _facing


func _tick_free(delta: float, input: Vector3) -> void:
	if aim_mode != AIM_NONE:
		_tick_aim(delta)
		return
	var dir := input * (0.5 if submerged else 1.0)
	velocity.x = move_toward(velocity.x, dir.x * SPEED, ACCEL * delta)
	velocity.z = move_toward(velocity.z, dir.z * SPEED, ACCEL * delta)
	_face_input(input, false)
	visual.rotation.y = lerp_angle(visual.rotation.y, _facing, 1.0 - exp(-16.0 * delta))
	var spd := Vector2(velocity.x, velocity.z).length() / SPEED
	body.rotation.x = lerpf(body.rotation.x, -0.14 * spd, 1.0 - exp(-10.0 * delta))
	visual.position.y = sin(Time.get_ticks_msec() * 0.006) * 0.025 * (1.0 + spd * 2.0)
	# 全速奔跑有靴聲：附近未警戒的敵人會過來查看（潛行要放慢搖桿）
	_run_noise_t -= delta
	if spd > 0.85 and is_on_floor() and _run_noise_t <= 0.0:
		_run_noise_t = 0.4
		get_tree().call_group("enemies", "hear_noise", global_position, RUN_NOISE_RADIUS)
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


func _tick_attack(delta: float, _input: Vector3) -> void:
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
		# 未察覺的敵人從背後砍 = 暗殺（一擊必殺、無聲）；之後 1 秒硬直
		if tgt.has_method("can_be_assassinated") and tgt.can_be_assassinated(self):
			tgt.assassinate(info)
			Feel.shake(0.6)
			hit_landed.emit(info)
			_lock_t = 1.0
			_queued = false
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
		_dash_dir = input.normalized()
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


## 被打到（閃步中無敵）。「危」技（unblockable）不能格擋，只能閃。
func take_hit(info: Dictionary) -> void:
	if _invuln or state == State.HURT or state == State.DEAD:
		return
	var unblockable: bool = info.get("unblockable", false)
	if state == State.BLOCK and not unblockable and _forward().dot(-(info.dir as Vector3)) > 0.2:
		_blocked_hit(info)
		return
	var was_broken := state == State.BROKEN
	var dmg := int(info.dmg)
	if was_broken:
		# 體幹崩壞中挨刀：1.5 倍傷害（崩壞就是會死人的）
		dmg = int(dmg * 1.5)
	hp = maxi(hp - dmg, 0)
	hp_changed.emit(hp)
	damaged.emit(dmg)
	if not was_broken:
		_add_posture(POSTURE_HIT, info.get("src"))
	if state == State.BROKEN and hp > 0:
		# 崩壞中被打：只扣血、不脫離崩壞（敵人的獎勵時間）
		_hurt_fx(info)
		return
	if state == State.BROKEN:
		visual.position.y = 0.0
	state = State.HURT
	_hurt_t = 0.0
	_queued = false
	trail.visible = false
	var dir: Vector3 = info.dir
	velocity.x = dir.x * 7.0
	velocity.z = dir.z * 7.0
	_hurt_fx(info)
	if hp <= 0:
		_die(dir)
		died.emit()


func _hurt_fx(info: Dictionary) -> void:
	var dir: Vector3 = info.dir
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


## 敗北：往受擊方向倒下，刀落地；由關卡決定重來或由道場 revive()
func _die(dir: Vector3) -> void:
	state = State.DEAD
	_block_held = false
	trail.visible = false
	velocity.x = dir.x * 3.0
	velocity.z = dir.z * 3.0
	_facing = atan2(dir.x, dir.z)   # 面向攻擊來源，往後倒
	visual.rotation.y = _facing
	if _jolt_tw and _jolt_tw.is_valid():
		_jolt_tw.kill()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(visual, "rotation:x", 1.5, 0.55).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(visual, "position:y", -0.25, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(sword_pivot, "rotation_degrees", Vector3(40.0, 70.0, 20.0), 0.5)
	tw.tween_property(body, "rotation:x", 0.0, 0.3)


## 道場／檢查點用：原地復活（補滿血、體幹歸零、手裡劍補滿）
func revive() -> void:
	max_hp = Progress.max_hp()
	hp = max_hp
	posture = 0.0
	_posture_immune_t = 0.0
	_posture_sources.clear()
	_lock_t = 0.0
	_dash_lock_t = 0.0
	_hook_cd = 0.0
	_block_held = false
	hp_changed.emit(hp)
	posture_changed.emit(posture, MAX_POSTURE)
	refill_shuriken()
	body.rotation.x = 0.0
	visual.rotation = Vector3(0.0, _facing, 0.0)
	visual.position = Vector3.ZERO
	sword_pivot.rotation_degrees = Vector3.ZERO
	sword_pivot.position = PIVOT_HOME
	state = State.FREE


## 格擋（隻狼式）
## 一般格擋：刀被震開一下、小火花、小後退，不扣血。
## 彈反：舉刀後 parry_ms 內擋下 → 刀向外一撥、大片火花、閃白、長頓幀，對方後仰並累積「體幹」。
func _blocked_hit(info: Dictionary) -> void:
	var dir: Vector3 = info.dir
	var ranged: bool = info.get("ranged", false)
	var perfect: bool = (not ranged) and Time.get_ticks_msec() - _block_start_ms <= int(Feel.get_p("parry_ms"))
	var src = info.get("src")
	# 普通格擋：體幹 +10（連擋會崩）；完美彈反：體幹 −10
	_add_posture(POSTURE_DEFLECT if perfect else POSTURE_GUARD, src)
	if state == State.BROKEN:
		# 這一擋把體幹擋滿了：崩壞，不扣血但接下來 2.5 秒任人宰割
		return
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
	# 兩把刀的交擊點：在我和對方中間偏我這邊（火花在那裡迸，不是在我刀尖上）
	if src is Node3D:
		var sp: Vector3 = (src as Node3D).global_position
		tip = global_position.lerp(sp, 0.4) + Vector3(0.0, 1.25, 0.0)
		# 轉身迎刀：格擋的瞬間面向來刀的人
		var face := sp - global_position
		face.y = 0.0
		if face.length() > 0.1:
			_facing = atan2(-face.x, -face.z)
			visual.rotation.y = _facing
	# 對方也要有反應：刀被彈回、人被推半步（普通格擋小、彈反由 deflected 處理）
	if not perfect and src and src.has_method("on_guarded"):
		src.on_guarded(dir)
	Feel.haptic(50 if perfect else 20)
	# 身體被壓得往後仰一下再回來（看得出在「頂住」對方）
	visual.rotation.x = -0.22 if not perfect else 0.12
	var lean := create_tween()
	lean.set_ignore_time_scale(true)
	lean.tween_property(visual, "rotation:x", 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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
