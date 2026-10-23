extends CanvasLayer
## HUD：命中 / 連段 / 擊破統計、HP 條、目標文字、大字宣告、受擊閃光、手感面板、
## 以及暫停式覆蓋層（敗北 / 結算）。道場與關卡共用。

@onready var stats: Label = $Stats
@onready var hp_bar: ProgressBar = $HpBar
@onready var objective: Label = $Objective
@onready var announce: Label = $Announce
@onready var flash: ColorRect = $Flash
@onready var fps: Label = $Fps
@onready var gear: Button = $GearBtn
@onready var panel: Control = $TuningPanel
@onready var touch: Control = $TouchControls

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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	touch.process_mode = Node.PROCESS_MODE_PAUSABLE
	Feel.flash_requested.connect(_on_flash)
	gear.pressed.connect(toggle_panel)
	panel.visible = false
	var blockers: Array[Control] = [panel, gear]
	touch.blockers = blockers
	_refresh()


## 把觸控與玩家接起來（道場、關卡共用）
func attach(player: Node, cam_rig: Node) -> void:
	player.touch = touch
	touch.attack_pressed.connect(player.request_attack)
	touch.dash_pressed.connect(player.request_dash)
	touch.block_changed.connect(player.set_block)
	cam_rig.set_target(player)
	player.hit_landed.connect(func(info: Dictionary) -> void:
		add_hit(bool(info.heavy)))
	player.hp_changed.connect(set_hp)
	player.parried.connect(func() -> void:
		say("彈反！", Color(1.0, 0.92, 0.5)))


func toggle_panel() -> void:
	panel.visible = not panel.visible
	gear.visible = not panel.visible


func _process_panel_state() -> void:
	gear.visible = not panel.visible and _overlay == null


func add_hit(heavy: bool) -> void:
	hits += 1
	combo += 1
	best_combo = maxi(best_combo, combo)
	_combo_t = 1.8
	_refresh()
	if heavy:
		_pop(stats, 1.25)


func add_kill(text: String = "擊破！", color: Color = Color(1.0, 0.85, 0.4)) -> void:
	kills += 1
	_refresh()
	say(text, color)


func set_hp(v: int) -> void:
	hp_bar.value = v


func set_objective(text: String) -> void:
	objective.text = text
	_pop(objective, 1.15)


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
	fps.text = "%d fps　最長一幀 %d ms" % [Engine.get_frames_per_second(), _worst_shown]
	_process_panel_state()


func _refresh() -> void:
	stats.text = "命中 %d　連段 %d（最高 %d）　擊破 %d" % [hits, combo, best_combo, kills]


func _pop(c: Control, s: float) -> void:
	c.pivot_offset = Vector2(c.size.x / 2.0, c.size.y / 2.0)
	c.scale = Vector2.ONE * s
	var tw := c.create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(c, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
