extends Node3D
# VanLab engine test scene - Godot route. Same scene as the web route; see SCENE-SPEC.md.
# Everything is built in code so the project is plain text an agent can write.

const BOX_L := 6.0   # along x. A test box, not a real van.
const BOX_W := 1.8   # along z
const BOX_H := 1.9   # up
const SNAP := 0.05
const ITEM_DEFS := [
	["Bed platform", 1.9, 1.4, 0.5, "8fb3a0"],
	["Galley", 1.2, 0.55, 0.9, "d9b26f"],
	["Fridge", 0.5, 0.55, 0.85, "c9ced6"],
	["Shower stall", 0.8, 0.8, 1.9, "6fa8c9"],
	["Bench", 1.0, 0.5, 0.45, "b98b6b"],
	["Water tank", 0.8, 0.4, 0.4, "5b8fd6"],
	["Battery box", 0.5, 0.35, 0.3, "e0c341"],
	["Toilet", 0.4, 0.45, 0.45, "f1efe8"],
	["Closet", 0.6, 0.55, 1.8, "a37f5c"],
	["Table", 0.7, 0.5, 0.72, "c7a17a"],
	["Step", 0.4, 0.3, 0.2, "8a8f98"],
	["Drawer unit", 0.6, 0.5, 0.6, "9c6f8f"],
]
const START := [
	[2.05, 0.0], [-1.85, -0.6], [-2.75, -0.6], [-2.6, 0.5], [-1.2, 0.65], [0.5, -0.7],
	[0.4, 0.7], [-1.95, 0.65], [-0.9, -0.6], [-0.25, 0.65], [0.85, 0.75], [-0.25, -0.65],
]
const RED := Color(0.85, 0.28, 0.23)

var items := []          # each: {name, node, mat, l, w, h, base, quarter}
var extra := []
var selected = null
var overlap_count := 0

var cam: Camera3D
var cam_target := Vector3(0, 0.6, 0)
var cam_dist := 9.8
var cam_yaw := 0.8
var cam_pitch := 0.48
var sun: DirectionalLight3D
var shadows_on := true
var full_res := true

var touches := {}        # finger index -> last position
var drag = null          # {item, index, off_x, off_z, start_x, start_z}
var pinch_dist := 0.0
var pinch_mid := Vector2.ZERO
var counters := {"itemDrags": 0, "orbits": 0, "pinchHandovers": 0}

var ui: Control
var hud: Label
var sel_label: Label
var buttons := []
var frame_times := []
var recent := []         # [time_ms, frame_ms] for the slowest frame in 2 s
var hud_timer := 0.0
var stats := {"fps": 0.0, "worstMs": 0.0, "calls": 0, "triangles": 0}
var stress_mesh: BoxMesh


func _ready() -> void:
	_build_world()
	_build_ui()
	_reset()
	get_viewport().size_changed.connect(_layout_ui)
	_layout_ui()


# ---- world ---------------------------------------------------------------------

func _box_node(size: Vector3, pos: Vector3, color: Color, shadow: bool):
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.75
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return [node, mat]


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("14171c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, 35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	add_child(sun)

	cam = Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.05
	cam.far = 80.0
	add_child(cam)
	cam.make_current()

	_box_node(Vector3(BOX_L, 0.04, BOX_W), Vector3(0, -0.02, 0), Color("3b4048"), false)
	var wall_color := Color(0.55, 0.59, 0.65, 0.22)
	var walls := [
		[Vector3(BOX_L, BOX_H, 0.01), Vector3(0, BOX_H / 2.0, -BOX_W / 2.0)],
		[Vector3(BOX_L, BOX_H, 0.01), Vector3(0, BOX_H / 2.0, BOX_W / 2.0)],
		[Vector3(0.01, BOX_H, BOX_W), Vector3(-BOX_L / 2.0, BOX_H / 2.0, 0)],
	]
	for w in walls:
		var made = _box_node(w[0], w[1], wall_color, false)
		made[1].transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		made[1].cull_mode = BaseMaterial3D.CULL_DISABLED

	for i in ITEM_DEFS.size():
		var d = ITEM_DEFS[i]
		var color := Color(d[4])
		var made = _box_node(Vector3(d[1], d[3], d[2]), Vector3(START[i][0], d[3] / 2.0, START[i][1]), color, true)
		items.append({"name": d[0], "node": made[0], "mat": made[1], "l": d[1], "w": d[2], "h": d[3], "base": color, "quarter": 0})

	stress_mesh = BoxMesh.new()
	stress_mesh.size = Vector3(0.18, 0.18, 0.18)
	_update_camera()


func _half(it) -> Vector2:
	if it.quarter % 2 == 0:
		return Vector2(it.l / 2.0, it.w / 2.0)
	return Vector2(it.w / 2.0, it.l / 2.0)


func _clamp_inside(it, x: float, z: float) -> Vector2:
	var h := _half(it)
	var max_x := BOX_L / 2.0 - h.x
	var max_z := BOX_W / 2.0 - h.y
	return Vector2(clampf(snappedf(x, SNAP), -max_x, max_x), clampf(snappedf(z, SNAP), -max_z, max_z))


func _overlaps(a, b) -> bool:
	var ha := _half(a)
	var hb := _half(b)
	var e := 0.000001
	return absf(a.node.position.x - b.node.position.x) < ha.x + hb.x - e and absf(a.node.position.z - b.node.position.z) < ha.y + hb.y - e


func _refresh_overlaps() -> void:
	overlap_count = 0
	for a in items:
		var hit := false
		for b in items:
			if a != b and _overlaps(a, b):
				hit = true
				break
		a.mat.albedo_color = RED if hit else a.base
		if hit:
			overlap_count += 1


func _select(it) -> void:
	if selected != null:
		selected.mat.emission_enabled = false
	selected = it
	if it != null:
		it.mat.emission_enabled = true
		it.mat.emission = Color(1, 1, 1)
		it.mat.emission_energy_multiplier = 0.18
	if sel_label != null:
		sel_label.text = it.name if it != null else "nothing selected"
	if buttons.size() > 0:
		buttons[0].disabled = it == null


func _update_camera() -> void:
	var dir := Vector3(cos(cam_pitch) * sin(cam_yaw), sin(cam_pitch), cos(cam_pitch) * cos(cam_yaw))
	cam.look_at_from_position(cam_target + dir * cam_dist, cam_target, Vector3.UP)


# ---- picking without physics: a ray against each item's box ---------------------------

func _ray(pos: Vector2) -> Array:
	var size := get_viewport().get_visible_rect().size
	var nx := pos.x / size.x
	var ny := pos.y / size.y
	var t := tan(deg_to_rad(cam.fov) / 2.0)
	var local := Vector3((2.0 * nx - 1.0) * t * (size.x / size.y), (1.0 - 2.0 * ny) * t, -1.0).normalized()
	return [cam.global_position, (cam.global_transform.basis * local).normalized()]


func _hit_box(origin: Vector3, dir: Vector3, bmin: Vector3, bmax: Vector3) -> float:
	var tmin := -INF
	var tmax := INF
	for axis in 3:
		if absf(dir[axis]) < 0.0000001:
			if origin[axis] < bmin[axis] or origin[axis] > bmax[axis]:
				return -1.0
		else:
			var t1: float = (bmin[axis] - origin[axis]) / dir[axis]
			var t2: float = (bmax[axis] - origin[axis]) / dir[axis]
			tmin = maxf(tmin, minf(t1, t2))
			tmax = minf(tmax, maxf(t1, t2))
	if tmax < 0.0 or tmin > tmax:
		return -1.0
	return maxf(tmin, 0.0)


func _pick(pos: Vector2):
	var r := _ray(pos)
	var best = null
	var best_t := INF
	for it in items:
		var h := _half(it)
		var p: Vector3 = it.node.position
		var t := _hit_box(r[0], r[1], Vector3(p.x - h.x, 0.0, p.z - h.y), Vector3(p.x + h.x, it.h, p.z + h.y))
		if t >= 0.0 and t < best_t:
			best_t = t
			best = it
	return best


func _floor_point(pos: Vector2):
	var r := _ray(pos)
	if absf(r[1].y) < 0.000001:
		return null
	var t: float = -r[0].y / r[1].y
	if t < 0.0:
		return null
	return r[0] + r[1] * t


# ---- input: item drag first, camera second ------------------------------------------------

func _over_buttons(pos: Vector2) -> bool:
	for b in buttons:
		if Rect2(b.position, b.size).has_point(pos):
			return true
	return false


func _set_xz(node, x: float, z: float) -> void:
	node.position = Vector3(x, node.position.y, z)


func _unhandled_input(event) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if _over_buttons(event.position):
				return
			touches[event.index] = event.position
			if touches.size() == 1:
				var it = _pick(event.position)
				if it == null:
					_select(null)
					counters.orbits += 1
				else:
					_select(it)
					var fp = _floor_point(event.position)
					if fp != null:
						drag = {"item": it, "index": event.index, "off_x": it.node.position.x - fp.x, "off_z": it.node.position.z - fp.z,
							"start_x": it.node.position.x, "start_z": it.node.position.z}
						counters.itemDrags += 1
			elif touches.size() == 2:
				if drag != null:
					# A second finger means zoom or pan: put the item back and give both fingers to the camera.
					_set_xz(drag.item.node, drag.start_x, drag.start_z)
					_refresh_overlaps()
					drag = null
					counters.pinchHandovers += 1
				var keys := touches.keys()
				pinch_dist = (touches[keys[0]] as Vector2).distance_to(touches[keys[1]])
				pinch_mid = ((touches[keys[0]] as Vector2) + (touches[keys[1]] as Vector2)) / 2.0
		else:
			touches.erase(event.index)
			if drag != null and drag.index == event.index:
				drag = null
	elif event is InputEventScreenDrag:
		if not touches.has(event.index):
			return
		touches[event.index] = event.position
		if drag != null and event.index == drag.index and touches.size() == 1:
			var fp = _floor_point(event.position)
			if fp != null:
				var c := _clamp_inside(drag.item, fp.x + drag.off_x, fp.z + drag.off_z)
				_set_xz(drag.item.node, c.x, c.y)
				_refresh_overlaps()
		elif touches.size() == 1:
			var size := get_viewport().get_visible_rect().size
			var k := 3.2 / minf(size.x, size.y)
			cam_yaw -= event.relative.x * k
			cam_pitch = clampf(cam_pitch + event.relative.y * k, 0.05, 1.5)
			_update_camera()
		elif touches.size() == 2:
			var keys := touches.keys()
			var a: Vector2 = touches[keys[0]]
			var b: Vector2 = touches[keys[1]]
			var d := a.distance_to(b)
			var mid := (a + b) / 2.0
			if pinch_dist > 1.0 and d > 1.0:
				cam_dist = clampf(cam_dist * pinch_dist / d, 1.5, 18.0)
			var size := get_viewport().get_visible_rect().size
			var pan := (mid - pinch_mid) * (cam_dist * 1.1 / minf(size.x, size.y))
			cam_target -= cam.global_transform.basis.x * pan.x
			cam_target += cam.global_transform.basis.y * pan.y
			pinch_dist = d
			pinch_mid = mid
			_update_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_dist = clampf(cam_dist * 0.9, 1.5, 18.0)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_dist = clampf(cam_dist * 1.1, 1.5, 18.0)
			_update_camera()


# ---- buttons ---------------------------------------------------------------------------

func _rotate_selected() -> void:
	if selected == null:
		return
	selected.quarter = (selected.quarter + 1) % 4
	selected.node.rotation = Vector3(0.0, selected.quarter * PI / 2.0, 0.0)
	var c := _clamp_inside(selected, selected.node.position.x, selected.node.position.z)
	_set_xz(selected.node, c.x, c.y)
	_refresh_overlaps()


func _add_stress() -> void:
	for i in 500:
		var k := extra.size()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color.from_hsv(fmod(k * 0.137, 1.0), 0.5, 0.85)
		var node := MeshInstance3D.new()
		node.mesh = stress_mesh
		node.material_override = mat
		node.position = Vector3(-3.4 + (k % 20) * 0.36, 0.09 + floorf(k / 400.0) * 0.3, 1.6 + (int(floorf(k / 20.0)) % 20) * 0.3)
		add_child(node)
		extra.append(node)


func _toggle_shadows() -> void:
	shadows_on = not shadows_on
	sun.shadow_enabled = shadows_on
	buttons[2].text = "Shadows: on" if shadows_on else "Shadows: off"


func _toggle_res() -> void:
	full_res = not full_res
	get_viewport().scaling_3d_scale = 1.0 if full_res else 0.5
	buttons[3].text = "Res: full" if full_res else "Res: half"


func _reset() -> void:
	for n in extra:
		n.queue_free()
	extra.clear()
	for i in items.size():
		var it = items[i]
		it.quarter = 0
		it.node.rotation = Vector3.ZERO
		it.node.position = Vector3(START[i][0], it.h / 2.0, START[i][1])
	_select(null)
	_refresh_overlaps()
	cam_target = Vector3(0, 0.6, 0)
	cam_dist = 9.8
	cam_yaw = 0.8
	cam_pitch = 0.48
	_update_camera()


# ---- on-screen readout and buttons --------------------------------------------------------

func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.11, 0.82)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(8)
	return sb


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud = Label.new()
	hud.add_theme_stylebox_override("normal", _panel_style())
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hud)
	sel_label = Label.new()
	sel_label.add_theme_stylebox_override("normal", _panel_style())
	sel_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sel_label.text = "nothing selected"
	ui.add_child(sel_label)
	var defs := [["Rotate 90", _rotate_selected], ["+500 boxes", _add_stress], ["Shadows: on", _toggle_shadows], ["Res: full", _toggle_res], ["Reset", _reset]]
	for d in defs:
		var b := Button.new()
		b.text = d[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(d[1])
		ui.add_child(b)
		buttons.append(b)
	buttons[0].disabled = true


func _layout_ui() -> void:
	var size := get_viewport().get_visible_rect().size
	var font := int(clampf(minf(size.x, size.y) / 28.0, 11.0, 44.0))
	var gap := font * 0.5
	hud.add_theme_font_size_override("font_size", font)
	sel_label.add_theme_font_size_override("font_size", font)
	hud.position = Vector2(gap, gap)
	sel_label.reset_size()
	sel_label.position = Vector2(size.x - sel_label.size.x - gap, gap)
	var per_row := 3 if size.x < size.y else 5
	var bw := (size.x - gap * (per_row + 1)) / per_row
	var bh := font * 2.8
	var rows := int(ceil(buttons.size() / float(per_row)))
	for i in buttons.size():
		var b: Button = buttons[i]
		b.add_theme_font_size_override("font_size", font)
		var row := i / per_row
		var col := i % per_row
		b.size = Vector2(bw, bh)
		b.position = Vector2(gap + col * (bw + gap), size.y - (rows - row) * (bh + gap))


func _process(delta: float) -> void:
	var ms := delta * 1000.0
	var now := Time.get_ticks_msec()
	frame_times.append(ms)
	if frame_times.size() > 60:
		frame_times.pop_front()
	recent.append([now, ms])
	while recent.size() > 0 and now - recent[0][0] > 2000:
		recent.pop_front()
	hud_timer += delta
	if hud_timer < 0.25:
		return
	hud_timer = 0.0
	var total := 0.0
	for f in frame_times:
		total += f
	stats.fps = 1000.0 / (total / frame_times.size())
	var worst := 0.0
	for r in recent:
		worst = maxf(worst, r[1])
	stats.worstMs = worst
	stats.calls = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	stats.triangles = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	hud.text = "%d frames/s\nslowest (2 s) %d ms\ndraw calls %d\ntriangles %d\nboxes %d\noverlapping %d\nGodot %s" % [
		int(round(stats.fps)), int(round(worst)), stats.calls, stats.triangles, items.size() + extra.size(), overlap_count,
		Engine.get_version_info().string]
	sel_label.reset_size()
	sel_label.position = Vector2(get_viewport().get_visible_rect().size.x - sel_label.size.x - hud.position.x, hud.position.y)
	_publish_state()


# For automated tests in a browser: the scene's state as a plain object on window.
func _publish_state() -> void:
	if not OS.has_feature("web"):
		return
	var size := get_viewport().get_visible_rect().size
	var list := []
	for it in items:
		var top: Vector3 = Vector3(it.node.position.x, it.h, it.node.position.z)
		var sp := cam.unproject_position(top)
		list.append({"id": it.name, "x": it.node.position.x, "z": it.node.position.z, "quarter": it.quarter,
			"sx": sp.x / size.x, "sy": sp.y / size.y, "hx": _half(it).x, "hz": _half(it).y})
	var state := {
		"ready": true, "engine": Engine.get_version_info().string, "items": list,
		"selected": selected.name if selected != null else null,
		"overlapCount": overlap_count, "total": items.size() + extra.size(),
		"camDist": cam_dist, "camYaw": cam_yaw, "camPitch": cam_pitch,
		"stats": stats, "counters": counters, "box": {"length": BOX_L, "width": BOX_W},
		"viewport": [size.x, size.y],
		"buttons": buttons.map(func(b): return {"text": b.text, "cx": (b.position.x + b.size.x / 2.0) / size.x, "cy": (b.position.y + b.size.y / 2.0) / size.y}),
	}
	JavaScriptBridge.eval("window.__vanlabGodot = %s;" % JSON.stringify(state), true)
