extends Area2D
class_name Spring

@export var bounce_force: float = -600.0

var base_width: float = 32.0
var base_height: float = 24.0
var current_height_ratio: float = 1.0 # 1.0 is normal, 0.4 is compressed, 1.25 is expanded
var animating: bool = false
var time_anim: float = 0.0

func _ready():
	collision_layer = 0
	collision_mask = (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4) # Detect players (Layers 2, 3, 4, 5)
	
	# Create collision shape (a rectangle on top of the spring)
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(28.0, 12.0)
	col.shape = shape
	col.position = Vector2(0, -6) # Positioned slightly above the base
	add_child(col)
	
	body_entered.connect(_on_body_entered)

func _physics_process(delta):
	if animating:
		time_anim += delta * 15.0 # speed of animation
		if time_anim < PI:
			# Compress phase
			current_height_ratio = lerp(1.0, 0.4, sin(time_anim))
		elif time_anim < 2.0 * PI:
			# Bounce/extend phase
			current_height_ratio = lerp(1.0, 1.25, sin(time_anim - PI))
		else:
			# Settling back
			current_height_ratio = 1.0
			animating = false
		queue_redraw()

func _on_body_entered(body):
	if body is PlayerController:
		# Apply strong upward velocity
		body.velocity.y = bounce_force
		
		# Play bounce animation
		animating = true
		time_anim = 0.0
		queue_redraw()
		
		# Vibrate device if this is the player we control
		if body.is_multiplayer_authority():
			Input.vibrate_handheld(100)

func _draw():
	if DisplayServer.get_name() == "headless":
		return
		
	# Drawing the spring programmatically for rich cartoon aesthetics
	var h = base_height * current_height_ratio
	
	# 1. Base Plate (Dark charcoal grey)
	draw_rect(Rect2(-base_width/2.0, -4.0, base_width, 4.0), Color("#212121"))
	
	# 2. Coil (Vibrant orange metallic zig-zag)
	var points = PackedVector2Array()
	points.append(Vector2(0, -4))
	
	var turns = 3
	for i in range(turns):
		var y = -4 - (float(i + 0.5) / turns) * (h - 8)
		var x = (base_width / 3.0) if (i % 2 == 0) else (-base_width / 3.0)
		points.append(Vector2(x, y))
		
		var y_next = -4 - (float(i + 1.0) / turns) * (h - 8)
		points.append(Vector2(0, y_next))
		
	draw_polyline(points, Color("#ff6d00"), 4.0, true)
	
	# 3. Top Plate (Vibrant neon cyan cap)
	var top_y = -h
	draw_rect(Rect2(-base_width/2.0 - 2.0, top_y, base_width + 4.0, 4.0), Color("#00e5ff"), true) # Neon Cyan cap
	draw_rect(Rect2(-base_width/2.0 - 2.0, top_y, base_width + 4.0, 4.0), Color("#ffffff"), false, 1.5) # White border
