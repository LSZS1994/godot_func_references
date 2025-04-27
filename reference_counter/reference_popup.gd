# reference_popup.gd
@tool
extends Window

@export var item_scene: PackedScene

var editor_interface: EditorInterface
var references_data: Dictionary = {}
var current_method: String = ""
# 添加与 reference_counter.gd 相同的保存路径常量
const SAVE_PATH = "res://addons/reference_counter/reference_data.json"

@onready var method_label: Label = $VBoxContainer/MethodLabel
@onready var references_list: VBoxContainer = $VBoxContainer/ScrollContainer/ReferencesList
@onready var search_edit: LineEdit = $VBoxContainer/SearchEdit


func _init():
	size = Vector2(500, 400)
	title = "Method References"
	


# 新增方法：从文件加载数据
func _load_data():
	if FileAccess.file_exists(SAVE_PATH):
		var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
		if file:
			var parsed = JSON.parse_string(file.get_as_text())
			if parsed and parsed.has("data"):
				references_data = parsed["data"]
				print("弹窗加载引用数据成功，共", references_data.size(), "个方法")
			else:
				push_error("引用数据文件格式错误")
	else:
		print("未找到引用数据文件，等待扫描结果")


func _ready():
	size = Vector2(800, 400)
	title = "Method References"
	close_requested.connect(hide)

	# 确保子节点正确获取
	method_label = $VBoxContainer/MethodLabel
	references_list = $VBoxContainer/ScrollContainer/ReferencesList
	search_edit = $VBoxContainer/SearchEdit
	
	search_edit.text_changed.connect(_on_search_changed)
	item_scene = preload("res://addons/reference_counter/reference_item.tscn")


func update_references_data(new_data: Dictionary):
	references_data = new_data
	#print("弹窗接收数据，总方法数:", references_data.size()) # 调试

	# 验证特定方法
	if references_data.has("test"):
		var test_data = references_data["test"]
		#print("test方法详情 - 引用数:", test_data["count"], "引用位置:", test_data["references"])


func show_references(method_name: String):
	#print("请求显示方法引用：", method_name)
	#print("当前引用数据：", references_data.get(method_name, "无数据"))
	current_method = method_name
	if references_data.has(method_name):
		var data = references_data[method_name]
		method_label.text = "References to: %s() (defined in %s)" % [
			method_name,
			data["file"].get_file()
		]

		_update_references_list(data["references"])
	else:
		#push_error("方法 '%s' 不存在于引用数据中" % method_name)
		# 可以尝试重新加载
		_load_data()
		if references_data.has(method_name):
			show_references(method_name) # 重试	
	popup_centered()
	self.popup()


func _update_references_list(references: Array, filter: String = ""):
	# 清空现有列表
	for child in references_list.get_children():
		child.queue_free()

	# 添加引用项
	for ref in references:
		if filter.is_empty() or filter.to_lower() in ref["line_text"].to_lower():
			var item = item_scene.instantiate()
			item.set_reference(ref["file"], ref["line"], ref["line_text"], ref["caller_method"], current_method)
			item.reference_clicked.connect(_on_reference_clicked)
			references_list.add_child(item)


func _on_reference_clicked(file_path: String, line_number: int):
	# 打开文件并跳转到指定行
	var script = load(file_path)
	if script:
		editor_interface.edit_script(script)
		var editor = editor_interface.get_script_editor()
		var text_edit = editor.get_current_editor().get_base_editor()
		text_edit.set_caret_line(line_number - 1) # 转换为0-based行号
		text_edit.set_caret_column(0) # 将光标移动到行首
		text_edit.deselect() # 清除选中文本
		text_edit.center_viewport_to_caret()
	hide()


func _on_search_changed(new_text: String):
	if references_data.has(current_method):
		_update_references_list(references_data[current_method]["references"], new_text)
