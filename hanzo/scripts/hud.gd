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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	touch.process_mode = Node.PROCESS_MODE_PAUSABLE
	Feel.flash_requested.connect(_on_flash)
	_setup_latency_probe()
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
	player.cam_rig = cam_rig
	touch.look_delta.connect(cam_rig.look)
	player.posture_changed.connect(set_posture)
	player.posture_broken.connect(func() -> void:
		say("體幹崩壞", Color(1.0, 0.55, 0.2))
		flash_posture())
	touch.attack_down.connect(player.on_attack_down)
	touch.attack_up.connect(player.on_attack_up)
	touch.hook_down.connect(player.on_hook_down)
	touch.hook_up.connect(player.on_hook_up)
	touch.weapon_toggle.connect(player.toggle_weapon)
	player.weapon_changed.connect(func(m: int) -> void:
		touch.weapon_label = "劍" if m == 1 else "刀")
	touch.dash_pressed.connect(player.request_dash)
	touch.block_changed.connect(player.set_block)
	player.shuriken_changed.connect(func(n: int) -> void:
		touch.shuriken_count = n)
	touch.shuriken_count = player.shuriken
	cam_rig.set_target(player)
	player.hit_landed.connect(func(info: Dictionary) -> void:
		add_hit(bool(info.heavy)))
	player.hp_changed.connect(set_hp)
	player.parried.connect(func() -> void:
		say("彈反！", Color(1.0, 0.92, 0.5)))


func toggle_panel() -> void:
	panel.visible = not panel.visible
	gear.visible = _debug and not panel.visible


func _process_panel_state() -> void:
	gear.visible = _debug and not panel.visible and _overlay == null
	pause_btn.visible = _overlay == null


## 連點羅盤三下：顯示／隱藏除錯資訊（統計、fps、手感鈕）
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
	vb.custom_minimum_size = Vector2(520, 0)
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
	hp_bar.value = v


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
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 16)
	vb.add_child(hb)
	for b in buttons:
		var btn := Button.new()
		btn.text = str(b[0])
		btn.custom_minimum_size = Vector2(220, 64)
		btn.add_theme_font_size_override("font_size", 26)
		var cb: Callable = b[1]
		btn.pressed.connect(func() -> void:
			hide_overlay()
			cb.call())
		hb.add_child(btn)
	add_child(_overlay)
	touch.blockers.append(_overlay)
	get_tree().paused = true


func hide_overlay() -> void:
	if _overlay:
		touch.blockers.erase(_overlay)
		_overlay.queue_free()
		_overlay = null
	get_tree().paused = false


func _on_flash(color: Color, dur: float) -> void:
	flash.color = color
	if _flash_tw:
		_flash_tw.kill()
	_flash_tw = flash.create_tween()
	_flash_tw.tween_property(flash, "color:a", 0.0, dur)


func _process(delta: float) -> void:
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
	fps.text = "%d fps　最長一幀 %d ms%s" % [Engine.get_frames_per_second(), _worst_shown, _latency_text()]
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
