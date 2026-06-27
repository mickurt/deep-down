extends Line2D
class_name RopePhysics

# RopePhysics.gd
# Simulates a segmented physical rope connecting two players using Verlet Integration.
# Exerts tension forces on players based on constraint extensions.

class RopePoint:
	var position: Vector2
	var previous_position: Vector2
	var is_pinned: bool = false

# Configuration
@export var point_count: int = 20
@export var base_segment_length: float = 16.0
@export var min_segment_length: float = 4.0 # Length when fully reeled in
@export var gravity: Vector2 = Vector2(0, 500)
@export var damping: float = 0.98 # Simulates air resistance / drag
@export var constraint_iterations: int = 60
@export var stiffness: float = 6.0 # Tension force scalar applied to players



# Internal State
var rope_points: Array[RopePoint] = []
var current_segment_length: float = 16.0
var target_segment_length: float = 16.0

# Anchors (Player nodes)
var player_a: CharacterBody2D = null
var player_b: CharacterBody2D = null

func _ready() -> void:
	current_segment_length = base_segment_length
	target_segment_length = base_segment_length
	_initialize_rope()

func initialize(p_a: CharacterBody2D, p_b: CharacterBody2D) -> void:
	player_a = p_a
	player_b = p_b
	_initialize_rope()

func _initialize_rope() -> void:
	rope_points.clear()
	var start_pos = player_a.global_position if player_a else global_position
	var end_pos = player_b.global_position if player_b else global_position + Vector2(0, 100)
	
	for i in range(point_count):
		var t = float(i) / float(point_count - 1)
		var p = RopePoint.new()
		p.position = start_pos.lerp(end_pos, t)
		p.previous_position = p.position
		rope_points.append(p)
		
	# Setup Line2D points
	clear_points()
	for i in range(point_count):
		add_point(Vector2.ZERO)

func _physics_process(delta: float) -> void:
	# 1. Update segment length (reel-in when either player is anchored)
	var is_pulling = false
	if is_instance_valid(player_a) and player_a.is_anchored:
		is_pulling = true
	if is_instance_valid(player_b) and player_b.is_anchored:
		is_pulling = true
		
	if is_pulling:
		target_segment_length = min_segment_length
	else:
		target_segment_length = base_segment_length

	current_segment_length = lerp(current_segment_length, target_segment_length, 12.0 * delta)

	
	# 2. Verlet integration step
	for i in range(point_count):
		var p = rope_points[i]
		if p.is_pinned:
			continue
		var velocity = (p.position - p.previous_position) * damping
		
		# Clamp velocity to prevent runaway kinetic energy (explosions)
		if velocity.length() > 600.0:
			velocity = velocity.normalized() * 600.0
			
		p.previous_position = p.position
		p.position += velocity + gravity * delta

		
	# 3. Resolve constraints (relaxation loop)
	var solver_segment_length = current_segment_length
	if is_instance_valid(player_a) and is_instance_valid(player_b):
		var p_dist = player_a.global_position.distance_to(player_b.global_position)
		var max_len = (point_count - 1) * current_segment_length
		if p_dist > max_len:
			solver_segment_length = p_dist / (point_count - 1)

	for iteration in range(constraint_iterations):

		# Pin Player A to Point 0
		if is_instance_valid(player_a):
			rope_points[0].position = player_a.global_position
			rope_points[0].is_pinned = true
		else:
			rope_points[0].is_pinned = false
			
		# Pin Player B to the last Point
		if is_instance_valid(player_b):
			rope_points[point_count - 1].position = player_b.global_position
			rope_points[point_count - 1].is_pinned = true
		else:
			rope_points[point_count - 1].is_pinned = false
			
		# Solve distance constraints between segments
		for i in range(point_count - 1):
			var p1 = rope_points[i]
			var p2 = rope_points[i + 1]
			
			var delta_pos = p2.position - p1.position
			var dist = delta_pos.length()
			if dist == 0.0:
				dist = 0.001
			
			# How much it deviates from desired segment length
			var diff = solver_segment_length - dist
			var percent = diff / dist / 2.0
			var offset = delta_pos * percent

			
			if p1.is_pinned and p2.is_pinned:
				# Both pinned: cannot move
				continue
			elif p1.is_pinned:
				# p1 fixed, p2 takes all correction
				p2.position += offset * 2.0
			elif p2.is_pinned:
				# p2 fixed, p1 takes all correction
				p1.position -= offset * 2.0
			else:
				# Both free, share correction
				p1.position -= offset
				p2.position += offset
				
	# 3.5 Inelastic hard constraint solver for Player positions and velocities
	if is_instance_valid(player_a) and is_instance_valid(player_b):
		var diff = player_b.global_position - player_a.global_position
		var dist = diff.length()
		var max_rope_length = (point_count - 1) * current_segment_length
		
		if dist > max_rope_length:
			var overlap = dist - max_rope_length
			var dir = diff.normalized()
			
			var mass_a = player_a.current_mass
			var mass_b = player_b.current_mass
			var total_mass = mass_a + mass_b
			
			var ratio_a = mass_b / total_mass
			var ratio_b = mass_a / total_mass
			
			# Grounded platform protection: if A is grounded but B is hanging in the void, B takes 100% of correction.
			if player_a.is_on_floor() and not player_b.is_on_floor():
				ratio_a = 0.0
				ratio_b = 1.0
			# If B is grounded but A is hanging in the void, A takes 100% of correction.
			elif player_b.is_on_floor() and not player_a.is_on_floor():
				ratio_a = 1.0
				ratio_b = 0.0
				
			# Resolve position using move_and_collide to respect platform collisions
			var correction_a = dir * overlap * ratio_a
			var correction_b = -dir * overlap * ratio_b
			
			player_a.move_and_collide(correction_a)
			player_b.move_and_collide(correction_b)
			
			# Resolve velocity by canceling separating speed along the rope direction
			var rel_vel = player_b.velocity - player_a.velocity
			var vel_along_rope = rel_vel.dot(dir)
			if vel_along_rope > 0.0:
				var impulse = vel_along_rope
				player_a.velocity += dir * impulse * ratio_a
				player_b.velocity -= dir * impulse * ratio_b

	# 4. Render the rope
	if is_instance_valid(player_a):
		rope_points[0].position = player_a.global_position
	if is_instance_valid(player_b):
		rope_points[point_count - 1].position = player_b.global_position
		
	var render_points: Array[Vector2] = []
	var rx = 18.0
	var ry = 8.0
	
	# Loop around Player A's waist (waist is around y = 5) - only draw front half
	if is_instance_valid(player_a) and rope_points.size() > 1:
		var center_a = player_a.global_position + Vector2(0, 5)
		var dir_a = (rope_points[1].position - center_a).normalized()
		var start_angle = PI if dir_a.x >= 0.0 else 0.0
		var end_angle = 0.0 if dir_a.x >= 0.0 else PI
		for i in range(13):
			var t = float(i) / 12.0
			var angle = lerp(start_angle, end_angle, t)
			render_points.append(to_local(center_a + Vector2(cos(angle) * rx, sin(angle) * ry)))
	else:
		render_points.append(to_local(rope_points[0].position))
		
	# Middle segments
	for i in range(1, point_count - 1):
		render_points.append(to_local(rope_points[i].position))
		
	# Loop around Player B's waist - only draw front half
	if is_instance_valid(player_b) and rope_points.size() > 1:
		var center_b = player_b.global_position + Vector2(0, 5)
		var dir_b = (rope_points[point_count - 2].position - center_b).normalized()
		var start_angle = 0.0 if dir_b.x >= 0.0 else PI
		var end_angle = PI if dir_b.x >= 0.0 else 0.0
		for i in range(13):
			var t = float(i) / 12.0
			var angle = lerp(start_angle, end_angle, t)
			render_points.append(to_local(center_b + Vector2(cos(angle) * rx, sin(angle) * ry)))
	else:
		render_points.append(to_local(rope_points[point_count - 1].position))
		
	points = PackedVector2Array(render_points)


## --- Tension Calculations ---

# Returns the pulling force (tension) exerted on a specific player (directed towards the other player)
func get_tension_force_for_player(player: CharacterBody2D) -> Vector2:
	if not is_instance_valid(player_a) or not is_instance_valid(player_b):
		return Vector2.ZERO
		
	var partner = player_b if player == player_a else player_a
	if not is_instance_valid(partner):
		return Vector2.ZERO
		
	# Grounded platform protection: if a player is standing on a platform
	# but their partner is hanging in the void, the grounded player feels no pull.
	if player.is_on_floor() and not partner.is_on_floor():
		return Vector2.ZERO
		
	var diff = player_b.global_position - player_a.global_position
	var dist = diff.length()
	var max_rope_length = (point_count - 1) * current_segment_length
	
	if dist > max_rope_length:
		var stretch = dist - max_rope_length
		
		var active_stiffness = stiffness
		var max_force = 2500.0
		
		# High mechanical pull only when reeling a player hanging in the air
		if not player.is_on_floor():
			if current_segment_length < base_segment_length - 1.0:
				active_stiffness = stiffness * 4.0
				max_force = 6000.0
		else:
			# Grounded player: soft tension to prevent slingshotting/ejection
			max_force = 800.0
			
		var force_magnitude = stretch * active_stiffness * 60.0
		if force_magnitude > max_force:
			force_magnitude = max_force
			
		# Direction depends on which player is requesting
		var force = Vector2.ZERO
		if player == player_a:
			force = diff.normalized() * force_magnitude
		elif player == player_b:
			force = -diff.normalized() * force_magnitude
			
		# Cancel any upward force if we have reached or passed our partner's height
		partner = player_b if player == player_a else player_a
		if is_instance_valid(partner):
			if player.global_position.y <= partner.global_position.y + 15.0:
				if force.y < 0.0:
					force.y = 0.0
					
		return force
	return Vector2.ZERO




## --- Reeling/Pulling Mechanics ---

# Deprecated: Reeling is now handled automatically in _physics_process


## --- Server State Sync / Reconciliation ---

func get_state() -> Array:
	var state = []
	for p in rope_points:
		state.append(p.position)
	return state

func set_state(positions: Array) -> void:
	if positions.size() != rope_points.size():
		return
	for i in range(rope_points.size()):
		rope_points[i].position = positions[i]
		# Keep previous position aligned to prevent sudden velocity jumps
		rope_points[i].previous_position = positions[i]
