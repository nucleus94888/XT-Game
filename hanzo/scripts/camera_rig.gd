extends Node3D
## 跟隨鏡頭：平時俯視環繞（可旋轉 yaw、微調俯角）；瞄準時切到「過肩鏡頭」（像射擊遊戲），
## 拖曳視角＝瞄準，畫面中心就是準心。創傷式震動與方向性踢擊以真實時間推進。

@export var distance := 12.5
@export var follow_speed := 7.0
@export var look_height := 1.0

@onready var cam: Camera3D = $Camera3D

## 水平旋轉角（弧度）。0 = 從 +Z 往 -Z 看（北）
var yaw := 0.0
## 俯視環繞的俯角（弧度，從水平面算）
var pitch := deg_to_rad(49.0)
## 瞄準中：過肩鏡頭
var aiming := false
## 瞄準時的抬頭／低頭（弧度，正 = 向下看）
var aim_pitch := 0.15

var _target: Node3D
var _trauma := 0.0
var _decay := 0.0
var _kick := Vector3.ZERO
var _last_ms := 0
var _blend := 0.0
var _base_fov := 55.0
## 下劈時多壓一點俯角、拉遠一點，落點與目標留在畫面中段（不被拇指蓋住）
var extra_pitch := 0.0
var _extra := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Feel.shake_requested.connect(_on_shake)
	Feel.kick_requested.connect(_on_kick)
	Feel.params_changed.connect(_apply_params)
	_apply_params()
	_last_ms = Time.get_ticks_msec()


func set_target(t: Node3D) -> void:
	_target = t
	snap_to_target()


## 立刻跳到目標位置並算好鏡頭（關卡把玩家傳送到起點後呼叫，不然開場會看到鏡頭從原點飛過去）
func snap_to_target() -> void:
	if _target:
		global_position = _target.global_position
		_process(0.0)


## 滑動視角：delta 為螢幕像素位移。瞄準中靈敏度較低、可上下抬頭低頭。
func look(delta: Vector2) -> void:
	delta *= Feel.get_p("look_sens")
	if aiming:
		yaw -= delta.x * 0.0032
		aim_pitch = clampf(aim_pitch + delta.y * 0.0024, -0.75, 0.8)
	else:
		yaw -= delta.x * 0.0045
		pitch = clampf(pitch + delta.y * 0.0025, deg_to_rad(28.0), deg_to_rad(72.0))


## 鏡頭正前方（水平）的世界方向
func forward() -> Vector3:
	return Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, yaw)


## 瞄準射線：從鏡頭中心往畫面正中央
func aim_ray() -> Array:
	return [cam.global_position, -cam.global_transform.basis.z]


func _apply_params() -> void:
	_base_fov = Feel.get_p("cam_fov")


## 遮擋處理（第十次議會＋使用者要求）：每 3 幀從人物頭頂往鏡頭打射線。
##   樹冠擋住 → 樹冠變半透明（兩種模式都一樣，樹不拉鏡頭）
##   牆擋住 → 設定「牆擋住時鏡頭拉近」開：0.3 秒拉近到牆前（最近 3 公尺），離開遮擋 0.5 秒後拉回；
##            關：牆變半透明
##   室內的屋頂仍由遮蔽層整片隱藏
var _occ_dist := -1.0
var _occ_target := 12.5
var _occ_clear_t := 0.0
var _occ_frame := 0
var _faded := {}
## 被擋住時先把鏡頭抬高（更俯視、從障礙物上方看下來），抬到底還擋才拉近
var occ_pitch := 0.0
var _occ_pitch_target := 0.0
const OCC_PITCHES := [0.0, 0.22, 0.42, 0.6]
const MAX_PITCH := 1.4


## 從頭頂往鏡頭打射線：回傳第一個實心障礙的距離（沒擋＝-1），樹幹與透明牆略過；fade 收集要變半透明的東西
func _occ_probe(space: PhysicsDirectSpaceState3D, head: Vector3, cam_w: Vector3, fade: Dictionary, fade_walls: bool) -> float:
	var ex: Array = [_target.get_rid()] if _target is CollisionObject3D else []
	var first_d := -1.0
	for i in range(5):
		var q := PhysicsRayQueryParameters3D.create(head, cam_w, 1)
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		ex.append(hit.rid)
		var c: Node = hit.collider
		if c is Node3D and (c.has_meta("ghost") or not (c as Node3D).is_visible_in_tree()):
			continue
		if c.has_meta("no_pull") or fade_walls:
			for ch in c.get_children():
				if ch is MeshInstance3D:
					fade[ch] = true
			if c.has_meta("no_pull"):
				continue
		if first_d < 0.0:
			first_d = head.distance_to(hit.position)
	return first_d


func _cam_at(pitch_v: float, dist: float) -> Vector3:
	return global_position + Vector3(0.0, sin(pitch_v) * dist, cos(pitch_v) * dist).rotated(Vector3.UP, yaw)


func _update_occlusion(p: float, dt: float) -> void:
	if _target == null:
		return
	_occ_frame += 1
	if _occ_frame % 3 == 0:
		var head := _target.global_position + Vector3(0.0, 1.5, 0.0)
		var pull := Feel.get_p("cam_pull") >= 0.5
		var want := {}
		var space := get_world_3d().direct_space_state
		var cam_w := _cam_at(p, distance)
		if pull:
			# 依序試：原角度、抬高 12°、24°、34°；第一個沒被擋的就用它。全部都擋才拉近（最近 4 公尺）
			var chosen := -1.0
			var last_d := -1.0
			for extra in OCC_PITCHES:
				var pp := minf(p + float(extra), MAX_PITCH)
				var scratch := {}
				var d := _occ_probe(space, head, _cam_at(pp, distance), scratch, false)
				if d < 0.0:
					chosen = float(extra)
					cam_w = _cam_at(pp, distance)
					for k in scratch:
						want[k] = true
					break
				last_d = d
			if chosen >= 0.0:
				_occ_pitch_target = chosen
				_occ_clear_t += dt * 3.0
				if chosen > 0.0 or _occ_clear_t > 0.5:
					_occ_target = distance
				if chosen > 0.0:
					_occ_clear_t = 0.0
			else:
				_occ_pitch_target = float(OCC_PITCHES[-1])
				_occ_target = clampf(last_d - 0.6, 4.0, distance)
				_occ_clear_t = 0.0
				cam_w = _cam_at(minf(p + _occ_pitch_target, MAX_PITCH), _occ_target)
				_occ_probe(space, head, cam_w, want, false)
		else:
			_occ_pitch_target = 0.0
			_occ_target = distance
			_occ_probe(space, head, cam_w, want, true)
		# 樹冠
		var seg := cam_w - head
		var seg_len2 := seg.length_squared()
		for n in get_tree().get_nodes_in_group("canopy"):
			var c3 := n as Node3D
			var t := clampf((c3.global_position - head).dot(seg) / maxf(seg_len2, 0.001), 0.0, 1.0)
			var closest := head + seg * t
			if c3.global_position.distance_to(closest) < float(c3.get_meta("radius", 1.5)) + 0.3:
				want[c3] = true
		# 套用：新擋住的變透明、不再擋的還原
		for n in _faded.keys():
			if not want.has(n):
				if is_instance_valid(n):
					(n as MeshInstance3D).material_override = n.get_meta("orig_mat")
				_faded.erase(n)
		for n in want.keys():
			if _faded.has(n):
				continue
			var mi := n as MeshInstance3D
			if not mi.has_meta("orig_mat"):
				mi.set_meta("orig_mat", mi.material_override)
				var m: StandardMaterial3D = (mi.material_override as StandardMaterial3D).duplicate() if mi.material_override else StandardMaterial3D.new()
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.albedo_color.a = 0.25
				mi.set_meta("fade_mat", m)
			mi.material_override = mi.get_meta("fade_mat")
			_faded[n] = true
	# 拉近／抬高快、恢復慢
	var rate := 1.0 / 0.3 if _occ_target < _occ_dist else 1.0 / 0.6
	_occ_dist = move_toward(_occ_dist, _occ_target, (distance - 4.0) * rate * dt)
	var prate := 1.0 / 0.3 if _occ_pitch_target > occ_pitch else 1.0 / 0.8
	occ_pitch = move_toward(occ_pitch, _occ_pitch_target, 0.6 * prate * dt)


## 射線，但跳過被遮蔽層隱藏的東西（屋頂、樓板隱藏時還有碰撞）
func _ray_visible(from: Vector3, to: Vector3, mask: int, exclude: Array = []) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var ex: Array = exclude.duplicate()
	for i in range(4):
		var q := PhysicsRayQueryParameters3D.create(from, to, mask)
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return hit
		var c: Node = hit.collider
		# 隱藏的遮蔽層、沒有外觀的透明牆：鏡頭都當作不存在
		if c is Node3D and (not (c as Node3D).is_visible_in_tree() or c.has_meta("ghost")):
			ex.append(hit.rid)
			continue
		return hit
	return {}


func _on_shake(amp: float, dur: float) -> void:
	_trauma = minf(maxf(_trauma, amp), 1.0)
	_decay = amp / maxf(dur, 0.02)


func _on_kick(dir: Vector3, amount: float) -> void:
	_kick += Vector3(dir.x, 0.0, dir.z) * amount


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	var real_dt := clampf(float(now - _last_ms) / 1000.0, 0.0, 0.1)
	_last_ms = now
	if _target:
		var w := 1.0 - exp(-follow_speed * delta)
		global_position = global_position.lerp(_target.global_position, w)
	_blend = move_toward(_blend, 1.0 if aiming else 0.0, real_dt * 6.0)
	var t := float(now) * 0.06
	var sh := _trauma * _trauma
	var off := Vector3(
		sin(t * 1.9) * 0.6 + sin(t * 3.7) * 0.4,
		cos(t * 2.3) * 0.6 + sin(t * 4.1) * 0.4,
		0.0
	) * sh * 1.6
	var roll := sin(t * 2.9) * sh * 0.09
	# 俯視環繞
	_extra = lerpf(_extra, extra_pitch, 1.0 - exp(-6.0 * real_dt))
	var p := pitch + _extra
	if _occ_dist < 0.0:
		_occ_dist = distance
		_occ_target = distance
	_update_occlusion(p, real_dt)
	p = minf(p + occ_pitch, MAX_PITCH)
	var dist := _occ_dist + _extra * 4.0
	var orbit_pos := Vector3(0.0, sin(p) * dist, cos(p) * dist).rotated(Vector3.UP, yaw)
	var orbit_look := Vector3(0.0, look_height, 0.0)
	# 過肩
	var f := forward()
	var right := Vector3(1.0, 0.0, 0.0).rotated(Vector3.UP, yaw)
	# 過肩：偏右上，避免半藏的頭擋住準心
	var shoulder_pos := Vector3(0.0, 2.05, 0.0) - f * 3.0 + right * 1.05
	# 鏡頭不能退到牆後面：從頭頂往肩後位置打射線，撞到牆就把鏡頭拉到牆前面
	# （不然畫面中心的射線從牆外打過來，準心點手搆不到，手裡劍會射偏）
	if _blend > 0.01 and _target:
		var head := global_position + Vector3(0.0, 1.7, 0.0)
		var want := global_position + shoulder_pos
		var hit := _ray_visible(head, want, 1, [_target.get_rid()] if _target is CollisionObject3D else [])
		if not hit.is_empty():
			var pulled: Vector3 = (hit.position as Vector3) + ((head - want).normalized()) * 0.3
			shoulder_pos = pulled - global_position
	var aim_f := (f * cos(aim_pitch) + Vector3(0.0, -sin(aim_pitch), 0.0)).normalized()
	var shoulder_look := shoulder_pos + aim_f * 12.0
	var k := smoothstep(0.0, 1.0, _blend)
	cam.position = orbit_pos.lerp(shoulder_pos, k) + off.rotated(Vector3.UP, yaw) + _kick
	var look_at_p := global_position + orbit_look.lerp(shoulder_look, k) + _kick * 0.5
	cam.look_at(look_at_p, Vector3.UP)
	cam.rotate_object_local(Vector3(0.0, 0.0, 1.0), roll)
	cam.fov = lerpf(_base_fov, 42.0, k)
	_trauma = maxf(_trauma - _decay * real_dt, 0.0)
	_kick = _kick.lerp(Vector3.ZERO, 1.0 - exp(-14.0 * real_dt))
