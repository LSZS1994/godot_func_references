# reference_counter.gd
@tool
extends RefCounted

signal references_updated(references_data)

var editor_interface: EditorInterface
var _references_data = {}# 改为成员变量持久保存

# 添加常量定义存储路径
const SAVE_PATH = "res://addons/reference_counter/reference_data.json"


func _init(p_editor_interface: EditorInterface):
	editor_interface = p_editor_interface
	_load_data()


# 保存数据到文件
func _save_data():
	var dir = DirAccess.open("res://addons/reference_counter")
	if not dir:
		push_error("无法访问res://addons/reference_counter/目录")
		return

	# 创建/覆盖JSON文件（不是文件夹！）
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		var data = {
			"version": 1,
			"data": _references_data,
			"timestamp": Time.get_datetime_string_from_system()
		}
		file.store_string(JSON.stringify(data, "\t")) # 带格式化的JSON
		print("引用数据已保存到文件:", SAVE_PATH)
	else:
		push_error("文件创建失败，错误码:", FileAccess.get_open_error())


# 从文件加载数据
func _load_data():
	if FileAccess.file_exists(SAVE_PATH):
		var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
		if file:
			var parsed = JSON.parse_string(file.get_as_text())
			if parsed and parsed.has("data"):
				_references_data = parsed["data"]
				print("已加载引用数据，共", _references_data.size(), "个方法")
			else:
				push_error("引用数据文件格式错误")
	else:
		print("未找到现有引用数据文件，将创建新文件")


# 获取持久化数据（供外部访问）
func get_persisted_data() -> Dictionary:
	return _references_data.duplicate(true)


func scan_project():
	var scripts = _find_all_scripts()
	_references_data = _build_reference_map(scripts)
	_update_script_comments(scripts, _references_data)
	_save_data() # 扫描完成后自动保存
	references_updated.emit(_references_data)
	#print("_references_data:" + str(_references_data.size()))
	editor_interface.get_resource_filesystem().scan()


func _find_all_scripts() -> Array[String]:
	var scripts: Array[String] = []
	#var dir_access = DirAccess.open("res://Scene/test/")
	#_scan_dir("res://Scene/test/", dir_access, scripts)
	var dir_access = DirAccess.open("res://")
	_scan_dir("res://", dir_access, scripts)
	return scripts


func _scan_dir(path: String, dir_access: DirAccess, scripts: Array[String]):
	if dir_access == null:
		return

	# 跳过addons文件夹
	if "addons" in path.split("/"):
		return

	dir_access.list_dir_begin()
	var file_name = dir_access.get_next()

	while file_name != "":
		var full_path = path.path_join(file_name)

		if dir_access.current_is_dir():
			if file_name != "." and file_name != "..":
				var sub_dir = DirAccess.open(full_path)
				_scan_dir(full_path, sub_dir, scripts)
		else:
			if file_name.ends_with(".gd"):
				scripts.append(full_path)

		file_name = dir_access.get_next()

	dir_access.list_dir_end()


func _build_reference_map(scripts: Array[String]) -> Dictionary:
	var references = {}
	var current_method_stack = [] # 用栈处理嵌套调用（虽然GDScript不支持方法嵌套）

	# 第一遍：记录所有方法定义
	for script_path in scripts:
		var content = _read_file_content(script_path)
		if content.is_empty():
			continue

		var methods = _extract_methods(content)
		for method in methods:
			references[method] = {
				"count": 0,
				"file": script_path,
				"references": [],
				"caller_method": "GLOBAL" # 新增调用者方法名
			}

	# 第二遍：统计引用并记录位置
	for script_path in scripts:
		var content = _read_file_content(script_path)
		if content.is_empty():
			continue

		var lines = content.split("\n")
		var current_method = "GLOBAL" # 默认全局上下文

		for line_num in lines.size():
			var line = lines[line_num]
			var stripped_line = line.strip_edges()


			# 检测方法定义
			if stripped_line.begins_with("func "):
				current_method = _extract_method_name(stripped_line)
				current_method_stack.push_back(current_method)
				continue

			# 检测方法结束（简化版）
			if stripped_line == "end" or stripped_line == "pass":
				if not current_method_stack.is_empty():
					current_method_stack.pop_back()
					current_method = current_method_stack[ - 1] if current_method_stack else "GLOBAL"

			for method in references:


				# 查找方法调用（排除定义本身）
				if line.strip_edges().begins_with("func %s(" % method):
					continue

				# 查找方法调用
				var call_pattern = "(^|[^a-zA-Z0-9_])%s\\(" % method
				var regex = RegEx.new()
				if regex.compile(call_pattern) == OK:
					var results = regex.search_all(line)
					for result in results:
						references[method]["count"] += 1
						references[method]["references"].append({
							"file": script_path,
							"line": line_num + 1, # 转换为1-based行号
							"line_text": line.strip_edges(),
							"caller_method": current_method # 新增调用者方法名
						})

				# 情况2：信号连接
				if "signal " in line and method in line:
					references[method]["count"] += 1
					references[method]["references"].append({
						"file": script_path,
						"line": line_num + 1,
						"line_text": line.strip_edges(),
						"caller_method": current_method # 新增调用者方法名
					})

				# 情况3：super调用
				if "super.%s(" % method in line:
					references[method]["count"] += 1
					references[method]["references"].append({
						"file": script_path,
						"line": line_num + 1,
						"line_text": line.strip_edges(),
						"caller_method": current_method # 新增调用者方法名
					})

	return references


func _extract_methods(content: String) -> Array[String]:
	var methods: Array[String] = []
	var lines = content.split("\n")
	var pattern = "^\\s*func\\s+([a-zA-Z0-9_]+)\\("
	var regex = RegEx.new()

	if regex.compile(pattern) != OK:
		push_error("Failed to compile regex pattern")
		return methods

	for line in lines:
		var result = regex.search(line.strip_edges())
		if result:
			var method_name = result.get_string(1)
			methods.append(method_name)

	return methods


func _update_script_comments(scripts: Array[String], references: Dictionary):
	for script_path in scripts:
		var content = _read_file_content(script_path)
		if content.is_empty():
			continue

		var new_lines: PackedStringArray = []
		var lines = content.split("\n")
		var i = 0
		var line_offset = 0 # 新增：跟踪行号偏移量

		while i < lines.size():
			var line = lines[i]
			var stripped_line = line.strip_edges()
			# 跳过所有旧格式的引用注释
			if stripped_line.begins_with("# References:") or stripped_line.begins_with("# [ref:"):
				i += 1
				line_offset -= 1 # 移除的行需要偏移
				continue


			# 检查是否是方法定义行
			if line.strip_edges().begins_with("func "):
				var method_name = _extract_method_name(line.strip_edges())
				if references.has(method_name):
					var ref_data = references[method_name]
					# 添加引用注释
					var comment = "# [ref:%s]References: %d (click to view)" % [
						method_name,
						ref_data["count"]
					]
					new_lines.append(comment)
					line_offset += 1 # 新增的行需要偏移

					# 修正该方法的引用行号
					for ref in references[method_name]["references"]:
						if ref["file"] == script_path and ref["line"] > i:
							ref["line"] += line_offset
						# 如果调用者方法也在同一文件中，修正其行号
						if ref["caller_method"] in references and ref["caller_method"] != "GLOBAL":
							for caller_ref in references[ref["caller_method"]]["references"]:
								if caller_ref["file"] == script_path and caller_ref["line"] > i:
									caller_ref["line"] += line_offset

			# 保留原始行（除非是旧的引用注释）
			if not line.strip_edges().begins_with("# [ref:"):
				new_lines.append(line)
			#new_lines.append(line)#清除的时候用，注释上面
			i += 1

		_write_file_content(script_path, "\n".join(new_lines))


func _extract_method_name(func_line: String) -> String:


	var start = func_line.find("func ") + 5
	var end = func_line.find("(", start)
	return func_line.substr(start, end - start).strip_edges()


func _read_file_content(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open file: %s" % path)
		return ""
	var content = file.get_as_text()
	file.close()
	return content


func _write_file_content(path: String, content: String):
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to write file: %s" % path)
		return
	file.store_string(content)
	file.close()
