extends "res://scripts/level_base.gd"
## 第三關：夜之城下町 — 大將已除，今川軍封鎖城下町、關了城門。
## 第十三次議會重做：病根是「沒有選擇」，不是「不夠彎」。鉤繩改成只能鉤發光鉤點，
## 屋頂分成一段一段（房子之間留 3 公尺以上的巷子，走不過去），整關有四個「決定點」，每個都有 2–3 條代價不同的路：
##   決一 町口：正面過番所柵欄（亮、有哨兵）／西後巷（暗、警鈴繩、巡邏，死巷藏口糧）／鉤上東邊二樓屋頂（弓兵站在上面）
##   決二 十字路口：直走大街（巡邏）／火之見櫓（兩段鉤點爬上去，卷軸；再鉤到西邊二樓屋頂）／東後巷（暗、警鈴繩，死巷藏焙烙玉）
##   決三 河：過橋（武士守橋、燈亮）／西邊水遁潛過去（慢、竹筒會被近距離發現）／東邊鉤環飛過河（落點在番所弓兵眼前）
##   決四 城門廣場：西番所屋頂→鉤上城牆／東番所屋頂（弓兵）→城牆／殺侍大將拿鑰匙開城門正面出去
## 捷徑：河北岸東側有一道門閂門，從北邊拉開以後，死了從河南岸的檢查點重來就不用再過橋。
## 地標：城牆後的天守從町口就看得到。

const WALL_Y := 9.0
const R2 := 6.5      # 二樓町家屋脊高（牆 5.2＋屋頂 1.3）
const R1 := 3.9      # 一樓町家屋脊高（牆 2.8＋屋頂 1.1）
const BAN := 6.2     # 番所屋脊高（牆 5.0＋屋頂 1.2）

var _gate_out := false


func _init() -> void:
	level_title = "夜之城下町"
	objective_text = "城門已關。找路穿過城下町，翻上城牆（或奪鑰開門）出城"
	start_pos = Vector3(0.0, 0.1, 31.0)
	exit_pos = Vector3(0.0, WALL_Y + 0.1, -28.5)
	checkpoints = [Vector3(0.0, 0.0, 31.0), Vector3(0.0, 0.0, 14.0), Vector3(0.0, 0.0, -9.0)]
	next_scene = ""
	bounds = AABB(Vector3(-21.4, -1.0, -29.6), Vector3(42.8, 22.0, 63.0))


func _on_level_ready() -> void:
	$Moon.rotation_degrees = Vector3(-55.0, 40.0, 0.0)
	hud.set_compass_target(Vector3(0.0, WALL_Y, -28.5), Color(0.6, 0.9, 1.0))
	_open_exit("出城")


# ---------------------------------------------------------------- 世界

func _build_world() -> void:
	var gravel := Color(0.24, 0.23, 0.21)
	var street := Color(0.3, 0.29, 0.27)
	var stone := Color(0.42, 0.42, 0.4)
	var wood := Color(0.32, 0.24, 0.16)
	var plaster := Color(0.8, 0.76, 0.68)
	var dark_plaster := Color(0.55, 0.5, 0.42)
	var roof := Color(0.2, 0.22, 0.27)
	var roof2 := Color(0.24, 0.2, 0.18)
	var water := Color(0.08, 0.16, 0.26)
	var fence := Color(0.26, 0.2, 0.13)
	var wall_c := Color(0.5, 0.48, 0.44)

	_ground(90.0, gravel)
	# 大街（微微彎）、十字橫街、城門廣場
	_path_poly([Vector3(0.0, 0.0, 33.0), Vector3(0.6, 0.0, 22.0), Vector3(-0.4, 0.0, 10.0), Vector3(0.3, 0.0, -2.0), Vector3(0.0, 0.0, -12.0)], 5.0, street)
	_box(Vector3(0.0, 0.02, 14.0), Vector3(40.0, 0.04, 4.6), street, Vector3.ZERO, false)
	_box(Vector3(0.0, 0.02, -23.0), Vector3(30.0, 0.04, 9.0), street, Vector3.ZERO, false)

	# 外圍板塀（看起來 2 公尺，碰撞 12 公尺）
	_fence(-21.5, 2.0, 63.0, false, 2.0, fence, 0.0, 12.0)
	_fence(21.5, 2.0, 63.0, false, 2.0, fence, 0.0, 12.0)
	_fence(0.0, 33.5, 44.0, true, 2.0, fence, 0.0, 12.0)

	# 町家：前排每棟微微歪斜、一樓二樓交錯，房子之間留 3 公尺以上（屋頂不再連成一條高速公路）
	# [x, z, 二樓?, 歪斜角, 門]
	var houses := [
		[-7.8, 28.0, false, 4.0, "e"], [-7.5, 18.5, true, -3.0, "e"], [-8.0, 8.0, false, 6.0, "e"], [-7.5, -1.0, true, -5.0, "e"], [-8.2, -8.4, false, 3.0, "e"],
		[7.8, 28.0, false, -4.0, "w"], [7.5, 19.5, true, 3.0, "w"], [7.8, 9.0, true, -6.0, "w"], [7.5, 0.0, false, 4.0, "w"], [8.0, -8.4, true, -3.0, "w"],
	]
	for h in houses:
		var two: bool = h[2]
		_group_begin(Vector3(h[0], 0.0, h[1]), h[3])
		_hut(0.0, 0.0, 6.0, 6.0, 5.2 if two else 2.8, 0.0, plaster if two else dark_plaster, roof if two else roof2, h[4], 1.3 if two else 1.1)
		if two:
			for side in [-1.0, 1.0]:
				_box(Vector3(side * 3.1, 4.0, 0.0), Vector3(0.1, 1.0, 2.6), wood.darkened(0.2), Vector3.ZERO, false)
		_group_end()
	# 後排矮屋（也錯開，不對稱）
	for b in [[-16.5, 27.0, 5.0], [-16.8, 8.5, -4.0], [-16.2, -5.0, 3.0], [16.5, 26.5, -3.0], [16.8, 6.5, 5.0], [16.3, -5.5, -2.0]]:
		_group_begin(Vector3(b[0], 0.0, b[1]), b[2])
		_hut(0.0, 0.0, 5.0, 6.0, 2.6, 0.0, dark_plaster, roof2, "e" if b[0] < 0.0 else "w", 1.0)
		_group_end()
	# 街邊：暖簾、酒樽
	for z in [26.5, 17.5, 6.5, -2.5]:
		_box(Vector3(-4.4, 2.0, z), Vector3(0.1, 0.9, 2.0), Color(0.2, 0.3, 0.55), Vector3.ZERO, false)
		_box(Vector3(4.4, 2.0, z + 1.5), Vector3(0.1, 0.9, 2.0), Color(0.55, 0.2, 0.2), Vector3.ZERO, false)
	for p in [Vector3(-4.0, 0.0, 30.0), Vector3(4.2, 0.0, 23.0), Vector3(-4.2, 0.0, 11.0), Vector3(4.0, 0.0, 2.5), Vector3(-13.0, 0.0, 16.5), Vector3(13.0, 0.0, 16.5)]:
		_box(p + Vector3(0.0, 0.45, 0.0), Vector3(0.7, 0.9, 0.7), wood)

	# ---- 決一：町口。番所柵欄擋住大街，只留中間 2 公尺（哨兵＋燈籠）；東巷封死，西巷開著
	_fence(-6.5, 24.2, 8.0, true, 1.8, fence, 0.0, 12.0)
	_fence(6.5, 24.2, 8.0, true, 1.8, fence, 0.0, 12.0)
	_fence(16.1, 24.2, 10.6, true, 1.8, fence, 0.0, 12.0)
	_box(Vector3(-1.6, 1.2, 24.2), Vector3(0.3, 2.4, 0.3), wood.darkened(0.3))
	_box(Vector3(1.6, 1.2, 24.2), Vector3(0.3, 2.4, 0.3), wood.darkened(0.3))
	_lantern(Vector3(2.4, 0.0, 23.4))
	_lantern(Vector3(-3.6, 0.0, 28.0))
	_bell_wire(Vector3(-10.8, 0.0, 21.0), Vector3(-14.0, 0.0, 21.0))
	_ration_at(Vector3(-18.6, 0.0, 19.5))
	_guide_glow(Vector3(-12.3, 0.0, 26.0))
	_hook_point(Vector3(5.3, 5.7, 18.6))       # 東邊二樓屋頂西側屋簷（弓兵站在同一片屋頂的屋脊上）

	# ---- 決二：十字路口。火之見櫓（全町最高）、東後巷
	_tower(-14.0, 14.0, 8.6, 0.0, wood, roof)
	_box(Vector3(-14.0, 9.4, 14.0), Vector3(0.5, 0.5, 0.5), Color(0.6, 0.45, 0.2), Vector3.ZERO, false)  # 半鐘
	_hook_point(Vector3(-15.0, 3.0, 8.6))     # 西後排矮屋東側屋簷（櫓的第一段）
	_hook_point(Vector3(-14.0, 8.6, 14.0))    # 櫓頂
	_hook_point(Vector3(7.8, R2, 10.2))       # 東二樓屋脊（從決一屋頂接過來）
	_hook_point(Vector3(-7.5, R2, 0.4))       # 西二樓屋脊（從櫓頂飛過來）
	_lantern(Vector3(3.6, 0.0, 17.0))
	_lantern(Vector3(-3.6, 0.0, 5.5))
	_lantern(Vector3(3.6, 0.0, -3.0))
	_bell_wire(Vector3(10.8, 0.0, 3.0), Vector3(14.0, 0.0, 3.0))
	_bomb(Vector3(18.6, 0.0, 17.5))
	_guide_glow(Vector3(12.3, 0.0, 10.0))
	_guide_glow(Vector3(-12.2, 0.0, 11.0))

	# ---- 決三：河。兩岸石堤，各留三個缺口：橋、西邊水遁口、東邊捷徑門
	_box(Vector3(0.0, 0.03, -16.0), Vector3(46.0, 0.06, 6.0), water, Vector3.ZERO, false, 0.2)
	for z in [-13.0, -19.0]:
		_bank(z, [[-2.2, 2.2], [-11.2, -8.8], [8.8, 11.2]], stone)
	_box(Vector3(0.0, 0.2, -16.0), Vector3(4.0, 0.3, 7.6), wood)
	for side in [-1.0, 1.0]:
		_box(Vector3(side * 2.0, 0.8, -16.0), Vector3(0.12, 0.9, 7.6), wood.darkened(0.2), Vector3.ZERO, false)
	_ramp_z(0.0, -11.6, -12.3, 0.0, 0.35, 4.0, wood)
	_ramp_z(0.0, -20.4, -19.7, 0.0, 0.35, 4.0, wood)
	_lantern(Vector3(-2.6, 0.0, -11.0))
	_lantern(Vector3(2.6, 0.0, -21.0))
	_bell_wire(Vector3(-2.8, 0.0, -10.0), Vector3(2.8, 0.0, -10.0))
	_water(Vector3(-10.0, 0.0, -16.0), Vector3(9.0, 1.0, 5.4))
	_guide_glow(Vector3(-10.0, 0.0, -11.8))
	# 東邊鉤環樁：在北岸，從南岸東側鉤得到
	_box(Vector3(14.2, 1.2, -21.6), Vector3(0.25, 2.4, 0.25), wood.darkened(0.3))
	_hook_point(Vector3(13.4, 0.0, -21.4))
	_hook_point(Vector3(8.0, R2, -8.6))       # 河南岸東二樓屋脊（往番所屋頂的高路）
	# 捷徑門：北岸東缺口，門閂在北邊
	_gate("short", Vector3(10.0, 0.0, -19.0), 2.4, 2.2, true, wood.darkened(0.2))
	var latch: Node3D = _prop("latch", Vector3(10.0, 0.0, -20.2))
	latch.set("on_use", func() -> void: _gate_set("short", true))
	_oil_jar(Vector3(-14.5, 0.0, -21.5))

	# ---- 決四：城門廣場。兩側番所（屋頂是上城牆的跳板）、城牆中間是城門（殺侍大將拿鑰匙才開）
	_hut(-8.0, -23.0, 6.0, 6.0, 5.0, 0.0, plaster, roof, "e", 1.2)
	_hut(8.0, -23.0, 6.0, 6.0, 5.0, 0.0, plaster, roof, "w", 1.2)
	_hook_point(Vector3(-8.0, 5.4, -20.7))    # 西番所南側屋簷
	_hook_point(Vector3(8.0, 5.4, -20.7))     # 東番所南側屋簷（弓兵在屋脊上）
	_hook_point(Vector3(-8.0, WALL_Y, -28.3))
	_hook_point(Vector3(8.0, WALL_Y, -28.3))
	# 城牆：左右兩段＋城門上方的門樓（牆頂連通，可走到中間的出口）
	_box(Vector3(-12.25, WALL_Y / 2.0, -28.5), Vector3(19.5, WALL_Y, 2.4), wall_c)
	_box(Vector3(12.25, WALL_Y / 2.0, -28.5), Vector3(19.5, WALL_Y, 2.4), wall_c)
	_box(Vector3(0.0, WALL_Y - 0.6, -28.5), Vector3(5.0, 1.2, 2.4), wall_c)
	_box(Vector3(0.0, WALL_Y + 0.5, -27.4), Vector3(44.0, 1.0, 0.3), wall_c.darkened(0.2), Vector3.ZERO, false)   # 女牆
	_box(Vector3(0.0, 5.5, -27.2), Vector3(6.0, 0.6, 1.0), wood, Vector3.ZERO, false)
	_gate("castle", Vector3(0.0, 0.0, -27.4), 5.0, 5.2, true, wood.darkened(0.3))
	_invisible(Vector3(0.0, 10.0, -30.2), Vector3(44.0, 20.0, 0.6))
	_lantern(Vector3(-4.5, 0.0, -25.5))
	_lantern(Vector3(4.5, 0.0, -25.5))
	_stone_lantern(Vector3(-13.0, 0.0, -21.0))
	_stone_lantern(Vector3(13.0, 0.0, -21.0))
	_tree(Vector3(-18.0, 0.0, -24.0), 1.0)
	_tree(Vector3(18.5, 0.0, -24.5), 1.1)
	_guide_glow(Vector3(-8.0, 0.0, -18.8))

	# 地標：城牆後面的天守（町口就看得到）
	_landmark_keep(Vector3(0.0, 0.0, -50.0), 1.2)

	# 決定點與路線（--map 畫出來、--routes 量代價）
	_decision("決一", Vector3(0.0, 0.0, 27.0), [
		{"name": "正面", "pts": [Vector3(0, 0, 27), Vector3(0, 0, 24.2), Vector3(0, 0, 18), Vector3(0, 0, 14)]},
		{"name": "西巷", "pts": [Vector3(0, 0, 27), Vector3(-12.3, 0, 26), Vector3(-12.3, 0, 21), Vector3(-12.3, 0, 16), Vector3(0, 0, 14)]},
		{"name": "屋頂", "pts": [Vector3(0, 0, 27), Vector3(5.3, 5.7, 18.6), Vector3(7.8, R2, 10.2), Vector3(4.5, 0, 12.5), Vector3(0, 0, 14)]},
	])
	_decision("決二", Vector3(0.0, 0.0, 14.0), [
		{"name": "大街", "pts": [Vector3(0, 0, 14), Vector3(0, 0, 4), Vector3(0, 0, -10)]},
		{"name": "火之見櫓", "pts": [Vector3(0, 0, 14), Vector3(-11.5, 0, 11), Vector3(-15.0, 3.0, 8.6), Vector3(-14, 8.6, 14), Vector3(-7.5, R2, 0.4), Vector3(-5, 0, -10)]},
		{"name": "東巷", "pts": [Vector3(0, 0, 14), Vector3(12.3, 0, 12), Vector3(12.3, 0, -4), Vector3(10, 0, -10)]},
	])
	_decision("決三", Vector3(0.0, 0.0, -10.0), [
		{"name": "橋", "pts": [Vector3(0, 0, -10), Vector3(0, 0.35, -16), Vector3(0, 0, -21)]},
		{"name": "水遁", "pts": [Vector3(0, 0, -10), Vector3(-10, 0, -12), Vector3(-10, 0, -16), Vector3(-10, 0, -20), Vector3(-4, 0, -21)]},
		{"name": "鉤環", "pts": [Vector3(0, 0, -10), Vector3(10, 0, -12.2), Vector3(13.4, 0, -21.4), Vector3(4, 0, -21)]},
	])
	_decision("決四", Vector3(0.0, 0.0, -20.0), [
		{"name": "西番所", "pts": [Vector3(0, 0, -20), Vector3(-8, 0, -11.5), Vector3(-8, 5.4, -20.7), Vector3(-8, WALL_Y, -28.3), Vector3(0, WALL_Y, -28.5)]},
		{"name": "東番所", "pts": [Vector3(0, 0, -20), Vector3(8, 0, -11.5), Vector3(8, 5.4, -20.7), Vector3(8, WALL_Y, -28.3), Vector3(0, WALL_Y, -28.5)]},
		{"name": "城門", "pts": [Vector3(0, 0, -20), Vector3(0, 0, -25), Vector3(0, 0, -29.3)]},
	])


## 河堤：沿 x 從 -22 到 22，gaps 是 [[x0, x1], ...] 缺口
func _bank(z: float, gaps: Array, stone: Color) -> void:
	var cuts := gaps.duplicate()
	cuts.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var x := -22.0
	for g in cuts:
		var x0: float = g[0]
		if x0 - x > 0.05:
			_box(Vector3((x + x0) / 2.0, 0.25, z), Vector3(x0 - x, 0.5, 0.6), stone)
		x = g[1]
	if 22.0 - x > 0.05:
		_box(Vector3((x + 22.0) / 2.0, 0.25, z), Vector3(22.0 - x, 0.5, 0.6), stone)


func _ration_at(pos: Vector3) -> void:
	var r := Ration.new()
	add_child(r)
	r.global_position = pos


# ---------------------------------------------------------------- 敵人

func _spawn_enemies() -> void:
	# 決一
	_spawn(Enemy.Kind.ASHIGARU, Vector3(0.0, 0.0, 22.8), [], Vector3(0.0, 0.0, 1.0))
	_spawn(Enemy.Kind.ARCHER, Vector3(7.5, R2, 21.0), [], Vector3(-0.6, 0.0, 0.8))
	_spawn(Enemy.Kind.ASHIGARU, Vector3(-12.3, 0.0, 23.0), [Vector3(-12.3, 0.0, 23.0), Vector3(-12.3, 0.0, 11.5)])
	# 決二
	_spawn(Enemy.Kind.ASHIGARU, Vector3(-10.0, 0.0, 14.0), [Vector3(-10.0, 0.0, 14.0), Vector3(11.0, 0.0, 14.0)])
	_spawn(Enemy.Kind.ASHIGARU, Vector3(0.0, 0.0, 7.0), [Vector3(0.0, 0.0, 7.0), Vector3(0.5, 0.0, -7.0), Vector3(-0.5, 0.0, 3.0)])
	_spawn(Enemy.Kind.ASHIGARU, Vector3(12.3, 0.0, -3.0), [], Vector3(0.0, 0.0, 1.0))
	# 決三
	_spawn(Enemy.Kind.SAMURAI, Vector3(0.0, 0.35, -17.5), [], Vector3(0.0, 0.0, 1.0))
	_spawn(Enemy.Kind.ASHIGARU, Vector3(-6.0, 0.0, -10.6), [Vector3(-6.0, 0.0, -10.6), Vector3(6.0, 0.0, -10.6)])
	# 決四
	_spawn(Enemy.Kind.SAMURAI, Vector3(-5.0, 0.0, -20.5), [Vector3(-5.0, 0.0, -20.5), Vector3(5.0, 0.0, -20.5), Vector3(5.0, 0.0, -25.0), Vector3(-5.0, 0.0, -25.0)])
	_spawn(Enemy.Kind.ARCHER, Vector3(8.0, BAN, -23.0), [], Vector3(0.0, 0.0, 1.0))
	if not _target_dead:
		var captain := _spawn(Enemy.Kind.TARGET, Vector3(0.0, 0.0, -25.2), [], Vector3(0.0, 0.0, 1.0))
		captain.hp = 130
	_respawn_scrolls()


## 卷軸「飛鉤」：火之見櫓頂
func _respawn_scrolls() -> void:
	_scroll(Vector3(-14.0, 8.6, 14.8), "hook_fly")


func _after_respawn() -> void:
	if _target_dead:
		_gate_set("castle", true)


func _on_enemy_died_hook(e: Enemy, _stealth: bool) -> void:
	if e.kind == Enemy.Kind.TARGET and not _target_dead:
		_target_dead = true
		hud.set_objective("侍大將已除，奪得城門鑰匙。開城門出去，或翻城牆")
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			_gate_set("castle", true))


func _physics_process(delta: float) -> void:
	super(delta)
	# 第二個出口：城門開了，走出門洞就過關
	if _target_dead and not _finished and not _dead and not _gate_out:
		var d := player.global_position - Vector3(0.0, 0.0, -29.3)
		d.y = 0.0
		if d.length() < 1.6 and player.global_position.y < 2.0:
			_gate_out = true
			_finish()
