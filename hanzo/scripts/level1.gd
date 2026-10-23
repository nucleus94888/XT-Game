extends "res://scripts/level_base.gd"
## 第一關：伊賀夜襲 — 今川軍在伊賀山村的本營。
## 鳥居山門（低）→ 第一院：農家、水井、櫓上的弓兵 → 石階上台地 → 第二院：長屋、土藏、練兵場 →
## 本陣：陣屋裡副將守著大將。大將一察覺就從後門逃走（故事：下一關追進湖畔屋敷）。
## 殺了副將後門才會開，追出去就過關。
##
## 自動試玩：godot --path hanzo scenes/level1.tscn ++ --shot=<dir> --walk

const T := 1.5          # 台地高度
const HALL_Y := T + 0.6 # 陣屋地板
const REAR_GATE := Vector3(0.0, T, -25.5)

var _lord: Enemy
var _vice: Enemy
var _lord_fled := false
var _walk := false
var _walk_t := 0.0
var _auto_done := {}


func _init() -> void:
	level_title = "伊賀夜襲"
	objective_text = "潛入今川軍本營，取下大將首級"
	start_pos = Vector3(0.0, 0.1, 30.0)
	exit_pos = Vector3(0.0, T, -28.5)
	checkpoints = [Vector3(0.0, 0.0, 30.0), Vector3(0.0, 0.0, 19.0), Vector3(0.0, T, 1.5), Vector3(0.0, T, -10.0)]
	next_scene = "res://scenes/level2.tscn"
	next_label = "下一關：湖畔屋敷"
	bounds = AABB(Vector3(-13.4, -1.0, -29.0), Vector3(26.8, 20.0, 60.5))


func _on_level_ready() -> void:
	hud.set_compass_target(Vector3(0.0, HALL_Y, -21.0), Color(1.0, 0.8, 0.3))
	$Moon.rotation_degrees = Vector3(-52.0, 25.0, 0.0)
	_walk = _extra_args.has("--walk")


# ---------------------------------------------------------------- 世界

func _build_world() -> void:
	var dirt := Color(0.17, 0.17, 0.15)
	var stone := Color(0.42, 0.42, 0.4)
	var wood := Color(0.32, 0.24, 0.16)
	var plaster := Color(0.78, 0.74, 0.66)
	var roof := Color(0.2, 0.22, 0.27)
	var thatch := Color(0.45, 0.38, 0.22)
	var palisade := Color(0.26, 0.2, 0.13)

	_ground(90.0, dirt)
	# 台地（第二院＋本陣）：z < 4 全部墊高 1.5 公尺，前緣是石砌擋土牆
	_terrace(0.0, -12.0, 28.0, 32.0, T, stone.darkened(0.3))
	_box(Vector3(0.0, T - 0.25, 4.0), Vector3(28.0, 0.5, 0.3), stone, Vector3.ZERO, false)
	# 中央石階
	_ramp_z(0.0, 8.0, 4.0, 0.0, T, 5.0, stone)
	_stone_lantern(Vector3(-3.2, T, 3.2))
	_stone_lantern(Vector3(3.2, T, 3.2))

	# 外圍木柵（看起來 2.2 公尺，碰撞 12 公尺）
	_fence(-13.5, 2.0, 63.0, false, 2.2, palisade, 0.0, 12.0)
	_fence(13.5, 2.0, 63.0, false, 2.2, palisade, 0.0, 12.0)
	_fence(0.0, 33.0, 28.0, true, 2.2, palisade, 0.0, 12.0)
	_fence(0.0, -29.5, 28.0, true, 2.2, palisade, T, 12.0)

	# 山門：鳥居與兩座石燈籠
	_torii(Vector3(0.0, 0.0, 28.0))
	_stone_lantern(Vector3(-3.0, 0.0, 27.0))
	_stone_lantern(Vector3(3.0, 0.0, 27.0))
	_box(Vector3(0.0, 0.03, 20.0), Vector3(3.0, 0.06, 18.0), Color(0.3, 0.29, 0.27), Vector3.ZERO, false)  # 碎石路

	# 第一院：兩間農家（茅葺）、水井、菜畦、松樹、櫓
	_hut(-9.0, 20.0, 5.0, 4.0, 2.4, 0.0, plaster, thatch, "e", 1.3)
	_hut(9.0, 22.5, 5.0, 4.0, 2.4, 0.0, plaster, thatch, "w", 1.3)
	_box(Vector3(3.5, 0.5, 16.0), Vector3(1.6, 1.0, 1.6), stone)                       # 水井
	_box(Vector3(3.5, 1.9, 16.0), Vector3(1.8, 0.1, 1.8), wood, Vector3.ZERO, false)   # 井蓋
	for i in range(4):
		_box(Vector3(-8.0 + i * 1.2, 0.12, 11.0), Vector3(0.8, 0.24, 5.0), Color(0.22, 0.2, 0.14), Vector3.ZERO, false)  # 菜畦
	_tree(Vector3(-11.0, 0.0, 13.0), 1.1)
	_tree(Vector3(11.5, 0.0, 29.0), 0.9)
	_tree(Vector3(-5.0, 0.0, 26.5), 1.0)
	_tree(Vector3(-11.5, 0.0, 6.0), 0.8)
	_tower(10.5, 13.0, 4.5, 0.0, wood, roof)
	_lantern(Vector3(-4.5, 0.0, 22.0))
	_lantern(Vector3(6.5, 0.0, 12.5))
	_lantern(Vector3(-9.5, 0.0, 8.0))

	# 第二院（台地）：西側長屋（屋頂可走）、東側土藏（兩層高）、練兵場木樁、燈籠
	_hut(-9.0, -5.0, 5.0, 12.0, 2.6, T, plaster, roof, "e", 1.2)
	_box(Vector3(9.5, T + 2.25, -8.0), Vector3(5.0, 4.5, 6.0), Color(0.86, 0.84, 0.8))  # 土藏本體
	_gable(9.5, -8.0, 5.0, 6.0, T + 4.5, 0.9, roof, true, 0.5)
	_box(Vector3(9.5, T + 1.0, -4.85), Vector3(1.4, 2.0, 0.3), wood, Vector3.ZERO, false)  # 藏門
	for i in range(3):
		_box(Vector3(2.0 + i * 2.0, T + 0.9, -2.5), Vector3(0.3, 1.8, 0.3), thatch)       # 練兵木樁
	_box(Vector3(4.0, T + 0.02, -3.0), Vector3(8.0, 0.04, 5.0), Color(0.3, 0.27, 0.22), Vector3.ZERO, false)
	_tree(Vector3(-12.0, T, -1.0), 0.9)
	_tree(Vector3(12.0, T, 1.0), 0.8)
	_lantern(Vector3(-3.0, T, 0.5))
	_lantern(Vector3(7.5, T, -1.5))
	_lantern(Vector3(-11.0, T, -13.0))
	_lantern(Vector3(11.0, T, -14.5))

	# 本陣：陣幕（兩側）＋陣屋（高床、前面敞開、後門通後門道）
	for side in [-1.0, 1.0]:
		_box(Vector3(side * 9.0, T + 1.0, -15.0), Vector3(6.0, 2.0, 0.12), Color(0.1, 0.1, 0.12))
		_box(Vector3(side * 9.0, T + 1.0, -15.0), Vector3(6.0, 0.5, 0.14), Color(0.75, 0.15, 0.12), Vector3.ZERO, false)
	_hall()
	_lantern(Vector3(-4.0, T, -16.2))
	_lantern(Vector3(4.0, T, -16.2))

	# 後門：殺了副將才開；大將逃跑時會先開再關
	_fence(-7.0, -25.5, 10.0, true, 2.2, palisade, T, 12.0)
	_fence(7.0, -25.5, 10.0, true, 2.2, palisade, T, 12.0)
	_gate("rear", REAR_GATE, 4.0, 2.4, true, wood)
	_box(Vector3(0.0, T + 0.02, -27.5), Vector3(3.0, 0.04, 4.0), Color(0.3, 0.29, 0.27), Vector3.ZERO, false)


## 陣屋：12×8 高床，三面牆、前面敞開（帳幕），後牆留門
func _hall() -> void:
	var wood := Color(0.3, 0.22, 0.14)
	var plaster := Color(0.8, 0.76, 0.68)
	var roof := Color(0.2, 0.22, 0.27)
	var cx := 0.0
	var cz := -20.0
	var sx := 12.0
	var sz := 8.0
	# 高床（可走上去）＋前緣階梯
	_box(Vector3(cx, T + 0.3, cz), Vector3(sx, 0.6, sz), wood)
	_ramp_z(cx, cz + sz / 2.0 + 1.2, cz + sz / 2.0, T, HALL_Y, 4.0, wood.lightened(0.1))
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
	_cover_begin("hall", AABB(Vector3(cx - sx / 2.0 - 1.0, T - 0.3, cz - sz / 2.0 - 1.0), Vector3(sx + 2.0, 3.6, sz + 2.5)))
	_gable(cx, cz, sx, sz, HALL_Y + 3.0, 1.6, roof, false, 0.8)
	_cover_end()
	# 室內：軍議桌、屏風、燭台
	_box(Vector3(cx, HALL_Y + 0.35, cz - 1.5), Vector3(2.4, 0.7, 1.2), wood.darkened(0.2))
	_box(Vector3(cx, HALL_Y + 1.0, cz - 3.0), Vector3(3.6, 2.0, 0.1), Color(0.85, 0.7, 0.3), Vector3.ZERO, false)  # 金屏風
	_lantern(Vector3(cx - 4.5, HALL_Y, cz - 2.0))
	_lantern(Vector3(cx + 4.5, HALL_Y, cz - 2.0))


# ---------------------------------------------------------------- 敵人與故事

func _spawn_enemies() -> void:
	_spawn(Enemy.Kind.ASHIGARU, Vector3(-6.0, 0.0, 24.0), [Vector3(-6.0, 0.0, 24.0), Vector3(-5.0, 0.0, 10.0), Vector3(2.0, 0.0, 9.0), Vector3(1.0, 0.0, 24.0)])
	_spawn(Enemy.Kind.ASHIGARU, Vector3(7.0, 0.0, 9.0), [Vector3(7.0, 0.0, 9.0), Vector3(7.5, 0.0, 19.0), Vector3(-1.0, 0.0, 26.0)])
	_spawn(Enemy.Kind.ARCHER, Vector3(10.5, 4.5, 13.0), [], Vector3(-1.0, 0.0, 0.3))
	_spawn(Enemy.Kind.SAMURAI, Vector3(-4.0, T, -3.0), [Vector3(-4.0, T, -3.0), Vector3(5.5, T, -6.0), Vector3(5.0, T, -12.5), Vector3(-5.0, T, -12.0)])
	_spawn(Enemy.Kind.ASHIGARU, Vector3(-6.0, T, -16.5), [], Vector3(0.6, 0.0, 1.0))
	if not _target_dead:
		# 副將：守在陣屋前段，面向入口（要暗殺得從後門或屋頂來）
		_vice = _spawn(Enemy.Kind.TARGET, Vector3(0.0, HALL_Y, -17.5), [], Vector3(0.0, 0.0, 1.0))
		_vice.name = "Vice"
	if not _lord_fled:
		_lord = _spawn(Enemy.Kind.LORD, Vector3(0.0, HALL_Y, -21.5), [], Vector3(0.0, 0.0, -1.0))
		_lord.flee_route = [Vector3(0.0, HALL_Y, -23.5), Vector3(0.0, T, -25.5), Vector3(0.0, T, -28.8)]
		_lord.flee_started.connect(_on_lord_flee)
		_lord.escaped.connect(_on_lord_escaped)


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
		hud.set_compass_target(Vector3(0.0, HALL_Y, -17.5), Color(1.0, 0.8, 0.3))


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
		_open_exit("追擊")
		hud.say("追！", Color(0.6, 0.9, 1.0)))


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
			player.global_position = Vector3(0.0, HALL_Y + 0.1, -15.5)
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
