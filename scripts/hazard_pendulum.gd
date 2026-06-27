extends Node2D
class_name HazardPendulum

@export var length: float = 160.0
@export var max_angle_degrees: float = 55.0
@export var swing_speed: float = 2.5
@export var phase_offset: float = 0.0

var time: float = 0.0
var line: Line2D
var line_overlay: Line2D
var ball: Area2D
var swing_velocity: Vector2 = Vector2.ZERO

func _ready():
	# 1. Line2D for the swinging chain/rope (black background)
	line = Line2D.new()
	line.width = 8.0
	line.default_color = Color("#111111")
	add_child(line)
	
	# Line2D overlay (pink neon warning stripe)
	line_overlay = Line2D.new()
	line_overlay.width = 3.0
	line_overlay.default_color = Color("#ff4081") # Hot Pink highlight
	add_child(line_overlay)
	
	# Pivot Joint Cap
	var pivot_cap = Polygon2D.new()
	var cap_pts = PackedVector2Array()
	for i in range(12):
		var angle = float(i) * 2.0 * PI / 12.0
		cap_pts.append(Vector2(cos(angle) * 8.0, sin(angle) * 8.0))
	pivot_cap.polygon = cap_pts
	pivot_cap.color = Color(1.0, 1.0, 1.0, 1.0) # White center
	add_child(pivot_cap)
	
	var pivot_core = Polygon2D.new()
	var core_pts = PackedVector2Array()
	for i in range(12):
		var angle = float(i) * 2.0 * PI / 12.0
		core_pts.append(Vector2(cos(angle) * 4.0, sin(angle) * 4.0))
	pivot_core.polygon = core_pts
	pivot_core.color = Color("#111111") # Black inner core
	pivot_cap.add_child(pivot_core)
	
	# 2. Area2D for the spiked ball hazard
	ball = Area2D.new()
	ball.collision_layer = 0
	ball.collision_mask = (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4) # Detect players (Layers 2, 3, 4, 5)
	add_child(ball)
	
	# Ball collision shape
	var col = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 22.0
	col.shape = shape
	ball.add_child(col)
	
	# Programmatic spiked ball polygon (styled like a saw blade)
	var poly = Polygon2D.new()
	var points = PackedVector2Array()
	var spikes_count = 14
	for i in range(spikes_count * 2):
		var angle = float(i) * PI / float(spikes_count)
		var r = 28.0 if (i % 2 == 0) else 18.0
		var offset_angle = angle
		if i % 2 == 0:
			offset_angle += 0.08
		points.append(Vector2(cos(offset_angle) * r, sin(offset_angle) * r))
	poly.polygon = points
	poly.color = Color("#111111") # Rich black base
	ball.add_child(poly)
	
	# Inner yellow warning highlight
	var inner = Polygon2D.new()
	var inner_points = PackedVector2Array()
	for i in range(12):
		var angle = float(i) * 2.0 * PI / 12.0
		inner_points.append(Vector2(cos(angle) * 13.0, sin(angle) * 13.0))
	inner.polygon = inner_points
	inner.color = Color("#ffeb3b") # Neon yellow highlight
	ball.add_child(inner)
	
	# White center core dot
	var core_dot = Polygon2D.new()
	var core_dot_pts = PackedVector2Array()
	for i in range(12):
		var angle = float(i) * 2.0 * PI / 12.0
		core_dot_pts.append(Vector2(cos(angle) * 5.0, sin(angle) * 5.0))
	core_dot.polygon = core_dot_pts
	core_dot.color = Color(1.0, 1.0, 1.0, 1.0)
	ball.add_child(core_dot)
	
	ball.body_entered.connect(_on_body_entered)

func _physics_process(delta):
	time += delta
	var angle = deg_to_rad(max_angle_degrees) * sin((time * swing_speed) + phase_offset)
	var ball_pos = Vector2(sin(angle), cos(angle)) * length
	
	# Calculate swing velocity (derivative of position with respect to time)
	var angle_dot = deg_to_rad(max_angle_degrees) * swing_speed * cos((time * swing_speed) + phase_offset)
	swing_velocity = Vector2(cos(angle), -sin(angle)) * length * angle_dot
	
	line.points = PackedVector2Array([Vector2.ZERO, ball_pos])
	line_overlay.points = PackedVector2Array([Vector2.ZERO, ball_pos])
	ball.position = ball_pos

func _on_body_entered(body):
	if body is PlayerController:
		var game_node = get_node_or_null("/root/Game")
		if game_node:
			var normal = (body.global_position - ball.global_position).normalized()
			# Combine normal bounce force with pendulum swing velocity projection
			var knockback = normal * 300.0 + swing_velocity * 0.8
			# Ensure we pop the player upward somewhat
			if knockback.y > -200.0:
				knockback.y = -200.0
			game_node.call_deferred("player_hit_spike", body, knockback)
