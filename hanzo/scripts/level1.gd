extends Node3D
## 第一關：伊賀夜襲。
## 山門 → 第一院（足輕×2 巡邏、弓兵×1）→ 窄道 → 第二院（武士巡邏）→ 小屋（目標武將，背對門）。
## 暗殺武將後回山門撤離。死亡可重來；撤離後結算。
##
## 截圖：godot --path hanzo ++ --shot=<dir> [--walk]   （--walk：往北走 6 秒，每 2 秒截一張）

const WALL_H := 2.6
const EXIT_POS := Vector3(0.0, 0.0, 29.0)
const TARGET_POS := Vector3(0.0, 0.0, -18.0)

## [中心x, 中心z, 寬x, 長z]
const WALLS := [
	[-13.0, 4.5, 1.0, 58.0], [13.0, 4.5, 1.0, 58.0], [0.0, -23.5, 27.0, 1.0], [0.0, 32.5, 27.0, 1.0],
	[-8.75, 24.0, 7.5, 12.0], [8.75, 24.0, 7.5, 12.0],
	[-8.0, 4.0, 10.0, 1.0], [8.0, 4.0, 10.0, 1.0],
	[-8.0, -1.0, 10.0, 10.0], [8.0, -1.0, 10.0, 10.0],
	[0.0, -20.6, 6.4, 0.6], [-3.0, -18.0, 0.6, 5.2], [3.0, -18.0, 0.6, 5.2],
	[-6.0, 11.0, 2.0, 2.0], [5.0, 14.5, 2.0, 2.0], [-5.0, -10.0, 2.0, 2.0], [7.0, -12.5, 2.0, 2.0],
	[-10.5, 8.0, 1.5, 1.5], [10.5, 15.0, 1.5, 1.5],
]
const LANTERNS := [
	Vector3(-10.5, 0, 16.5), Vector3(10.5, 0, 6.0), Vector3(-10.5, 0, -8.0), Vector3(10.0, 0, -20.0),
	Vector3(-2.2, 0, -15.2), Vector3(2.2, 0, -15.2), Vector3(3.6, 0, 27.0),
]

@onready var player: CharacterBody3D = $Player
@onready var cam_rig: Node3D = $CameraRig
@onready var hud: CanvasLayer = $HUD

var _enemies: Array = []
var _target: Enemy
var _target_dead := false
var _finished := false
var _dead := false
var _time := 0.0
var _hits_taken := 0
var _stealth_kills := 0
var _kills := 0
var _alert_count := 0
var _exit_beacon: Node3D
var _lanterns: Array = []
var _shot_dir := ""
var _walk := false
var _walk_t := 0.0
var _walk_shots := 0
var _auto_done := {}


func _ready() -> void:
	$Moon.rotation_degrees = Vector3(-52.0, 25.0, 0.0)
	hud.attach(player, cam_rig)
	player.died.connect(_on_player_died)
	player.damaged.connect(func(_a: int) -> void:
		_hits_taken += 1)
	_build_world()
	_spawn_enemies()
	hud.set_objective("潛入山村，暗殺今川家的武將")
	hud.set_compass_target(TARGET_POS, Color(1.0, 0.8, 0.3))
	hud.say("伊賀夜襲", Color(0.95, 0.9, 0.8))
	_warmup()
	_parse_args()


func _warmup() -> void:
	await get_tree().process_frame
	player.warmup()
	Fx.warmup(player.global_position + Vector3(0, 1.5, 0), player.body)


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot_dir = a.substr(7)
		elif a == "--walk":
			_walk = true
	if _shot_dir != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			await _shot("idle")
			if not _walk:
				get_tree().quit())


func _process(delta: float) -> void:
	if not _finished and not _dead:
		_time += delta
	if _walk:
		# 自動試玩：走到東側牆頂鉤繩點下方 → 轉鏡頭朝東 → 鉤上牆頂 → 投手裡劍 → 每段截圖
		_walk_t += delta
		hud.touch.move_vector = Vector2(0.0, -1.0) if _walk_t < 1.3 else Vector2.ZERO
		if _walk_t > 1.35 and not _auto_done.has("look"):
			_auto_done["look"] = true
			cam_rig.yaw = -PI / 2.0
		if _walk_t > 1.7 and not _auto_done.has("grapple"):
			_auto_done["grapple"] = true
			player.request_hook()
		if _walk_t > 2.4 and not _auto_done.has("shot_grapple"):
			_auto_done["shot_grapple"] = true
			_shot("grapple")
		if _walk_t > 3.2 and not _auto_done.has("throw"):
			_auto_done["throw"] = true
			cam_rig.yaw = PI
			player.toggle_weapon()
			player.request_throw()
		if _walk_t > 3.5 and not _auto_done.has("shot_throw"):
			_auto_done["shot_throw"] = true
			_shot("throw")
		if _walk_t > 6.0 and not _auto_done.has("shot_end"):
			_auto_done["shot_end"] = true
			_shot("end")
		if _walk_t > 6.5:
			get_tree().quit()


func _physics_process(_delta: float) -> void:
	# 玩家是否站在燈光下（敵人視野據此縮放）
	var lit := false
	for l in _lanterns:
		if l.lights(player.global_position):
			lit = true
			break
	player.in_light = lit
	if _target_dead and not _finished and not _dead:
		var d := player.global_position - EXIT_POS
		d.y = 0.0
		if d.length() < 3.0:
			_finish()


func _shot(name: String) -> void:
	if _shot_dir == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s.png" % [_shot_dir, name])
	img.save_png(path)
	print("shot: ", path)


# ---------------------------------------------------------------- 世界

func _build_world() -> void:
	var region := NavigationRegion3D.new()
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 2.0
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	# 執行期烘焙：只解析碰撞形狀（解析視覺網格要把資料從 GPU 讀回來，會卡）
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	region.navigation_mesh = nm
	add_child(region)

	# 地面
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	ground.collision_mask = 0
	var gm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.17, 0.17, 0.16)
	gmat.roughness = 1.0
	gm.mesh = pm
	gm.material_override = gmat
	ground.add_child(gm)
	var gs := CollisionShape3D.new()
	var gshape := BoxShape3D.new()
	gshape.size = Vector3(80, 1, 80)
	gs.shape = gshape
	gs.position = Vector3(0, -0.5, 0)
	ground.add_child(gs)
	region.add_child(ground)

	# 牆與遮蔽物
	var wall_mesh_mat := StandardMaterial3D.new()
	wall_mesh_mat.albedo_color = Color(0.3, 0.26, 0.22)
	wall_mesh_mat.roughness = 1.0
	for w in WALLS:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(w[2], WALL_H, w[3])
		mi.mesh = bm
		mi.material_override = wall_mesh_mat
		sb.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = bm.size
		cs.shape = bs
		sb.add_child(cs)
		sb.position = Vector3(w[0], WALL_H / 2.0, w[1])
		region.add_child(sb)

	# 燈籠
	for p in LANTERNS:
		var l := Lantern.new()
		add_child(l)
		l.global_position = p
		_lanterns.append(l)

	# 屋頂與鉤繩點（立體路線）
	_slab(0.0, -18.0, 6.8, 5.6, 2.75)

	# 撤離點信標（暗殺後才亮）
	_exit_beacon = Node3D.new()
	add_child(_exit_beacon)
	_exit_beacon.position = EXIT_POS
	var pillar := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.9
	cyl.bottom_radius = 0.9
	cyl.height = 6.0
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.albedo_color = Color(0.4, 0.8, 1.0, 0.2)
	pillar.mesh = cyl
	pillar.material_override = bmat
	pillar.position = Vector3(0, 3.0, 0)
	_exit_beacon.add_child(pillar)
	var lbl := Label3D.new()
	lbl.text = "撤離"
	lbl.font = Fx.ui_font
	lbl.font_size = 96
	lbl.pixel_size = 0.014
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.outline_size = 12
	lbl.modulate = Color(0.6, 0.9, 1.0)
	lbl.position = Vector3(0, 3.2, 0)
	_exit_beacon.add_child(lbl)
	_exit_beacon.visible = false

	region.bake_navigation_mesh(false)


## 可站立的平板（屋頂）
func _slab(cx: float, cz: float, sx: float, sz: float, y: float) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(sx, 0.3, sz)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.18, 0.16)
	mi.mesh = bm
	mi.material_override = mat
	sb.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = bm.size
	cs.shape = bs
	sb.add_child(cs)
	add_child(sb)
	sb.position = Vector3(cx, y, cz)




# ---------------------------------------------------------------- 敵人

func _spawn_enemies() -> void:
	_spawn(Enemy.Kind.ASHIGARU, Vector3(-8, 0, 15), [Vector3(-8, 0, 15), Vector3(-8, 0, 7), Vector3(1, 0, 7), Vector3(1, 0, 15)])
	_spawn(Enemy.Kind.ASHIGARU, Vector3(8, 0, 8), [Vector3(8, 0, 8), Vector3(8, 0, 16), Vector3(-1, 0, 17)])
	_spawn(Enemy.Kind.ARCHER, Vector3(9.5, 0, 10), [], Vector3(-1, 0, 0))
	_spawn(Enemy.Kind.SAMURAI, Vector3(-8, 0, -9), [Vector3(-8, 0, -9), Vector3(8, 0, -9), Vector3(8, 0, -13), Vector3(-8, 0, -13)])
	_target = _spawn(Enemy.Kind.TARGET, TARGET_POS, [], Vector3(0, 0, -1))


func _spawn(kind: Enemy.Kind, pos: Vector3, route: Array, face := Vector3.FORWARD) -> Enemy:
	var e := Enemy.new()
	e.kind = kind
	e.patrol = route
	e.face_dir = face
	add_child(e)
	e.global_position = pos + Vector3(0, 0.1, 0)
	e.died.connect(_on_enemy_died)
	e.alerted.connect(_on_enemy_alerted)
	_enemies.append(e)
	return e


func _on_enemy_alerted(_e: Enemy) -> void:
	_alert_count += 1
	if _alert_count == 1:
		hud.say("被發現了！", Color(1.0, 0.4, 0.3))


func _on_enemy_died(e: Enemy, stealth: bool) -> void:
	_kills += 1
	# 忍者口糧：目標必掉，其他 35% 機率
	if e == _target or randf() < 0.35:
		var r := Ration.new()
		add_child(r)
		r.global_position = e.global_position
	if stealth:
		_stealth_kills += 1
		hud.add_kill("暗殺", Color(0.85, 0.85, 0.95))
	else:
		hud.add_kill()
	if e == _target and not _target_dead:
		_target_dead = true
		_exit_beacon.visible = true
		hud.set_objective("目標已除。回到南邊山門撤離")
		hud.set_compass_target(EXIT_POS, Color(0.6, 0.9, 1.0))
		get_tree().create_timer(1.2).timeout.connect(func() -> void:
			hud.say("撤離！", Color(0.6, 0.9, 1.0)))


# ---------------------------------------------------------------- 結束

func _on_player_died() -> void:
	if _dead or _finished:
		return
	_dead = true
	hud.say("敗北…", Color(0.9, 0.3, 0.3))
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		hud.show_overlay("敗北", ["時間 %s　擊破 %d　被擊中 %d 次" % [_fmt_time(_time), _kills, _hits_taken]],
			[["再來一次", func() -> void: get_tree().reload_current_scene()],
			 ["回標題", func() -> void: get_tree().change_scene_to_file("res://scenes/title.tscn")]],
			Color(0.95, 0.3, 0.3)))


func _finish() -> void:
	_finished = true
	var rank := _rank()
	hud.say("任務完成", Color(0.95, 0.9, 0.6))
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		hud.show_overlay("任務完成　評價 %s" % rank, [
			"時間 %s" % _fmt_time(_time),
			"擊破 %d（暗殺 %d）　被擊中 %d 次　被發現 %d 次" % [_kills, _stealth_kills, _hits_taken, _alert_count],
			_rank_comment(rank),
		], [["再玩一次", func() -> void: get_tree().reload_current_scene()],
			["回標題", func() -> void: get_tree().change_scene_to_file("res://scenes/title.tscn")]],
			Color(1.0, 0.9, 0.5)))


func _rank() -> String:
	if _hits_taken == 0 and _alert_count == 0:
		return "影"
	if _hits_taken <= 1 and _time < 150.0:
		return "S"
	if _hits_taken <= 3 and _time < 240.0:
		return "A"
	if _hits_taken <= 6:
		return "B"
	return "C"


func _rank_comment(r: String) -> String:
	match r:
		"影": return "無人察覺，無傷而歸。真正的忍者。"
		"S": return "幾近完美。"
		"A": return "俐落。試試全程不被發現。"
		"B": return "完成了，但傷痕不少。多用格擋與閃步。"
	return "活著回來就好。下次試著從背後接近。"


func _fmt_time(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]
