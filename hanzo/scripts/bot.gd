extends Node
## 自動試玩 bot（議會驗證用）：對一名武士 1v1 打 N 場，印出勝率。
##   godot --path hanzo scenes/level1.tscn ++ --bot=mash --runs=20
##   godot --path hanzo scenes/level1.tscn ++ --bot=deflect --runs=20
## mash：走到武士面前每幀狂按攻擊，從不格擋、從不閃（模擬無腦連按）。
## deflect：等武士出手，在打到前 70～170ms 舉刀（人類反應抖動），趁硬直砍兩刀；看到「危」就閃步。
## 目標（第五次議會）：mash 勝率 <30%、deflect 勝率 >70%。

var mode := "mash"
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
	if _trace:
		player.hit_landed.connect(func(info: Dictionary) -> void:
			if is_instance_valid(enemy):
				print("  [%.2f] player hit landed dmg=%d heavy=%s -> enemy hp=%d guard=%s streak=%d state=%s" % [_t, int(info.dmg), info.heavy, enemy.hp, enemy._guard, enemy._blocked_streak, enemy.State.keys()[enemy.state]]))
	_begin_run()


func _begin_run() -> void:
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
	enemy.kind = Enemy.Kind.SAMURAI
	enemy.face_dir = Vector3(0, 0, 1)
	level.add_child(enemy)
	enemy.global_position = _start_pos + Vector3(0.0, 0.0, -4.0)
	enemy.alerted_once = true
	enemy.died.connect(func(_e: Enemy, _s: bool) -> void:
		_end_run(true))
	enemy._go_alert()
	cam_rig.yaw = 0.0


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
	if player.state in [player.State.FREE, player.State.BLOCK]:
		player._facing = atan2(-dir.x, -dir.z)
	var local := dir.rotated(Vector3.UP, -cam_rig.yaw)
	var joy := Vector2(local.x, local.z)
	match mode:
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
