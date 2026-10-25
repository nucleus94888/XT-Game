extends Node3D
## 水遁（第十二次議會，第二關湖畔屋敷）：一片深水區。
## 玩家走進去自動潛下：身體隱藏、頭上一圈波紋、8 秒氣息條；敵人看不到你；水裡不能攻擊、移動變慢。
## 氣用完被迫浮上來 3 秒（這 3 秒誰都看得到你）。離開水面氣慢慢回滿。

var size := Vector3(8.0, 1.0, 5.0)


func _ready() -> void:
	add_to_group("water")


func contains(p: Vector3) -> bool:
	var d := p - global_position
	return absf(d.x) < size.x / 2.0 and absf(d.z) < size.z / 2.0 and d.y > -1.5 and d.y < 1.2
