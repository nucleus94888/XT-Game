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
## 旋轉群組：_group_begin(center, yaw) 之後建的東西都掛在一個旋轉過的節點下（座標變成相對 center），
## 整棟小屋、整段柵欄就能斜著放，地圖才不會全是對齊座標軸的方塊。導航烘焙照樣看得到（節點仍在 _region 底下）
var _pivot: Node3D = null
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
	# 看地圖用：++ --cam=俯角度,距離（例 --cam=75,60 從高空俯瞰整張關卡）
	for a in _extra_args:
		if a.begins_with("--cam="):
			var c: PackedStringArray = a.substr(6).split(",")
			if c.size() == 2:
				cam_rig.pitch = deg_to_rad(float(c[0]))
				cam_rig.distance = float(c[1])
	# 月光陰影：預設涵蓋 100 公尺、4 層，2048 貼圖攤下來每格很大，屋簷／台地的影子邊緣一格一格的（破圖）。
	# 鏡頭只看得到附近 30–40 公尺，縮到 40 公尺、2 層，同樣貼圖解析度約兩倍；加一點偏移與模糊消掉條紋
	var moon := get_node_or_null("Moon") as DirectionalLight3D
	if moon:
		moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		moon.directional_shadow_max_distance = 32.0
		moon.shadow_bias = 0.05
		moon.shadow_normal_bias = 1.4
		moon.shadow_blur = 2.0
	_checkpoint = start_pos
	player.global_position = start_pos
	# 玩家傳送後鏡頭立刻定位；再用黑幕蓋住開場的著色器預熱（火花、刀光），淡入 0.45 秒
	cam_rig.snap_to_target()
	hud.curtain(0.45)
	player.hook_bounds = bounds
	_nav_begin()
	_build_world()
	if outskirts:
		_build_outskirts()
	_build_bounds_walls()
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
	if _extra_args.has("--map"):
		_draw_decisions()
		cam_rig.pitch = deg_to_rad(88.0)
		cam_rig.distance = 95.0
	if _extra_args.has("--routes"):
		_measure_routes()
	if _extra_args.has("--hooktest"):
		_hook_test()
	if _extra_args.has("--zfight"):
		_zfight_scan()
	if _extra_args.has("--stucktest"):
		_stuck_test()
	if _extra_args.has("--wallpush"):
		_wall_push_test()


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
	var args: Array = Array(OS.get_cmdline_user_args())
	# 網頁版測試：網址 ?level=2&tour=x,y,z 會把參數帶進來（自動測試在真網頁版上傳送到指定位置）
	if OS.has_feature("web"):
		var qs = JavaScriptBridge.eval("window.location.search", true)
		if typeof(qs) == TYPE_STRING and String(qs).contains("tour="):
			for part in String(qs).trim_prefix("?").split("&"):
				if part.begins_with("tour="):
					args.append("--tour=" + part.substr(5).uri_decode())
	for a in args:
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
			if a == "--walk" or a == "--props" or a.begins_with("--tour=") or a.begins_with("--hookpull="):
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
	if _extra_args.has("--props"):
		_props_test(delta)
	if _extra_args.any(func(a: String) -> bool: return a.begins_with("--hookpull=")):
		_hookpull_test(delta)
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


## 甩掉追兵的回饋：
##   地上的灰色殘影＝敵人以為你在哪（追丟或搜索中的敵人回報的最後位置）——你人已經不在那裡就代表甩開了
##   最後一個在追你的敵人追丟 → 輕震一下（輔助文字開著才說「甩掉了」）
var _ghost: MeshInstance3D
var _ghost_mat: StandardMaterial3D
var _was_chased := false


func _update_hunt() -> void:
	if _ghost == null:
		_ghost = MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.36
		cm.height = 1.5
		_ghost.mesh = cm
		_ghost_mat = StandardMaterial3D.new()
		_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_mat.albedo_color = Color(0.85, 0.85, 0.95, 0.22)
		_ghost.material_override = _ghost_mat
		_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_ghost)
		_ghost.visible = false
	var marker = null
	var chased := false
	for e in _enemies:
		if not is_instance_valid(e) or e.state == e.State.DEAD:
			continue
		if e.state in [e.State.ALERT, e.State.ATTACK] and float(e._lost_t) <= 0.0:
			chased = true
		var m = e.hunt_marker()
		if m != null and marker == null:
			marker = m
	# 殘影只在你已經離開那個位置 1.5 公尺以上時才顯示（不然它就疊在你身上）
	if marker != null and (marker as Vector3).distance_to(player.global_position) > 1.5:
		_ghost.visible = true
		_ghost.global_position = (marker as Vector3) + Vector3(0.0, 0.95, 0.0)
		_ghost_mat.albedo_color.a = 0.18 + 0.06 * sin(Time.get_ticks_msec() * 0.006)
	else:
		_ghost.visible = false
	if _was_chased and not chased:
		Feel.haptic(30)
		hud.say_hint("甩掉了", Color(0.75, 0.85, 1.0))
	_was_chased = chased


## 保險：關卡範圍（bounds）四周一圈透明牆，柵欄有縫或忘了加透明牆也跑不出去
func _build_bounds_walls() -> void:
	var b := bounds
	var y0 := b.position.y - 2.0
	var h := 40.0
	var t := 1.0
	var cx := b.position.x + b.size.x / 2.0
	var cz := b.position.z + b.size.z / 2.0
	_invisible(Vector3(cx, y0 + h / 2.0, b.position.z - t / 2.0), Vector3(b.size.x + t * 2.0, h, t))
	_invisible(Vector3(cx, y0 + h / 2.0, b.end.z + t / 2.0), Vector3(b.size.x + t * 2.0, h, t))
	_invisible(Vector3(b.position.x - t / 2.0, y0 + h / 2.0, cz), Vector3(t, h, b.size.z + t * 2.0))
	_invisible(Vector3(b.end.x + t / 2.0, y0 + h / 2.0, cz), Vector3(t, h, b.size.z + t * 2.0))


func _physics_process(_delta: float) -> void:
	# 保險：掉出地圖（低於地面 4 公尺）或跑出範圍 → 送回最後的檢查點
	if not _dead and not _finished:
		var pp := player.global_position
		if pp.y < bounds.position.y - 4.0 or pp.x < bounds.position.x - 2.0 or pp.x > bounds.end.x + 2.0 or pp.z < bounds.position.z - 2.0 or pp.z > bounds.end.z + 2.0:
			push_warning("player out of map at %s, back to checkpoint" % pp)
			player.global_position = _checkpoint + Vector3(0.0, 0.2, 0.0)
			player.velocity = Vector3.ZERO
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
	if not lit:
		for f in get_tree().get_nodes_in_group("fires"):
			if f.lights(player.global_position):
				lit = true
				break
	player.in_light = lit
	_update_covers()
	_update_hunt()
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
	# 在旋轉群組裡建的遮蔽層：範圍留在群組座標，判定時把玩家位置轉進群組座標再比
	# （若改成包住旋轉後八個角的世界 AABB，人站在屋外斜角也會把屋頂藏掉）
	var xf := _pivot.transform if _pivot else Transform3D.IDENTITY
	if not _covers.has(key):
		_covers[key] = {"aabb": aabb, "xform": xf, "nodes": [], "hidden": false}
	_cover_key = key


# ---------------------------------------------------------------- 旋轉群組

## 之後建的東西都掛在這個旋轉節點下，座標相對 center（y 也相對）。用 _group_end() 結束
func _group_begin(center: Vector3, yaw_deg: float) -> void:
	var p := Node3D.new()
	_region.add_child(p)
	p.position = center
	p.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	_pivot = p


func _group_end() -> void:
	_pivot = null


## 折線柵欄：points 是一串 Vector3（y＝該點柵欄底部高度），逐段用旋轉群組建
func _fence_poly(points: Array, h: float, color: Color, collide_h: float = 0.0) -> void:
	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var d := b - a
		var flat := Vector2(d.x, d.z)
		var length := flat.length()
		if length < 0.1:
			continue
		var yaw := rad_to_deg(atan2(-d.x, -d.z))
		var base := minf(a.y, b.y)
		_group_begin(Vector3((a.x + b.x) / 2.0, base, (a.z + b.z) / 2.0), yaw)
		# 相鄰兩段高度差 1.5 公分：轉角重疊處的頂面不再同高（閃爍）
		var jit := 0.013 * float((absi(int(a.x * 3.1 + a.z * 7.3 + b.x * 1.3 - b.z * 2.9)) + i) % 4)
		_fence(0.0, 0.0, length, false, h + jit, color, 0.0, collide_h)
		# 柵欄架在台地高度、但下面是地面時：補一段石垣到地面，不然人能從柵欄底下鑽出去
		if base > 0.05:
			_box(Vector3(0.0, -base / 2.0 - jit, 0.0), Vector3(0.6 + jit * 2.0, base, length), Color(0.3, 0.3, 0.28))
		_group_end()


## 折線小路：一段段旋轉的薄板接起來（純外觀）
func _path_poly(points: Array, width: float, color: Color, y_off: float = 0.03) -> void:
	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var d := b - a
		var length := Vector2(d.x, d.z).length() + width * 0.6
		var yaw := rad_to_deg(atan2(-d.x, -d.z))
		# 相鄰兩段錯開 1.3 公分：接縫處兩段重疊的上表面不再同高（不然會閃爍）
		_box(Vector3((a.x + b.x) / 2.0, (a.y + b.y) / 2.0 + y_off + 0.013 * (i % 2), (a.z + b.z) / 2.0), Vector3(width, 0.06, length), color, Vector3(0.0, yaw, 0.0), false)


## 任意方向的斜坡：from → to（含高度），寬 w。長軸沿 -Z 的板子，先依坡度繞 X、再依方向繞 Y
func _ramp(from: Vector3, to: Vector3, w: float, color: Color, steps: bool = true) -> void:
	var d := to - from
	var flat := Vector2(d.x, d.z).length()
	var slope_len := sqrt(flat * flat + d.y * d.y)
	var ang := rad_to_deg(atan2(d.y, flat))
	var yaw := rad_to_deg(atan2(-d.x, -d.z))
	var center := (from + to) / 2.0 - Vector3(0.0, 0.15, 0.0)
	_box(center, Vector3(w, 0.3, slope_len), color, Vector3(ang, yaw, 0.0))
	if steps:
		var n := int(flat / 0.5)
		for i in range(n):
			var k := (float(i) + 0.5) / n
			var p := from.lerp(to, k)
			_box(p + Vector3(0.0, 0.02, 0.0), Vector3(w + 0.1, 0.06, 0.12), color.darkened(0.25), Vector3(0.0, yaw, 0.0), false)


## 岩石：幾顆歪斜的方塊疊在一起（台地邊緣、路邊用來打破直線）
func _rock(pos: Vector3, size: float, yaw_deg: float, color: Color) -> void:
	_box(pos + Vector3(0.0, size * 0.35, 0.0), Vector3(size * 1.4, size * 0.7, size), color, Vector3(0.0, yaw_deg, 6.0))
	_box(pos + Vector3(size * 0.3, size * 0.75, size * 0.2), Vector3(size * 0.8, size * 0.6, size * 0.7), color.lightened(0.08), Vector3(8.0, yaw_deg + 30.0, -5.0))


func _cover_end() -> void:
	_cover_key = ""


func _cover_add(n: Node3D) -> void:
	if _cover_key != "" and _covers.has(_cover_key):
		(_covers[_cover_key].nodes as Array).append(n)


func _update_covers() -> void:
	var covered := false
	for key in _covers:
		var c: Dictionary = _covers[key]
		var local_p: Vector3 = (c.xform as Transform3D).affine_inverse() * player.global_position
		var inside: bool = (c.aabb as AABB).has_point(local_p)
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
	(parent if parent else (_pivot if _pivot else _region)).add_child(node)
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
	# 標記「幽靈牆」：鏡頭碰撞與手裡劍飛行要無視它（它只擋人與鉤繩），不然站在柵欄邊鏡頭會被頂到頭上、無法瞄準
	sb.set_meta("ghost", true)
	sb.set_meta("desc", "透明牆 中心(%.1f, %.1f, %.1f) 尺寸(%.1f×%.1f×%.1f)" % [center.x, center.y, center.z, size.x, size.y, size.z])
	(_pivot if _pivot else _region).add_child(sb)
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
	# 依位置錯開 0–2.4 公分：兩道柵欄在轉角相接時頂面不同高（不然轉角那塊會閃）
	h += 0.012 * float(absi(int(cx * 3.1 + cz * 7.3 + length * 1.7 + (5.0 if along_x else 0.0))) % 4)
	var sx := length if along_x else 0.22
	var sz := 0.22 if along_x else length
	_box(Vector3(cx, y_base + h / 2.0, cz), Vector3(sx, h, sz), color)
	if collide_h > h:
		_invisible(Vector3(cx, y_base + h + (collide_h - h) / 2.0, cz), Vector3(sx, collide_h - h, sz))
	var n := int(length / 1.5)
	for i in range(n + 1):
		var k := float(i) / maxf(n, 1.0)
		var p := Vector3(cx + (k - 0.5) * length if along_x else cx, y_base + (h + 0.3) / 2.0, cz if along_x else cz + (k - 0.5) * length)
		# 柱子粗細依段長微調：兩段柵欄在轉角各自的端柱疊在一起時不同大小（不閃）
		var pw := 0.28 + 0.012 * float(absi(int(cx * 5.0 + cz * 11.0 + length * 3.0)) % 5)
		_box(p, Vector3(pw, h + 0.3 + pw - 0.3, pw), color.darkened(0.3), Vector3.ZERO, false)


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
	# 屋脊木比屋頂兩端各長 4 公分：端面不跟屋頂板的端面疊在同一平面（閃爍）
	var ridge_size := Vector3(0.35, 0.25, length + 0.08) if ridge_along_z else Vector3(length + 0.08, 0.25, 0.35)
	_box(Vector3(cx, eave_y + rise + 0.07, cz), ridge_size, color.darkened(0.35), Vector3.ZERO, false)


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
	# 遮蔽層的鍵用世界座標（旋轉群組裡每棟小屋的 cx, cz 都是 0）
	var kx := cx + (_pivot.position.x if _pivot else 0.0)
	var kz := cz + (_pivot.position.z if _pivot else 0.0)
	_cover_begin("hut_%d_%d" % [int(kx * 10.0), int(kz * 10.0)], AABB(Vector3(cx - sx / 2.0, y_base - 0.3, cz - sz / 2.0), Vector3(sx, wall_h + 0.2, sz)))
	_gable(cx, cz, sx, sz, y_base + wall_h, rise, roof_color, sz >= sx)
	_cover_key = prev


## 櫓（瞭望台）：四根柱、平台、欄杆、小屋頂。平台可鉤可站。
func _tower(cx: float, cz: float, platform_y: float, y_base: float, wood: Color, roof: Color) -> void:
	var s := 3.2
	for dx in [-1.0, 1.0]:
		for dz in [-1.0, 1.0]:
			# 柱頂停在平台面下 3 公分（以前柱頂和平台面齊平，平台上四個角在閃）
			_box(Vector3(cx + dx * s / 2.0, y_base + (platform_y - 0.03) / 2.0, cz + dz * s / 2.0), Vector3(0.3, platform_y - 0.03, 0.3), wood)
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
	# 樹幹：鏡頭不因它拉近（細細一根，拉近只會把鏡頭撞到人背上），改成跟樹冠一樣變半透明
	var tr := _box(pos + Vector3(0.0, 1.5 * scale_k, 0.0), Vector3(0.4, 3.0 * scale_k, 0.4) * Vector3(scale_k, 1.0, scale_k), trunk)
	tr.set_meta("no_pull", true)
	var canopy := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.7 * scale_k
	sm.height = 2.2 * scale_k
	canopy.mesh = sm
	canopy.material_override = _mat(leaf)
	canopy.position = pos + Vector3(0.3, 3.2 * scale_k, 0.0)
	canopy.add_to_group("canopy")
	canopy.set_meta("radius", 1.8 * scale_k)
	(_pivot if _pivot else self).add_child(canopy)
	var canopy2 := MeshInstance3D.new()
	var sm2 := SphereMesh.new()
	sm2.radius = 1.2 * scale_k
	sm2.height = 1.6 * scale_k
	canopy2.mesh = sm2
	canopy2.material_override = _mat(leaf.lightened(0.08))
	canopy2.position = pos + Vector3(-0.6, 4.3 * scale_k, 0.4)
	canopy2.add_to_group("canopy")
	canopy2.set_meta("radius", 1.3 * scale_k)
	(_pivot if _pivot else self).add_child(canopy2)


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


## ---------------------------------------------------------------- 第十三次議會：鉤點、外圍景、地標、決定點

const HookPointScript := preload("res://scripts/hook_point.gd")
## 外圍景（山、林、遠處屋頂）：關卡框外一圈，只有外觀沒有碰撞，地圖不再像漂在黑暗裡的盒子
var outskirts := true
## 決定點：每個都有 2–3 條路線（--map 畫出來、--routes 量代價）
var decisions: Array = []


## 鉤點：pos 是落腳點（屋脊、牆頂、平台頂面）
func _hook_point(pos: Vector3) -> Node3D:
	var hp: Node3D = HookPointScript.new()
	add_child(hp)
	hp.global_position = _pivot.transform * pos if _pivot else pos
	return hp


## 引路微光：冷色、很暗、不算「光裡」（不會讓你被看見），只告訴玩家「這邊有路」
func _guide_glow(pos: Vector3) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(0.55, 0.7, 1.0)
	l.light_energy = 0.9
	l.omni_range = 4.5
	l.shadow_enabled = false
	add_child(l)
	l.global_position = pos + Vector3(0, 1.6, 0)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	mi.mesh = sm
	mi.material_override = _mat(Color(0.6, 0.78, 1.0), 1.0, true)
	add_child(mi)
	mi.global_position = pos + Vector3(0, 1.6, 0)


## 決定點：id、位置、路線清單 [{name, pts: [Vector3...]}]
func _decision(id: String, pos: Vector3, routes: Array) -> void:
	decisions.append({"id": id, "pos": pos, "routes": routes})


## 外圍：遠處的地面、山、林、屋頂剪影（依 bounds 自動排一圈）
func _build_outskirts() -> void:
	var c := bounds.get_center()
	var far_ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(360, 360)
	far_ground.mesh = pm
	far_ground.material_override = _mat(Color(0.09, 0.1, 0.1))
	far_ground.position = Vector3(c.x, -0.06, c.z)
	add_child(far_ground)
	var hill := _mat(Color(0.1, 0.12, 0.13))
	var hill2 := _mat(Color(0.13, 0.15, 0.15))
	var leaf := _mat(Color(0.08, 0.16, 0.1))
	var roof := _mat(Color(0.14, 0.15, 0.19))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(level_title)
	var hx := bounds.size.x / 2.0
	var hz := bounds.size.z / 2.0
	# 遠山：一圈大錐體
	for i in range(14):
		var a := TAU * float(i) / 14.0 + rng.randf() * 0.2
		var r := maxf(hx, hz) + rng.randf_range(38.0, 60.0)
		var m := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = rng.randf_range(2.0, 6.0)
		cm.bottom_radius = rng.randf_range(22.0, 34.0)
		cm.height = rng.randf_range(14.0, 30.0)
		cm.radial_segments = 7
		m.mesh = cm
		m.material_override = hill if i % 2 == 0 else hill2
		m.position = Vector3(c.x + cos(a) * r, cm.height / 2.0 - 1.0, c.z + sin(a) * r)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
	# 框外一圈林：樹冠球（沒有樹幹碰撞），貼著外牆外 4–14 公尺
	for i in range(46):
		var side := i % 4
		var t := rng.randf_range(-1.0, 1.0)
		var off := rng.randf_range(4.0, 14.0)
		var p := Vector3.ZERO
		match side:
			0: p = Vector3(c.x + t * (hx + 8.0), 0.0, bounds.position.z - off)
			1: p = Vector3(c.x + t * (hx + 8.0), 0.0, bounds.end.z + off)
			2: p = Vector3(bounds.position.x - off, 0.0, c.z + t * (hz + 8.0))
			3: p = Vector3(bounds.end.x + off, 0.0, c.z + t * (hz + 8.0))
		var s := rng.randf_range(1.6, 3.2)
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = s
		sm.height = s * 1.5
		sm.radial_segments = 8
		sm.rings = 4
		m.mesh = sm
		m.material_override = leaf
		m.position = p + Vector3(0, s * 0.9 + rng.randf_range(0.5, 2.5), 0)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
	# 遠處屋頂剪影：外圍幾排矮矮的切妻屋頂（城下町、村落延伸出去的感覺）
	for i in range(16):
		var side2 := i % 4
		var t2 := rng.randf_range(-0.9, 0.9)
		var off2 := rng.randf_range(16.0, 30.0)
		var p2 := Vector3.ZERO
		match side2:
			0: p2 = Vector3(c.x + t2 * hx, 0.0, bounds.position.z - off2)
			1: p2 = Vector3(c.x + t2 * hx, 0.0, bounds.end.z + off2)
			2: p2 = Vector3(bounds.position.x - off2, 0.0, c.z + t2 * hz)
			3: p2 = Vector3(bounds.end.x + off2, 0.0, c.z + t2 * hz)
		var w := rng.randf_range(5.0, 9.0)
		var body := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(w, rng.randf_range(2.5, 4.5), rng.randf_range(4.0, 6.0))
		body.mesh = bm
		body.material_override = roof
		body.position = p2 + Vector3(0, bm.size.y / 2.0, 0)
		body.rotation.y = rng.randf_range(-0.4, 0.4)
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(body)
		var cap := MeshInstance3D.new()
		var pr := PrismMesh.new()
		pr.size = Vector3(w + 1.0, 1.6, bm.size.z + 1.0)
		cap.mesh = pr
		cap.material_override = roof
		cap.position = Vector3(0, bm.size.y / 2.0 + 0.8, 0)
		cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(cap)


## 遠方地標：天守（三層、窗戶亮著），只有外觀
func _landmark_keep(pos: Vector3, scale_k: float = 1.0) -> void:
	var wall := _mat(Color(0.82, 0.8, 0.74))
	var roof := _mat(Color(0.16, 0.18, 0.24))
	var win := _mat(Color(1.0, 0.75, 0.4), 1.0, true)
	var stone := _mat(Color(0.32, 0.32, 0.3))
	var y := 0.0
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(18, 6, 16) * scale_k
	base.mesh = bm
	base.material_override = stone
	base.position = pos + Vector3(0, bm.size.y / 2.0, 0)
	add_child(base)
	y = bm.size.y
	for tier in range(3):
		var w := (13.0 - tier * 3.2) * scale_k
		var h := 4.2 * scale_k
		var body := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(w, h, w * 0.85)
		body.mesh = b
		body.material_override = wall
		body.position = pos + Vector3(0, y + h / 2.0, 0)
		add_child(body)
		for k in range(3):
			var wi := MeshInstance3D.new()
			var wm := BoxMesh.new()
			wm.size = Vector3(0.9, 1.2, 0.1) * scale_k
			wi.mesh = wm
			wi.material_override = win
			wi.position = pos + Vector3((k - 1) * w * 0.28, y + h * 0.5, w * 0.425 + 0.06)
			add_child(wi)
		var cap := MeshInstance3D.new()
		var pr := PrismMesh.new()
		pr.size = Vector3(w + 3.0 * scale_k, 2.4 * scale_k, w * 0.85 + 3.0 * scale_k)
		cap.mesh = pr
		cap.material_override = roof
		cap.position = pos + Vector3(0, y + h + 1.2 * scale_k, 0)
		add_child(cap)
		y += h + 2.0 * scale_k
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.7, 0.4)
	glow.light_energy = 2.0
	glow.omni_range = 18.0
	add_child(glow)
	glow.global_position = pos + Vector3(0, y * 0.6, 12)


## 遠方地標：五重塔
func _landmark_pagoda(pos: Vector3) -> void:
	var red := _mat(Color(0.55, 0.16, 0.12))
	var roof := _mat(Color(0.15, 0.16, 0.2))
	var y := 0.0
	for tier in range(5):
		var w := 6.0 - tier * 0.7
		var body := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(w, 2.6, w)
		body.mesh = b
		body.material_override = red
		body.position = pos + Vector3(0, y + 1.3, 0)
		add_child(body)
		var cap := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = w * 0.35
		cm.bottom_radius = w * 0.95
		cm.height = 0.9
		cm.radial_segments = 4
		cap.mesh = cm
		cap.material_override = roof
		cap.rotation.y = PI / 4.0
		cap.position = pos + Vector3(0, y + 3.0, 0)
		add_child(cap)
		y += 3.3
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.75, 0.45)
	lamp.light_energy = 1.5
	lamp.omni_range = 10.0
	add_child(lamp)
	lamp.global_position = pos + Vector3(0, y * 0.5, 5)


## 俯瞰除錯畫面：--map  鏡頭拉到正上方，畫出每個決定點（紅字）與它的路線（彩色線）；鉤點本來就會發光
func _draw_decisions() -> void:
	var colors := [Color(1.0, 0.35, 0.3), Color(0.35, 0.8, 1.0), Color(0.5, 1.0, 0.45)]
	for d in decisions:
		var lb := Label3D.new()
		lb.text = String(d.id)
		lb.font_size = 160
		lb.pixel_size = 0.03
		lb.outline_size = 24
		lb.modulate = Color(1, 0.9, 0.3)
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.no_depth_test = true
		add_child(lb)
		lb.global_position = (d.pos as Vector3) + Vector3(0, 3.0, 0)
		var i := 0
		for r in d.routes:
			var im := ImmediateMesh.new()
			var mi := MeshInstance3D.new()
			mi.mesh = im
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = colors[i % colors.size()]
			m.no_depth_test = true
			mi.material_override = m
			im.surface_begin(Mesh.PRIMITIVE_LINES)
			var pts: Array = r.pts
			for k in range(pts.size() - 1):
				for w in [-0.15, 0.0, 0.15]:
					im.surface_add_vertex((pts[k] as Vector3) + Vector3(w, 0.4, w))
					im.surface_add_vertex((pts[k + 1] as Vector3) + Vector3(w, 0.4, w))
			im.surface_end()
			add_child(mi)
			var rl := Label3D.new()
			rl.text = String(r.name)
			rl.font_size = 90
			rl.pixel_size = 0.03
			rl.outline_size = 16
			rl.modulate = colors[i % colors.size()]
			rl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			rl.no_depth_test = true
			add_child(rl)
			rl.global_position = (pts[pts.size() / 2] as Vector3) + Vector3(0, 1.5, 0)
			i += 1


## 路線代價量測：--routes  每條路線算長度、亮處比例、靠近敵人的段數、鉤繩段數，代價＝長度＋危險×權重。
## 同一決定點最便宜與最貴的代價要差 30% 以上，不然等於「看起來有三條路、其實都一樣」。
func _measure_routes() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var all_ok := true
	for d in decisions:
		var costs: Array = []
		for r in d.routes:
			var pts: Array = r.pts
			var length := 0.0
			var lit := 0
			var danger := 0
			var hooks := 0
			var samples := 0
			for k in range(pts.size() - 1):
				var a: Vector3 = pts[k]
				var b: Vector3 = pts[k + 1]
				var seg := a.distance_to(b)
				length += seg
				if absf(b.y - a.y) > 1.2 or _near_hook_point(b):
					hooks += 1
				var n := maxi(int(seg), 1)
				for s in range(n):
					var p := a.lerp(b, float(s) / n)
					samples += 1
					for l in _lanterns:
						if l.lights(p):
							lit += 1
							break
					for e in get_tree().get_nodes_in_group("enemies"):
						if (e as Node3D).global_position.distance_to(p) < 7.0:
							danger += 1
							break
			var lit_k := float(lit) / maxf(samples, 1)
			var cost := length + float(danger) * 1.5 + lit_k * 20.0 + hooks * 2.0
			costs.append(cost)
			print("ROUTES %s %-6s 長 %5.1f m  亮處 %3d%%  近敵段 %3d  鉤 %d  → 代價 %.1f" % [d.id, r.name, length, int(lit_k * 100), danger, hooks, cost])
		var lo: float = costs.min()
		var hi: float = costs.max()
		var ok := hi >= lo * 1.3
		all_ok = all_ok and ok
		print("ROUTES %s 最便宜 %.1f 最貴 %.1f 差 %d%% %s" % [d.id, lo, hi, int((hi / maxf(lo, 0.01) - 1.0) * 100), "OK" if ok else "太接近"])
	print("ROUTES 總結：%s" % ("全部決定點都有明顯不同代價的路" if all_ok else "有決定點路線代價太接近"))
	get_tree().quit()


## 鉤繩路線實測：--hooktest  每條路線裡「下一點是鉤點」的段落：把半藏放在前一點、鏡頭轉向鉤點、
## 真的按一下鉤繩，1.3 秒後看有沒有落在那個鉤點上。印出每段 OK／失敗（失敗＝路線走不通）。
func _hook_test() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await get_tree().physics_frame
	var ok_n := 0
	var fail_n := 0
	for d in decisions:
		for r in d.routes:
			var pts: Array = r.pts
			for k in range(pts.size() - 1):
				var a: Vector3 = pts[k]
				var b: Vector3 = pts[k + 1]
				if not _near_hook_point(b):
					continue
				player.global_position = a + Vector3(0, 0.1, 0)
				player.velocity = Vector3.ZERO
				player.state = player.State.FREE
				player._hook_cd = 0.0
				await get_tree().physics_frame
				await get_tree().physics_frame
				var to := b - a
				cam_rig.yaw = atan2(-to.x, -to.z)
				cam_rig.aim_pitch = clampf(atan2(to.y + 0.5, Vector2(to.x, to.z).length()), -0.6, 0.9)
				await get_tree().process_frame
				await get_tree().process_frame
				var ray: Array = cam_rig.aim_ray()
				var pick = player._pick_hook_point(ray[0], ray[1])
				print("HOOKTEST   吸附到 %s  lock=%.2f state=%s" % [pick.global_position if pick else "（沒有）", player._lock_t, player.State.keys()[player.state]])
				if pick == null:
					var h: Dictionary = player._ray_visible(player.global_position + Vector3(0, 1.4, 0), b + Vector3(0, 0.8, 0), 1)
					var hn: Node = h.get("collider")
					print("HOOKTEST   視線打到 %s  在 %s  ghost=%s" % [hn.get_meta("desc", hn.name) if hn else "（沒擋）", h.get("position"), hn.has_meta("ghost") if hn else false])
				player.request_hook()
				await get_tree().create_timer(1.3).timeout
				var land: Vector3 = player.global_position
				var good := land.distance_to(b) < 1.8
				if good:
					ok_n += 1
				else:
					fail_n += 1
				print("HOOKTEST %s %s 段%d %s → %s：落在 %s %s" % [d.id, r.name, k, a, b, land, "OK" if good else "失敗"])
	print("HOOKTEST 總結：成功 %d 段、失敗 %d 段" % [ok_n, fail_n])
	get_tree().quit()


## 閃爍（z-fighting）掃描：--zfight  找出「朝同一方向、在同一個平面上、又互相重疊」的方塊面
## （兩個面搶同一個深度 → 畫面上條紋閃爍，就是常說的破圖）。印出每一對的描述，對回原始碼就找得到。
func _zfight_scan() -> void:
	await get_tree().process_frame
	var faces: Dictionary = {}
	var all: Array = []
	var stack: Array = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var mi := n as MeshInstance3D
		if mi == null or not (mi.mesh is BoxMesh) or not mi.is_visible_in_tree():
			continue
		var size: Vector3 = (mi.mesh as BoxMesh).size
		var xf := mi.global_transform
		for axis in range(3):
			for sgn in [-1.0, 1.0]:
				var col: Vector3 = xf.basis[axis]
				var nrm: Vector3 = col.normalized() * sgn
				if nrm.y < -0.9:
					continue   # 朝下的底面看不到
				var center: Vector3 = xf.origin + col * (size[axis] / 2.0) * sgn
				var j := (axis + 1) % 3
				var k := (axis + 2) % 3
				var u: Vector3 = xf.basis[j] * (size[j] / 2.0)
				var v: Vector3 = xf.basis[k] * (size[k] / 2.0)
				var d := nrm.dot(center)
				var f := {"mi": mi, "n": nrm, "c": center, "u": u, "v": v, "d": d}
				var key := "%d,%d,%d|%d" % [roundi(nrm.x * 50), roundi(nrm.y * 50), roundi(nrm.z * 50), roundi(d * 100)]
				if not faces.has(key):
					faces[key] = []
				faces[key].append(f)
				all.append([key, f])
	var hits := 0
	var seen := {}
	for e in all:
		var key: String = e[0]
		var f: Dictionary = e[1]
		var parts := key.split("|")
		var dk := int(parts[1])
		for dd in [-1, 0, 1]:
			var k2 := "%s|%d" % [parts[0], dk + dd]
			if not faces.has(k2):
				continue
			for g in faces[k2]:
				if g.mi == f.mi:
					continue
				var pair := "%d-%d" % [mini(f.mi.get_instance_id(), g.mi.get_instance_id()), maxi(f.mi.get_instance_id(), g.mi.get_instance_id())]
				if seen.has(pair):
					continue
				if (f.n as Vector3).dot(g.n) < 0.999 or absf(float(f.d) - float(g.d)) > 0.012:
					continue
				if _face_overlap(f, g) < 0.02:
					continue
				seen[pair] = true
				hits += 1
				if hits <= 80:
					print("ZFIGHT %s  ↔  %s" % [_desc_of(f.mi), _desc_of(g.mi)])
	print("ZFIGHT 總共 %d 對重疊的面" % hits)
	get_tree().quit()


func _face_overlap(f: Dictionary, g: Dictionary) -> float:
	var u: Vector3 = f.u
	var v: Vector3 = f.v
	var uh := u.normalized()
	var vh := v.normalized()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for su in [-1.0, 1.0]:
		for sv in [-1.0, 1.0]:
			var corner: Vector3 = (g.c as Vector3) + (g.u as Vector3) * su + (g.v as Vector3) * sv - (f.c as Vector3)
			var p := Vector2(corner.dot(uh), corner.dot(vh))
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var ox := minf(hi.x, u.length()) - maxf(lo.x, -u.length())
	var oy := minf(hi.y, v.length()) - maxf(lo.y, -v.length())
	return maxf(ox, 0.0) * maxf(oy, 0.0)


func _desc_of(n: Node) -> String:
	var w: Node = n
	while w:
		if w.has_meta("desc"):
			return String(w.get_meta("desc"))
		w = w.get_parent()
	return "%s @ %s" % [n.name, (n as Node3D).global_position]


## 脫困測試：--stucktest  在半藏周圍蓋一個 1 公尺見方的籠子（四面牆），推著搖桿 2.5 秒，看有沒有被放出來
func _stuck_test() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await get_tree().create_timer(0.5).timeout
	var c := player.global_position
	for side in [Vector3(0.75, 0, 0), Vector3(-0.75, 0, 0), Vector3(0, 0, 0.75), Vector3(0, 0, -0.75)]:
		var sz := Vector3(0.3, 3.0, 1.8) if side.x != 0.0 else Vector3(1.8, 3.0, 0.3)
		_box(c + side + Vector3(0, 1.5, 0), sz, Color(0.8, 0.2, 0.2))
	await get_tree().physics_frame
	hud.touch.move_vector = Vector2(0.0, -1.0)
	await get_tree().create_timer(2.5).timeout
	hud.touch.move_vector = Vector2.ZERO
	var moved := Vector2(player.global_position.x - c.x, player.global_position.z - c.z).length()
	print("STUCKTEST 從 %s 到 %s，移動 %.1f 公尺 → %s" % [c, player.global_position, moved, "脫困成功" if moved > 0.9 else "還卡著"])
	get_tree().quit()


## 頂牆測試：--wallpush  從起點往後（朝外牆）推搖桿 3 秒，不應該被脫困機制傳走
func _wall_push_test() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await get_tree().create_timer(0.5).timeout
	hud.touch.move_vector = Vector2(0.0, 1.0)
	await get_tree().create_timer(3.5).timeout
	var a := player.global_position
	await get_tree().create_timer(1.5).timeout
	hud.touch.move_vector = Vector2.ZERO
	print("WALLPUSH 頂牆 1.5 秒內位置變化 %.2f 公尺（應接近 0：沒有被亂傳）" % player.global_position.distance_to(a))
	get_tree().quit()


func _near_hook_point(p: Vector3) -> bool:
	for hp in get_tree().get_nodes_in_group("hook_points"):
		if (hp as Node3D).global_position.distance_to(p) < 1.6:
			return true
	return false


## 第十二次議會的關卡道具：油壺、稻草堆、焙烙玉、警鈴繩、水遁區
const PropScript := preload("res://scripts/props.gd")
const BellWireScript := preload("res://scripts/bell_wire.gd")
const WaterScript := preload("res://scripts/water.gd")


func _prop(kind: String, pos: Vector3, yaw_deg: float = 0.0) -> Node3D:
	var p: Node3D = PropScript.new()
	p.kind = kind
	add_child(p)
	p.global_position = pos
	p.rotation.y = deg_to_rad(yaw_deg)
	return p


func _oil_jar(pos: Vector3) -> Node3D:
	return _prop("oil", pos)


func _straw(pos: Vector3, yaw_deg: float = 0.0) -> Node3D:
	return _prop("straw", pos, yaw_deg)


func _bomb(pos: Vector3) -> Node3D:
	return _prop("bomb", pos)


func _bell_wire(a: Vector3, b: Vector3) -> Node3D:
	var w: Node3D = BellWireScript.new()
	w.a = a
	w.b = b
	add_child(w)
	return w


func _water(center: Vector3, size: Vector3) -> Node3D:
	var w: Node3D = WaterScript.new()
	w.size = size
	add_child(w)
	w.global_position = center
	return w


## 道具自動測試：--props  每種可互動道具依序：傳送到旁邊 → 看情境鍵文字 → 按下 → 印結果
## （第二關另測水遁、煙玉；有 --shot 時每步拍一張）
var _pt := 0.0
var _pstep := 0
var _pqueue: Array = []


func _props_test(delta: float) -> void:
	_pt += delta
	if _pstep == 0 and _pt > 1.0:
		_pstep = 1
		for n in get_tree().get_nodes_in_group("interactable"):
			_pqueue.append(n)
		for w in get_tree().get_nodes_in_group("water"):
			_pqueue.append(w)
		_pqueue.append("smoke")
		print("PROPS: %d items" % _pqueue.size())
		_pt = 0.0
		return
	if _pstep == 1:
		if _pqueue.is_empty():
			print("PROPS: done hp=%d" % player.hp)
			get_tree().quit()
			return
		if _pt < 0.1:
			return
		var it = _pqueue[0]
		if it is String:
			var e := _nearest_enemy_alive()
			if e:
				player.global_position = e.global_position + Vector3(0, 0.2, 4.0)
				e._go_alert()
		elif not is_instance_valid(it):
			pass
		elif it.is_in_group("water"):
			player.global_position = (it as Node3D).global_position + Vector3(0, 0.3, 0)
		else:
			var at := (it as Node3D).global_position + Vector3(float(it.interact_radius()) * 0.7, 0.3, 0.0)
			if it.get("a") is Vector3:
				at = ((it.a + it.b) / 2.0) + Vector3(0.6, 0.3, 0.6)
			player.global_position = at
		_pstep = 2
		_pt = 0.0
	elif _pstep == 2 and _pt > 0.5:
		var it = _pqueue[0]
		if it is String:
			player.weapon_mode = 2
			player.on_attack_down()
			print("PROPS: smoke left=%d smokes=%d state=%d" % [player.smoke, get_tree().get_nodes_in_group("smoke").size(), player.state])
		if it is String:
			var e := _nearest_enemy_alive()
			print("PROPS: after smoke enemy state=%s" % (Enemy.State.keys()[e.state] if e else "-"))
		elif is_instance_valid(it) and it.is_in_group("water"):
			print("PROPS: water submerged=%s breath=%.1f visible=%s" % [player.submerged, player.breath, player.visual.visible])
			_shot("props_water")
		elif is_instance_valid(it):
			print("PROPS: %s ctx='%s' rung=%s" % [it.get("kind") if it.get("kind") else "bell", player._ctx_label, it.get("rung")])
			_pstep = 3
			_pt = 0.0
			await _shot("props_%s_before" % str(_pqueue.size()))
			player.interact()
			if player.held_bomb:
				print("PROPS: holding bomb, ctx='%s'" % player._ctx_label)
				player.interact()
		_pstep = 3
		_pt = 0.0
	elif _pstep == 3 and _pt > 2.2:
		var ne := _nearest_enemy_alive()
		print("PROPS:   fires=%d in_light=%s hp=%d nearest=%s" % [get_tree().get_nodes_in_group("fires").size(), player.in_light, player.hp, Enemy.State.keys()[ne.state] if ne else "-"])
		_shot("props_smoke" if _pqueue[0] is String else "props_%s_after" % str(_pqueue.size()))
		player.hp = player.max_hp
		_pqueue.pop_front()
		_pstep = 1
		_pt = 0.0


## 鉤人高低差測試：--hookpull=x,y,z;ex,ez  玩家站在 (x,y,z)（台地上），最近的敵人放到地面 (ex,0,ez)，鉤過來，印敵人最後高度
var _hp_t := 0.0
var _hp_e: Enemy


func _hookpull_test(delta: float) -> void:
	_hp_t += delta
	var spec := ""
	for a in _extra_args:
		if a.begins_with("--hookpull="):
			spec = a.substr(11)
	var parts := spec.split(";")
	if parts.size() < 2:
		return
	var pv := parts[0].split_floats(",")
	var ev := parts[1].split_floats(",")
	if _hp_t > 1.0 and _hp_e == null:
		player.global_position = Vector3(pv[0], pv[1], pv[2])
		_hp_e = _nearest_enemy_alive()
		_hp_e.global_position = Vector3(ev[0], 0.0, ev[1])
		_hp_e.set_physics_process(true)
		print("HOOKPULL: enemy %s placed at %s" % [_hp_e.name, _hp_e.global_position])
	if _hp_t > 2.0 and not _auto_hp_done:
		_auto_hp_done = true
		if parts.size() > 2 and parts[2] == "nopull":
			return
		var dir := Vector3(ev[0] - pv[0], 0, ev[1] - pv[2]).normalized()
		_hp_e.hooked(player.global_position + dir * 1.6, 1, false, player, 0.45)
	if _hp_t > 4.0:
		print("HOOKPULL: player %s enemy %s embedded=%s" % [player.global_position, _hp_e.global_position, _hp_e._embedded()])
		_shot("hookpull")
		get_tree().quit()


var _auto_hp_done := false


func _nearest_enemy_alive() -> Enemy:
	var best: Enemy = null
	var bd := 1e9
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.state != Enemy.State.DEAD and e.kind != Enemy.Kind.LORD:
			var d: float = e.global_position.distance_to(player.global_position)
			if d < bd:
				bd = d
				best = e
	return best


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
	(_pivot if _pivot else _region).add_child(sb)
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
