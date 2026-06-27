extends Node2D
class_name HazardAxe

@export var length: float = 160.0
@export var max_angle_degrees: float = 55.0
@export var swing_speed: float = 2.5
@export var phase_offset: float = 0.0

var time: float = 0.0
var line: Line2D
var line_overlay: Line2D
var axe: Area2D
var swing_velocity: Vector2 = Vector2.ZERO

func _ready():
	# 1. Line2D for the swinging shaft (black backing)
	line = Line2D.new()
	line.width = 8.0
	line.default_color = Color("#111111")
	add_child(line)
	
	# Line2D overlay (neon pink highlight to contrast with the pendulum's cyan)
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
	pivot_cap.color = Color(1.0, 1.0, 1.0, 1.0)
	add_child(pivot_cap)
	
	var pivot_core = Polygon2D.new()
	var core_pts = PackedVector2Array()
	for i in range(12):
		var angle = float(i) * 2.0 * PI / 12.0
		core_pts.append(Vector2(cos(angle) * 4.0, sin(angle) * 4.0))
	pivot_core.polygon = core_pts
	pivot_core.color = Color("#111111")
	pivot_cap.add_child(pivot_core)
	
	# 2. Area2D for the axe head
	axe = Area2D.new()
	axe.collision_layer = 0
	axe.collision_mask = (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4) # Detect players (Layers 2, 3, 4, 5)
	add_child(axe)
	
	# Axe collision shape
	var col = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 24.0 # safe collision size covering blades
	col.shape = shape
	axe.add_child(col)
	
	# Left Blade Polygon (Double-headed axe left crescent)
	var left_blade = Polygon2D.new()
	left_blade.polygon = PackedVector2Array([
		Vector2(0, -12),
		Vector2(-25, -20),
		Vector2(-15, 0),
		Vector2(-25, 20),
		Vector2(0, 12)
	])
	left_blade.color = Color("#cfd8dc") # Steel grey
	axe.add_child(left_blade)
	
	# Left Blade Glow Outline
	var left_glow = Line2D.new()
	left_glow.points = PackedVector2Array([
		Vector2(-25, -20),
		Vector2(-15, 0),
		Vector2(-25, 20)
	])
	left_glow.width = 3.0
	left_glow.default_color = Color(1, 1, 1, 1) # White edge highlight
	left_glow.joint_mode = Line2D.LINE_JOINT_ROUND
	left_glow.begin_cap_mode = Line2D.LINE_CAP_ROUND
	left_glow.end_cap_mode = Line2D.LINE_CAP_ROUND
	left_blade.add_child(left_glow)
	
	# Right Blade Polygon (Double-headed axe right crescent)
	var right_blade = Polygon2D.new()
	right_blade.polygon = PackedVector2Array([
		Vector2(0, -12),
		Vector2(25, -20),
		Vector2(15, 0),
		Vector2(25, 20),
		Vector2(0, 12)
	])
	right_blade.color = Color("#cfd8dc")
	axe.add_child(right_blade)
	
	# Right Blade Glow Outline
	var right_glow = Line2D.new()
	right_glow.points = PackedVector2Array([
		Vector2(25, -20),
		Vector2(15, 0),
		Vector2(25, 20)
	])
	right_glow.width = 3.0
	right_glow.default_color = Color(1, 1, 1, 1)
	right_glow.joint_mode = Line2D.LINE_JOINT_ROUND
	right_glow.begin_cap_mode = Line2D.LINE_CAP_ROUND
	right_glow.end_cap_mode = Line2D.LINE_CAP_ROUND
	right_blade.add_child(right_glow)
	
	# Central Socket Hub (Neon Orange)
	var hub = Polygon2D.new()
	var hub_pts = PackedVector2Array()
	for i in range(8):
		var angle = float(i) * 2.0 * PI / 8.0
		hub_pts.append(Vector2(cos(angle) * 10.0, sin(angle) * 10.0))
	hub.polygon = hub_pts
	hub.color = Color("#ffd54f") # Fall Guys gold center
	axe.add_child(hub)
	
	# Top Spike
	var spike = Polygon2D.new()
	spike.polygon = PackedVector2Array([
		Vector2(0, -25),
		Vector2(-6, -10),
		Vector2(6, -10)
	])
	spike.color = Color("#ffd54f")
	axe.add_child(spike)
	
	axe.body_entered.connect(_on_body_entered)

func _physics_process(delta):
	time += delta
	var angle = deg_to_rad(max_angle_degrees) * sin((time * swing_speed) + phase_offset)
	var axe_pos = Vector2(sin(angle), cos(angle)) * length
	
	# Calculate swing velocity
	var angle_dot = deg_to_rad(max_angle_degrees) * swing_speed * cos((time * swing_speed) + phase_offset)
	swing_velocity = Vector2(cos(angle), -sin(angle)) * length * angle_dot
	
	line.points = PackedVector2Array([Vector2.ZERO, axe_pos])
	line_overlay.points = PackedVector2Array([Vector2.ZERO, axe_pos])
	axe.position = axe_pos
	axe.rotation = angle

func _on_body_entered(body):
	if body is PlayerController:
		var game_node = get_node_or_null("/root/Game")
		if game_node:
			var normal = (body.global_position - axe.global_position).normalized()
			# Project player using normal bounce and swing velocity momentum
			var knockback = normal * 320.0 + swing_velocity * 0.85
			if knockback.y > -200.0:
				knockback.y = -200.0
			game_node.call_deferred("player_hit_spike", body, knockback)
