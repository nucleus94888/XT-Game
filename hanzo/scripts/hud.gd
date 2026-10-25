extends CanvasLayer
## HUD：命中 / 連段 / 擊破統計、HP 條、目標文字、大字宣告、受擊閃光、手感面板、
## 以及暫停式覆蓋層（敗北 / 結算）。道場與關卡共用。

@onready var stats: Label = $Stats
@onready var hp_bar: ProgressBar = $HpBar
@onready var posture_bar: ProgressBar = $PostureBar
@onready var compass: Control = $Compass
@onready var objective: Label = $Objective
@onready var announce: Label = $Announce
@onready var flash: ColorRect = $Flash
@onready var fps: Label = $Fps
@onready var gear: Button = $GearBtn
@onready var panel: Control = $TuningPanel
@onready var touch: Control = $TouchControls
@onready var pause_btn: Button = $PauseBtn
@onready var debug_tap: Control = $DebugTap

var hits := 0
var combo := 0
var best_combo := 0
var kills := 0
var _combo_t := 0.0
var _flash_tw: Tween
var _last_ms := 0
var _worst_ms := 0
var _worst_shown := 0
var _worst_t := 1.0
var _overlay: Control
var _player: Node3D
var _cam: Node3D
var _compass_target := Vector3.ZERO
var _has_compass_target := false
var _posture_tw: Tween
var _obj_tw: Tween
var _debug := false
var _tap_times: Array = []
var _paused_by_menu := false
## 觸控延遲量測（網頁版）：JS touchstart 時間戳 → Godot 收到 InputEventScreenTouch 的毫秒差
var _lat_samples: Array = []
var _lat_js := false


var items_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("hud")
	touch.process_mode = Node.PROCESS_MODE_PAUSABLE
	items_label = Label.new()
	items_label.position = Vector2(18, 48)
	items_label.add_theme_font_size_override("font_size", 16)
	items_label.add_theme_color_override("font_outline_color", Color.BLACK)
	items_label.add_theme_constant_override("outline_size", 4)
	items_label.modulate = Color(0.85, 1.0, 0.85)
	add_child(items_label)
	Feel.flash_requested.connect(_on_flash)
	fps.offset_right = 980.0
	fps.modulate = Color(1, 1, 1, 0.9)
	if "--debug" in OS.get_cmdline_user_args():
		_debug = true
		stats.visible = true
		fps.visible = true
	# 截圖用：++ --overlay=pause|lose 一秒後直接開覆蓋層看排版
	for a in OS.get_cmdline_user_args():
		if a == "--overlay=pause":
			get_tree().create_timer(0.6).timeout.connect(show_pause)
		elif a == "--overlay=lose":
			get_tree().create_timer(0.6).timeout.connect(func() -> void:
				show_overlay("敗北", ["時間 1:05　擊破 3　被擊中 6 次"], [["從檢查點再來", func() -> void: pass], ["整關重來", func() -> void: pass], ["回標題", func() -> void: pass]], Color(0.95, 0.3, 0.3)))
	_setup_latency_probe()
	get_tree().root.size_changed.connect(_layout_orientation)
	_layout_orientation()


## 直立（高 > 寬）：任務文字從置中改成靠左、放到血條下面，不然會壓到暫停鍵與羅盤
func _layout_orientation() -> void:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var portrait: bool = vs.y > vs.x
	if portrait:
		objective.offset_left = -vs.x / 2.0 + 18.0
		objective.offset_right = vs.x / 2.0 - 215.0
		objective.offset_top = 58.0
		objective.offset_bottom = 130.0
		objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		items_label.position = Vector2(18, 136)
	else:
		objective.offset_left = -400.0
		objective.offset_right = 400.0
		objective.offset_top = 12.0
		objective.offset_bottom = 44.0
		objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		objective.autowrap_mode = TextServer.AUTOWRAP_OFF
		items_label.position = Vector2(18, 48)
	gear.pressed.connect(toggle_panel)
	panel.visible = false
	pause_btn.pressed.connect(show_pause)
	debug_tap.mouse_filter = Control.MOUSE_FILTER_STOP
	debug_tap.gui_input.connect(_on_debug_tap)
	var blockers: Array[Control] = [panel, gear, pause_btn, debug_tap]
	touch.blockers = blockers
	_refresh()


## 把觸控與玩家接起來（道場、關卡共用）
func attach(player: Node, cam_rig: Node) -> void:
	_player = player
	_cam = cam_rig
	compass.player = player
	player.touch = touch
	# 鉤點畫面記號：畫在按鍵下面
	var marks: Control = preload("res://scripts/hook_marks.gd").new()
	marks.player = player
	touch.get_parent().add_child(marks)
	touch.get_parent().move_child(marks, touch.get_index())
	player.cam_rig = cam_rig
	touch.look_delta.connect(cam_rig.look)
	player.posture_changed.connect(set_posture)
	player.posture_broken.connect(func() -> void:
		say_hint("體幹崩壞", Color(1.0, 0.55, 0.2))
		flash_posture())
	touch.attack_down.connect(player.on_attack_down)
	touch.attack_up.connect(player.on_attack_up)
	touch.hook_down.connect(player.on_hook_down)
	touch.hook_up.connect(player.on_hook_up)
	touch.weapon_toggle.connect(player.toggle_weapon)
	player.weapon_changed.connect(func(m: int) -> void:
		touch.weapon_label = ["刀", "劍", "煙"][clampi(m, 0, 2)])
	touch.ctx_pressed.connect(player.interact)
	player.ctx_changed.connect(touch.set_ctx)
	player.smoke_changed.connect(func(n: int) -> void:
		touch.smoke_count = n)
	touch.smoke_count = player.smoke
	_pl = player
	_build_breath()
	touch.dash_pressed.connect(player.request_dash)
	touch.block_changed.connect(player.set_block)
	player.shuriken_changed.connect(func(n: int) -> void:
		touch.set_shuriken_count(n))
	touch.shuriken_count = player.shuriken
	cam_rig.set_target(player)
	player.hit_landed.connect(func(info: Dictionary) -> void:
		add_hit(bool(info.heavy)))
	player.hp_changed.connect(set_hp)
	player.rations_changed.connect(func(_n: int) -> void:
		_refresh_items()
		pop_items())
	set_hp(player.hp)
	_refresh_items()
	player.parried.connect(func() -> void:
		say_hint("彈反！", Color(1.0, 0.92, 0.5)))


## 輔助文字（第九次議會）：「已經發生、身體看得見」的事不再跳字，交給表情、血條、音效、震動。
## 設定裡的「輔助文字」開關打開才顯示（預設關）
func say_hint(text: String, color: Color = Color.WHITE) -> void:
	if Feel.get_p("hints") >= 0.5:
		say(text, color)


## 血條閃一下（回血綠、念珠金）：取代「+35」「念珠 +10」飄字
var _hp_tw: Tween


func flash_hp(color: Color) -> void:
	if _hp_tw and _hp_tw.is_valid():
		_hp_tw.kill()
	hp_bar.modulate = color
	_hp_tw = hp_bar.create_tween()
	_hp_tw.set_ignore_time_scale(true)
	_hp_tw.tween_property(hp_bar, "modulate", Color.WHITE, 0.6)


## 持有物那行彈一下（撿口糧、卷軸）
func pop_items() -> void:
	items_label.pivot_offset = Vector2(0.0, items_label.size.y / 2.0)
	items_label.scale = Vector2(1.35, 1.35)
	var tw := items_label.create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(items_label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func toggle_panel() -> void:
	panel.visible = not panel.visible
	gear.visible = _debug and not panel.visible


func _process_panel_state() -> void:
	gear.visible = _debug and not panel.visible and _overlay == null
	pause_btn.visible = _overlay == null


## 破圖回報（除錯模式左下）：關卡、玩家座標、鏡頭座標與角度、畫面中心看到的東西。
## 看到破圖就連點羅盤三下、把畫面中心對準破的地方、截圖傳來，座標對回關卡原始碼就能修。
func _debug_where() -> String:
	if _player == null or _cam == null:
		return ""
	var scene := get_tree().current_scene
	var lv := scene.scene_file_path.get_file().get_basename() if scene else "?"
	var p: Vector3 = _player.global_position
	var cam: Camera3D = _cam.get("cam")
	# 卡死回報：玩家狀態、瞄準、格擋、鎖定秒數、鉤繩工作、搖桿／按鍵手指、時間流速、是否暫停
	var st: String = _player.State.keys()[_player.state]
	var job: Dictionary = _player.get("_hook_job")
	var line := "狀態 %s　瞄 %d　擋 %s　鎖 %.1f　鉤 %s　搖桿 %d 視角 %d 鍵 %s　流速 %.2f%s" % [
		st, int(_player.get("aim_mode")), "是" if bool(_player.get("_block_held")) else "否", float(_player.get("_lock_t")),
		String(job.get("kind", "-")), int(touch.get("_joy_idx")), int(touch.get("_look_idx")), str(touch.get("_btn_touch").values()),
		Engine.time_scale, "　暫停" if get_tree().paused else ""]
	line += "\n%s　玩家 (%.1f, %.1f, %.1f)" % [lv, p.x, p.y, p.z]
	# 最近的敵人：他的高度、視野錐畫在哪個高度、用哪種畫法（俯視＝斜往下看的格點；平視＝水平射線）
	var best: Node3D = null
	var bd := 1e9
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node3D and e.get("_cone") != null:
			var dd := (e as Node3D).global_position.distance_to(p)
			if dd < bd:
				bd = dd
				best = e
	if best:
		var cone: Node3D = best.get("_cone")
		var mode := "俯視" if best.global_position.y - p.y > 0.8 else "平視"
		line += "\n最近敵人 %s 距 %.1f m　身高 y=%.1f　錐 y=%.1f（%s）%s" % [best.spec.name, bd, best.global_position.y, cone.global_position.y, mode, "" if cone.visible else "　錐隱藏"]
	if cam == null:
		return line
	var c := cam.global_position
	line += "　鏡頭 (%.1f, %.1f, %.1f) 轉 %d° 俯 %d°" % [c.x, c.y, c.z, int(rad_to_deg(float(_cam.get("yaw")))), int(rad_to_deg(float(_cam.get("pitch"))))]
	# 畫面中心射線：打到什麼、多遠（遮蔽層隱藏的屋頂也會打到，名稱會說）
	var space := cam.get_world_3d().direct_space_state
	var dir := -cam.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(c, c + dir * 60.0, 1 | 2)
	q.exclude = [_player.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return line + "\n中心：沒打到東西"
	var n: Node = hit.collider
	var desc := ""
	var walk: Node = n
	while walk and desc == "":
		if walk.has_meta("desc"):
			desc = String(walk.get_meta("desc"))
		walk = walk.get_parent()
	if desc == "":
		desc = n.name
	var hp: Vector3 = hit.position
	return line + "\n中心：%s　距 %.1f m　點 (%.1f, %.1f, %.1f)" % [desc, c.distance_to(hp), hp.x, hp.y, hp.z]


## 連點羅盤三下：顯示／隱藏除錯資訊（統計、fps、手感鈕、破圖回報座標）
func _on_debug_tap(ev: InputEvent) -> void:
	if (ev is InputEventScreenTouch and ev.pressed) or (ev is InputEventMouseButton and ev.pressed):
		var now := Time.get_ticks_msec()
		_tap_times.append(now)
		_tap_times = _tap_times.filter(func(t: int) -> bool: return now - t < 900)
		if _tap_times.size() >= 3:
			_tap_times.clear()
			_debug = not _debug
			stats.visible = _debug
			fps.visible = _debug
			gear.visible = _debug
			say("除錯 開" if _debug else "除錯 關", Color(0.8, 0.8, 0.8))


## 暫停選單
func show_pause() -> void:
	if _overlay != null:
		return
	show_overlay("暫停", [], [
		["繼續", func() -> void: pass],
		["設定", func() -> void: show_settings()],
		["重來", func() -> void: get_tree().reload_current_scene()],
		["回標題", func() -> void: get_tree().change_scene_to_file("res://scenes/title.tscn")],
	])


## 設定：音量、視角靈敏度、介面大小、左撇子；進階＝手感調校面板
func show_settings() -> void:
	hide_overlay()
	_overlay = Control.new()
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.11, 0.96)
	sb.set_content_margin_all(24.0)
	box.add_theme_stylebox_override("panel", sb)
	center.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.custom_minimum_size = Vector2(minf(520.0, get_viewport().get_visible_rect().size.x - 90.0), 0)
	box.add_child(vb)
	var t := Label.new()
	t.text = "設定"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 40)
	vb.add_child(t)
	for key in ["volume", "look_sens", "ui_scale"]:
		var spec: Array = Feel.PARAMS[key]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		vb.add_child(row)
		var l := Label.new()
		l.text = spec[0]
		l.custom_minimum_size.x = 150
		l.add_theme_font_size_override("font_size", 22)
		row.add_child(l)
		var s := HSlider.new()
		s.min_value = spec[1]
		s.max_value = spec[2]
		s.step = spec[3]
		s.value = Feel.get_p(key)
		s.custom_minimum_size = Vector2(240, 40)
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.value_changed.connect(func(v: float) -> void:
			Feel.set_p(key, v))
		row.add_child(s)
	var lefty := CheckButton.new()
	lefty.text = "左撇子（搖桿在右、按鍵在左）"
	lefty.button_pressed = Feel.get_p("lefty") >= 0.5
	lefty.add_theme_font_size_override("font_size", 22)
	lefty.toggled.connect(func(on: bool) -> void:
		Feel.set_p("lefty", 1.0 if on else 0.0))
	vb.add_child(lefty)
	var hints := CheckButton.new()
	hints.text = "輔助文字（被發現、彈反、體幹崩壞…）"
	hints.button_pressed = Feel.get_p("hints") >= 0.5
	hints.add_theme_font_size_override("font_size", 22)
	hints.toggled.connect(func(on: bool) -> void:
		Feel.set_p("hints", 1.0 if on else 0.0))
	vb.add_child(hints)
	var pull := CheckButton.new()
	pull.text = "牆擋住時鏡頭拉近（關＝牆變半透明）"
	pull.button_pressed = Feel.get_p("cam_pull") >= 0.5
	pull.add_theme_font_size_override("font_size", 22)
	pull.toggled.connect(func(on: bool) -> void:
		Feel.set_p("cam_pull", 1.0 if on else 0.0))
	vb.add_child(pull)
	var cones := CheckButton.new()
	cones.text = "顯示敵人視野扇形"
	cones.button_pressed = Feel.get_p("cones") >= 0.5
	cones.add_theme_font_size_override("font_size", 22)
	cones.toggled.connect(func(on: bool) -> void:
		Feel.set_p("cones", 1.0 if on else 0.0))
	vb.add_child(cones)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 14)
	vb.add_child(hb)
	for b in [["進階：手感調校", func() -> void:
			panel.visible = true],
		["返回", func() -> void: pass]]:
		var btn := Button.new()
		btn.text = str(b[0])
		btn.custom_minimum_size = Vector2(200, 58)
		btn.add_theme_font_size_override("font_size", 24)
		var cb: Callable = b[1]
		btn.pressed.connect(func() -> void:
			Feel.save_cfg()
			hide_overlay()
			cb.call())
		hb.add_child(btn)
	add_child(_overlay)
	touch.blockers.append(_overlay)
	touch.reset_touches()
	get_tree().paused = true


func add_hit(heavy: bool) -> void:
	hits += 1
	combo += 1
	best_combo = maxi(best_combo, combo)
	_combo_t = 1.8
	_refresh()
	if heavy:
		_pop(stats, 1.2, false)


func add_kill(text: String = "擊破！", color: Color = Color(1.0, 0.85, 0.4)) -> void:
	kills += 1
	_refresh()
	if text != "":
		say(text, color)


func set_hp(v: int) -> void:
	if _player:
		var mx: int = _player.max_hp
		hp_bar.max_value = mx
		# 血條長度跟著最大 HP 變（念珠）
		hp_bar.size.x = 240.0 * float(mx) / 100.0
	hp_bar.value = v


func _refresh_items() -> void:
	if _player == null:
		return
	var parts: Array = []
	if _player.rations > 0:
		parts.append("口糧 ×%d" % _player.rations)
	items_label.text = "　".join(parts)


## 體幹條：空的時候幾乎看不見，越滿越亮、超過 70% 開始脈動
func set_posture(v: float, max_v: float) -> void:
	posture_bar.max_value = max_v
	posture_bar.value = v
	var k := v / maxf(max_v, 1.0)
	posture_bar.modulate = Color(1.0, 1.0, 1.0, 0.35 + 0.65 * k)


## 體幹崩壞時閃紅
func flash_posture() -> void:
	if _posture_tw and _posture_tw.is_valid():
		_posture_tw.kill()
	posture_bar.modulate = Color(1.0, 0.25, 0.2)
	_posture_tw = posture_bar.create_tween()
	_posture_tw.set_ignore_time_scale(true)
	_posture_tw.tween_property(posture_bar, "modulate", Color(1, 1, 1, 0.35), 2.5)


## 網頁版：在 JS 端記 touchstart 的時間戳，Godot 端收到觸控時算延遲（除錯模式顯示在 fps 旁）
func _setup_latency_probe() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval("window.__xt_touch_t=0;window.addEventListener('touchstart',function(e){window.__xt_touch_t=e.timeStamp;},{passive:true,capture:true});", true)
	_lat_js = true


func _input(ev: InputEvent) -> void:
	if not _lat_js or not (ev is InputEventScreenTouch) or not ev.pressed:
		return
	var now = JavaScriptBridge.eval("performance.now()", true)
	var t0 = JavaScriptBridge.eval("window.__xt_touch_t", true)
	if now == null or t0 == null or float(t0) <= 0.0:
		return
	var lat := float(now) - float(t0)
	if lat < 0.0 or lat > 1000.0:
		return
	_lat_samples.append(lat)
	if _lat_samples.size() > 30:
		_lat_samples.pop_front()


func _latency_text() -> String:
	if _lat_samples.is_empty():
		return ""
	var sum := 0.0
	var worst := 0.0
	for s in _lat_samples:
		sum += float(s)
		worst = maxf(worst, float(s))
	return "　觸控延遲 %d ms（最差 %d）" % [int(sum / _lat_samples.size()), int(worst)]


func set_compass_target(pos: Vector3, color: Color = Color(0.6, 0.9, 1.0)) -> void:
	_compass_target = pos
	_has_compass_target = true
	compass.target_color = color


func clear_compass_target() -> void:
	_has_compass_target = false


## 目標文字：顯示 4 秒後淡出；再次設定時重新出現
func set_objective(text: String) -> void:
	objective.text = text
	objective.modulate = Color(1, 1, 1, 1)
	_pop(objective, 1.15)
	if _obj_tw and _obj_tw.is_valid():
		_obj_tw.kill()
	_obj_tw = objective.create_tween()
	_obj_tw.set_ignore_time_scale(true)
	_obj_tw.tween_interval(4.0)
	_obj_tw.tween_property(objective, "modulate:a", 0.0, 0.8)


func say(text: String, color: Color = Color.WHITE) -> void:
	announce.text = text
	announce.modulate = color
	announce.pivot_offset = announce.size / 2.0
	announce.scale = Vector2.ONE * 1.6
	var tw := announce.create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(announce, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.6)
	tw.tween_property(announce, "modulate:a", 0.0, 0.3)


## 暫停遊戲並顯示覆蓋層。buttons = [[文字, Callable], ...]
func show_overlay(title: String, lines: Array, buttons: Array, title_color: Color = Color.WHITE) -> void:
	hide_overlay()
	_overlay = Control.new()
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.11, 0.96)
	sb.set_content_margin_all(28.0)
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	box.add_theme_stylebox_override("panel", sb)
	center.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	box.add_child(vb)
	var t := Label.new()
	t.text = title
	t.modulate = title_color
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 52)
	vb.add_child(t)
	for line in lines:
		var l := Label.new()
		l.text = str(line)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 24)
		vb.add_child(l)
	# 直立或按鈕排不下一排時改成直向疊放（面板不能比螢幕寬）
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var stack: bool = vs.y > vs.x or buttons.size() * 236.0 > vs.x - 80.0
	var hb: BoxContainer = VBoxContainer.new() if stack else HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 16 if not stack else 10)
	vb.add_child(hb)
	for b in buttons:
		var btn := Button.new()
		btn.text = str(b[0])
		btn.custom_minimum_size = Vector2(minf(320.0, vs.x - 140.0) if stack else 220.0, 60 if stack else 64)
		btn.add_theme_font_size_override("font_size", 26)
		var cb: Callable = b[1]
		btn.pressed.connect(func() -> void:
			hide_overlay()
			cb.call())
		hb.add_child(btn)
	add_child(_overlay)
	touch.blockers.append(_overlay)
	touch.reset_touches()
	get_tree().paused = true


func hide_overlay() -> void:
	if _overlay:
		touch.blockers.erase(_overlay)
		_overlay.queue_free()
		_overlay = null
	get_tree().paused = false
	# 暫停期間按下、放開的手指 touch 都沒收到，回來時一律當成全部放開
	touch.reset_touches()


func _on_flash(color: Color, dur: float) -> void:
	flash.color = color
	if _flash_tw:
		_flash_tw.kill()
	_flash_tw = flash.create_tween()
	_flash_tw.tween_property(flash, "color:a", 0.0, dur)


## 開場黑幕：全黑再淡入（蓋住鏡頭定位與著色器預熱）
func curtain(dur: float) -> void:
	flash.color = Color(0.0, 0.0, 0.0, 1.0)
	if _flash_tw:
		_flash_tw.kill()
	_flash_tw = flash.create_tween()
	_flash_tw.tween_interval(0.12)
	_flash_tw.tween_property(flash, "color:a", 0.0, dur)


## 水遁的氣息條：潛水中／氣沒滿才出現，畫面上方中央一條藍色細條（快沒氣變紅閃）
var _pl: Node = null
var _breath: ProgressBar


func _build_breath() -> void:
	_breath = ProgressBar.new()
	_breath.show_percentage = false
	_breath.max_value = 1.0
	_breath.step = 0.0
	_breath.custom_minimum_size = Vector2(180, 10)
	_breath.size = Vector2(180, 10)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.set_corner_radius_all(5)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color(0.45, 0.8, 1.0)
	fg.set_corner_radius_all(5)
	_breath.add_theme_stylebox_override("background", bg)
	_breath.add_theme_stylebox_override("fill", fg)
	_breath.visible = false
	add_child(_breath)


func _update_breath() -> void:
	if _pl == null or _breath == null:
		return
	var b: float = _pl.get("breath")
	var mx: float = _pl.BREATH_MAX
	# 改成竹筒呼吸後不限時間，氣息條只在氣沒滿時出現（目前不會出現；保留給之後的「沒竹筒的深水」）
	var show: bool = b < mx - 0.01
	_breath.visible = show
	if not show:
		return
	var vr := get_viewport().get_visible_rect().size
	_breath.position = Vector2((vr.x - _breath.size.x) / 2.0, vr.y * 0.18)
	_breath.value = b / mx
	var low := b < 2.5
	var fg := _breath.get_theme_stylebox("fill") as StyleBoxFlat
	fg.bg_color = Color(1.0, 0.35, 0.3) if low else Color(0.45, 0.8, 1.0)
	_breath.modulate.a = (0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.02)) if low else 1.0


func _process(delta: float) -> void:
	_update_breath()
	if _combo_t > 0.0:
		_combo_t -= delta
		if _combo_t <= 0.0:
			combo = 0
			_refresh()
	# 以真實時間量最長一幀（頓幀不算），用來分辨「故意的頓幀」與「真的卡」
	var now := Time.get_ticks_msec()
	if _last_ms > 0:
		_worst_ms = maxi(_worst_ms, now - _last_ms)
	_last_ms = now
	_worst_t -= delta
	if _worst_t <= 0.0:
		_worst_t = 1.0
		_worst_shown = _worst_ms
		_worst_ms = 0
	if _debug:
		fps.text = "%d fps　最長一幀 %d ms%s\n%s" % [Engine.get_frames_per_second(), _worst_shown, _latency_text(), _debug_where()]
	if posture_bar.value >= posture_bar.max_value * 0.7:
		posture_bar.modulate.a = 0.75 + 0.25 * sin(float(Time.get_ticks_msec()) * 0.015)
	_process_panel_state()
	# 鍵盤轉視角（Q / E）與指南針
	if _cam:
		var turn := 0.0
		if Input.is_action_pressed("look_left"):
			turn -= 1.0
		if Input.is_action_pressed("look_right"):
			turn += 1.0
		if turn != 0.0:
			_cam.look(Vector2(turn * 420.0 * delta, 0.0))
		compass.cam_yaw = _cam.yaw
	if _player:
		touch.aiming = _player.aim_mode != 0
		touch.aim_status = _player.aim_status
		touch.dash_cd = maxf(_player._dash_lock_t, 0.0)
		touch.hook_cd = maxf(_player._hook_cd, 0.0)
	compass.has_target = _has_compass_target and _player != null
	if compass.has_target:
		var d := _compass_target - _player.global_position
		compass.target_bearing = atan2(d.x, -d.z)


func _refresh() -> void:
	stats.text = "命中 %d　連段 %d（最高 %d）　擊破 %d" % [hits, combo, best_combo, kills]


func _pop(c: Control, s: float, center: bool = true) -> void:
	c.pivot_offset = Vector2(c.size.x / 2.0 if center else 0.0, c.size.y / 2.0)
	c.scale = Vector2.ONE * s
	var tw := c.create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(c, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
