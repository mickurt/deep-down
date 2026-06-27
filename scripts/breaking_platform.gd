extends StaticBody2D
class_name BreakingPlatform

@export var width: float = 140.0

const TIME_TO_BREAK = 1.0

var standing_players: Array = []
var standing_time: float = 0.0
var is_broken: bool = false

var col_shape: CollisionShape2D
var detector: Area2D
var platform_color = Color("#ff7043") # Terracotta Coral for warning

var crack_lines: Array[PackedVector2Array] = []

func _ready():
	add_to_group("platforms")
	
	# Create platform collision shape
	col_shape = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(width, 20)
	col_shape.shape = shape
	add_child(col_shape)
	
	# Create Area2D detector slightly above the top edge
	detector = Area2D.new()
	detector.collision_layer = 0
	detector.collision_mask = (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4) # Detect players (Layers 2, 3, 4, 5)
	add_child(detector)
	
	var det_col = CollisionShape2D.new()
	var det_shape = RectangleShape2D.new()
	det_shape.size = Vector2(width - 12.0, 10.0) # slightly narrower to prevent wall/corner catches
	det_col.shape = det_shape
	det_col.position = Vector2(0, -15) # top of platform is y = -10, detector is at y = -20 to -10
	detector.add_child(det_col)
	
	detector.body_entered.connect(_on_detector_body_entered)
	detector.body_exited.connect(_on_detector_body_exited)
	
	# Define a few aesthetic zig-zag crack lines relative to width
	var w = width / 2.0
	crack_lines = [
		# Main center crack
		PackedVector2Array([
			Vector2(0, -10),
			Vector2(-6, -3),
			Vector2(6, 3),
			Vector2(-2, 10)
		]),
		# Left crack
		PackedVector2Array([
			Vector2(-w/3.0, -10),
			Vector2(-w/3.0 - 8, -2),
			Vector2(-w/3.0 - 2, 4),
			Vector2(-w/3.0 - 12, 10)
		]),
		# Right crack
		PackedVector2Array([
			Vector2(w/3.0, -10),
			Vector2(w/3.0 + 6, -4),
			Vector2(w/3.0 + 2, 3),
			Vector2(w/3.0 + 10, 10)
		])
	]

func _physics_process(delta):
	# Make sure players in the detector are still valid nodes
	var active_count = 0
	for p in standing_players:
		if is_instance_valid(p):
			active_count += 1
			
	if active_count > 0 and not is_broken:
		standing_time += delta
		if standing_time >= TIME_TO_BREAK:
			break_platform()
		else:
			queue_redraw()

func _on_detector_body_entered(body):
	if body is PlayerController and not standing_players.has(body):
		standing_players.append(body)

func _on_detector_body_exited(body):
	if standing_players.has(body):
		standing_players.erase(body)

func break_platform():
	is_broken = true
	standing_players.clear()
	
	# Disable collisions (both physical wall and detection area)
	col_shape.disabled = true
	var det_shape_node = detector.get_child(0) as CollisionShape2D
	if det_shape_node:
		det_shape_node.disabled = true
		
	queue_redraw()

func _draw():
	if is_broken:
		return
		
	if DisplayServer.get_name() == "headless":
		return
		
	# Shaking intensity increases as breaking time approaches
	var shake = Vector2.ZERO
	if standing_time > 1.0:
		var intensity = lerp(0.0, 4.0, (standing_time - 1.0) / (TIME_TO_BREAK - 1.0))
		shake = Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
		
	# 1. Main platform rounded rect cushion base
	var points = _get_rounded_rect_points(Vector2(width, 20), 8.0)
	var shifted_points = PackedVector2Array()
	for pt in points:
		shifted_points.append(pt + shake)
	draw_polygon(shifted_points, [platform_color])
	
	# 2. Semi-transparent top glossy white highlight
	var top_points = _get_rounded_rect_points(Vector2(width, 8), 4.0)
	var shifted_top_points = PackedVector2Array()
	for pt in top_points:
		shifted_top_points.append(pt + Vector2(0, -6) + shake)
	draw_polygon(shifted_top_points, [Color(1.0, 1.0, 1.0, 0.65)])
	
	# 3. Draw cracks
	var progress = standing_time / TIME_TO_BREAK
	var color = Color(0.08, 0.08, 0.08, lerp(0.3, 0.95, progress))
	var line_width = lerp(1.5, 4.5, progress)
	
	# Always draw at least 1 crack, draw more as progress grows
	var cracks_to_draw = 1
	if progress > 0.35:
		cracks_to_draw = 2
	if progress > 0.7:
		cracks_to_draw = 3
		
	for idx in range(min(cracks_to_draw, crack_lines.size())):
		var shifted_crack = PackedVector2Array()
		for pt in crack_lines[idx]:
			shifted_crack.append(pt + shake)
		draw_polyline(shifted_crack, color, line_width, true)

func _get_rounded_rect_points(size: Vector2, radius: float, steps: int = 8) -> PackedVector2Array:
	var points = PackedVector2Array()
	var w = size.x / 2.0
	var h = size.y / 2.0
	radius = min(radius, min(w, h))
	
	# Bottom-Right corner
	for i in range(steps + 1):
		var angle = lerp(0.0, PI / 2.0, float(i) / steps)
		points.append(Vector2(w - radius, h - radius) + Vector2(cos(angle) * radius, sin(angle) * radius))
	# Bottom-Left corner
	for i in range(steps + 1):
		var angle = lerp(PI / 2.0, PI, float(i) / steps)
		points.append(Vector2(-w + radius, h - radius) + Vector2(cos(angle) * radius, sin(angle) * radius))
	# Top-Left corner
	for i in range(steps + 1):
		var angle = lerp(PI, 3.0 * PI / 2.0, float(i) / steps)
		points.append(Vector2(-w + radius, -h + radius) + Vector2(cos(angle) * radius, sin(angle) * radius))
	# Top-Right corner
	for i in range(steps + 1):
		var angle = lerp(3.0 * PI / 2.0, 2.0 * PI, float(i) / steps)
		points.append(Vector2(w - radius, -h + radius) + Vector2(cos(angle) * radius, sin(angle) * radius))
		
	return points
