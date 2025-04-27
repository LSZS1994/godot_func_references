# reference_counter_plugin.gd
@tool
extends EditorPlugin

const ReferenceCounter = preload("reference_counter.gd")
const ReferencePopup = preload("reference_popup.gd")

var reference_counter: ReferenceCounter
var reference_popup: ReferencePopup
var script_editor: ScriptEditor
var text_edit: CodeEdit


func _enter_tree():
	reference_counter = ReferenceCounter.new(get_editor_interface())

	# 确保弹窗场景加载正确
	var popup_scene = preload("res://addons/reference_counter/reference_popup.tscn")
	reference_popup = popup_scene.instantiate()
	reference_popup.editor_interface = get_editor_interface()
	get_editor_interface().get_base_control().add_child(reference_popup)

	add_tool_menu_item("Count Method References", _count_references)
	script_editor = get_editor_interface().get_script_editor()
	script_editor.editor_script_changed.connect(_on_script_changed)
	#reference_popup.hide()
	if not reference_counter.references_updated.is_connected(_on_references_updated):
		reference_counter.references_updated.connect(_on_references_updated)

	#if reference_counter.references_updated.is_connected(_on_references_updated):
		#print("references_updated 连接成功")


func _on_references_updated(data):
	print("收到更新数据，方法数量:", data.size()) # 调试输出
	if reference_popup:
		reference_popup.update_references_data(data)
	else:
		push_error("reference_popup 未初始化")


func _exit_tree():
	remove_tool_menu_item("Count Method References")
	if reference_counter:
		reference_counter.references_updated.disconnect(reference_popup.update_references_data)
	reference_counter = null
	reference_popup = null


func _count_references():
	# 扫描前先尝试加载已有数据
	reference_counter._load_data()
	reference_counter.scan_project()
	# 调试：打印保存位置
	print("引用数据保存在:", reference_counter.SAVE_PATH)


func get_reference_data() -> Dictionary:
	return reference_counter.get_persisted_data()


func _on_script_changed(script: Script):
	if script_editor.get_current_editor():
		var current_editor = script_editor.get_current_editor()
		if current_editor.has_method("get_base_editor"):
			text_edit = current_editor.get_base_editor()
			if text_edit is CodeEdit:
				if !text_edit.gutter_clicked.is_connected(_on_gutter_clicked):
					text_edit.gutter_clicked.connect(_on_gutter_clicked)


func _on_gutter_clicked(line: int, gutter: int):
	#print("Gutter clicked at line:", line) # 调试输出
#
	#if !text_edit or line < 0 or line >= text_edit.get_line_count():
		#push_error("Invalid line number")
		#return

	var line_text = text_edit.get_line(line)
	#print("Line text:", line_text) # 调试输出

	if line_text.begins_with("# [ref:"):
		var method_start = line_text.find("[ref:") + 5
		var method_end = line_text.find("]", method_start)
		if method_end != -1:
			var method_name = line_text.substr(method_start, method_end - method_start)
			print("Found method reference:", method_name) # 调试输出
			if reference_popup:
				reference_popup.show_references(method_name)
			else:
				push_error("Reference popup is null")
		else:
			push_error("Invalid reference format")


func _make_visible(visible: bool):
	if reference_popup:
		reference_popup.visible = visible


func _has_main_screen():
	return false
