class_name PageBox
extends PanelContainer

signal moved
signal delete_requested(page_id: int)
signal link_drag_started(from_page_id: int, start_global_pos: Vector2)

var page_id: int = -1
var _is_dragging_box: bool = false
var _drag_local_offset: Vector2 = Vector2.ZERO

@onready var id_label: Label = $MarginContainer/HBoxContainer/VBoxContainer/HeaderRow/IdLabel
@onready var delete_button: Button = $MarginContainer/HBoxContainer/VBoxContainer/HeaderRow/DeleteButton
@onready var title_edit: LineEdit = $MarginContainer/HBoxContainer/VBoxContainer/TitleEdit
@onready var link_port: Panel = $MarginContainer/HBoxContainer/LinkPort
@onready var page_rank_bar: ProgressBar = $PageRankBar
@onready var page_rank_label: Label = $MarginContainer/HBoxContainer/VBoxContainer/HeaderRow/PageRankLabel
@onready var ordinal_rank_label: Label = $MarginContainer/HBoxContainer/VBoxContainer/HeaderRow/OrdinalRankLabel

func _ready() -> void:
	_apply_styles()
	link_port.gui_input.connect(_on_link_port_gui_input)
	delete_button.pressed.connect(func() -> void: delete_requested.emit(page_id))

	# PageRank scores range from 0.0 to 1.0 (default ProgressBar max is 100)
	page_rank_bar.min_value = 0.0
	page_rank_bar.max_value = 1.0
	page_rank_bar.step = 0.001


func setup(id: int, default_title: String) -> void:
	page_id = id
	id_label.text = "Page #%d" % id
	title_edit.text = default_title
	set_page_rank(0.0, 0)


func set_page_rank(rank: float, placement: int = 0) -> void:
	page_rank_bar.value = rank
	page_rank_label.text = "%.3f" % rank
	ordinal_rank_label.text = _format_ordinal(placement)


func _format_ordinal(n: int) -> String:
	if n <= 0:
		return "-"

	# Special case for 11th, 12th, 13th
	var last_two := n % 100
	if last_two >= 11 and last_two <= 13:
		return "%dth" % n

	match n % 10:
		1:
			return "%dst" % n
		2:
			return "%dnd" % n
		3:
			return "%drd" % n
		_:
			return "%dth" % n

func get_page_title() -> String:
	return title_edit.text.strip_edges()


func get_port_global_center() -> Vector2:
	return link_port.get_global_rect().get_center()


# Scale-independent dragging of the box body
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_is_dragging_box = true
			_drag_local_offset = get_local_mouse_position()
			move_to_front()
			accept_event()
		else:
			_is_dragging_box = false

	elif event is InputEventMouseMotion and _is_dragging_box:
		position += get_local_mouse_position() - _drag_local_offset
		moved.emit()
		accept_event()


func _on_link_port_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		link_drag_started.emit(page_id, get_port_global_center())
		link_port.accept_event()


func _apply_styles() -> void:
	var box_style := StyleBoxFlat.new()
	box_style.bg_color = Color("#2b2d38")
	box_style.border_color = Color("#4c5166")
	box_style.set_border_width_all(2)
	box_style.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", box_style)

	var port_style := StyleBoxFlat.new()
	port_style.bg_color = Color("#4ea8de")
	port_style.set_corner_radius_all(9)
	link_port.add_theme_stylebox_override("panel", port_style)

	delete_button.add_theme_color_override("font_color", Color("#8d99ae"))
	delete_button.add_theme_color_override("font_hover_color", Color("#f94144"))
