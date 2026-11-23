class_name DiagramEditor
extends Control

const PAGE_BOX_SCENE := preload("res://page_box.tscn")
const MIN_ZOOM := 0.25
const MAX_ZOOM := 2.5
const ZOOM_STEP := 1.12

# Graph data structures (directed multigraph)
var pages: Dictionary = {} # { page_id (int): PageBox }
var edges: Array[Dictionary] = [] # [ { "from": int, "to": int }, ... ]

var _next_page_id: int = 1
var _zoom: float = 1.0
var _is_panning: bool = false
var _pan_button: MouseButton = MOUSE_BUTTON_NONE

var is_dragging_link: bool = false
var drag_from_id: int = -1
var drag_current_global_pos: Vector2 = Vector2.ZERO

@onready var background: ColorRect = $Background
@onready var graph_canvas: Control = $GraphCanvas
@onready var nodes_container: Control = $GraphCanvas/NodesContainer
@onready var edges_layer: EdgesLayer = $GraphCanvas/EdgesLayer
@onready var top_bar: HBoxContainer = $TopBar
@onready var add_page_button: Button = $TopBar/AddPageButton
@onready var zoom_out_button: Button = $TopBar/ZoomOutButton
@onready var zoom_label: Label = $TopBar/ZoomLabel
@onready var zoom_in_button: Button = $TopBar/ZoomInButton
@onready var reset_view_button: Button = $TopBar/ResetViewButton
@onready var iterations_spin_box: SpinBox = $TopBar/IterationsSpinBox
@onready var damping_spin_box: SpinBox = $TopBar/DampingSpinBox

func _ready() -> void:
	# Ensure layout/container nodes never intercept mouse clicks meant for PageBoxes or empty canvas
	mouse_filter = Control.MOUSE_FILTER_STOP
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	graph_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nodes_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edges_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE

	edges_layer.editor = self
	add_page_button.pressed.connect(_on_add_page_pressed)
	zoom_out_button.pressed.connect(func() -> void: _set_zoom(_zoom / ZOOM_STEP, size * 0.5))
	zoom_in_button.pressed.connect(func() -> void: _set_zoom(_zoom * ZOOM_STEP, size * 0.5))
	reset_view_button.pressed.connect(_reset_view)
	resized.connect(_update_edges_layer_bounds)
	iterations_spin_box.value_changed.connect(_on_rank_param_changed)
	damping_spin_box.value_changed.connect(_on_rank_param_changed)
	_update_edges_layer_bounds()


func get_zoom() -> float:
	return _zoom


func is_panning() -> bool:
	return _is_panning


func _update_edges_layer_bounds() -> void:
	if edges_layer == null or graph_canvas == null:
		return
	edges_layer.position = -graph_canvas.position / _zoom
	edges_layer.size = size / _zoom
	edges_layer.queue_redraw()


func _on_add_page_pressed() -> void:
	var box: PageBox = PAGE_BOX_SCENE.instantiate()
	nodes_container.add_child(box)

	var id := _next_page_id
	_next_page_id += 1

	var default_slug := "/home" if id == 1 else "/page-%d" % id
	box.setup(id, default_slug)

	var offset := ((id - 1) % 8) * 28.0
	var visible_origin := (-graph_canvas.position) / _zoom
	box.position = visible_origin + Vector2(120.0 + offset, 100.0 + offset)

	box.moved.connect(edges_layer.queue_redraw)
	box.delete_requested.connect(delete_page)
	box.link_drag_started.connect(_on_link_drag_started)

	pages[id] = box
	edges_layer.queue_redraw()
	calculate_page_rank()


func delete_page(page_id: int) -> void:
	if not pages.has(page_id):
		return

	for i in range(edges.size() - 1, -1, -1):
		if edges[i]["from"] == page_id or edges[i]["to"] == page_id:
			edges.remove_at(i)

	if is_dragging_link and drag_from_id == page_id:
		is_dragging_link = false
		drag_from_id = -1

	var box: PageBox = pages[page_id]
	pages.erase(page_id)
	box.queue_free()
	edges_layer.queue_redraw()
	calculate_page_rank()


func remove_edge_at(edge_index: int) -> void:
	if edge_index >= 0 and edge_index < edges.size():
		edges.remove_at(edge_index)
		edges_layer.queue_redraw()
		calculate_page_rank()


func _on_link_drag_started(from_page_id: int, start_global_pos: Vector2) -> void:
	is_dragging_link = true
	drag_from_id = from_page_id
	drag_current_global_pos = start_global_pos
	edges_layer.queue_redraw()


# Receives clicks on empty canvas (clicks on buttons, PageBoxes, and LinkPorts are consumed before reaching here)
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if edges_layer.try_delete_hovered_edge():
				accept_event()
				return
			_start_panning(MOUSE_BUTTON_LEFT)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT:
			_start_panning(event.button_index)
			accept_event()


func _start_panning(button: MouseButton) -> void:
	_is_panning = true
	_pan_button = button
	mouse_default_cursor_shape = Control.CURSOR_DRAG


func _stop_panning() -> void:
	_is_panning = false
	_pan_button = MOUSE_BUTTON_NONE
	mouse_default_cursor_shape = Control.CURSOR_ARROW


func _input(event: InputEvent) -> void:
	# 1. Zooming with mouse wheel around the cursor
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(_zoom * ZOOM_STEP, get_local_mouse_position())
			get_viewport().set_input_as_handled()
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(_zoom / ZOOM_STEP, get_local_mouse_position())
			get_viewport().set_input_as_handled()
			return

	# 2. Active canvas panning
	if _is_panning:
		if event is InputEventMouseMotion:
			graph_canvas.position += event.relative
			_update_edges_layer_bounds()
			get_viewport().set_input_as_handled()
			return
		elif event is InputEventMouseButton and event.button_index == _pan_button and not event.pressed:
			_stop_panning()
			get_viewport().set_input_as_handled()
			return

	# 3. Active link creation drag
	if not is_dragging_link:
		return

	if event is InputEventMouseMotion:
		drag_current_global_pos = event.global_position
		edges_layer.queue_redraw()

	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_finish_link_drag(event.global_position)


func _set_zoom(target_zoom: float, anchor_local_pos: Vector2) -> void:
	var new_zoom := clampf(target_zoom, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(new_zoom, _zoom):
		return

	var canvas_point := (anchor_local_pos - graph_canvas.position) / _zoom
	_zoom = new_zoom
	graph_canvas.scale = Vector2.ONE * _zoom
	graph_canvas.position = anchor_local_pos - canvas_point * _zoom

	zoom_label.text = "%d%%" % roundi(_zoom * 100.0)
	_update_edges_layer_bounds()


func _reset_view() -> void:
	_zoom = 1.0
	graph_canvas.scale = Vector2.ONE
	graph_canvas.position = Vector2.ZERO
	zoom_label.text = "100%"
	_update_edges_layer_bounds()


func _finish_link_drag(drop_global_pos: Vector2) -> void:
	var target_id := get_page_id_at_position(drop_global_pos)

	if target_id != -1 and target_id != drag_from_id:
		edges.append({
			"from": drag_from_id,
			"to": target_id
		})

	is_dragging_link = false
	drag_from_id = -1
	edges_layer.queue_redraw()
	calculate_page_rank()


func get_page_id_at_position(global_pos: Vector2) -> int:
	var children := nodes_container.get_children()
	for i in range(children.size() - 1, -1, -1):
		var box := children[i] as PageBox
		if box and box.get_global_rect().has_point(global_pos):
			return box.page_id
	return -1


func is_point_over_ui(global_pos: Vector2) -> bool:
	return top_bar.get_global_rect().has_point(global_pos)


# --- Multigraph Helper Methods (Ready for your PageRank implementation) ---

func has_edge(from_id: int, to_id: int) -> bool:
	return get_edge_count(from_id, to_id) > 0


func get_edge_count(from_id: int, to_id: int) -> int:
	var count := 0
	for edge in edges:
		if edge["from"] == from_id and edge["to"] == to_id:
			count += 1
	return count


func get_outgoing_links(page_id: int) -> Array[int]:
	var outgoing: Array[int] = []
	for edge in edges:
		if edge["from"] == page_id:
			outgoing.append(edge["to"])
	return outgoing


func get_incoming_links(page_id: int) -> Array[int]:
	var incoming: Array[int] = []
	for edge in edges:
		if edge["to"] == page_id:
			incoming.append(edge["from"])
	return incoming


func get_adjacency_list() -> Dictionary:
	var graph: Dictionary = {}
	for id in pages.keys():
		graph[id] = get_outgoing_links(id)
	return graph

func _on_rank_param_changed(_value: float) -> void:
	calculate_page_rank()


func calculate_page_rank() -> void:
	var page_ids := pages.keys()
	if page_ids.is_empty():
		return

	# Store your final computed scores here as { page_id (int): rank (float) }
	var ranks: Dictionary = {}
	var iterations := int(iterations_spin_box.value)
	for id in page_ids:
		ranks[id] = 1.0 / page_ids.size()
	
	var d := damping_spin_box.value
	
	# ---------------------------------------------------------
	# TODO: Implement your PageRank algorithm here.
	#
	# Available graph data:
	# - `iterations`               -> int from IterationsSpinBox
	# - `page_ids`                 -> Array of all active page IDs
	# - `get_outgoing_links(id)`   -> Array[int] of target page IDs
	# - `get_incoming_links(id)`   -> Array[int] of source page IDs
	# - `get_edge_count(from, to)` -> int count of direct links
	# ---------------------------------------------------------
	for step in range(iterations):
		var next_ranks: Dictionary = {}
		var baseline = (1.0-d) / page_ids.size()
		var dangling_sum := 0.0
		for p in page_ids:
			if get_outgoing_links(p).is_empty():
				dangling_sum += ranks[p]
		var dangling_bonus = d * (dangling_sum / page_ids.size())
		for A in page_ids:
			next_ranks[A] = baseline + dangling_bonus
			for T in get_incoming_links(A):
				next_ranks[A] += d * (ranks[T] / get_outgoing_links(T).size())
		ranks = next_ranks

	# Sort page IDs from highest PageRank to lowest
	var sorted_ids := page_ids.duplicate()
	sorted_ids.sort_custom(func(a: int, b: int) -> bool: return ranks[a] > ranks[b])

	# Assign placements (handles ties cleanly, e.g., tied pages share "1st")
	var current_placement := 1
	for i in range(sorted_ids.size()):
		var id: int = sorted_ids[i]
		if i > 0 and not is_equal_approx(ranks[id], ranks[sorted_ids[i - 1]]):
			current_placement = i + 1

		var box: PageBox = pages[id]
		box.set_page_rank(ranks[id], current_placement)
