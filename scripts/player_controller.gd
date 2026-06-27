extends CharacterBody2D
class_name PlayerController

# PlayerController.gd
# Handles player physics, inputs, and client-side prediction / server reconciliation.

# Movement Constants
const SPEED = 200.0
const GRAVITY = 800.0
const ANCHOR_FRICTION = 0.9 # High deceleration when anchored
const NORMAL_FRICTION = 0.15

# Mass / Physics weight
const NORMAL_MASS = 1.0
const ANCHOR_MASS = 15.0

# Network Tick / Sync State
var current_tick: int = 0
var input_buffer: Array[Dictionary] = [] # [{tick, dir, pull}]
var state_buffer: Array[Dictionary] = [] # [{tick, pos, vel, anchored}]

# Remote State Interpolation (for non-local players)
var target_position: Vector2
var target_velocity: Vector2
var interp_factor: float = 15.0

# Reference to the Rope nodes
var ropes: Array[RopePhysics] = []
var is_anchored: bool = false
var current_mass: float = NORMAL_MASS
var is_dummy: bool = false # Controlled by simple gravity/rope simulation offline
var player_index: int = 1: # 1 for Player 1, 2 for Player 2
	set(val):
		player_index = val
		if is_node_ready():
			_update_player_visuals()
var is_offline: bool = true
var controls_enabled: bool = true
var sync_timer: float = 0.0

# Voice Chat variables
var voice_capture_effect: AudioEffectCapture = null
var voice_playback_player: AudioStreamPlayer = null
var voice_playback: AudioStreamGeneratorPlayback = null
var mic_active: bool = false




# Node References
@onready var collision_shape = $CollisionShape2D

func _ready() -> void:
	is_offline = (multiplayer.multiplayer_peer == null)
	
	# Set authority dynamically based on node name
	if not is_offline and name.is_valid_int():
		set_multiplayer_authority(name.to_int())
		
	print("INFO: Player script loaded! Name: ", name, " | IsDummy: ", is_dummy, " | Index: ", player_index, " | Offline: ", is_offline)
	target_position = global_position
	# Disable player-on-player platform velocity inheritance (Layer 2 is players, Layer 1 is platforms)
	platform_floor_layers = 1
		
	# Initialize visual shape and coloring
	_update_player_visuals()

	# Initialize voice chat (if not running headlessly)
	if DisplayServer.get_name() != "headless":
		_setup_voice_playback()
		if is_multiplayer_authority() and not is_dummy:
			_setup_voice_capture()


func _physics_process(delta: float) -> void:
	var game_node = get_node_or_null("/root/Game")
	if game_node and game_node.lobby_is_active:
		velocity = Vector2.ZERO
		return

	# Platform phase-through logic when being pulled
	# Platform phase-through logic when being pulled
	var is_pulling = false
	var partner = null
	for r in ropes:
		if is_instance_valid(r):
			var other = r.player_b if r.player_a == self else r.player_a
			if is_instance_valid(other):
				if (is_instance_valid(r.player_a) and r.player_a.is_anchored) or (is_instance_valid(r.player_b) and r.player_b.is_anchored):
					is_pulling = true
					partner = other
					break
			
	if is_pulling and is_instance_valid(partner):
		# Ignore platform collisions (Layer 1) if in the air, below partner, and partner is grounded
		if not is_on_floor() and partner.is_on_floor() and global_position.y > partner.global_position.y - 10.0:
			set_collision_mask_value(1, false)
		else:
			# Transition frame: just re-enabling collision. Snap to floor and kill upward inertia.
			if not is_on_floor() and get_collision_mask_value(1) == false:
				global_position.y = partner.global_position.y
				if velocity.y < 0.0:
					velocity.y = 0.0
			set_collision_mask_value(1, true)
	else:
		set_collision_mask_value(1, true)


	if is_offline:
		# Offline / Singleplayer mode testing

		if is_dummy:
			# Dummy player logic: only feels gravity and rope tension
			velocity.y += GRAVITY * delta
			for r in ropes:
				if is_instance_valid(r):
					var t_force = r.get_tension_force_for_player(self)
					velocity += (t_force / current_mass) * delta
			_move_and_push()
			
			# Visual feedback

			var shield = get_node_or_null("AnchorShield")
			if shield:
				shield.visible = is_anchored
		else:
			# Controllable player
			var input = _get_local_input()
			if input.dir != 0.0 or input.pull:
				print("DEBUG INPUT: Player ", name, " (idx=", player_index, ") dir=", input.dir, " pull=", input.pull)
			_apply_movement_logic(input, delta)
			_move_and_push()
		return

	current_tick += 1

	# Periodically broadcast controlled player's position to other peers as a safety sync
	if is_multiplayer_authority():
		sync_timer += delta
		if sync_timer >= 1.0:
			sync_timer = 0.0
			force_sync_position.rpc(global_position, velocity)

	if multiplayer.is_server():
		# SERVER AUTHORITY LOGIC (Runs on Server/Host for ALL players)
		var input: Dictionary
		if is_multiplayer_authority():
			# This is the Host Player (Player 1) on the Server
			input = _get_local_input()
			input["tick"] = current_tick
		else:
			# This is a Client Player (Player 2, etc.) on the Server
			input = _get_next_input_for_tick(current_tick)
			
		# Apply movement & move
		_apply_movement_logic(input, delta)
		_move_and_push()
		
		# Server broadcasts the authoritative state of this player to all clients
		_broadcast_state.rpc(current_tick, global_position, velocity, is_anchored)
		
	else:
		# CLIENT LOGIC (Runs on Clients)
		if is_multiplayer_authority():
			# This is the local client player (Player 2) on its own client
			var input = _get_local_input()
			input["tick"] = current_tick
			
			# Record input for reconciliation
			input_buffer.append(input)
			if input_buffer.size() > 120:
				input_buffer.remove_at(0)
				
			# Predict movement locally
			_apply_movement_logic(input, delta)
			_move_and_push()
			
			# Record predicted state
			var state = {
				"tick": current_tick,
				"position": global_position,
				"velocity": velocity,
				"is_anchored": is_anchored
			}
			state_buffer.append(state)
			if state_buffer.size() > 120:
				state_buffer.remove_at(0)
				
			# Send input to server
			_send_input_to_server.rpc_id(1, input)
		else:
			# This is a remote player (e.g., Host Player 1) on the client
			# Smoothly interpolate to the last received server state
			global_position = global_position.lerp(target_position, interp_factor * delta)
			velocity = velocity.lerp(target_velocity, interp_factor * delta)

## --- Input Sampling ---

func _get_local_input() -> Dictionary:
	var dir = 0.0
	var pull = false
	
	if is_offline:
		# Offline / Singleplayer mode testing - Split Keyboard controls
		if player_index == 1:
			# Player 1: Q/A for left, D for right
			if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_Q):
				dir = -1.0
			elif Input.is_key_pressed(KEY_D):
				dir = 1.0
			
			# Touch controls fallback (invisible drag/tap controls)
			var game_node = get_node_or_null("/root/Game")
			if game_node:
				if abs(game_node.touch_dir) > 0.01:
					dir = game_node.touch_dir
				if game_node.touch_pull:
					pull = true
					game_node.touch_pull = false # consume
		else:
			# Player 2: Arrow keys for movement, Shift/Up/Tab for pull
			if Input.is_key_pressed(KEY_LEFT):
				dir = -1.0
			elif Input.is_key_pressed(KEY_RIGHT):
				dir = 1.0
				
			if Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_TAB):
				pull = true
	else:
		# Online / Multiplayer mode: Standard inputs mapped for each local authority client
		if Input.is_action_pressed("ui_left"):
			dir = -1.0
		elif Input.is_action_pressed("ui_right"):
			dir = 1.0
		
		# Touch controls fallback
		var game_node = get_node_or_null("/root/Game")
		if game_node:
			if abs(game_node.touch_dir) > 0.01:
				dir = game_node.touch_dir
			if game_node.touch_pull:
				pull = true
				game_node.touch_pull = false # consume

	return {
		"tick": 0,
		"dir": dir,
		"pull": pull
	}


## --- Physics & Movement Logic ---

func _apply_movement_logic(input: Dictionary, delta: float) -> void:
	# Unpack inputs
	var dir = input.get("dir", 0.0)
	var pull = input.get("pull", false)
	
	if not controls_enabled:
		dir = 0.0
		pull = false
		
	is_anchored = pull
	
	# We can only anchor (become heavy and static) if we are standing on a platform!
	if is_anchored and is_on_floor():
		current_mass = ANCHOR_MASS
		velocity.x = lerp(velocity.x, 0.0, ANCHOR_FRICTION)
	else:
		current_mass = NORMAL_MASS
		if is_on_floor():
			if dir != 0.0:
				velocity.x = dir * SPEED
			else:
				velocity.x = lerp(velocity.x, 0.0, NORMAL_FRICTION)
		else:
			# Mid-air/void swing control: apply soft horizontal force instead of overriding velocity.
			# Also reduce damping/air resistance to conserve pendulum swing momentum.
			if dir != 0.0:
				var air_accel = 300.0
				velocity.x += dir * air_accel * delta
			else:
				velocity.x = lerp(velocity.x, 0.0, NORMAL_FRICTION * 0.15)


	# Gravity
	velocity.y += GRAVITY * delta

	# Apply Rope Tension Force (Physics feedback)
	for r in ropes:
		if is_instance_valid(r):
			var tension_force = r.get_tension_force_for_player(self)
			# Divide tension by mass (heavier / anchored players are pulled less)
			velocity += (tension_force / current_mass) * delta

	# Clamp velocity to prevent physical glitches/slingshots
	velocity.x = clamp(velocity.x, -400.0, 400.0)
	velocity.y = clamp(velocity.y, -600.0, 1000.0)



	# Visual updates for rich aesthetics
	var shield = get_node_or_null("AnchorShield")
	if shield:
		shield.visible = is_anchored
	var body = get_node_or_null("Body")
	if body and dir != 0.0:
		body.scale.x = sign(dir)

## --- Server Input Queue ---

var server_input_queue: Array[Dictionary] = []

@rpc("any_peer", "call_local", "unreliable")
func _send_input_to_server(input: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	# Validate client authority
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != get_multiplayer_authority():
		return
	server_input_queue.append(input)
	# Limit server queue size to prevent memory leak under bad network
	if server_input_queue.size() > 60:
		server_input_queue.remove_at(0)

func _get_next_input_for_tick(tick: int) -> Dictionary:
	# Try to find input for exact tick
	for i in range(server_input_queue.size()):
		if server_input_queue[i]["tick"] == tick:
			var input = server_input_queue[i]
			# Keep queue small by discarding older processed ticks
			while server_input_queue.size() > 0 and server_input_queue[0]["tick"] <= tick:
				server_input_queue.remove_at(0)
			return input
			
	# Fallback: if we miss a tick due to packet loss/lag, repeat the last known input
	if server_input_queue.size() > 0:
		return server_input_queue[-1]
		
	# absolute fallback
	return {"tick": tick, "dir": 0.0, "jump": false, "pull": false}

## --- Server State Broadcasting & Client Reconciliation ---

@rpc("any_peer", "call_local", "unreliable")
func _broadcast_state(tick: int, server_pos: Vector2, server_vel: Vector2, server_anchored: bool) -> void:
	if multiplayer.is_server():
		return # Server doesn't reconcile itself
		
	# Security check: only accept state broadcasts from the server (peer 1)
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != 1 and sender_id != 0:
		return
		
	if is_multiplayer_authority():
		# Local Player: Reconcile predicted state with server authority
		_reconcile_state(tick, server_pos, server_vel, server_anchored)
	else:
		# Remote Player: Set target position for interpolation
		target_position = server_pos
		target_velocity = server_vel
		is_anchored = server_anchored

func _reconcile_state(server_tick: int, server_pos: Vector2, server_vel: Vector2, server_anchored: bool) -> void:
	# Find the state in our local history buffer matching the server tick
	var matching_state_idx = -1
	for i in range(state_buffer.size()):
		if state_buffer[i]["tick"] == server_tick:
			matching_state_idx = i
			break
			
	if matching_state_idx != -1:
		var local_state = state_buffer[matching_state_idx]
		var pos_error = local_state["position"].distance_to(server_pos)
		
		# Reconcile if position error exceeds safety threshold (0.5 pixels)
		if pos_error > 0.5:
			# Desync detected! Reset player to server authority state
			global_position = server_pos
			velocity = server_vel
			is_anchored = server_anchored
			
			# Clean history buffers up to the server tick
			state_buffer = state_buffer.slice(matching_state_idx + 1)
			
			# Replay inputs from server_tick + 1 to current_tick
			var input_start_idx = -1
			for i in range(input_buffer.size()):
				if input_buffer[i]["tick"] == server_tick:
					input_start_idx = i + 1
					break
					
			if input_start_idx != -1:
				input_buffer = input_buffer.slice(input_start_idx)
				# Replay steps
				var delta = get_physics_process_delta_time()
				for replay_input in input_buffer:
					_apply_movement_logic(replay_input, delta)
					_move_and_push()
					# Re-save replayed states
					var replayed_state = {
						"tick": replay_input["tick"],
						"position": global_position,
						"velocity": velocity,
						"is_anchored": is_anchored
					}
					state_buffer.append(replayed_state)
		else:
			# No desync or below threshold. Clear old history to save memory.
			state_buffer = state_buffer.slice(matching_state_idx + 1)
			# Clean input buffer as well
			var input_clean_idx = -1
			for i in range(input_buffer.size()):
				if input_buffer[i]["tick"] == server_tick:
					input_clean_idx = i
					break
			if input_clean_idx != -1:
				input_buffer = input_buffer.slice(input_clean_idx + 1)
	else:
		# If the server tick is not in our buffer, we are out of sync.
		# Snap to server state and synchronize our current_tick to the server tick!
		global_position = server_pos
		velocity = server_vel
		is_anchored = server_anchored
		current_tick = server_tick
		state_buffer.clear()
		input_buffer.clear()


func _get_partner() -> PlayerController:
	for r in ropes:
		if is_instance_valid(r):
			var partner = r.player_b if r.player_a == self else r.player_a
			if is_instance_valid(partner):
				return partner
	var players = get_tree().get_nodes_in_group("players")
	for p in players:
		if p != self and p is PlayerController:
			return p
	return null

func _get_stacked_player() -> PlayerController:
	var players = get_tree().get_nodes_in_group("players")
	for p in players:
		if p != self and p is PlayerController:
			if is_player_on_top(p):
				return p
	return null

func carry_stacked_players(disp: Vector2) -> void:
	var stacked = _get_stacked_player()
	if is_instance_valid(stacked):
		stacked.move_and_collide(disp)
		stacked.carry_stacked_players(disp)

func is_player_on_top(other: PlayerController) -> bool:
	if not is_instance_valid(other):
		return false
	# other is above self. y-distance center-to-center is ~60px
	var y_dist = self.global_position.y - other.global_position.y
	if y_dist > 54.0 and y_dist < 66.0:
		# Width is 32, so overlap occurs when centers are within 32 pixels
		var x_dist = abs(self.global_position.x - other.global_position.x)
		if x_dist < 32.0:
			return true
	return false

func _move_and_push() -> void:
	# 1. Store position to compute actual displacement
	var prev_pos = global_position
	
	# 2. Perform movement
	move_and_slide()
	
	# 3. Compute displacement and carry stacked players recursively
	var displacement = global_position - prev_pos
	var stacked_player = _get_stacked_player()
	if is_instance_valid(stacked_player):
		stacked_player.move_and_collide(displacement)
		stacked_player.carry_stacked_players(displacement)
		
	# 4. Push other players horizontally
	if not is_instance_valid(stacked_player):
		for i in get_slide_collision_count():
			var collision = get_slide_collision(i)
			var collider = collision.get_collider()
			if collider is PlayerController and collider != self:
				var push_dir = -collision.get_normal()
				# Push horizontally if moving against each other
				if abs(push_dir.x) > 0.5:
					collider.velocity.x += push_dir.x * (SPEED * 0.8) / collider.current_mass


func _update_player_visuals() -> void:
	# Set static collision layer and mask based on player index to prevent locking
	# Player 1 is Layer 2, Player 2 is Layer 3, etc.
	collision_layer = 0
	set_collision_layer_value(player_index + 1, true)
	
	# Always collide with platforms (Layer 1)
	collision_mask = 0
	set_collision_mask_value(1, true)
	# Collide with the player directly below us in the stack
	if player_index > 1:
		set_collision_mask_value(player_index, true)

	# 1. Update Body capsule polygon
	var body = get_node_or_null("Body")
	if body:
		body.polygon = _generate_capsule_polygon(32.0, 60.0, 16)
		# Set colors based on player index
		if player_index == 1:
			body.color = Color("#0091ff") # Vibrant Blue
		elif player_index == 2:
			body.color = Color("#b624ff") # Vibrant Purple
		elif player_index == 3:
			body.color = Color("#ffd54f") # Vibrant Yellow
		else:
			body.color = Color("#ff6d00") # Vibrant Orange
			
	# 2. Update LeftEye and RightEye to be small capsules
	var left_eye = get_node_or_null("Body/LeftEye")
	if left_eye:
		left_eye.polygon = _generate_capsule_polygon(6.0, 12.0, 8)
		left_eye.position = Vector2(-6, -8)
		left_eye.color = Color(1, 1, 1, 1)
		
	var right_eye = get_node_or_null("Body/RightEye")
	if right_eye:
		right_eye.polygon = _generate_capsule_polygon(6.0, 12.0, 8)
		right_eye.position = Vector2(6, -8)
		right_eye.color = Color(1, 1, 1, 1)
		
	# 3. Update pupils to be smaller black capsules
	var left_pupil = get_node_or_null("Body/LeftEye/LeftPupil")
	if left_pupil:
		left_pupil.polygon = _generate_capsule_polygon(3.0, 6.0, 8)
		left_pupil.position = Vector2(0, 1)
		left_pupil.color = Color(0.05, 0.05, 0.1, 1)
		
	var right_pupil = get_node_or_null("Body/RightEye/RightPupil")
	if right_pupil:
		right_pupil.polygon = _generate_capsule_polygon(3.0, 6.0, 8)
		right_pupil.position = Vector2(0, 1)
		right_pupil.color = Color(0.05, 0.05, 0.1, 1)

func _generate_capsule_polygon(width: float, height: float, segments: int = 16) -> PackedVector2Array:
	var points = PackedVector2Array()
	var r = width / 2.0
	var cap_h = height / 2.0 - r
	
	# Top arc
	for i in range(segments + 1):
		var angle = PI + (i * PI / segments)
		var px = r * cos(angle)
		var py = -cap_h + r * sin(angle)
		points.append(Vector2(px, py))
		
	# Bottom arc
	for i in range(segments + 1):
		var angle = i * PI / segments
		var px = r * cos(angle)
		var py = cap_h + r * sin(angle)
		points.append(Vector2(px, py))
		
	return points

func _process(delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
		
	# Animate pupils based on velocity and body scale
	var left_pupil = get_node_or_null("Body/LeftEye/LeftPupil")
	var right_pupil = get_node_or_null("Body/RightEye/RightPupil")
	var body = get_node_or_null("Body")
	if left_pupil and right_pupil and body:
		var target_x = 0.0
		if abs(velocity.x) > 10.0:
			target_x = sign(velocity.x) * body.scale.x * 1.5
		# LERP x offset
		left_pupil.position.x = lerp(left_pupil.position.x, target_x, 15.0 * delta)
		right_pupil.position.x = lerp(right_pupil.position.x, target_x, 15.0 * delta)

	# Voice capture
	if is_multiplayer_authority() and not is_dummy and mic_active and voice_capture_effect:
		var available = voice_capture_effect.get_frames_available()
		if available > 0:
			var stereo_frames = voice_capture_effect.get_buffer(available)
			var mono_data = PackedFloat32Array()
			mono_data.resize(stereo_frames.size())
			for i in range(stereo_frames.size()):
				mono_data[i] = (stereo_frames[i].x + stereo_frames[i].y) * 0.5
			
			if not is_offline:
				receive_voice_data.rpc(mono_data)


@rpc("any_peer", "call_local", "reliable")
func force_sync_position(forced_pos: Vector2, forced_vel: Vector2) -> void:
	# If we are the authority of this player, we don't overwrite ourselves
	if is_multiplayer_authority():
		return
		
	# If we are remote, check desync distance
	var dist = global_position.distance_to(forced_pos)
	if dist > 15.0: # threshold of 15 pixels
		# Snap position and velocity
		global_position = forced_pos
		velocity = forced_vel
		# Update target_position/velocity for remote interpolation
		target_position = forced_pos
		target_velocity = forced_vel
		
	# If we are the server/host, we should forward this forced position to other clients
	if multiplayer.is_server():
		for peer_id in multiplayer.get_peers():
			if peer_id != get_multiplayer_authority():
				force_sync_position.rpc_id(peer_id, forced_pos, forced_vel)


## --- Voice Chat Methods ---

func _setup_voice_playback() -> void:
	var generator = AudioStreamGenerator.new()
	generator.mix_rate = AudioServer.get_mix_rate()
	generator.buffer_length = 0.5 # 500ms buffer
	
	voice_playback_player = AudioStreamPlayer.new()
	voice_playback_player.name = "VoicePlaybackPlayer"
	voice_playback_player.stream = generator
	voice_playback_player.bus = "Master"
	add_child(voice_playback_player)
	voice_playback_player.play()
	
	voice_playback = voice_playback_player.get_stream_playback()

func _setup_voice_capture() -> void:
	var record_bus_idx = AudioServer.get_bus_index("Record")
	if record_bus_idx == -1:
		AudioServer.add_bus()
		record_bus_idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(record_bus_idx, "Record")
		AudioServer.set_bus_mute(record_bus_idx, true) # Mute so player doesn't hear their own echo
		
		var capture = AudioEffectCapture.new()
		AudioServer.add_bus_effect(record_bus_idx, capture)
		
	var mic_player = AudioStreamPlayer.new()
	mic_player.name = "MicPlayer"
	mic_player.stream = AudioStreamMicrophone.new()
	mic_player.bus = "Record"
	add_child(mic_player)
	mic_player.play()
	
	voice_capture_effect = AudioServer.get_bus_effect(record_bus_idx, 0)

func toggle_microphone() -> bool:
	mic_active = not mic_active
	if not mic_active and voice_capture_effect:
		var available = voice_capture_effect.get_frames_available()
		if available > 0:
			var _discard = voice_capture_effect.get_buffer(available)
	print("Microphone active state toggled to: ", mic_active)
	return mic_active


@rpc("any_peer", "call_local", "unreliable_ordered")
func receive_voice_data(data: PackedFloat32Array) -> void:
	if is_multiplayer_authority():
		return # Do not play back our own voice
		
	var game_node = get_node_or_null("/root/Game")
	if game_node and game_node.get("mute_others") == true:
		return # Muted others, discard
		
	if voice_playback:
		var frames = PackedVector2Array()
		frames.resize(data.size())
		for i in range(data.size()):
			var val = data[i]
			frames[i] = Vector2(val, val)
			
		var space = voice_playback.get_frames_available()
		if space < frames.size():
			frames = frames.slice(0, space)
		if frames.size() > 0:
			voice_playback.push_buffer(frames)
