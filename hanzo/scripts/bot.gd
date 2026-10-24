extends Node
## 自動試玩 bot（議會驗證用）：對一名武士 1v1 打 N 場，印出勝率。
##   godot --path hanzo scenes/level1.tscn ++ --bot=mash --runs=20
##   godot --path hanzo scenes/level1.tscn ++ --bot=deflect --runs=20
## mash：走到武士面前每幀狂按攻擊，從不格擋、從不閃（模擬無腦連按）。
## deflect：等武士出手，在打到前 70～170ms 舉刀（人類反應抖動），趁硬直砍兩刀；看到「危」就閃步。
## 目標（第五次議會）：mash 勝率 <30%、deflect 勝率 >70%。
## chase：追擊量測（第七次議會）。敵人在 6 公尺外已警戒，玩家只走路（不閃步）直線逃；
##   印出拉近速率（公尺/秒）與「從 6 公尺到被追上要幾秒」。--kind=ashigaru|samurai|target|archer
##   godot --headless --path hanzo scenes/level1.tscn ++ --bot=chase --kind=ashigaru --runs=3

## throw：手裡劍準度量測。站在起點，用幾組鏡頭角度瞄準、投擲，印出「準心射線打到的點」和「手裡劍最後停的點」差多少。
##   godot --headless --path hanzo scenes/level1.tscn ++ --bot=throw
const KINDS := {"ashigaru": Enemy.Kind.ASHIGARU, "archer": Enemy.Kind.ARCHER, "samurai": Enemy.Kind.SAMURAI, "target": Enemy.Kind.TARGET}
const THROW_VARIANTS := [[0.0, 0.15], [0.0, 0.45], [0.0, -0.15], [0.8, 0.15], [-0.8, 0.3], [2.4, 0.2]]
const CHASE_START := 6.0
const CHASE_MAX_T := 8.0

var mode := "mash"
var kind: Enemy.Kind = Enemy.Kind.SAMURAI
var _chase_d0 := 0.0
var _chase_caught := false
var _chase_armed := false
var runs := 20
var level: Node3D
var player: CharacterBody3D
var hud: CanvasLayer
var cam_rig: Node3D

var enemy: Enemy
var _run := 0
var _t := 0.0
var _wins := 0
var _results: Array = []
var _done := false
var _block_t := 0.0
var _atk_cd := 0.0
var _react := 0.12
var _dash_at := 0.10
var _acted_this_attack := false
var _start_pos := Vector3.ZERO
var _hits_taken := 0
var _breaks := 0


func start() -> void:
	_start_pos = player.global_position
	player.damaged.connect(func(_a: int) -> void:
		_hits_taken += 1)
	player.posture_broken.connect(func() -> void:
		_breaks += 1)
	for a in OS.get_cmdline_user_args():
		if a == "--trace":
			_trace = true
		elif a.begins_with("--kind="):
			kind = KINDS.get(a.substr(7), Enemy.Kind.SAMURAI)
		elif a == "--full":
			# 全升級組合：念珠四枚（HP 140）＋三卷卷軸（不寫存檔）
			Progress.beads = Progress.MAX_BEADS
			Progress._pending = Progress.SCROLLS.keys()
			player.refresh_progress()
			print("BOT full upgrades: max_hp=%d shuriken=%d/%d" % [player.max_hp, player.shuriken, Progress.shuriken_max()])
	if _trace:
		player.hit_landed.connect(func(info: Dictionary) -> void:
			if is_instance_valid(enemy):
				print("  [%.2f] player hit landed dmg=%d heavy=%s -> enemy hp=%d guard=%s streak=%d state=%s" % [_t, int(info.dmg), info.heavy, enemy.hp, enemy._guard, enemy._blocked_streak, enemy.State.keys()[enemy.state]]))
	_begin_run()


func _throw_test() -> void:
	if player.weapon_mode != player.WEAPON_SHURIKEN:
		player.toggle_weapon()
	var space := player.get_world_3d().direct_space_state
	# --at=x,y,z：改從這個點投（例如站進屋敷裡測被隱藏的屋頂會不會擋到準心）
	var at := _start_pos
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--at="):
			var c: PackedStringArray = a.substr(5).split(",")
			if c.size() == 3:
				at = Vector3(float(c[0]), float(c[1]), float(c[2]))
	# --kind=xxx：在前方 6 公尺放一個敵人（第一組角度會鎖定到他），確認命中與扣血
	var dummy: Enemy = null
	if "--kind=" in " ".join(OS.get_cmdline_user_args()):
		dummy = Enemy.new()
		dummy.kind = kind
		dummy.face_dir = Vector3(0, 0, 1)
		level.add_child(dummy)
		dummy.global_position = at + Vector3(0.0, 0.0, -6.0)
	for v in THROW_VARIANTS:
		player.global_position = at
		player.velocity = Vector3.ZERO
		player.refill_shuriken()
		cam_rig.yaw = float(v[0])
		cam_rig.aim_pitch = float(v[1])
		await get_tree().create_timer(0.3).timeout
		player.on_attack_down()
		await get_tree().create_timer(0.5).timeout
		var r: Array = cam_rig.aim_ray()
		# 和玩家一樣跳過被隱藏的遮蔽層
		var hit: Dictionary = player._ray_visible(r[0], r[0] + r[1] * 35.0, 1 | 2)
		var expect: Vector3 = hit.position if not hit.is_empty() else r[0] + r[1] * 35.0
		var desc := "沒打到"
		if not hit.is_empty():
			var n: Node = hit.collider
			desc = String(n.get_meta("desc")) if n.has_meta("desc") else n.name
			desc += "（%s）" % ("可見" if (n as Node3D).is_visible_in_tree() else "隱藏")
		var locked = player._aim_target
		player.on_attack_up()
		await get_tree().process_frame
		var s: Node = player._shuriken_in_flight
		var t := 0.0
		if _trace:
			print("  after throw: shuriken=%d node=%s valid=%s pstate=%d aim=%d" % [player.shuriken, str(s), is_instance_valid(s), player.state, player.aim_mode])
		var next_log := 0.0
		while is_instance_valid(s) and s.is_inside_tree() and not s.get("stuck") and t < 2.5:
			await get_tree().process_frame
			t += get_process_delta_time()
			if _trace and t >= next_log:
				next_log += 0.2
				print("  [%.2f] shuriken at %s" % [t, (s as Node3D).global_position])
		var end_s := "消失（命中敵人／燈籠）"
		var miss := -1.0
		var offline := -1.0
		if is_instance_valid(s) and s.is_inside_tree():
			var e: Vector3 = s.global_position
			end_s = "(%.1f, %.1f, %.1f)" % [e.x, e.y, e.z]
			miss = e.distance_to(expect)
			var rel: Vector3 = e - r[0]
			offline = (rel - r[1] * rel.dot(r[1])).length()
		var ehp := ("　敵人 hp=%d" % dummy.hp) if is_instance_valid(dummy) else ""
		print("THROW yaw=%.1f pitch=%.2f 鎖定=%s　準心點 (%.1f, %.1f, %.1f) %s　手裡劍停在 %s　差 %.2f m　離射線 %.2f m%s" % [
			float(v[0]), float(v[1]), str(locked != null), expect.x, expect.y, expect.z, desc, end_s, miss, offline, ehp])
		await get_tree().create_timer(0.4).timeout
	get_tree().quit()


## plunge：下劈量測。敵人（--kind）在起點警戒，玩家在他上方 4 公尺按攻擊，印落地後敵人 hp／狀態與玩家狀態
func _plunge_test() -> void:
	for i in range(3):
		for n in get_tree().get_nodes_in_group("enemies"):
			n.queue_free()
		await get_tree().process_frame
		var e := Enemy.new()
		e.kind = kind
		e.face_dir = Vector3(0, 0, 1)
		level.add_child(e)
		e.global_position = _start_pos + Vector3(0.0, 0.0, -2.0)
		e.alerted_once = true
		e._go_alert()
		player.revive()
		player.global_position = _start_pos + Vector3(0.3, 4.0, -2.3)
		player.velocity = Vector3.ZERO
		await get_tree().create_timer(0.15).timeout
		var hp0: int = e.hp
		player.request_attack()
		var st0: String = player.State.keys()[player.state]
		await get_tree().create_timer(1.2).timeout
		var es: String = e.State.keys()[e.state] if is_instance_valid(e) else "freed"
		print("PLUNGE %s run %d: 按下後狀態=%s　敵人 hp %d→%d（%s）　體幹 %.0f　玩家最後狀態=%s hp=%d" % [
			e.spec.name if is_instance_valid(e) else "?", i + 1, st0, hp0, e.hp if is_instance_valid(e) else 0, es,
			e.posture if is_instance_valid(e) else 0.0, player.State.keys()[player.state], player.hp])
		await get_tree().create_timer(0.3).timeout
	get_tree().quit()


## ui：對觸控層直接送按鍵事件，驗證「換」會切武器、「鉤」按住會進瞄準、放開會射、攻擊會出刀
func _touch(tc: Node, pos: Vector2, pressed: bool, idx: int = 0) -> void:
	var ev := InputEventScreenTouch.new()
	ev.position = pos
	ev.pressed = pressed
	ev.index = idx
	tc._unhandled_input(ev)


func _ui_test() -> void:
	await get_tree().create_timer(0.5).timeout
	var tc: Node = hud.touch
	print("UI size=%s swap=%s atk=%s hook=%s dash=%s block=%s" % [tc.size, tc._swap_center(), tc._atk_center(), tc._hook_center(), tc._dash_center(), tc._block_center()])
	_touch(tc, tc._swap_center(), true)
	_touch(tc, tc._swap_center(), false)
	await get_tree().process_frame
	print("UI 換 → weapon_mode=%d（1＝手裡劍） label=%s" % [player.weapon_mode, tc.weapon_label])
	_touch(tc, tc._hook_center(), true)
	await get_tree().create_timer(0.4).timeout
	print("UI 鉤按住 → aim_mode=%d（2＝鉤） cam.aiming=%s role=%s" % [player.aim_mode, cam_rig.aiming, str(tc._btn_touch)])
	_touch(tc, tc._hook_center(), false)
	await get_tree().create_timer(0.3).timeout
	print("UI 鉤放開 → aim_mode=%d state=%s" % [player.aim_mode, player.State.keys()[player.state]])
	_touch(tc, tc._atk_center(), true)
	await get_tree().create_timer(0.3).timeout
	print("UI 攻擊按住（手裡劍模式）→ aim_mode=%d（1＝手裡劍）" % player.aim_mode)
	_touch(tc, tc._atk_center(), false)
	await get_tree().create_timer(0.3).timeout
	print("UI 攻擊放開 → shuriken=%d state=%s" % [player.shuriken, player.State.keys()[player.state]])
	get_tree().quit()


func _begin_run() -> void:
	if mode == "ui":
		_ui_test()
		return
	if mode == "throw":
		_throw_test()
		return
	if mode == "plunge":
		_plunge_test()
		return
	_run += 1
	_t = 0.0
	_done = false
	_hits_taken = 0
	_breaks = 0
	_block_t = 0.0
	_atk_cd = 0.0
	for n in get_tree().get_nodes_in_group("enemies"):
		n.queue_free()
	for c in level.get_children():
		if c is Shuriken or c is Ration or c is Arrow:
			c.queue_free()
	player.global_position = _start_pos
	player.velocity = Vector3.ZERO
	player.revive()
	player.set_block(false)
	hud.touch.move_vector = Vector2.ZERO
	enemy = Enemy.new()
	enemy.kind = kind if mode == "chase" else Enemy.Kind.SAMURAI
	enemy.face_dir = Vector3(0, 0, 1)
	level.add_child(enemy)
	if mode == "chase":
		# 敵人站在起點，玩家在他前方 6 公尺、面向 -Z（第一院往石階的直線）
		enemy.global_position = _start_pos
		player.global_position = _start_pos + Vector3(0.0, 0.0, -CHASE_START)
		enemy.face_dir = Vector3(0, 0, -1)
		_chase_d0 = CHASE_START
		_chase_caught = false
		_chase_armed = false
		player.damaged.connect(func(_a: int) -> void:
			_chase_caught = true, CONNECT_ONE_SHOT)
	else:
		enemy.global_position = _start_pos + Vector3(0.0, 0.0, -4.0)
	enemy.alerted_once = true
	enemy.died.connect(func(_e: Enemy, _s: bool) -> void:
		_end_run(true))
	enemy._go_alert()
	cam_rig.yaw = 0.0


func _end_chase(reason: String, dist: float) -> void:
	if _done:
		return
	_done = true
	var rate := (_chase_d0 - dist) / maxf(_t, 0.01)
	var reach := float(enemy.spec.reach)
	var eta := (CHASE_START - reach) / rate if rate > 0.01 else INF
	var eta_s := "%.1fs" % eta if rate > 0.01 else "永遠追不上"
	_results.append({"win": false, "t": _t, "rate": rate, "eta": eta, "reason": reason})
	print("CHASE %s run %d/%d: %s  t=%.2fs  dist %.1f→%.1f  closing %.2f m/s  6公尺→追上 %s" % [enemy.spec.name, _run, runs, reason, _t, _chase_d0, dist, rate, eta_s])
	if _run >= runs:
		var avg := 0.0
		for r in _results:
			avg += float(r.rate)
		avg /= maxf(_results.size(), 1.0)
		var reach2 := float(enemy.spec.reach)
		print("CHASE SUMMARY %s: run=%.1f walk=5.4 closing %.2f m/s  6公尺→追上 %s" % [enemy.spec.name, float(enemy.spec.run), avg, ("%.1fs" % ((CHASE_START - reach2) / avg)) if avg > 0.01 else "永遠追不上"])
		get_tree().quit()
		return
	get_tree().create_timer(0.6).timeout.connect(_begin_run)


func _end_run(win: bool) -> void:
	if _done:
		return
	_done = true
	if win:
		_wins += 1
	var ehp: int = enemy.hp if is_instance_valid(enemy) else 0
	_results.append({"win": win, "t": _t, "hp": player.hp, "ehp": ehp, "taken": _hits_taken, "breaks": _breaks})
	print("BOT %s run %d/%d: %s  t=%.1fs  hp=%d  enemy_hp=%d  hits_taken=%d  posture_breaks=%d" % [mode, _run, runs, "WIN" if win else "LOSS", _t, player.hp, ehp, _hits_taken, _breaks])
	if _run >= runs:
		var avg_t := 0.0
		for r in _results:
			avg_t += float(r.t)
		avg_t /= maxf(_results.size(), 1.0)
		print("BOT SUMMARY %s: wins %d/%d (%.0f%%)  avg_time %.1fs" % [mode, _wins, runs, 100.0 * _wins / runs, avg_t])
		get_tree().quit()
		return
	get_tree().create_timer(0.6).timeout.connect(_begin_run)


var _last_state := -1
var _trace := false


func _physics_process(delta: float) -> void:
	if mode == "throw" or mode == "plunge" or mode == "ui":
		return
	if _done or not is_instance_valid(enemy) or player == null:
		return
	_t += delta
	if _trace and enemy.state != _last_state:
		_last_state = enemy.state
		var d: Vector3 = enemy.global_position - player.global_position
		print("  [%.2f] enemy state=%s dist=%.2f cd=%.2f guard=%s pstate=%d" % [_t, enemy.State.keys()[enemy.state], Vector2(d.x, d.z).length(), enemy._attack_cd, enemy._guard, player.state])
	if player.state == player.State.DEAD:
		_end_run(false)
		return
	if _t > 60.0:
		_end_run(false)
		return
	var to: Vector3 = enemy.global_position - player.global_position
	to.y = 0.0
	var dist := to.length()
	var dir := to.normalized() if dist > 0.01 else Vector3.FORWARD
	# 面向敵人（站著不動時也轉身）
	if mode != "chase" and player.state in [player.State.FREE, player.State.BLOCK]:
		player._facing = atan2(-dir.x, -dir.z)
	var local := dir.rotated(Vector3.UP, -cam_rig.yaw)
	var joy := Vector2(local.x, local.z)
	match mode:
		"chase":
			# 前 0.25 秒把兩人釘在起始位置（剛生成那幾幀物理會把重疊的身體彈開），之後才開始計時
			if not _chase_armed:
				player.global_position = _start_pos + Vector3(0.0, 0.0, -CHASE_START)
				player.velocity = Vector3.ZERO
				enemy.global_position = _start_pos
				enemy.velocity = Vector3.ZERO
				if _t >= 0.25:
					_chase_armed = true
					_t = 0.0
				return
			# 背對敵人全速走（不閃步）；被打到／進攻擊距離＝追上；撞牆或時間到就結算
			hud.touch.move_vector = -joy
			var reach := float(enemy.spec.reach)
			if _chase_caught or dist < reach * 1.05:
				_end_chase("追上", dist)
			elif _t > 0.6 and Vector2(player.velocity.x, player.velocity.z).length() < 2.5:
				_end_chase("撞牆（量測截止）", dist)
			elif _t > CHASE_MAX_T:
				_end_chase("時間到", dist)
			return
		"mash":
			hud.touch.move_vector = joy if dist > 1.9 else Vector2.ZERO
			player.request_attack()
		"deflect":
			_tick_deflect(delta, dist, joy)


func _tick_deflect(delta: float, dist: float, joy: Vector2) -> void:
	_block_t -= delta
	_atk_cd -= delta
	var attacking: bool = enemy.state == enemy.State.ATTACK
	var vulnerable: bool = enemy.state in [enemy.State.STAGGER, enemy.State.BROKEN]
	hud.touch.move_vector = Vector2.ZERO
	if attacking:
		var w: float = enemy._windup()
		var atk_t: float = enemy._atk_t
		if not _acted_this_attack:
			if enemy._perilous:
				# 危：不能擋，打到前約 100ms 往側邊閃（無敵幀蓋住打擊瞬間）
				if atk_t >= w - _dash_at:
					hud.touch.move_vector = Vector2(joy.y, -joy.x)
					player.request_dash()
					_acted_this_attack = true
			elif atk_t >= w - _react:
				player.set_block(true)
				_block_t = 0.3
				_acted_this_attack = true
	else:
		if _acted_this_attack:
			_react = randf_range(0.07, 0.17)
			_dash_at = randf_range(0.07, 0.13)
		_acted_this_attack = false
		if dist > 2.3 and not vulnerable:
			hud.touch.move_vector = joy * 0.6
	if _block_t <= 0.0 and player._block_held:
		player.set_block(false)
	# 敵人硬直／崩壞時砍（走近一點）
	if vulnerable:
		if dist > 2.0:
			hud.touch.move_vector = joy
		elif _atk_cd <= 0.0:
			player.request_attack()
			_atk_cd = 0.3
