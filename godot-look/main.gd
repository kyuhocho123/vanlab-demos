extends Node3D
# VanLab look check (task V1): the same van corner as the web look test, Realistic style only,
# drawn by Godot's Compatibility renderer. 49 parts, Day and Evening. No image or model files:
# every texture and mesh is made here in code. x runs along the van, y is up, z is across.

const CAM_TARGET := Vector3(0.95, 0.92, -0.3)

var parts_built := 0
var mats := {}            # role -> StandardMaterial3D
var tex := {}             # name -> ImageTexture
var box_cache := {}       # "sx,sy,sz,r" -> Mesh
var evening := false

var cam: Camera3D
var cam_dist := 4.4
var cam_yaw := 0.78
var cam_pitch := 0.22
var tall := true
var env: Environment
var sun: DirectionalLight3D
var led1: OmniLight3D
var led2: OmniLight3D

var touches := {}
var pinch_dist := 0.0
var gesture_lock := false
var counters := {"orbits": 0, "pinches": 0}

var ui: Control
var hud: Label
var mood_button: Button
var frame_times := []
var hud_timer := 0.0
var stats := {"fps": 0.0, "calls": 0, "triangles": 0}
var build_ms := 0


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	_make_textures()
	_build_light()
	_build_corner()
	_build_ui()
	cam = Camera3D.new()
	cam.near = 0.05
	cam.far = 40.0
	add_child(cam)
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()
	_apply_mood()
	build_ms = Time.get_ticks_msec() - t0


# ---- textures drawn in code -------------------------------------------------------

func _blend(img: Image, x: int, y: int, c: Color, a: float) -> void:
	var s := img.get_width()
	var px := posmod(x, s)
	var py := posmod(y, s)
	img.set_pixel(px, py, img.get_pixel(px, py).lerp(c, a))


func _finish(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _wood(base: Color, dark: Color, seed_value: int, planks: int) -> ImageTexture:
	var s := 256
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(base)
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	for i in 150:   # grain: thin wavy strokes running along v
		var x0 := r.randf() * s
		var wob := (r.randf() - 0.5) * 9.0
		var x3 := x0 + (r.randf() - 0.5) * 4.0
		var a := 0.05 + r.randf() * 0.16
		var wide := r.randf() > 0.6
		for y in s:
			var t := float(y) / s
			var u := 1.0 - t
			var x := u * u * u * x0 + 3.0 * u * u * t * (x0 + wob) + 3.0 * u * t * t * (x0 - wob) + t * t * t * x3
			_blend(img, int(x), y, dark, a)
			if wide:
				_blend(img, int(x) + 1, y, dark, a * 0.6)
	for i in 7:     # broad darker bands
		var bx := int(r.randf() * s)
		var bw := 9 + int(r.randf() * 25.0)
		var ba := 0.05 + r.randf() * 0.06
		for x in bw:
			for y in s:
				_blend(img, bx + x, y, dark, ba)
	if planks > 0:  # plank seams for the floor
		var seam := Color(0.157, 0.102, 0.063)
		for i in planks:
			var sx := int(float(i) * s / planks)
			for y in s:
				_blend(img, sx, y, seam, 0.55)
				_blend(img, sx + 1, y, seam, 0.3)
	return _finish(img)


func _tile(color: Color, grout: Color, seed_value: int) -> ImageTexture:
	var s := 256
	var n := 4
	var t := s / n
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(grout)
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	for i in n:
		for j in n:
			var c := Color.from_hsv(
				fposmod(color.h + (r.randf() - 0.5) * 0.015, 1.0),
				clampf(color.s + (r.randf() - 0.5) * 0.08, 0.0, 1.0),
				clampf(color.v + (r.randf() - 0.5) * 0.07, 0.0, 1.0))
			for x in range(2, t - 2):
				for y in range(2, t - 2):
					var f := float(x + y) / float(2 * t)   # a soft sheen across each tile
					var shade := c.lerp(Color.WHITE, 0.10 * (1.0 - f)).lerp(Color.BLACK, 0.08 * f)
					img.set_pixel(i * t + x, j * t + y, shade)
	return _finish(img)


func _fabric(color: Color, seed_value: int) -> ImageTexture:
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(color)
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	for i in 2600:
		var x := int(r.randf() * s)
		var y := int(r.randf() * s)
		if r.randf() > 0.5:
			_blend(img, x, y, Color.WHITE, 0.07)
		else:
			_blend(img, x, y, Color.BLACK, 0.08)
	return _finish(img)


func _make_textures() -> void:
	tex["walnut"] = _wood(Color("6b4630"), Color("2e1b10"), 11, 0)
	tex["walnutFront"] = _wood(Color("7a5236"), Color("34200f"), 23, 0)
	tex["oakFloor"] = _wood(Color("b99872"), Color("6e5236"), 37, 6)
	tex["tile"] = _tile(Color("2f6b55"), Color("d9d4c8"), 5)
	tex["fabricA"] = _fabric(Color("b8643f"), 3)
	tex["fabricB"] = _fabric(Color("7d8a5c"), 4)
	tex["lining"] = _fabric(Color("e9e4da"), 9)


# ---- materials (the Realistic style of the web look test) ---------------------------

func _std(color: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _textured(tex_name: String, rough: float, repeats_per_metre: float) -> StandardMaterial3D:
	var m := _std(Color.WHITE, rough)
	m.albedo_texture = tex[tex_name]
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(repeats_per_metre, repeats_per_metre, repeats_per_metre)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _glowing(color: Color, glow: Color, rough: float) -> StandardMaterial3D:
	var m := _std(color, rough)
	m.emission_enabled = true
	m.emission = glow
	m.emission_energy_multiplier = 1.0
	return m


func _mat(role: String) -> StandardMaterial3D:
	if mats.has(role):
		return mats[role]
	var m: StandardMaterial3D
	match role:
		"floor": m = _textured("oakFloor", 0.6, 1.0)
		"lining": m = _textured("lining", 0.95, 2.0)
		"tile": m = _textured("tile", 0.18, 5.0)
		"slatback": m = _std(Color("191613"), 0.85)
		"slat", "shelf", "cabinet": m = _textured("walnut", 0.5, 2.0)
		"front": m = _textured("walnutFront", 0.42, 2.0)
		"counter": m = _std(Color("2b2b2e"), 0.38)
		"metal": m = _std(Color("c9cdd2"), 0.25, 1.0)
		"brass": m = _std(Color("c9a35a"), 0.3, 1.0)
		"sink": m = _std(Color("17181a"), 0.35, 0.7)
		"glassblack": m = _std(Color("08080a"), 0.06)
		"cushion": m = _textured("fabricA", 1.0, 5.0)
		"cushion2": m = _textured("fabricB", 1.0, 5.0)
		"glass": m = _glowing(Color("9fc4d8"), Color("bfe3ff"), 0.05)
		"frame": m = _std(Color("141414"), 0.5)
		"led": m = _glowing(Color("fff1d6"), Color("ffc98a"), 0.5)
		"ceramic": m = _std(Color("f2efe9"), 0.3)
		"ceramic2": m = _std(Color("c86f4a"), 0.7)
		"book": m = _std(Color("3d5a80"), 0.8)
		"book2": m = _std(Color("d9c9a3"), 0.8)
		_: m = _std(Color("8a5a44"), 0.8)
	mats[role] = m
	return m


# ---- meshes -----------------------------------------------------------------------

func _samples(hh: float, r: float) -> PackedFloat32Array:
	return PackedFloat32Array([-hh, -hh + 0.3 * r, -hh + r, hh - r, hh - 0.3 * r, hh])


# A box whose edges and corners are rounded with radius r, with smooth normals.
func _rounded_box(size: Vector3, r: float) -> Mesh:
	var key := "%s,%s" % [size, r]
	if box_cache.has(key):
		return box_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := size * 0.5
	var lim := Vector3(h.x - r, h.y - r, h.z - r)
	var count := 0
	for a in 3:
		var b := (a + 1) % 3
		var c := (a + 2) % 3
		var ub := _samples(h[b], r)
		var vc := _samples(h[c], r)
		for side in 2:
			var sgn := -1.0 if side == 0 else 1.0
			var base := count
			for j in vc.size():
				for i in ub.size():
					var q := Vector3.ZERO
					q[a] = sgn * h[a]
					q[b] = ub[i]
					q[c] = vc[j]
					var inner := Vector3(clampf(q.x, -lim.x, lim.x), clampf(q.y, -lim.y, lim.y), clampf(q.z, -lim.z, lim.z))
					var n := (q - inner).normalized()
					st.set_normal(n)
					st.add_vertex(inner + n * r)
					count += 1
			var w := ub.size()
			for j in vc.size() - 1:
				for i in w - 1:
					var p0 := base + j * w + i
					st.add_index(p0)
					st.add_index(p0 + 1)
					st.add_index(p0 + w + 1)
					st.add_index(p0)
					st.add_index(p0 + w + 1)
					st.add_index(p0 + w)
	var mesh := st.commit()
	box_cache[key] = mesh
	return mesh


func _add(mesh: Mesh, role: String, pos: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(role)
	mi.position = pos
	if role == "led" or role == "glass":
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if parent == null:
		add_child(mi)
		parts_built += 1
	else:
		parent.add_child(mi)
	return mi


# kind: 0 = flat part (sharp edges), 1 = hard part (6 mm edge), 2 = soft part (cushion)
func _box(role: String, sx: float, sy: float, sz: float, x: float, y: float, z: float, kind: int = 1) -> MeshInstance3D:
	var size := Vector3(sx, sy, sz)
	var smallest := minf(sx, minf(sy, sz))
	var mesh: Mesh
	if kind == 0:
		var bm := BoxMesh.new()
		bm.size = size
		mesh = bm
	elif kind == 2:
		mesh = _rounded_box(size, minf(0.04, smallest * 0.45))
	else:
		mesh = _rounded_box(size, minf(0.006, smallest * 0.4))
	return _add(mesh, role, Vector3(x, y, z))


func _cyl(role: String, radius: float, height: float, pos: Vector3) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 28
	_add(cm, role, pos + Vector3(0, height * 0.5, 0))


func _spline(pts: Array, steps: int) -> Array:
	var out := []
	for k in pts.size() - 1:
		var p0 = pts[maxi(k - 1, 0)]
		var p1 = pts[k]
		var p2 = pts[k + 1]
		var p3 = pts[mini(k + 2, pts.size() - 1)]
		for s in steps:
			out.append(p1.cubic_interpolate(p2, p0, p3, float(s) / steps))
	out.append(pts[pts.size() - 1])
	return out


# The van's side wall curving into the roof: a cross-section swept along the van.
func _wall() -> void:
	var ctrl := [Vector2(-0.86, 0), Vector2(-0.89, 0.35), Vector2(-0.9, 0.8), Vector2(-0.885, 1.2), Vector2(-0.84, 1.5),
		Vector2(-0.74, 1.72), Vector2(-0.58, 1.86), Vector2(-0.3, 1.9), Vector2(0.3, 1.92)]   # (z, y)
	var line := _spline(ctrl, 5)
	var normals := []
	for k in line.size():
		var a: Vector2 = line[maxi(k - 1, 0)]
		var b: Vector2 = line[mini(k + 1, line.size() - 1)]
		var d := (b - a).normalized()
		var n := Vector2(d.y, -d.x)          # perpendicular in the (z, y) plane
		var here: Vector2 = line[k]
		if n.dot(Vector2(0.0, 1.0) - here) < 0.0:
			n = -n                           # make it point into the van
		normals.append(n)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := 2.6
	var thick := 0.04
	var count := 0
	for k in line.size():                    # inner skin: two vertices per sample
		var p: Vector2 = line[k]
		var n2: Vector2 = normals[k]
		for x in [0.0, length]:
			st.set_normal(Vector3(0.0, n2.y, n2.x))
			st.add_vertex(Vector3(x, p.y, p.x))
			count += 1
	for k in line.size() - 1:
		var i0 := k * 2
		for t in [[i0, i0 + 1, i0 + 3], [i0, i0 + 3, i0 + 2]]:
			for v in t:
				st.add_index(v)
	var cap := count                         # the cut end of the wall at the open side
	for k in line.size():
		var p: Vector2 = line[k]
		var n2: Vector2 = normals[k]
		var o := p - n2 * thick
		st.set_normal(Vector3(1, 0, 0))
		st.add_vertex(Vector3(length, p.y, p.x))
		st.set_normal(Vector3(1, 0, 0))
		st.add_vertex(Vector3(length, o.y, o.x))
	for k in line.size() - 1:
		var i0 := cap + k * 2
		for t in [[i0, i0 + 1, i0 + 3], [i0, i0 + 3, i0 + 2]]:
			for v in t:
				st.add_index(v)
	_add(st.commit(), "lining", Vector3.ZERO)


func _tap(pos: Vector3) -> void:
	var holder := Node3D.new()
	holder.position = pos
	add_child(holder)
	parts_built += 1
	var ctrl := [Vector3(0, 0, 0), Vector3(0, 0.16, 0), Vector3(0, 0.25, 0.025), Vector3(0, 0.275, 0.09), Vector3(0, 0.235, 0.15), Vector3(0, 0.2, 0.16)]
	var path := _spline(ctrl, 4)
	for k in path.size() - 1:
		var a: Vector3 = path[k]
		var b: Vector3 = path[k + 1]
		var seg := b - a
		if seg.length() < 0.0005:
			continue
		var cm := CylinderMesh.new()
		cm.top_radius = 0.011
		cm.bottom_radius = 0.011
		cm.height = seg.length() + 0.004
		cm.radial_segments = 14
		var mi := _add(cm, "metal", (a + b) * 0.5, holder)
		var dir := seg.normalized()
		if absf(dir.dot(Vector3.UP)) < 0.9999:
			mi.basis = Basis(Quaternion(Vector3.UP, dir))


func _build_corner() -> void:
	var floor_part := _box("floor", 1.2, 0.03, 2.6, 1.3, -0.015, -0.3, 0)
	floor_part.rotation.y = PI / 2.0               # so the planks run along the van
	_box("lining", 0.04, 1.94, 1.24, -0.02, 0.97, -0.3, 0)        # partition wall
	_box("tile", 0.012, 1.86, 0.58, 0.006, 0.93, -0.6, 0)        # tiled part of the partition
	_box("slatback", 0.01, 1.86, 0.6, 0.005, 0.93, 0.0, 0)
	for i in 11:
		_box("slat", 0.022, 1.86, 0.032, 0.021, 0.93, -0.27 + i * 0.054)
	for y in [1.12, 1.5]:
		_box("shelf", 0.15, 0.022, 0.52, 0.107, y, 0.0)
		_box("led", 0.012, 0.008, 0.46, 0.05, y - 0.016, 0.0, 0)
	_box("book", 0.1, 0.16, 0.03, 0.1, 1.211, -0.17)
	_box("book2", 0.1, 0.14, 0.028, 0.1, 1.201, -0.137)
	_box("book3", 0.1, 0.15, 0.035, 0.1, 1.206, -0.102)
	# bench with cushions under the window
	_box("cabinet", 0.62, 0.42, 0.5, 0.37, 0.21, -0.61)
	_box("cushion", 0.6, 0.1, 0.49, 0.37, 0.47, -0.61, 2)
	_box("cushion2", 0.6, 0.3, 0.09, 0.37, 0.68, -0.815, 2)
	# window on the curved wall
	_box("frame", 0.58, 0.48, 0.02, 0.37, 1.24, -0.878)
	_box("glass", 0.5, 0.4, 0.024, 0.37, 1.24, -0.876, 0)
	# galley
	_box("cabinet", 1.2, 0.86, 0.55, 1.35, 0.43, -0.585)
	for x in [0.955, 1.35, 1.745]:
		_box("front", 0.385, 0.74, 0.018, x, 0.47, -0.301)
		_box("brass", 0.13, 0.012, 0.014, x, 0.79, -0.283)
	_box("counter", 1.26, 0.035, 0.6, 1.35, 0.8775, -0.575)
	_box("metal", 0.42, 0.004, 0.36, 1.62, 0.897, -0.6, 0)
	_box("sink", 0.37, 0.006, 0.31, 1.62, 0.899, -0.6, 0)
	_box("glassblack", 0.3, 0.005, 0.36, 1.08, 0.8975, -0.58, 0)
	# upper cabinet with a light strip under it
	_box("cabinet", 1.2, 0.34, 0.34, 1.35, 1.53, -0.63)
	for x in [1.052, 1.648]:
		_box("front", 0.585, 0.3, 0.018, x, 1.53, -0.451)
		_box("brass", 0.13, 0.012, 0.014, x, 1.41, -0.433)
	_box("led", 1.1, 0.008, 0.02, 1.35, 1.354, -0.5, 0)
	_box("led", 2.5, 0.01, 0.022, 1.3, 1.868, -0.5, 0)            # ceiling light line
	_cyl("ceramic", 0.037, 0.09, Vector3(0.93, 0.895, -0.44))    # mug on the counter
	_cyl("ceramic2", 0.05, 0.12, Vector3(0.1, 1.511, 0.13))      # pot on the shelf
	_tap(Vector3(1.62, 0.9, -0.8))
	_wall()


# ---- light ------------------------------------------------------------------------

func _build_light() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	var sky_mat := ProceduralSkyMaterial.new()       # stands in for the web version's generated room
	sky_mat.sky_top_color = Color(0.95, 0.9, 0.82)
	sky_mat.sky_horizon_color = Color(0.62, 0.56, 0.5)
	sky_mat.ground_horizon_color = Color(0.42, 0.36, 0.31)
	sky_mat.ground_bottom_color = Color(0.2, 0.16, 0.13)
	sky_mat.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	add_child(sun)
	sun.look_at_from_position(Vector3(3.2, 3.4, 2.6), Vector3(0.8, 0.6, -0.5), Vector3.UP)
	sun.light_color = Color("fff0dc")
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 12.0
	sun.shadow_blur = 1.5
	led1 = OmniLight3D.new()
	led1.position = Vector3(1.35, 1.3, -0.48)        # under the upper cabinet
	led1.light_color = Color("ffc58a")
	led1.omni_range = 2.4
	add_child(led1)
	led2 = OmniLight3D.new()
	led2.position = Vector3(0.22, 1.3, 0.0)          # at the slat wall shelves
	led2.light_color = Color("ffc58a")
	led2.omni_range = 2.2
	add_child(led2)


func _apply_mood() -> void:
	env.background_color = Color("0c0a09") if evening else Color("1d1916")
	env.ambient_light_energy = 0.14 if evening else 0.6
	env.tonemap_exposure = 0.95 if evening else 1.05
	sun.light_energy = 0.0 if evening else 1.7
	sun.shadow_enabled = not evening
	sun.visible = not evening
	led1.light_energy = 2.6 if evening else 0.5
	led2.light_energy = 2.2 if evening else 0.4
	_mat("led").emission_energy_multiplier = 5.0 if evening else 2.0
	_mat("glass").emission_energy_multiplier = 0.03 if evening else 1.0
	mood_button.text = "Light: evening" if evening else "Light: day"


func _toggle_mood() -> void:
	evening = not evening
	_apply_mood()


# ---- camera and touch -----------------------------------------------------------------

func _update_camera() -> void:
	var dir := Vector3(cos(cam_pitch) * sin(cam_yaw), sin(cam_pitch), cos(cam_pitch) * cos(cam_yaw))
	cam.look_at_from_position(CAM_TARGET + dir * cam_dist, CAM_TARGET, Vector3.UP)


func _on_resize() -> void:
	var size := get_viewport().get_visible_rect().size
	var now_tall := size.x < size.y
	cam.fov = 58.0 if now_tall else 42.0     # a taller screen needs a wider view to keep the corner in frame
	if now_tall != tall or frame_times.is_empty():
		tall = now_tall
		cam_dist = 4.4 if tall else 2.9
	_update_camera()
	_layout_ui()


func _pinch() -> float:
	var pts := touches.values()
	if pts.size() < 2:
		return 0.0
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[1]
	return a.distance_to(b)


func _unhandled_input(event) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position
			if touches.size() >= 2:
				gesture_lock = true
				pinch_dist = _pinch()
				counters.pinches += 1
		else:
			touches.erase(event.index)
			if touches.is_empty():
				gesture_lock = false
			pinch_dist = _pinch()
	elif event is InputEventScreenDrag:
		touches[event.index] = event.position
		if touches.size() == 1 and not gesture_lock:
			cam_yaw = clampf(cam_yaw - event.relative.x * 0.006, 0.12, 1.42)   # stay in front of both walls
			cam_pitch = clampf(cam_pitch + event.relative.y * 0.006, 0.03, 1.0)
			counters.orbits += 1
		elif touches.size() >= 2:
			var d := _pinch()
			if pinch_dist > 0.0 and d > 0.0:
				cam_dist = clampf(cam_dist * pinch_dist / d, 1.4, 7.0)
			pinch_dist = d
		_update_camera()


# ---- interface ------------------------------------------------------------------------

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
	mood_button = Button.new()
	mood_button.focus_mode = Control.FOCUS_NONE
	mood_button.pressed.connect(_toggle_mood)
	ui.add_child(mood_button)


func _layout_ui() -> void:
	if hud == null:
		return
	var size := get_viewport().get_visible_rect().size
	var font := int(clampf(minf(size.x, size.y) / 28.0, 11.0, 44.0))
	var gap := font * 0.5
	hud.add_theme_font_size_override("font_size", font)
	hud.position = Vector2(gap, gap)
	mood_button.add_theme_font_size_override("font_size", font)
	var bw := minf(size.x - gap * 2.0, font * 12.0)
	var bh := font * 2.8
	mood_button.size = Vector2(bw, bh)
	mood_button.position = Vector2((size.x - bw) / 2.0, size.y - bh - gap * 2.0)


func _process(delta: float) -> void:
	frame_times.append(delta * 1000.0)
	if frame_times.size() > 60:
		frame_times.pop_front()
	hud_timer += delta
	if hud_timer < 0.25:
		return
	hud_timer = 0.0
	var total := 0.0
	for f in frame_times:
		total += f
	stats.fps = 1000.0 / (total / frame_times.size())
	stats.calls = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	stats.triangles = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	hud.text = "%d frames/s\ndraw calls %d\ntriangles %d\nparts %d\nGodot %s" % [
		int(round(stats.fps)), stats.calls, stats.triangles, parts_built, Engine.get_version_info().string]
	_publish_state()


# For automated tests in a browser: the scene's state as a plain object on window.
func _publish_state() -> void:
	if not OS.has_feature("web"):
		return
	var size := get_viewport().get_visible_rect().size
	var state := {
		"ready": true, "engine": Engine.get_version_info().string,
		"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method")),
		"parts": parts_built, "mood": "evening" if evening else "day",
		"sunEnergy": sun.light_energy, "ledEnergy": led1.light_energy,
		"camDist": cam_dist, "camYaw": cam_yaw, "camPitch": cam_pitch,
		"stats": stats, "counters": counters, "buildMs": build_ms, "viewport": [size.x, size.y],
		"button": {"text": mood_button.text, "cx": (mood_button.position.x + mood_button.size.x / 2.0) / size.x,
			"cy": (mood_button.position.y + mood_button.size.y / 2.0) / size.y},
	}
	JavaScriptBridge.eval("window.__vanlabLook = %s;" % JSON.stringify(state), true)
