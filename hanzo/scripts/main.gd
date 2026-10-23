extends Node3D
## 場景總管：接線（觸控→玩家、玩家→HUD、稻草人→HUD），擺四根柱子當空間參考。
##
## 自動試玩 / 截圖（給 AI 或 CI 用）：
##   godot --path hanzo ++ --shot=../build/shots            只截一張閒置畫面後離開
##   godot --path hanzo ++ --shot=../build/shots --autoplay 走向稻草人、三段斬、閃步，
##                                                          在重擊命中瞬間與其後各截一張
##   加 --mobile 模擬手機介面倍率；加 --panel 一開始就打開手感面板

@onready var player: CharacterBody3D = $Player
@onready var dummy: CharacterBody3D = $Dummy
@onready var cam_rig: Node3D = $CameraRig
@onready var hud: CanvasLayer = $HUD
@onready var touch: Control = $HUD/TouchControls

var _shot_dir := ""
var _auto := false
var _auto_t := 0.0
var _auto_done := {}


func _ready() -> void:
	$Sun.rotation_degrees = Vector3(-58.0, 32.0, 0.0)
	player.touch = touch
	touch.attack_pressed.connect(player.request_attack)
	touch.dash_pressed.connect(player.request_dash)
	cam_rig.set_target(player)
	player.hit_landed.connect(_on_hit_landed)
	player.hp_changed.connect(hud.set_hp)
	player.died.connect(func() -> void:
		hud.say("敗北…", Color(0.9, 0.3, 0.3)))
	dummy.destroyed.connect(hud.add_kill)
	_place_pillars()
	hud.say("斬", Color(1, 1, 1))
	_parse_args()


func _on_hit_landed(info: Dictionary) -> void:
	hud.add_hit(bool(info.heavy))
	if _auto and info.heavy and not _auto_done.has("hit"):
		_auto_done["hit"] = true
		_shot("hit")
		get_tree().create_timer(0.45, true, false, true).timeout.connect(func() -> void:
			_shot("after"))


func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("toggle_panel"):
		hud.toggle_panel()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot_dir = a.substr(7)
		elif a == "--autoplay":
			_auto = true
		elif a == "--panel":
			hud.panel.visible = true
	if _shot_dir != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
		if not _auto:
			get_tree().create_timer(1.0).timeout.connect(func() -> void:
				await _shot("idle")
				get_tree().quit())


func _process(delta: float) -> void:
	if not _auto:
		return
	_auto_t += delta
	if _auto_t < 0.3:
		pass
	elif _auto_t < 0.5 and not _auto_done.has("idle"):
		_auto_done["idle"] = true
		_shot("idle")
	elif _auto_t < 1.3:
		touch.move_vector = Vector2(0.0, -1.0)
	elif _auto_t < 1.35:
		touch.move_vector = Vector2.ZERO
		_once("a1", player.request_attack)
	elif _auto_t < 1.7:
		_once("a2", player.request_attack)
	elif _auto_t < 2.1:
		_once("a3", player.request_attack)
	elif _auto_t < 3.2:
		pass
	elif _auto_t < 3.25:
		_once("d", player.request_dash)
	elif _auto_t > 4.5:
		get_tree().quit()


func _once(key: String, cb: Callable) -> void:
	if not _auto_done.has(key):
		_auto_done[key] = true
		cb.call()


func _shot(name: String) -> void:
	if _shot_dir == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s.png" % [_shot_dir, name])
	img.save_png(path)
	print("shot: ", path)


func _place_pillars() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.6, 3.2, 0.6)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.17, 0.15)
	for pos in [Vector3(-9, 1.6, -9), Vector3(9, 1.6, -9), Vector3(-9, 1.6, 9), Vector3(9, 1.6, 9)]:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = mesh.size
		cs.shape = sh
		sb.add_child(mi)
		sb.add_child(cs)
		add_child(sb)
		sb.global_position = pos
