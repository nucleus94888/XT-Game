extends "res://scripts/level_base.gd"
## 第二關：湖畔屋敷 — 大將從伊賀逃到山下的屋敷。
## 山道（高處俯瞰）→ 池泉庭園（石橋、茶室、松）→ 屋敷一樓（緣側、障子隔間、走廊）→
## 二樓（樓梯、奧座敷的大將、北側露台）→ 殺了大將後鉤上屋頂撤離。

const F1 := 0.6   # 一樓地板
const F2 := 3.6   # 二樓地板
const HILL := 3.0

var _lord: Enemy


func _init() -> void:
	level_title = "湖畔屋敷"
	objective_text = "追進屋敷，取下大將首級"
	start_pos = Vector3(0.0, HILL + 0.1, 28.0)
	exit_pos = Vector3(0.0, 8.1, -16.75)
	checkpoints = [Vector3(0.0, HILL, 28.0), Vector3(0.0, 0.0, 12.0), Vector3(0.0, F1, -3.0), Vector3(10.5, F2, -10.5)]
	next_scene = "res://scenes/level3.tscn"
	next_label = "下一關：夜之城下町"
	bounds = AABB(Vector3(-20.4, -1.0, -31.0), Vector3(40.8, 20.0, 64.0))


func _on_level_ready() -> void:
	hud.set_compass_target(Vector3(0.0, F2, -18.5), Color(1.0, 0.8, 0.3))
	$Moon.rotation_degrees = Vector3(-48.0, -35.0, 0.0)


# ---------------------------------------------------------------- 世界

func _build_world() -> void:
	var moss := Color(0.13, 0.19, 0.13)
	var gravel := Color(0.36, 0.34, 0.3)
	var stone := Color(0.42, 0.42, 0.4)
	var wood := Color(0.32, 0.24, 0.16)
	var dark_wood := Color(0.22, 0.16, 0.1)
	var roof := Color(0.2, 0.22, 0.27)
	var thatch := Color(0.45, 0.38, 0.22)
	var tatami := Color(0.55, 0.52, 0.32)
	var water := Color(0.1, 0.2, 0.3)
	var fence := Color(0.28, 0.21, 0.14)

	_ground(90.0, moss)
	# 山道：南側高台，石階下到庭園
	_terrace(0.0, 25.5, 44.0, 15.0, HILL, Color(0.2, 0.23, 0.18))
	_ramp_z(0.0, 18.0, 12.0, HILL, 0.0, 4.0, stone)
	_box(Vector3(0.0, HILL + 0.03, 25.0), Vector3(3.0, 0.06, 14.0), gravel, Vector3.ZERO, false)
	_stone_lantern(Vector3(-2.8, HILL, 19.0))
	_stone_lantern(Vector3(2.8, HILL, 19.0))
	_tree(Vector3(-8.0, HILL, 24.0), 1.2)
	_tree(Vector3(9.0, HILL, 22.0), 1.0)
	_tree(Vector3(-15.0, HILL, 20.0), 0.9)
	_tree(Vector3(16.0, HILL, 26.0), 1.1)
	_lantern(Vector3(0.0, HILL, 30.5))

	# 板塀（外圍）：看起來 2 公尺，碰撞 12 公尺
	_fence(-20.5, 1.0, 64.0, false, 2.0, fence, 0.0, 12.0)
	_fence(20.5, 1.0, 64.0, false, 2.0, fence, 0.0, 12.0)
	_fence(0.0, 33.0, 42.0, true, 2.0, fence, HILL, 12.0)
	_fence(0.0, -31.5, 42.0, true, 2.0, fence, 0.0, 12.0)

	# 庭園：碎石路、池、石橋、茶室、松、燈籠
	_box(Vector3(0.0, 0.03, 6.0), Vector3(3.0, 0.06, 14.0), gravel, Vector3.ZERO, false)
	# 池（可涉水）：水面抬高 3 公分，不然和地面同高會 z-fighting 閃爍
	_box(Vector3(-9.0, -0.37, 8.0), Vector3(9.0, 0.8, 6.0), water, Vector3.ZERO, true, 0.2)
	_box(Vector3(-9.0, 0.25, 8.0), Vector3(1.6, 0.3, 7.6), stone)                               # 石橋
	for p in [Vector3(-13.8, 0.0, 11.2), Vector3(-4.2, 0.0, 4.8), Vector3(-5.0, 0.0, 11.5)]:
		_box(p + Vector3(0.0, 0.35, 0.0), Vector3(1.2, 0.7, 0.9), stone.darkened(0.2))              # 庭石
	_hut(11.0, 9.0, 4.0, 4.0, 2.4, 0.0, Color(0.78, 0.74, 0.66), thatch, "w", 1.0)              # 茶室
	_tree(Vector3(-16.0, 0.0, 14.0), 1.1)
	_tree(Vector3(16.5, 0.0, 15.0), 1.0)
	_tree(Vector3(-15.5, 0.0, 1.5), 0.9)
	_tree(Vector3(17.0, 0.0, 2.5), 1.2)
	_tree(Vector3(5.5, 0.0, 16.0), 0.8)
	_stone_lantern(Vector3(-12.5, 0.0, 4.5))
	_stone_lantern(Vector3(-5.0, 0.0, 12.5))
	_lantern(Vector3(3.0, 0.0, 12.5))
	_lantern(Vector3(-3.0, 0.0, 2.5))
	_lantern(Vector3(13.0, 0.0, 3.0))
	_lantern(Vector3(-14.5, 0.0, 9.0))

	# 屋敷
	_mansion(wood, dark_wood, roof, tatami)
	_lantern(Vector3(-3.0, 0.0, -1.0))
	_lantern(Vector3(3.0, 0.0, -1.0))


func _mansion(wood: Color, dark_wood: Color, roof: Color, tatami: Color) -> void:
	var shoji_h := 2.8
	# 高床（緣側含在內）：x -14..14, z -24..-2
	_box(Vector3(0.0, F1 / 2.0, -13.0), Vector3(28.0, F1, 22.0), dark_wood)
	_box(Vector3(0.0, F1 + 0.02, -13.0), Vector3(25.0, 0.04, 19.0), tatami, Vector3.ZERO, false)
	# 緣側邊的階梯
	_ramp_z(0.0, -0.4, -2.0, 0.0, F1, 3.0, wood)
	_ramp_z(0.0, -25.6, -24.0, 0.0, F1, 3.0, wood)
	_ramp_x(-13.0, -15.6, -14.0, 0.0, F1, 3.0, wood)
	# 緣側柱子
	for x in [-14.0, -7.0, 0.0, 7.0, 14.0]:
		for z in [-2.0, -24.0]:
			_box(Vector3(x, F1 + 1.4, z), Vector3(0.3, 2.8, 0.3), wood)
	for z in [-9.0, -16.0]:
		for x in [-14.0, 14.0]:
			_box(Vector3(x, F1 + 1.4, z), Vector3(0.3, 2.8, 0.3), wood)

	# 一樓外牆（障子，內縮 1.5 當緣側）
	var sh := func(x: float, z: float, len: float, along_x: bool) -> void:
		_shoji(x, z, len, along_x, shoji_h, F1)
	_wall_with_gap(-12.5, 12.5, -3.5, true, 0.0, 2.0, func(x: float, z: float, len: float) -> void: sh.call(x, z, len, true))     # 前
	_wall_with_gap(-12.5, 12.5, -22.5, true, 0.0, 2.0, func(x: float, z: float, len: float) -> void: sh.call(x, z, len, true))    # 後
	_wall_with_gap(-22.5, -3.5, -12.5, false, -13.0, 1.8, func(x: float, z: float, len: float) -> void: sh.call(x, z, len, false))  # 西
	sh.call(12.5, -13.0, 19.0, false)                                                                                              # 東
	# 一樓內牆：中央走廊兩側（門口通各房間）
	for side in [-1.0, 1.0]:
		var x: float = side * 1.5
		var pieces := [[-3.5, -6.1], [-7.9, -12.6], [-14.4, -18.6], [-20.4, -22.5]]
		for p in pieces:
			var z0: float = p[0]
			var z1: float = p[1]
			sh.call(x, (z0 + z1) / 2.0, absf(z1 - z0), false)
		# 房間隔間（沿 x）
		for z in [-10.0, -16.5]:
			_wall_with_gap(side * 1.5, side * 12.5, z, true, side * 9.5, 1.6, func(x2: float, z2: float, len: float) -> void: sh.call(x2, z2, len, true))
	# 樓梯：東前房，沿 z 往北爬到二樓
	_ramp_z(10.5, -3.8, -9.5, F1, F2, 2.0, wood)
	_box(Vector3(9.4, F1 + 1.0, -6.65), Vector3(0.1, 1.2, 5.7), wood, Vector3.ZERO, false)   # 扶手（裝飾）
	# 二樓地板（也是後段一樓的天花板）：z -24..-9.5。半藏在一樓後段時整個二樓隱藏
	_cover_begin("floor2", AABB(Vector3(-14.5, -0.5, -25.0), Vector3(29.0, F2 - 0.3 + 0.5, 15.5)))
	_box(Vector3(0.0, F2 - 0.1, -16.75), Vector3(28.0, 0.2, 14.5), dark_wood)
	_box(Vector3(0.0, F2 + 0.02, -16.75), Vector3(25.0, 0.04, 12.0), tatami, Vector3.ZERO, false)
	# 二樓外牆：前（留樓梯口）、後（留露台門）、東西
	var sh2 := func(x: float, z: float, len: float, along_x: bool) -> void:
		_shoji(x, z, len, along_x, shoji_h, F2)
	_wall_with_gap(-12.5, 12.5, -10.0, true, 10.5, 2.4, func(x: float, z: float, len: float) -> void: sh2.call(x, z, len, true))
	_wall_with_gap(-12.5, 12.5, -22.5, true, 0.0, 2.0, func(x: float, z: float, len: float) -> void: sh2.call(x, z, len, true))
	sh2.call(-12.5, -16.25, 12.5, false)
	sh2.call(12.5, -16.25, 12.5, false)
	# 二樓內牆：奧座敷（x -6..6, z -22.5..-14）南面留門；兩翼牆留門
	_wall_with_gap(-6.0, 6.0, -14.0, true, 0.0, 2.0, func(x: float, z: float, len: float) -> void: sh2.call(x, z, len, true))
	for side in [-1.0, 1.0]:
		_wall_with_gap(-22.5, -14.0, side * 6.0, false, -18.0, 1.8, func(x: float, z: float, len: float) -> void: sh2.call(x, z, len, false))
	# 北側露台（從後院鉤上來的潛入路線）
	_box(Vector3(0.0, F2 - 0.1, -23.6), Vector3(6.0, 0.2, 2.2), wood)
	_box(Vector3(0.0, F2 + 0.5, -24.7), Vector3(6.0, 0.08, 0.08), wood, Vector3.ZERO, false)
	for x in [-3.0, 0.0, 3.0]:
		_box(Vector3(x, F2 + 0.5, -24.7), Vector3(0.12, 1.0, 0.12), wood, Vector3.ZERO, false)
	# 奧座敷陳設：床之間、屏風、刀架
	_box(Vector3(0.0, F2 + 0.15, -21.5), Vector3(4.0, 0.3, 1.2), dark_wood)
	_box(Vector3(0.0, F2 + 1.1, -22.3), Vector3(3.0, 1.6, 0.08), Color(0.85, 0.7, 0.3), Vector3.ZERO, false)
	_box(Vector3(3.5, F2 + 0.5, -20.0), Vector3(0.8, 1.0, 0.3), wood, Vector3.ZERO, false)
	_lantern(Vector3(-4.0, F2, -20.5))
	_lantern(Vector3(4.0, F2, -12.0))
	_lantern(Vector3(-9.0, F2, -12.0))
	_cover_end()
	# 後段屋頂：在一樓後段或二樓時都隱藏（範圍從地面到屋簷）
	_cover_begin("roof2", AABB(Vector3(-15.0, -0.5, -25.5), Vector3(30.0, F2 + shoji_h + 0.5, 16.5)))
	_gable(0.0, -16.75, 28.0, 14.5, F2 + shoji_h, 1.8, roof, false, 0.8)
	_cover_end()
	# 一樓房內燈籠
	_lantern(Vector3(-7.0, F1, -6.5))
	_lantern(Vector3(7.0, F1, -14.0))
	_lantern(Vector3(-7.0, F1, -19.5))
	_lantern(Vector3(0.0, F1, -8.5))
	# 前段屋頂（一樓前房與樓梯上方）：在底下時隱藏
	_cover_begin("roof1", AABB(Vector3(-15.0, -0.5, -10.0), Vector3(30.0, F1 + shoji_h + 0.3, 9.0)))
	_gable(0.0, -5.75, 28.0, 7.5, F1 + shoji_h, 1.2, roof, false, 0.8)
	_cover_end()


# ---------------------------------------------------------------- 敵人與故事

func _spawn_enemies() -> void:
	_spawn(Enemy.Kind.ASHIGARU, Vector3(-4.0, 0.0, 14.0), [Vector3(-4.0, 0.0, 14.0), Vector3(6.0, 0.0, 14.0), Vector3(6.0, 0.0, 2.0), Vector3(-3.0, 0.0, 1.5)])
	_spawn(Enemy.Kind.ASHIGARU, Vector3(-16.0, 0.0, 16.0), [Vector3(-16.0, 0.0, 16.0), Vector3(-16.5, 0.0, 4.0), Vector3(-10.0, 0.0, 0.5)])
	_spawn(Enemy.Kind.ARCHER, Vector3(11.0, 3.4, 9.0), [], Vector3(-0.7, 0.0, 0.7))
	_spawn(Enemy.Kind.SAMURAI, Vector3(0.0, F1, -5.0), [Vector3(0.0, F1, -5.0), Vector3(0.0, F1, -21.0), Vector3(-7.0, F1, -19.5), Vector3(0.0, F1, -19.5)])
	_spawn(Enemy.Kind.SAMURAI, Vector3(1.0, F2, -11.8), [], Vector3(1.0, 0.0, 0.0))
	_spawn(Enemy.Kind.ASHIGARU, Vector3(-9.0, F2, -18.0), [], Vector3(0.0, 0.0, 1.0))
	if not _target_dead:
		_lord = _spawn(Enemy.Kind.TARGET, Vector3(0.0, F2, -18.5), [], Vector3(0.0, 0.0, 1.0))
		_lord.hp = 150
	_respawn_scrolls()


## 卷軸「口糧可帶兩份」：二樓西翼房（足輕守著）
func _respawn_scrolls() -> void:
	_scroll(Vector3(-10.0, F2, -21.0), "ration2")


func _on_enemy_died_hook(e: Enemy, _stealth: bool) -> void:
	if e.kind != Enemy.Kind.TARGET or _target_dead:
		return
	_target_dead = true
	hud.set_objective("大將已除。從露台鉤上屋頂撤離")
	get_tree().create_timer(1.2).timeout.connect(func() -> void:
		_open_exit("撤離")
		hud.say("撤離！", Color(0.6, 0.9, 1.0)))
