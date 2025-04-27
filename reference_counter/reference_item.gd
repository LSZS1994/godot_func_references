# reference_item.gd
@tool
extends Button

signal reference_clicked(file_path: String, line_number: int)

var file_path: String
var line_number: int
var method_name: String # 新增：存储方法名


func _ready():
	add_theme_color_override("font_color", Color(0.8, 0.8, 1.0))
	add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	pressed.connect(_on_pressed)


func set_reference(p_file_path: String, p_line_number: int, p_line_text: String, p_caller_method: String, method_name: String):
	file_path = p_file_path
	line_number = p_line_number

	# 显示格式：被调方法名 <- 调用者方法名
	text = "%s <- %s | %s:%d" % [
		method_name, # 被调方法（从popup传入）
		p_caller_method if p_caller_method != "GLOBAL" else "全局",
		file_path.get_file(),
		line_number
	]

	# 悬停提示显示完整信息
	tooltip_text = "调用链：%s → %s\n文件：%s\n行号：%d\n代码：%s" % [
		p_caller_method,
		method_name,
		file_path,
		line_number,
		p_line_text
	]


func _on_pressed():
	emit_signal("reference_clicked", file_path, line_number)
