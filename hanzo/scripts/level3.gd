extends "res://scripts/level_base.gd"
## 第三關：夜之城下町 — 大將已除，今川軍封鎖城下町、關了城門。
## 町家一樓二樓交錯（屋頂高低差＝鉤繩路線）→ 十字路口與火之見櫓（最高點，卷軸）→ 河與橋（武士把守）→
## 城門廣場（侍大將守門，殺了得念珠，不殺也行）→ 從番所屋頂鉤上城牆出城。
## 地面路線走大街會一路被巡邏撞見；屋頂路線只要高低差夠就鉤得過去。

const WALL_Y := 9.0

var _walk := false


func _init() -> void:
	level_title = "夜之城下町"
	objective_text = "城門已關。沿屋頂穿過城下町，翻上城牆出城"
	start_pos = Vector3(0.0, 0.1, 31.0)
	exit_pos = Vector3(0.0, WALL_Y + 0.1, -28.5)
	checkpoints = [Vector3(0.0, 0.0, 31.0), Vector3(0.0, 0.0, 14.0), Vector3(0.0, 0.0, -9.0), Vector3(0.0, 0.0, -22.0)]
	next_scene = ""
	bounds = AABB(Vector3(-21.4, -1.0, -29.6), Vector3(42.8, 20.0, 63.0))


func _on_level_ready() -> void:
	$Moon.rotation_degrees = Vector3(-55.0, 40.0, 0.0)
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
	# 大街與十字路
	_box(Vector3(0.0, 0.02, 7.0), Vector3(6.0, 0.04, 52.0), street, Vector3.ZERO, false)
	_box(Vector3(0.0, 0.02, 14.0), Vector3(40.0, 0.04, 5.0), street, Vector3.ZERO, false)
	_box(Vector3(0.0, 0.02, -23.0), Vector3(30.0, 0.04, 9.0), street, Vector3.ZERO, false)

	# 外圍板塀（看起來 2 公尺，碰撞 12 公尺）
	_fence(-21.5, 2.0, 63.0, false, 2.0, fence, 0.0, 12.0)
	_fence(21.5, 2.0, 63.0, false, 2.0, fence, 0.0, 12.0)
	_fence(0.0, 33.5, 44.0, true, 2.0, fence, 0.0, 12.0)

	# 町家：靠街兩排（一樓／二樓交錯，屋頂高低差才鉤得過去）＋後排矮屋
	var two := [false, true, false, true, false]
	var zs := [28.0, 20.0, 8.0, 0.0, -8.0]
	for i in range(zs.size()):
		var z: float = zs[i]
		var h: float = 5.2 if two[i] else 2.8
		var r: float = 1.3 if two[i] else 1.1
		_hut(-7.5, z, 6.0, 7.0, h, 0.0, plaster if two[i] else dark_plaster, roof if two[i] else roof2, "e", r)
		_hut(7.5, z, 6.0, 7.0, h, 0.0, plaster if not two[i] else dark_plaster, roof2 if two[i] else roof, "w", r)
		# 二樓町家的格子窗（裝飾）
		if two[i]:
			for side in [-1.0, 1.0]:
				_box(Vector3(side * 4.4, 4.0, z), Vector3(0.1, 1.0, 3.0), wood.darkened(0.2), Vector3.ZERO, false)
	for z in [26.0, 18.0, 6.0, -2.0]:
		_hut(-16.5, z, 5.0, 6.0, 2.6, 0.0, dark_plaster, roof2, "e", 1.0)
		_hut(16.5, z, 5.0, 6.0, 2.6, 0.0, dark_plaster, roof2, "w", 1.0)
	# 街邊：暖簾、酒樽、燈籠
	for z in [24.5, 16.5, 4.5, -3.5]:
		_box(Vector3(-4.3, 2.0, z), Vector3(0.1, 0.9, 2.0), Color(0.2, 0.3, 0.55), Vector3.ZERO, false)
		_box(Vector3(4.3, 2.0, z - 1.0), Vector3(0.1, 0.9, 2.0), Color(0.55, 0.2, 0.2), Vector3.ZERO, false)
	for p in [Vector3(-4.0, 0.0, 30.0), Vector3(4.2, 0.0, 23.0), Vector3(-4.2, 0.0, 11.0), Vector3(4.0, 0.0, 2.5), Vector3(-13.0, 0.0, 14.0), Vector3(13.0, 0.0, 14.0)]:
		_box(p + Vector3(0.0, 0.45, 0.0), Vector3(0.7, 0.9, 0.7), wood)
	_lantern(Vector3(-3.6, 0.0, 26.0))
	_lantern(Vector3(3.6, 0.0, 18.0))
	_lantern(Vector3(-3.6, 0.0, 8.0))
	_lantern(Vector3(3.6, 0.0, -1.0))
	_lantern(Vector3(-12.0, 0.0, 12.0))
	_lantern(Vector3(12.0, 0.0, 16.0))

	# 火之見櫓：全町最高（8.6 公尺），從地面鉤不上，要先上一樓屋頂
	_tower(-14.0, 14.0, 8.6, 0.0, wood, roof)
	_box(Vector3(-14.0, 9.4, 14.0), Vector3(0.5, 0.5, 0.5), Color(0.6, 0.45, 0.2), Vector3.ZERO, false)  # 半鐘

	# 河：兩岸石堤（擋人），只有橋能過
	# 水面比大街高 2 公分，重疊處才不會閃
	_box(Vector3(0.0, 0.03, -16.0), Vector3(46.0, 0.06, 6.0), water, Vector3.ZERO, false, 0.2)
	_wall_with_gap(-22.0, 22.0, -13.0, true, 0.0, 4.4, func(x: float, z: float, len: float) -> void:
		_box(Vector3(x, 0.25, z), Vector3(len, 0.5, 0.6), stone))
	_wall_with_gap(-22.0, 22.0, -19.0, true, 0.0, 4.4, func(x: float, z: float, len: float) -> void:
		_box(Vector3(x, 0.25, z), Vector3(len, 0.5, 0.6), stone))
	_box(Vector3(0.0, 0.2, -16.0), Vector3(4.0, 0.3, 7.6), wood)
	for side in [-1.0, 1.0]:
		_box(Vector3(side * 2.0, 0.8, -16.0), Vector3(0.12, 0.9, 7.6), wood.darkened(0.2), Vector3.ZERO, false)
	_ramp_z(0.0, -11.6, -12.3, 0.0, 0.35, 4.0, wood)
	_ramp_z(0.0, -20.4, -19.7, 0.0, 0.35, 4.0, wood)
	_lantern(Vector3(-2.6, 0.0, -11.0))
	_lantern(Vector3(2.6, 0.0, -21.0))

	# 城門廣場：兩側番所（二樓高，屋頂是上城牆的跳板）、城牆、關著的城門
	_hut(-8.0, -23.0, 6.0, 6.0, 5.0, 0.0, plaster, roof, "e", 1.2)
	_hut(8.0, -23.0, 6.0, 6.0, 5.0, 0.0, plaster, roof, "w", 1.2)
	_box(Vector3(0.0, WALL_Y / 2.0, -28.5), Vector3(44.0, WALL_Y, 2.4), wall_c)
	_box(Vector3(0.0, WALL_Y + 0.5, -27.4), Vector3(44.0, 1.0, 0.3), wall_c.darkened(0.2), Vector3.ZERO, false)   # 女牆
	_box(Vector3(0.0, 2.6, -27.2), Vector3(5.0, 5.2, 0.3), wood.darkened(0.3))                                     # 城門（關）
	_box(Vector3(0.0, 5.5, -27.2), Vector3(6.0, 0.6, 1.0), wood, Vector3.ZERO, false)
	_invisible(Vector3(0.0, 10.0, -30.2), Vector3(44.0, 20.0, 0.6))
	_lantern(Vector3(-4.5, 0.0, -25.5))
	_lantern(Vector3(4.5, 0.0, -25.5))
	_stone_lantern(Vector3(-13.0, 0.0, -21.0))
	_stone_lantern(Vector3(13.0, 0.0, -21.0))
	_tree(Vector3(-18.0, 0.0, -24.0), 1.0)
	_tree(Vector3(18.5, 0.0, -24.5), 1.1)


# ---------------------------------------------------------------- 敵人

func _spawn_enemies() -> void:
	_spawn(Enemy.Kind.ASHIGARU, Vector3(0.0, 0.0, 24.0), [Vector3(0.0, 0.0, 24.0), Vector3(1.5, 0.0, 15.0), Vector3(-1.5, 0.0, 29.0)])
	_spawn(Enemy.Kind.ASHIGARU, Vector3(-12.0, 0.0, 14.0), [Vector3(-12.0, 0.0, 14.0), Vector3(12.0, 0.0, 14.0)])
	_spawn(Enemy.Kind.ASHIGARU, Vector3(0.0, 0.0, 6.0), [Vector3(0.0, 0.0, 6.0), Vector3(1.0, 0.0, -9.0), Vector3(-1.0, 0.0, 2.0)])
	_spawn(Enemy.Kind.ARCHER, Vector3(7.5, 6.5, 20.0), [], Vector3(-0.7, 0.0, 0.7))
	_spawn(Enemy.Kind.ARCHER, Vector3(-7.5, 3.9, 8.0), [], Vector3(0.7, 0.0, -0.5))
	_spawn(Enemy.Kind.SAMURAI, Vector3(0.0, 0.35, -17.5), [], Vector3(0.0, 0.0, 1.0))
	_spawn(Enemy.Kind.SAMURAI, Vector3(-6.0, 0.0, -21.0), [Vector3(-6.0, 0.0, -21.0), Vector3(6.0, 0.0, -21.0), Vector3(6.0, 0.0, -26.0), Vector3(-6.0, 0.0, -26.0)])
	if not _target_dead:
		var captain := _spawn(Enemy.Kind.TARGET, Vector3(0.0, 0.0, -25.0), [], Vector3(0.0, 0.0, 1.0))
		captain.hp = 130
	_respawn_scrolls()


## 卷軸「飛鉤」：火之見櫓頂
func _respawn_scrolls() -> void:
	_scroll(Vector3(-14.0, 8.6, 14.0), "hook_fly")


func _on_enemy_died_hook(e: Enemy, _stealth: bool) -> void:
	if e.kind == Enemy.Kind.TARGET and not _target_dead:
		_target_dead = true
		hud.set_objective("侍大將已除。翻上城牆出城")
