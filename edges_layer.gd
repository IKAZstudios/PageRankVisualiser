class_name EdgesLayer
extends Control

const ARROW_COLOR := Color("#72efdd")
const HOVER_COLOR := Color("#f94144")
const PREVIEW_COLOR := Color("#f9c74f")
const LINE_WIDTH := 2.5
const HOVER_LINE_WIDTH := 3.5
const ARROW_HEAD_SIZE := 12.0
const CURVE_SPACING := 36.0
const CURVE_SEGMENTS := 24
const HIT_RADIUS := 10.0

var editor: DiagramEditor
var _rendered_curves: Array[Dictionary] = [] # [{ "edge_index": int, "points": PackedVector2Array, "mid": Vector2 }]
var _hovered_edge_index: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _to_local(global_pos: Vector2) -> Vector2:
	return get_global_transform().affine_inverse() * global_pos


func _input(event: InputEvent) -> void:
	if editor == null:
		return

	if event is InputEventMouseMotion:
		_update_hovered_edge(event.global_position)


func try_delete_hovered_edge() -> bool:
	if _hovered_edge_index != -1 and editor != null and not editor.is_dragging_link:
		var removed_idx := _hovered_edge_index
		_hovered_edge_index = -1
		editor.remove_edge_at(removed_idx)
		return true
	return false


func _update_hovered_edge(global_mouse_pos: Vector2) -> void:
	var new_hover := -1

	if not editor.is_dragging_link \
			and not editor.is_panning() \
			and not editor.is_point_over_ui(global_mouse_pos) \
			and editor.get_page_id_at_position(global_mouse_pos) == -1:
		var local_mouse := _to_local(global_mouse_pos)
		var best_dist := HIT_RADIUS / editor.get_zoom()

		for curve in _rendered_curves:
			var pts: PackedVector2Array = curve["points"]
			for i in range(pts.size() - 1):
				var closest := Geometry2D.get_closest_point_to_segment(local_mouse, pts[i], pts[i + 1])
				var dist := local_mouse.distance_to(closest)
				if dist < best_dist:
					best_dist = dist
					new_hover = curve["edge_index"]

	if new_hover != _hovered_edge_index:
		_hovered_edge_index = new_hover
		queue_redraw()


func _draw() -> void:
	_rendered_curves.clear()
	if editor == null:
		return

	# 1. Group edges by unordered page pair, preserving each edge's index in editor.edges
	var edge_bundles: Dictionary = {} # { "minId_maxId": Array[Dictionary] }
	for idx in range(editor.edges.size()):
		var edge: Dictionary = editor.edges[idx]
		var from_id: int = edge["from"]
		var to_id: int = edge["to"]
		if not editor.pages.has(from_id) or not editor.pages.has(to_id):
			continue

		var key := "%d_%d" % [mini(from_id, to_id), maxi(from_id, to_id)]
		if not edge_bundles.has(key):
			edge_bundles[key] = []
		edge_bundles[key].append({ "edge": edge, "index": idx })

	# 2. Draw each bundle of edges
	for key in edge_bundles.keys():
		var bundle: Array = edge_bundles[key]
		var first_edge: Dictionary = bundle[0]["edge"]
		var id_a := mini(first_edge["from"], first_edge["to"])
		var id_b := maxi(first_edge["from"], first_edge["to"])

		var box_a: PageBox = editor.pages[id_a]
		var box_b: PageBox = editor.pages[id_b]

		var center_a := _to_local(box_a.get_global_rect().get_center())
		var center_b := _to_local(box_b.get_global_rect().get_center())
		var canonical_dir := (center_b - center_a).normalized()
		if canonical_dir == Vector2.ZERO:
			canonical_dir = Vector2.RIGHT
		var canonical_perp := Vector2(-canonical_dir.y, canonical_dir.x)

		var count := bundle.size()
		for i in range(count):
			var item: Dictionary = bundle[i]
			var edge: Dictionary = item["edge"]
			var edge_idx: int = item["index"]

			var from_box: PageBox = editor.pages[edge["from"]]
			var to_box: PageBox = editor.pages[edge["to"]]

			var start_pos := _to_local(from_box.get_port_global_center())
			var target_rect := Rect2(_to_local(to_box.global_position), to_box.size)
			var raw_end := target_rect.get_center()

			var offset_index := float(i) - (count - 1) * 0.5
			var bend := offset_index * CURVE_SPACING
			var control_point := (start_pos + raw_end) * 0.5 + canonical_perp * bend
			var end_pos := _get_rect_border_point(target_rect, control_point)

			var is_hovered := (edge_idx == _hovered_edge_index)
			var color := HOVER_COLOR if is_hovered else ARROW_COLOR
			var width := HOVER_LINE_WIDTH if is_hovered else LINE_WIDTH

			var pts := _draw_curved_arrow(start_pos, control_point, end_pos, color, width)
			if pts.size() > 0:
				var mid_pt := 0.25 * start_pos + 0.5 * control_point + 0.25 * end_pos
				_rendered_curves.append({
					"edge_index": edge_idx,
					"points": pts,
					"mid": mid_pt
				})
				if is_hovered:
					_draw_delete_badge(mid_pt)

	# 3. Draw active drag arrow while user is dragging from a port
	if editor.is_dragging_link and editor.pages.has(editor.drag_from_id):
		var source_box: PageBox = editor.pages[editor.drag_from_id]
		var start_pos := _to_local(source_box.get_port_global_center())
		var end_pos := _to_local(editor.drag_current_global_pos)
		var mid_point := (start_pos + end_pos) * 0.5
		_draw_curved_arrow(start_pos, mid_point, end_pos, PREVIEW_COLOR, LINE_WIDTH)


func _draw_curved_arrow(start: Vector2, control: Vector2, end: Vector2, color: Color, width: float) -> PackedVector2Array:
	if start.distance_to(end) < 4.0:
		return PackedVector2Array()

	var tangent := end - control
	if tangent.length_squared() < 0.001:
		tangent = end - start
	var dir_norm := tangent.normalized()

	var points := PackedVector2Array()
	points.resize(CURVE_SEGMENTS + 1)
	for s in range(CURVE_SEGMENTS + 1):
		var t := float(s) / float(CURVE_SEGMENTS)
		var one_minus_t := 1.0 - t
		points[s] = (one_minus_t * one_minus_t) * start + (2.0 * one_minus_t * t) * control + (t * t) * end

	var draw_points := points.duplicate()
	draw_points[CURVE_SEGMENTS] = end - dir_norm * (ARROW_HEAD_SIZE * 0.65)
	draw_polyline(draw_points, color, width, true)

	var perp := Vector2(-dir_norm.y, dir_norm.x)
	var tip := end
	var left := end - dir_norm * ARROW_HEAD_SIZE + perp * (ARROW_HEAD_SIZE * 0.45)
	var right := end - dir_norm * ARROW_HEAD_SIZE - perp * (ARROW_HEAD_SIZE * 0.45)
	draw_colored_polygon(PackedVector2Array([tip, left, right]), color)

	return points


func _draw_delete_badge(pos: Vector2) -> void:
	draw_circle(pos, 9.0, Color("#1e1e24"))
	draw_circle(pos, 8.0, HOVER_COLOR)
	var font := ThemeDB.fallback_font
	draw_string(font, pos + Vector2(-4.5, 4.5), "×", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


func _get_rect_border_point(rect: Rect2, from_point: Vector2) -> Vector2:
	var center := rect.get_center()
	var dir := from_point - center
	if dir == Vector2.ZERO:
		return center

	var half_size := rect.size * 0.5
	var scale_x := half_size.x / absf(dir.x) if not is_zero_approx(dir.x) else INF
	var scale_y := half_size.y / absf(dir.y) if not is_zero_approx(dir.y) else INF
	var t := minf(scale_x, scale_y)

	return center + dir * t
