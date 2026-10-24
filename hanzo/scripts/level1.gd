extends "res://scripts/level_base.gd"
## 第一關：伊賀夜襲 — 今川軍在伊賀山村的本營。
## 路線是 S 形、三層高度：東南角山門 → 村落（西北向，農家斜放、櫓是地標）→ 西側石階上第一台地（長屋）
## → 東側石階上第二台地（練兵場、土藏）→ 東北角陣屋（副將守著大將）→ 後門 → 出城。
## 站在山門看不到台地的階梯（被櫓、樹、農家擋住）；村落西邊有條死巷藏口糧；台地東南角有第二條階梯繞回村落（環）。
## 大將一察覺動靜就從後門逃走（門在他身後關上），殺了副將後門才開 → 追出去就過關。
##
## 自動試玩：godot --path hanzo scenes/level1.tscn ++ --shot=<dir> --walk

const T1 := 1.8            # 第一台地
const T2 := 3.6            # 第二台地（本陣）
const HALL_Y := T2 + 0.6   # 陣屋地板
const HX := 12.0           # 陣屋中心
const HZ := -22.0
const REAR_GATE := Vector3(HX, T2, -32.5)

var _lord: Enemy
var _vice: Enemy
var _lord_fled := false
var _walk := false
var _walk_t := 0.0
var _auto_done := {}


func _init() -> void:
	level_title = "伊賀夜襲"
	objective_text = "潛入今川軍本營，取下大將首級"
	start_pos = Vector3(15.0, 0.1, 29.0)
	exit_pos = Vector3(HX, T2, -35.0)
	checkpoints = [Vector3(15.0, 0.0, 29.0), Vector3(-2.0, 0.0, 14.0), Vector3(-12.0, T1, -4.0), Vector3(4.0, T2, -12.0)]
	next_scene = "res://scenes/level2.tscn"
	next_label = "下一關：湖畔屋敷"
	bounds = AABB(Vector3(-23.5, -1.0, -37.5), Vector3(47.0, 22.0, 73.0))


func _on_level_ready() -> void:
	hud.set_compass_target(Vector3(HX, HALL_Y, HZ - 1.0), Color(1.0, 0.8, 0.3))
	$Moon.rotation_degrees = Vector3(-52.0, 25.0, 0.0)
	_walk = _extra_args.has("--walk")


# ---------------------------------------------------------------- 世界

func _build_world() -> void:
	var dirt := Color(0.17, 0.17, 0.15)
	var stone := Color(0.42, 0.42, 0.4)
	var cliff := Color(0.3, 0.3, 0.28)
	var wood := Color(0.32, 0.24, 0.16)
	var plaster := Color(0.78, 0.74, 0.66)
	var roof := Color(0.2, 0.22, 0.27)
	var thatch := Color(0.45, 0.38, 0.22)
	var palisade := Color(0.26, 0.2, 0.13)
	var gravel := Color(0.3, 0.29, 0.27)

	_ground(110.0, dirt)

	# 兩層台地：第一台地在西北（x -21..3, z -16..4），第二台地在東北（x -4..21, z -32..-8）
	_terrace(-9.0, -6.0, 24.0, 20.0, T1, cliff)
	_terrace(8.5, -20.0, 25.0, 24.0, T2, cliff.darkened(0.1))
	# 台地邊緣的岩石：打破直線
	_rock(Vector3(-6.0, 0.0, 5.0), 1.3, 20.0, stone)
	_rock(Vector3(-19.5, 0.0, 5.2), 1.0, -35.0, stone)
	_rock(Vector3(3.6, 0.0, 1.0), 1.1, 50.0, stone)
	_rock(Vector3(-6.0, 0.0, -20.0), 1.6, 15.0, stone)
	_rock(Vector3(-6.5, 0.0, -27.0), 1.2, -20.0, stone)
	_rock(Vector3(22.0, 0.0, -7.0), 1.4, 40.0, stone)
	_rock(Vector3(-4.5, T1, -7.0), 0.9, 10.0, stone)
	_rock(Vector3(-22.0, 0.0, 14.0), 1.5, 70.0, stone)

	# 石階：村落西側上第一台地（藏在農家後面）；第一台地東側上第二台地；第一台地東南角繞回村落（環）
	_ramp_z(-14.0, 8.0, 4.0, 0.0, T1, 4.0, stone)
	_ramp_x(-12.0, -10.0, -4.0, T1, T2, 4.0, stone)
	_ramp_z(1.0, 8.0, 4.0, 0.0, T1, 3.0, stone)
	_stone_lantern(Vector3(-16.6, 0.0, 8.6))
	_stone_lantern(Vector3(-11.4, 0.0, 8.6))
	_stone_lantern(Vector3(-10.0, T1, -9.0))
	_stone_lantern(Vector3(-10.0, T1, -15.0))

	# 外圍木柵（折線，看起來 2.2 公尺，碰撞 14 公尺）；北側留後門
	_fence_poly([
		Vector3(17.0, 0.0, 34.0), Vector3(-6.0, 0.0, 33.0), Vector3(-21.0, 0.0, 27.0), Vector3(-22.5, 0.0, 3.0),
		Vector3(-21.5, T1, -16.5), Vector3(-5.0, T1, -16.5), Vector3(-4.5, T2, -32.5), Vector3(HX - 2.5, T2, -32.5),
	], 2.2, palisade, 14.0)
	_fence_poly([
		Vector3(HX + 2.5, T2, -32.5), Vector3(22.0, T2, -32.5), Vector3(22.0, T2, -8.5), Vector3(22.8, 0.0, -7.5),
		Vector3(22.5, 0.0, 20.0), Vector3(17.0, 0.0, 34.0),
	], 2.2, palisade, 14.0)
	# 後門外的小段柵欄與盡頭（出口在門外）
	_fence_poly([Vector3(HX - 6.0, T2, -37.0), Vector3(HX + 6.0, T2, -37.0)], 2.2, palisade, 14.0)
	_fence_poly([Vector3(HX - 6.0, T2, -32.5), Vector3(HX - 6.0, T2, -37.0)], 2.2, palisade, 14.0)
	_fence_poly([Vector3(HX + 6.0, T2, -32.5), Vector3(HX + 6.0, T2, -37.0)], 2.2, palisade, 14.0)

	# 山門（斜放的鳥居）與小路：東南角起點，彎向西北
	_group_begin(Vector3(12.0, 0.0, 26.0), 35.0)
	_torii(Vector3.ZERO)
	_stone_lantern(Vector3(-3.0, 0.0, -1.0))
	_stone_lantern(Vector3(3.0, 0.0, -1.0))
	_group_end()
	_path_poly([Vector3(15.0, 0.0, 30.0), Vector3(10.0, 0.0, 23.0), Vector3(3.0, 0.0, 18.0), Vector3(-5.0, 0.0, 13.0), Vector3(-12.0, 0.0, 8.5), Vector3(-14.0, 0.0, 6.0)], 2.6, gravel)

	# 村落：兩間斜放的農家、水井、菜畦、松樹、櫓（地標，從哪裡都看得到）
	_group_begin(Vector3(-8.0, 0.0, 14.0), 20.0)
	_hut(0.0, 0.0, 5.0, 4.0, 2.4, 0.0, plaster, thatch, "e", 1.3)
	_group_end()
	_group_begin(Vector3(6.0, 0.0, 20.0), -15.0)
	_hut(0.0, 0.0, 5.0, 4.0, 2.4, 0.0, plaster, thatch, "w", 1.3)
	_group_end()
	_group_begin(Vector3(-1.0, 0.0, 20.0), 15.0)
	_box(Vector3(0.0, 0.5, 0.0), Vector3(1.6, 1.0, 1.6), stone)                       # 水井
	_box(Vector3(0.0, 1.9, 0.0), Vector3(1.8, 0.1, 1.8), wood, Vector3.ZERO, false)   # 井蓋
	_group_end()
	_group_begin(Vector3(3.0, 0.0, 10.0), 30.0)
	for i in range(4):
		_box(Vector3(-1.8 + i * 1.2, 0.12, 0.0), Vector3(0.8, 0.24, 5.0), Color(0.22, 0.2, 0.14), Vector3.ZERO, false)  # 菜畦
	_group_end()
	_group_begin(Vector3(4.0, 0.0, 3.0), 15.0)
	_tower(0.0, 0.0, 5.0, 0.0, wood, roof)
	_group_end()
	_tree(Vector3(0.0, 0.0, 9.0), 1.2)
	_tree(Vector3(-5.0, 0.0, 17.5), 1.0)
	_tree(Vector3(16.0, 0.0, 20.0), 0.9)
	_tree(Vector3(-18.0, 0.0, 22.0), 1.0)
	_tree(Vector3(8.0, 0.0, 31.0), 0.8)
	_tree(Vector3(-19.5, 0.0, 2.0), 0.9)
	_tree(Vector3(19.0, 0.0, 8.0), 1.1)
	_lantern(Vector3(-4.0, 0.0, 22.0))
	_lantern(Vector3(7.0, 0.0, 12.0))
	_lantern(Vector3(-12.0, 0.0, 11.0))
	_lantern(Vector3(13.0, 0.0, 30.0))
	# 西邊死巷：農家後面一條窄路，盡頭有口糧
	_fence_poly([Vector3(-14.5, 0.0, 18.0), Vector3(-15.0, 0.0, 10.5)], 1.6, palisade, 14.0)
	_ration(Vector3(-19.0, 0.0, 11.0))

	# 第一台地：長屋（斜放，屋頂可走可鉤）、練兵木樁、松
	_group_begin(Vector3(-13.0, T1, -8.0), 8.0)
	_hut(0.0, 0.0, 5.0, 12.0, 2.6, 0.0, plaster, roof, "e", 1.2)
	_group_end()
	_group_begin(Vector3(-3.0, T1, 0.0), 20.0)
	for i in range(3):
		_box(Vector3(-2.0 + i * 2.0, 0.9, 0.0), Vector3(0.3, 1.8, 0.3), thatch)
	_box(Vector3(0.0, 0.02, -0.5), Vector3(7.0, 0.04, 4.0), Color(0.3, 0.27, 0.22), Vector3.ZERO, false)
	_group_end()
	_tree(Vector3(-19.5, T1, -3.0), 0.9)
	_tree(Vector3(-2.0, T1, -13.5), 0.8)
	_lantern(Vector3(-5.0, T1, -2.0))
	_lantern(Vector3(-17.0, T1, -14.5))
	_lantern(Vector3(-8.0, T1, -12.0))

	# 第二台地：土藏（兩層高，斜放）、陣幕、燈籠、松；本陣在東北角
	_group_begin(Vector3(14.0, T2, -12.0), -12.0)
	_box(Vector3(0.0, 2.25, 0.0), Vector3(5.0, 4.5, 6.0), Color(0.86, 0.84, 0.8))
	_gable(0.0, 0.0, 5.0, 6.0, 4.5, 0.9, roof, true, 0.5)
	_box(Vector3(0.0, 1.0, 3.15), Vector3(1.4, 2.0, 0.3), wood, Vector3.ZERO, false)
	_group_end()
	_group_begin(Vector3(5.0, T2, -16.5), -8.0)
	for side in [-1.0, 1.0]:
		_box(Vector3(side * 4.0, 1.0, 0.0), Vector3(6.0, 2.0, 0.12), Color(0.1, 0.1, 0.12))
		_box(Vector3(side * 4.0, 1.0, 0.0), Vector3(6.0, 0.5, 0.14), Color(0.75, 0.15, 0.12), Vector3.ZERO, false)
	_group_end()
	_tree(Vector3(19.5, T2, -30.0), 0.8)
	_tree(Vector3(0.0, T2, -30.0), 0.9)
	_tree(Vector3(-1.5, T2, -22.0), 0.8)
	_lantern(Vector3(1.5, T2, -10.0))
	_lantern(Vector3(19.0, T2, -16.0))
	_lantern(Vector3(4.0, T2, -25.0))
	_lantern(Vector3(19.5, T2, -25.0))
	_path_poly([Vector3(-6.0, T2, -12.0), Vector3(2.0, T2, -13.0), Vector3(8.0, T2, -16.5), Vector3(HX, T2, -17.5)], 2.4, gravel)
	_hall()

	# 後門：殺了副將才開；大將逃跑時會先開再關
	_gate("rear", REAR_GATE, 4.0, 2.4, true, wood)
	_path_poly([Vector3(HX, T2, -26.5), Vector3(HX, T2, -35.5)], 2.4, gravel)


## 陣屋：12×8 高床，三面牆、前面敞開（帳幕），後牆留門
func _hall() -> void:
	var wood := Color(0.3, 0.22, 0.14)
	var plaster := Color(0.8, 0.76, 0.68)
	var roof := Color(0.2, 0.22, 0.27)
	var cx := HX
	var cz := HZ
	var sx := 12.0
	var sz := 8.0
	# 高床（可走上去）＋前緣階梯
	_box(Vector3(cx, T2 + 0.3, cz), Vector3(sx, 0.6, sz), wood)
	_ramp_z(cx, cz + sz / 2.0 + 1.2, cz + sz / 2.0, T2, HALL_Y, 4.0, wood.lightened(0.1))
	# 側牆
	for side in [-1.0, 1.0]:
		_box(Vector3(cx + side * sx / 2.0, HALL_Y + 1.5, cz), Vector3(0.25, 3.0, sz), plaster)
	# 後牆留門（1.8 公尺）
	_wall_with_gap(cx - sx / 2.0, cx + sx / 2.0, cz - sz / 2.0, true, cx, 1.8, func(x: float, z: float, len: float) -> void:
		_box(Vector3(x, HALL_Y + 1.5, z), Vector3(len, 3.0, 0.25), plaster))
	# 前面：柱子＋橫楣
	for x in [-6.0, -2.0, 2.0, 6.0]:
		_box(Vector3(cx + x, HALL_Y + 1.5, cz + sz / 2.0), Vector3(0.3, 3.0, 0.3), wood)
	_box(Vector3(cx, HALL_Y + 2.9, cz + sz / 2.0), Vector3(sx, 0.25, 0.3), wood, Vector3.ZERO, false)
	# 屋頂（屋脊沿 x）：人在陣屋裡就隱藏
	_cover_begin("hall", AABB(Vector3(cx - sx / 2.0 - 1.0, T2 - 0.3, cz - sz / 2.0 - 1.0), Vector3(sx + 2.0, 3.6, sz + 2.5)))
	_gable(cx, cz, sx, sz, HALL_Y + 3.0, 1.6, roof, false, 0.8)
	_cover_end()
	# 室內：軍議桌、屏風、燭台
	_box(Vector3(cx, HALL_Y + 0.35, cz - 1.5), Vector3(2.4, 0.7, 1.2), wood.darkened(0.2))
	_box(Vector3(cx, HALL_Y + 1.0, cz - 3.0), Vector3(3.6, 2.0, 0.1), Color(0.85, 0.7, 0.3), Vector3.ZERO, false)  # 金屏風
	_lantern(Vector3(cx - 4.5, HALL_Y, cz - 2.0))
	_lantern(Vector3(cx + 4.5, HALL_Y, cz - 2.0))


## 口糧（關卡擺放的，死巷獎勵）
func _ration(pos: Vector3) -> void:
	var r := Ration.new()
	add_child(r)
	r.global_position = pos


# ---------------------------------------------------------------- 敵人與故事

func _spawn_enemies() -> void:
	# 村落：一個巡邏繞村、一個守死巷口
	_spawn(Enemy.Kind.ASHIGARU, Vector3(10.0, 0.0, 22.0), [Vector3(10.0, 0.0, 22.0), Vector3(2.0, 0.0, 16.5), Vector3(-6.0, 0.0, 11.5), Vector3(-11.0, 0.0, 9.0), Vector3(-5.0, 0.0, 20.0), Vector3(3.0, 0.0, 25.0)])
	_spawn(Enemy.Kind.ASHIGARU, Vector3(-16.5, 0.0, 13.0), [], Vector3(1.0, 0.0, -0.3))
	# 櫓上的弓兵（卷軸也在上面）
	_spawn(Enemy.Kind.ARCHER, Vector3(4.0, 5.0, 3.0), [], Vector3(-1.0, 0.0, 0.3))
	# 第一台地：武士繞長屋巡邏
	_spawn(Enemy.Kind.SAMURAI, Vector3(-9.0, T1, -3.0), [Vector3(-9.0, T1, -3.0), Vector3(-4.0, T1, -10.0), Vector3(-15.0, T1, -14.0), Vector3(-19.0, T1, -5.0)])
	# 第二台地：階梯口哨兵、練兵場巡邏
	_spawn(Enemy.Kind.ASHIGARU, Vector3(-1.0, T2, -12.0), [], Vector3(-1.0, 0.0, 0.0))
	_spawn(Enemy.Kind.ASHIGARU, Vector3(8.0, T2, -13.0), [Vector3(8.0, T2, -13.0), Vector3(2.0, T2, -27.0), Vector3(17.0, T2, -29.0)])
	if not _target_dead:
		# 副將：守在陣屋前段，面向入口（要暗殺得從後門或屋頂來）
		_vice = _spawn(Enemy.Kind.TARGET, Vector3(HX, HALL_Y, HZ + 2.5), [], Vector3(0.0, 0.0, 1.0))
		_vice.name = "Vice"
	if not _lord_fled:
		_lord = _spawn(Enemy.Kind.LORD, Vector3(HX, HALL_Y, HZ - 1.5), [], Vector3(0.0, 0.0, -1.0))
		_lord.flee_route = [Vector3(HX, HALL_Y, HZ - 3.5), Vector3(HX, T2, -28.5), Vector3(HX, T2, -35.5)]
		_lord.flee_started.connect(_on_lord_flee)
		_lord.escaped.connect(_on_lord_escaped)
	_respawn_scrolls()


## 卷軸「手裡劍 ×7」：櫓的平台上（弓兵旁邊）
func _respawn_scrolls() -> void:
	_scroll(Vector3(3.2, 5.05, 2.2), "shuriken7")


func _after_respawn() -> void:
	if _target_dead:
		_gate_set("rear", true)


func _on_lord_flee(_e: Enemy) -> void:
	if _lord_fled:
		return
	_lord_fled = true
	_gate_set("rear", true)
	hud.say("大將逃了！", Color(0.95, 0.6, 1.0))
	if _target_dead:
		hud.set_objective("大將往後門逃了，追上去")
		_open_exit("追擊")
	else:
		hud.set_objective("大將逃了！解決守著後門的副將，追出去")
		hud.set_compass_target(Vector3(HX, HALL_Y, HZ + 2.5), Color(1.0, 0.8, 0.3))


func _on_lord_escaped(_e: Enemy) -> void:
	# 門在他身後關上；副將死了才會再開
	if not _target_dead:
		_gate_set("rear", false)


func _on_enemy_died_hook(e: Enemy, _stealth: bool) -> void:
	if e.kind != Enemy.Kind.TARGET or _target_dead:
		return
	_target_dead = true
	if is_instance_valid(_lord) and not _lord_fled:
		# 副將倒下的動靜驚動大將
		_lord.start_flee()
	hud.set_objective("副將已除。大將往後門逃了，追上去")
	get_tree().create_timer(1.6).timeout.connect(func() -> void:
		_gate_set("rear", true)
		_open_exit("追擊"))


# ---------------------------------------------------------------- 自動試玩

## 故事流程自動測試：--story  把半藏丟到陣屋前 → 副將發現 → 大將逃、門關 → 殺副將 → 門開 → 走到出口過關
var _story := false
var _story_t := 0.0


func _process(delta: float) -> void:
	super(delta)
	if _extra_args.has("--story") and not _story:
		_story = true
	if _story:
		_story_t += delta
		if _story_t > 1.0 and not _auto_done.has("s1"):
			_auto_done["s1"] = true
			player.global_position = Vector3(HX, HALL_Y + 0.1, HZ + 4.5)
			print("STORY: player at hall front")
		if _story_t > 5.0 and not _auto_done.has("s2"):
			_auto_done["s2"] = true
			print("STORY: lord_fled=%s lord_valid=%s gate_open=%s" % [_lord_fled, is_instance_valid(_lord), _gates["rear"].open])
		if _story_t > 6.0 and not _auto_done.has("s3"):
			_auto_done["s3"] = true
			if is_instance_valid(_vice):
				_vice._die(false)
			print("STORY: vice killed")
		if _story_t > 8.5 and not _auto_done.has("s4"):
			_auto_done["s4"] = true
			print("STORY: target_dead=%s gate_open=%s exit_ready=%s" % [_target_dead, _gates["rear"].open, _exit_ready])
			player.global_position = exit_pos + Vector3(0.0, 0.1, 0.0)
		if _story_t > 10.0 and not _auto_done.has("s5"):
			_auto_done["s5"] = true
			print("STORY: finished=%s" % _finished)
			get_tree().quit()
		return
	if not _walk:
		return
	_walk_t += delta
	hud.touch.move_vector = Vector2(0.0, -1.0) if _walk_t < 1.3 else Vector2.ZERO
	if _walk_t > 1.35 and not _auto_done.has("look"):
		_auto_done["look"] = true
		cam_rig.yaw = -PI / 2.0
		cam_rig.aim_pitch = -0.05
	if _walk_t > 1.7 and not _auto_done.has("aim"):
		_auto_done["aim"] = true
		player.on_hook_down()
	if _walk_t > 2.5 and not _auto_done.has("shot_aim"):
		_auto_done["shot_aim"] = true
		_shot("aim_hook")
	if _walk_t > 2.6 and not _auto_done.has("grapple"):
		_auto_done["grapple"] = true
		player.on_hook_up()
	if _walk_t > 3.5 and not _auto_done.has("shot_grapple"):
		_auto_done["shot_grapple"] = true
		_shot("grapple")
	if _walk_t > 3.8 and not _auto_done.has("aim2"):
		_auto_done["aim2"] = true
		cam_rig.yaw = PI
		cam_rig.aim_pitch = 0.25
		player.toggle_weapon()
		player.on_attack_down()
	if _walk_t > 4.6 and not _auto_done.has("shot_aim2"):
		_auto_done["shot_aim2"] = true
		_shot("aim_shuriken")
	if _walk_t > 4.7 and not _auto_done.has("throw"):
		_auto_done["throw"] = true
		player.on_attack_up()
	if _walk_t > 5.0 and not _auto_done.has("shot_throw"):
		_auto_done["shot_throw"] = true
		_shot("throw")
	if _walk_t > 6.5 and not _auto_done.has("shot_end"):
		_auto_done["shot_end"] = true
		cam_rig.yaw = 0.0
		_shot("end")
	if _walk_t > 7.0:
		get_tree().quit()
