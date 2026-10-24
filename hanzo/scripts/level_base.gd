extends Node3D
## 關卡共用骨架（各關用 extends "res://scripts/level_base.gd" 繼承；不用 class_name，避免快取沒更新時解析失敗）：世界建構工具（地面、台地、斜坡、牆、透明牆、小屋、切妻屋頂、櫓、樹、鳥居、
## 石燈籠、障子、門）、敵人生成、檢查點／重生、燈光判定、結算與評價、自動試玩 bot。
## 各關只要覆寫 _build_world() / _spawn_enemies() 和幾個常數。

@onready var player: CharacterBody3D = $Player
@onready var cam_rig: Node3D = $CameraRig
@onready var hud: CanvasLayer = $HUD

## 子類別設定
var level_title := ""
var objective_text := ""
var start_pos := Vector3(0.0, 0.1, 0.0)
var exit_pos := Vector3.ZERO
var checkpoints: Array = []
var next_scene := ""
var next_label := "下一關"
var bounds := AABB(Vector3(-20, -2, -40), Vector3(40, 30, 80))

var _region: NavigationRegion3D
## 遮蔽層：半藏走進某個範圍（屋簷下、樓下）時，把該範圍上方的屋頂／樓板隱藏，鏡頭才看得到室內
var _covers := {}
var _cover_key := ""
var _enemies: Array = []
var _lanterns: Array = []
var _gates := {}
var _mats := {}
var _target_dead := false
var _bead_given := false
var _exit_ready := false
var _exit_beacon: Node3D
var _finished := false
var _dead := false
var _time := 0.0
var _hits_taken := 0
var _stealth_kills := 0
var _kills := 0
var _alert_count := 0
var _checkpoint := Vector3.ZERO
var _cp_index := 0
var _shot_dir := ""
var _bot: Node = null
var _bot_mode := ""
var _bot_runs := 20
var _extra_args: Array = []


func _ready() -> void:
	hud.attach(player, cam_rig)
	player.died.connect(_on_player_died)
	player.damaged.connect(func(_a: int) -> void:
		_hits_taken += 1)
	_parse_args()
	_checkpoint = start_pos
	player.global_position = start_pos
	# 玩家傳送後鏡頭立刻定位；再用黑幕蓋住開場的著色器預熱（火花、刀光），淡入 0.45 秒
	cam_rig.snap_to_target()
	hud.curtain(0.45)
	player.hook_bounds = bounds
	_nav_begin()
	_build_world()
	_build_exit_beacon()
	_nav_end()
	if _bot_mode != "":
		_start_bot()
		return
	_spawn_enemies()
	if objective_text != "":
		hud.set_objective(objective_text)
	if level_title != "":
		hud.say(level_title, Color(0.95, 0.9, 0.8))
	_warmup()
	_on_level_ready()


## 子類別覆寫
func _build_world() -> void:
	pass


func _spawn_enemies() -> void:
	pass


func _on_level_ready() -> void:
	pass


func _on_enemy_died_hook(_e: Enemy, _stealth: bool) -> void:
	pass


func _warmup() -> void:
	await get_tree().process_frame
	player.warmup()
	Fx.warmup(player.global_position + Vector3(0, 1.5, 0), player.body)


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot_dir = a.substr(7)
		elif a.begins_with("--bot="):
			_bot_mode = a.substr(6)
		elif a.begins_with("--runs="):
			_bot_runs = int(a.substr(7))
		else:
			_extra_args.append(a)
	if _shot_dir != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
		var scripted := false
		for a in _extra_args:
			if a == "--walk" or a.begins_with("--tour="):
				scripted = true
		if not scripted:
			get_tree().create_timer(1.0).timeout.connect(func() -> void:
				await _shot("idle")
				get_tree().quit())


func _start_bot() -> void:
	var b: Node = preload("res://scripts/bot.gd").new()
	b.mode = _bot_mode
	b.runs = _bot_runs
	b.level = self
	b.player = player
	b.hud = hud
	b.cam_rig = cam_rig
	add_child(b)
	_bot = b
	await get_tree().process_frame
	b.start()


var _tour: Array = []
var _tour_t := 0.0
var _tour_i := 0


func _process(delta: float) -> void:
	if not _finished and not _dead:
		_time += delta
	# 巡迴截圖：--tour=x,y,z;x,y,z… 把半藏傳送到每個點各拍一張（AI 看關卡用）
	if _tour.is_empty():
		for a in _extra_args:
			if a.begins_with("--tour="):
				for p in a.substr(7).split(";"):
					var c: PackedStringArray = String(p).split(",")
					if c.size() == 3:
						_tour.append(Vector3(float(c[0]), float(c[1]), float(c[2])))
				_tour_t = 0.0
	if not _tour.is_empty():
		_tour_t += delta
		if _tour_t > 1.2:
			_tour_t = 0.0
			if _tour_i >= _tour.size():
				get_tree().quit()
				return
			player.global_position = _tour[_tour_i]
			player.velocity = Vector3.ZERO
			_tour_i += 1
			get_tree().create_timer(0.9).timeout.connect(_shot.bind("tour%d" % _tour_i))


func _physics_process(_delta: float) -> void:
	for i in range(_cp_index + 1, checkpoints.size()):
		var cp: Vector3 = checkpoints[i]
		var d := player.global_position - cp
		d.y = 0.0
		if d.length() < 2.5 and absf(player.global_position.y - cp.y) < 1.5:
			_cp_index = i
			_checkpoint = cp + Vector3(0.0, 0.1, 0.0)
			player.refill_shuriken()
			# 撿到的卷軸走到檢查點才算數
			Progress.commit_pending()
	var lit := false
	for l in _lanterns:
		if l.lights(player.global_position):
			lit = true
			break
	player.in_light = lit
	_update_covers()
	if _exit_ready and not _finished and not _dead:
		if player.global_position.distance_to(exit_pos) < 3.0:
			_finish()


func _shot(name: String) -> void:
	if _shot_dir == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s.png" % [_shot_dir, name])
	img.save_png(path)
	print("shot: ", path)


# ---------------------------------------------------------------- 遮蔽層

## 開始收集：之後建的東西都歸到 key 這個遮蔽層；半藏站進 aabb 裡時整層隱藏。_cover_end() 結束收集。
func _cover_begin(key: String, aabb: AABB) -> void:
	if not _covers.has(key):
		_covers[key] = {"aabb": aabb, "nodes": [], "hidden": false}
	_cover_key = key


func _cover_end() -> void:
	_cover_key = ""


func _cover_add(n: Node3D) -> void:
	if _cover_key != "" and _covers.has(_cover_key):
		(_covers[_cover_key].nodes as Array).append(n)


func _update_covers() -> void:
	var covered := false
	for key in _covers:
		var c: Dictionary = _covers[key]
		var inside: bool = (c.aabb as AABB).has_point(player.global_position)
		covered = covered or inside
		if inside != bool(c.hidden):
			c.hidden = inside
			for n in c.nodes:
				if is_instance_valid(n):
					n.visible = not inside
	# 在屋簷下／樓下時，樓上的敵人也看不到（他們在被隱藏的樓板上）
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node3D:
			e.visible = not (covered and e.global_position.y > player.global_position.y + 2.2)


# ---------------------------------------------------------------- 建構工具

func _nav_begin() -> void:
	_region = NavigationRegion3D.new()
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.9
	nm.agent_max_climb = 0.4
	nm.agent_max_slope = 40.0
	nm.cell_size = 0.25
	nm.cell_height = 0.2
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	_region.navigation_mesh = nm
	add_child(_region)


func _nav_end() -> void:
	_region.bake_navigation_mesh(false)


func _mat(color: Color, rough: float = 1.0, unshaded: bool = false, alpha: bool = false, emission: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%s|%s|%.2f" % [color.to_html(), rough, unshaded, alpha, emission]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	_mats[key] = m
	return m


## 通用方塊：center 是中心點，size 是尺寸，rot 是歐拉角（度）。collide=false 只有外觀。
func _box(center: Vector3, size: Vector3, color: Color, rot: Vector3 = Vector3.ZERO, collide: bool = true, rough: float = 1.0, parent: Node = null) -> Node3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color, rough)
	var node: Node3D
	if collide:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		sb.add_child(cs)
		sb.add_child(mi)
		node = sb
	else:
		node = mi
	(parent if parent else _region).add_child(node)
	node.position = center
	node.rotation_degrees = rot
	# 除錯回報用：準心指到這塊時，螢幕上印出它的中心與尺寸，對回關卡原始碼就找得到那一行
	node.set_meta("desc", "box 中心(%.1f, %.1f, %.1f) 尺寸(%.1f×%.1f×%.1f)" % [center.x, center.y, center.z, size.x, size.y, size.z])
	_cover_add(node)
	return node


## 透明碰撞牆（沒有外觀）
func _invisible(center: Vector3, size: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	_region.add_child(sb)
	sb.position = center


## 地面（整張）
func _ground(size: float, color: Color, y: float = 0.0) -> void:
	_box(Vector3(0.0, y - 0.5, 0.0), Vector3(size, 1.0, size), color)


## 台地：頂面在 y_top，從地面長上來
func _terrace(cx: float, cz: float, sx: float, sz: float, y_top: float, color: Color, y_base: float = 0.0) -> void:
	var h := y_top - y_base
	_box(Vector3(cx, y_base + h / 2.0, cz), Vector3(sx, h, sz), color)


## 斜坡：沿 z 軸（z0 → z1）從 y0 爬到 y1，寬 w。做成一塊旋轉的板子，走得上去也能導航。
func _ramp_z(cx: float, z0: float, z1: float, y0: float, y1: float, w: float, color: Color) -> void:
	var len_z := absf(z1 - z0)
	var dh := y1 - y0
	var slope_len := sqrt(len_z * len_z + dh * dh)
	var ang := rad_to_deg(atan2(dh, len_z))
	var sign_z := signf(z1 - z0)
	# z 往負方向走且變高時，板子要往 +x 軸旋正角
	var rot_x := ang * (1.0 if sign_z < 0.0 else -1.0)
	var center := Vector3(cx, (y0 + y1) / 2.0 - 0.15, (z0 + z1) / 2.0)
	_box(center, Vector3(w, 0.3, slope_len), color, Vector3(rot_x, 0.0, 0.0))
	# 階梯外觀（純裝飾，走在斜坡上）
	var steps := int(len_z / 0.5)
	for i in range(steps):
		var k := (float(i) + 0.5) / steps
		var z := lerpf(z0, z1, k)
		var y := lerpf(y0, y1, k)
		_box(Vector3(cx, y + 0.02, z), Vector3(w + 0.1, 0.06, 0.12), color.darkened(0.25), Vector3.ZERO, false)


## 斜坡：沿 x 軸
func _ramp_x(cz: float, x0: float, x1: float, y0: float, y1: float, w: float, color: Color) -> void:
	var len_x := absf(x1 - x0)
	var dh := y1 - y0
	var slope_len := sqrt(len_x * len_x + dh * dh)
	var ang := rad_to_deg(atan2(dh, len_x))
	var rot_z := ang * (1.0 if (x1 - x0) > 0.0 else -1.0)
	var center := Vector3((x0 + x1) / 2.0, (y0 + y1) / 2.0 - 0.15, cz)
	_box(center, Vector3(slope_len, 0.3, w), color, Vector3(0.0, 0.0, rot_z))


## 牆：底在 y_base，高 h；collide_h > h 時上面接透明牆（擋鉤繩與翻越，不擋畫面）
func _wall(cx: float, cz: float, sx: float, sz: float, h: float, color: Color, y_base: float = 0.0, collide_h: float = 0.0) -> void:
	_box(Vector3(cx, y_base + h / 2.0, cz), Vector3(sx, h, sz), color)
	if collide_h > h:
		_invisible(Vector3(cx, y_base + h + (collide_h - h) / 2.0, cz), Vector3(sx, collide_h - h, sz))


## 木柵／圍籬：矮牆加上一排柱子
func _fence(cx: float, cz: float, length: float, along_x: bool, h: float, color: Color, y_base: float = 0.0, collide_h: float = 0.0) -> void:
	var sx := length if along_x else 0.22
	var sz := 0.22 if along_x else length
	_box(Vector3(cx, y_base + h / 2.0, cz), Vector3(sx, h, sz), color)
	if collide_h > h:
		_invisible(Vector3(cx, y_base + h + (collide_h - h) / 2.0, cz), Vector3(sx, collide_h - h, sz))
	var n := int(length / 1.5)
	for i in range(n + 1):
		var k := float(i) / maxf(n, 1.0)
		var p := Vector3(cx + (k - 0.5) * length if along_x else cx, y_base + (h + 0.3) / 2.0, cz if along_x else cz + (k - 0.5) * length)
		_box(p, Vector3(0.3, h + 0.3, 0.3), color.darkened(0.3), Vector3.ZERO, false)


## 切妻屋頂：兩片斜板在 ridge 交會。ridge_along_z=true 表示屋脊沿 z。
## eave_y 是屋簷高度，rise 是屋脊比屋簷高多少。可走、可鉤。
func _gable(cx: float, cz: float, sx: float, sz: float, eave_y: float, rise: float, color: Color, ridge_along_z: bool = true, overhang: float = 0.6) -> void:
	var half := (sx if ridge_along_z else sz) / 2.0 + overhang
	var span := sqrt(half * half + rise * rise)
	var ang := rad_to_deg(atan2(rise, half))
	var length := (sz if ridge_along_z else sx) + overhang * 2.0
	for side in [-1.0, 1.0]:
		var off: float = side * half / 2.0
		var center := Vector3(cx + off, eave_y + rise / 2.0, cz) if ridge_along_z else Vector3(cx, eave_y + rise / 2.0, cz + off)
		var size := Vector3(span, 0.22, length) if ridge_along_z else Vector3(length, 0.22, span)
		var rot := Vector3(0.0, 0.0, -side * ang) if ridge_along_z else Vector3(side * ang, 0.0, 0.0)
		_box(center, size, color, rot, true, 0.95)
	# 屋脊
	var ridge_size := Vector3(0.35, 0.25, length) if ridge_along_z else Vector3(length, 0.25, 0.35)
	_box(Vector3(cx, eave_y + rise + 0.05, cz), ridge_size, color.darkened(0.35), Vector3.ZERO, false)


## 小屋／長屋：四面牆（door 面留 1.8 公尺門口）、地板、切妻屋頂。door: "n"/"s"/"e"/"w"
func _hut(cx: float, cz: float, sx: float, sz: float, wall_h: float, y_base: float, wall_color: Color, roof_color: Color, door: String = "s", rise: float = 1.1, floor_color: Color = Color(0.4, 0.33, 0.24)) -> void:
	var t := 0.25
	var dw := 1.8
	# 地板
	_box(Vector3(cx, y_base + 0.05, cz), Vector3(sx, 0.1, sz), floor_color, Vector3.ZERO, false)
	# 南北牆（沿 x）
	for side in [["s", sz / 2.0], ["n", -sz / 2.0]]:
		var z: float = cz + float(side[1])
		if door == side[0]:
			var seg := (sx - dw) / 2.0
			_box(Vector3(cx - dw / 2.0 - seg / 2.0, y_base + wall_h / 2.0, z), Vector3(seg, wall_h, t), wall_color)
			_box(Vector3(cx + dw / 2.0 + seg / 2.0, y_base + wall_h / 2.0, z), Vector3(seg, wall_h, t), wall_color)
			_box(Vector3(cx, y_base + wall_h - 0.2, z), Vector3(dw, 0.4, t), wall_color)
		else:
			_box(Vector3(cx, y_base + wall_h / 2.0, z), Vector3(sx, wall_h, t), wall_color)
	# 東西牆（沿 z）
	for side in [["e", sx / 2.0], ["w", -sx / 2.0]]:
		var x: float = cx + float(side[1])
		if door == side[0]:
			var seg := (sz - dw) / 2.0
			_box(Vector3(x, y_base + wall_h / 2.0, cz - dw / 2.0 - seg / 2.0), Vector3(t, wall_h, seg), wall_color)
			_box(Vector3(x, y_base + wall_h / 2.0, cz + dw / 2.0 + seg / 2.0), Vector3(t, wall_h, seg), wall_color)
			_box(Vector3(x, y_base + wall_h - 0.2, cz), Vector3(t, 0.4, dw), wall_color)
		else:
			_box(Vector3(x, y_base + wall_h / 2.0, cz), Vector3(t, wall_h, sz), wall_color)
	# 屋頂：人走進屋裡就隱藏
	var prev := _cover_key
	_cover_begin("hut_%d_%d" % [int(cx * 10.0), int(cz * 10.0)], AABB(Vector3(cx - sx / 2.0, y_base - 0.3, cz - sz / 2.0), Vector3(sx, wall_h + 0.2, sz)))
	_gable(cx, cz, sx, sz, y_base + wall_h, rise, roof_color, sz >= sx)
	_cover_key = prev


## 櫓（瞭望台）：四根柱、平台、欄杆、小屋頂。平台可鉤可站。
func _tower(cx: float, cz: float, platform_y: float, y_base: float, wood: Color, roof: Color) -> void:
	var s := 3.2
	for dx in [-1.0, 1.0]:
		for dz in [-1.0, 1.0]:
			_box(Vector3(cx + dx * s / 2.0, y_base + platform_y / 2.0, cz + dz * s / 2.0), Vector3(0.3, platform_y, 0.3), wood)
	_box(Vector3(cx, y_base + platform_y - 0.1, cz), Vector3(s + 0.6, 0.2, s + 0.6), wood.lightened(0.1))
	# 欄杆（矮，不擋人）
	for side in [[0.0, 1.0], [0.0, -1.0], [1.0, 0.0], [-1.0, 0.0]]:
		var p := Vector3(cx + float(side[0]) * (s + 0.4) / 2.0, y_base + platform_y + 0.45, cz + float(side[1]) * (s + 0.4) / 2.0)
		var sz := Vector3(s + 0.6, 0.08, 0.08) if float(side[0]) == 0.0 else Vector3(0.08, 0.08, s + 0.6)
		_box(p, sz, wood.darkened(0.2), Vector3.ZERO, false)
	for dx in [-1.0, 1.0]:
		for dz in [-1.0, 1.0]:
			_box(Vector3(cx + dx * s / 2.0, y_base + platform_y + 1.1, cz + dz * s / 2.0), Vector3(0.2, 2.2, 0.2), wood, Vector3.ZERO, false)
	_gable(cx, cz, s, s, y_base + platform_y + 2.2, 0.7, roof, true, 0.4)


## 松樹：樹幹有碰撞，樹冠沒有
func _tree(pos: Vector3, scale_k: float = 1.0) -> void:
	var trunk := Color(0.3, 0.22, 0.14)
	var leaf := Color(0.12, 0.27, 0.14)
	_box(pos + Vector3(0.0, 1.5 * scale_k, 0.0), Vector3(0.4, 3.0 * scale_k, 0.4) * Vector3(scale_k, 1.0, scale_k), trunk)
	var canopy := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.7 * scale_k
	sm.height = 2.2 * scale_k
	canopy.mesh = sm
	canopy.material_override = _mat(leaf)
	canopy.position = pos + Vector3(0.3, 3.2 * scale_k, 0.0)
	add_child(canopy)
	var canopy2 := MeshInstance3D.new()
	var sm2 := SphereMesh.new()
	sm2.radius = 1.2 * scale_k
	sm2.height = 1.6 * scale_k
	canopy2.mesh = sm2
	canopy2.material_override = _mat(leaf.lightened(0.08))
	canopy2.position = pos + Vector3(-0.6, 4.3 * scale_k, 0.4)
	add_child(canopy2)


## 鳥居（朱紅）
func _torii(pos: Vector3, along_x: bool = true) -> void:
	var red := Color(0.72, 0.18, 0.14)
	var w := 4.0
	for side in [-1.0, 1.0]:
		var p := pos + (Vector3(side * w / 2.0, 2.0, 0.0) if along_x else Vector3(0.0, 2.0, side * w / 2.0))
		_box(p, Vector3(0.35, 4.0, 0.35), red)
	var beam1 := Vector3(w + 1.4, 0.3, 0.4) if along_x else Vector3(0.4, 0.3, w + 1.4)
	var beam2 := Vector3(w + 0.6, 0.22, 0.3) if along_x else Vector3(0.3, 0.22, w + 0.6)
	_box(pos + Vector3(0.0, 4.15, 0.0), beam1, red.darkened(0.1), Vector3.ZERO, false)
	_box(pos + Vector3(0.0, 3.5, 0.0), beam2, red.darkened(0.1), Vector3.ZERO, false)


## 石燈籠（裝飾，不發光；會發光的燈籠用 Lantern）
func _stone_lantern(pos: Vector3) -> void:
	var stone := Color(0.5, 0.5, 0.47)
	_box(pos + Vector3(0.0, 0.1, 0.0), Vector3(0.7, 0.2, 0.7), stone)
	_box(pos + Vector3(0.0, 0.7, 0.0), Vector3(0.25, 1.0, 0.25), stone, Vector3.ZERO, false)
	_box(pos + Vector3(0.0, 1.4, 0.0), Vector3(0.6, 0.45, 0.6), stone.lightened(0.1), Vector3.ZERO, false)
	_box(pos + Vector3(0.0, 1.75, 0.0), Vector3(0.8, 0.15, 0.8), stone.darkened(0.2), Vector3.ZERO, false)


## 卷軸（每關一卷，藏在潛行路線深處）；已經有的就不放
const ScrollScript := preload("res://scripts/scroll.gd")


func _scroll(pos: Vector3, id: String) -> void:
	if Progress.has_scroll(id):
		return
	var s: Node3D = ScrollScript.new()
	s.id = id
	add_child(s)
	s.global_position = pos


## 會亮的燈籠（可用手裡劍熄滅）
func _lantern(pos: Vector3) -> Lantern:
	var l := Lantern.new()
	add_child(l)
	l.global_position = pos
	_lanterns.append(l)
	_cover_add(l)
	return l


## 障子／襖：薄薄一片，暖色微透光。along_x 表示牆沿 x 延伸。
func _shoji(cx: float, cz: float, length: float, along_x: bool, h: float, y_base: float, lit: bool = true) -> void:
	var paper := Color(0.93, 0.88, 0.76, 0.92)
	var size := Vector3(length, h, 0.12) if along_x else Vector3(0.12, h, length)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(paper, 0.9, false, true, 0.25 if lit else 0.0)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	sb.add_child(mi)
	_region.add_child(sb)
	sb.position = Vector3(cx, y_base + h / 2.0, cz)
	_cover_add(sb)
	# 木框格子
	var n := int(length / 0.9)
	for i in range(n + 1):
		var k := float(i) / maxf(n, 1.0)
		var p := Vector3(cx + (k - 0.5) * length, y_base + h / 2.0, cz) if along_x else Vector3(cx, y_base + h / 2.0, cz + (k - 0.5) * length)
		_box(p, Vector3(0.08, h, 0.16) if along_x else Vector3(0.16, h, 0.08), Color(0.3, 0.22, 0.15), Vector3.ZERO, false)


## 一段牆留門口：沿 along_x 從 a 到 b，在 door_at 留 door_w 的洞。用 builder（Callable(cx, cz, length)）畫牆段。
func _wall_with_gap(a: float, b: float, fixed: float, along_x: bool, door_at: float, door_w: float, builder: Callable) -> void:
	var lo := minf(a, b)
	var hi := maxf(a, b)
	var d0 := door_at - door_w / 2.0
	var d1 := door_at + door_w / 2.0
	if d0 - lo > 0.05:
		var c := (lo + d0) / 2.0
		builder.call(c if along_x else fixed, fixed if along_x else c, d0 - lo)
	if hi - d1 > 0.05:
		var c := (d1 + hi) / 2.0
		builder.call(c if along_x else fixed, fixed if along_x else c, hi - d1)


## 門：兩片門板，open() 往兩側打開並關掉碰撞
func _gate(key: String, pos: Vector3, width: float, h: float, along_x: bool, color: Color) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = pos
	var panels: Array = []
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(side * width / 2.0, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, side * width / 2.0)
		root.add_child(pivot)
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var size := Vector3(width / 2.0, h, 0.2) if along_x else Vector3(0.2, h, width / 2.0)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = _mat(color)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		sb.add_child(mi)
		sb.add_child(cs)
		sb.position = Vector3(-side * width / 4.0, h / 2.0, 0.0) if along_x else Vector3(0.0, h / 2.0, -side * width / 4.0)
		pivot.add_child(sb)
		panels.append({"pivot": pivot, "shape": cs, "side": side})
	_gates[key] = {"root": root, "panels": panels, "open": false, "along_x": along_x}


func _gate_set(key: String, open: bool) -> void:
	if not _gates.has(key):
		return
	var g: Dictionary = _gates[key]
	if g.open == open:
		return
	g.open = open
	for p in g.panels:
		var pivot: Node3D = p.pivot
		var shape: CollisionShape3D = p.shape
		var side: float = p.side
		var target: float = (side * 100.0) if open else 0.0
		var tw := pivot.create_tween()
		tw.tween_property(pivot, "rotation_degrees:y", target, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		shape.set_deferred("disabled", open)


func _build_exit_beacon() -> void:
	_exit_beacon = Node3D.new()
	add_child(_exit_beacon)
	_exit_beacon.position = exit_pos
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


func _open_exit(text: String = "撤離") -> void:
	_exit_ready = true
	_exit_beacon.visible = true
	hud.set_compass_target(exit_pos, Color(0.6, 0.9, 1.0))
	var lbl: Label3D = _exit_beacon.get_child(1)
	lbl.text = text


# ---------------------------------------------------------------- 敵人

func _spawn(kind: Enemy.Kind, pos: Vector3, route: Array = [], face := Vector3.FORWARD) -> Enemy:
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
		hud.say_hint("被發現了！", Color(1.0, 0.4, 0.3))


func _on_enemy_died(e: Enemy, stealth: bool) -> void:
	_kills += 1
	if e.kind == Enemy.Kind.TARGET or randf() < 0.35:
		var r := Ration.new()
		add_child(r)
		r.global_position = e.global_position
	if stealth:
		_stealth_kills += 1
	hud.add_kill("")
	# 忍殺大將得念珠：最大 HP +10（每關一枚，最多四枚）
	if e.kind == Enemy.Kind.TARGET and not _bead_given and Progress.beads < Progress.MAX_BEADS:
		_bead_given = true
		Progress.add_bead()
		get_tree().create_timer(0.9).timeout.connect(func() -> void:
			# 血條變長並閃金色就是回饋；輔助文字開著才說
			hud.flash_hp(Color(1.0, 0.85, 0.4))
			hud.say_hint("念珠　最大 HP +10", Color(1.0, 0.85, 0.5)))
	_on_enemy_died_hook(e, stealth)


# ---------------------------------------------------------------- 結束

func _on_player_died() -> void:
	if _dead or _finished or _bot != null:
		return
	_dead = true
	hud.say("敗北…", Color(0.9, 0.3, 0.3))
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		hud.show_overlay("敗北", ["時間 %s　擊破 %d　被擊中 %d 次" % [_fmt_time(_time), _kills, _hits_taken]],
			[["從檢查點再來", func() -> void: _respawn()],
			 ["整關重來", func() -> void: get_tree().reload_current_scene()],
			 ["回標題", func() -> void: get_tree().change_scene_to_file("res://scenes/title.tscn")]],
			Color(0.95, 0.3, 0.3)))


## 從最近檢查點重生：半藏復活、敵人全部重置；故事進度（目標已死、門已開）保留
func _respawn() -> void:
	for n in get_tree().get_nodes_in_group("enemies"):
		n.queue_free()
	_enemies.clear()
	for a in get_children():
		if a is Arrow or a is Shuriken or a is Ration:
			a.queue_free()
	# 撿到但還沒到檢查點的卷軸：回溯後要重撿
	Progress.drop_pending()
	for a in get_children():
		if a.get_script() == ScrollScript:
			a.queue_free()
	_spawn_enemies()
	_after_respawn()
	player.global_position = _checkpoint
	player.revive()
	_dead = false
	_alert_count = 0
	hud.say("再起", Color(0.9, 0.9, 0.95))


## 子類別：重生後依故事進度移除已死的目標等
func _after_respawn() -> void:
	pass


## 子類別：在 _spawn_enemies 結尾呼叫，放這關的卷軸（已持有的不放；死亡回溯會重放）
func _respawn_scrolls() -> void:
	pass


func _finish() -> void:
	_finished = true
	var rank := _rank()
	Progress.commit_pending()
	Progress.mark_cleared(scene_file_path.get_file().get_basename(), rank)
	hud.say("任務完成", Color(0.95, 0.9, 0.6))
	var buttons: Array = []
	if next_scene != "":
		buttons.append([next_label, func() -> void: get_tree().change_scene_to_file(next_scene)])
	buttons.append(["再玩一次", func() -> void: get_tree().reload_current_scene()])
	buttons.append(["回標題", func() -> void: get_tree().change_scene_to_file("res://scenes/title.tscn")])
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		hud.show_overlay("任務完成　評價 %s" % rank, [
			"時間 %s" % _fmt_time(_time),
			"擊破 %d（暗殺 %d）　被擊中 %d 次　被發現 %d 次" % [_kills, _stealth_kills, _hits_taken, _alert_count],
			"念珠 %d/%d　卷軸 %d/%d" % [Progress.beads, Progress.MAX_BEADS, Progress.scroll_count(), Progress.SCROLLS.size()],
			_rank_comment(rank),
		], buttons, Color(1.0, 0.9, 0.5)))


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
