class_name Player
extends CharacterBody3D

enum ROLES {HUNTER, PROP}
enum ANIMATIONS {JUMP_UP, JUMP_DOWN, STRAFE, WALK}

const DIRECTION_INTERPOLATE_SPEED = 1
const MOTION_INTERPOLATE_SPEED = 10
const ROTATION_INTERPOLATE_SPEED = 10

const MIN_AIRBORNE_TIME = 0.1
const JUMP_SPEED = 5

var airborne_time = 100

var orientation = Transform3D()
var root_motion = Transform3D()
var motion = Vector2()

@onready var initial_position = transform.origin
@onready var gravity = ProjectSettings.get_setting("physics/3d/default_gravity") * ProjectSettings.get_setting("physics/3d/default_gravity_vector")

@export var health = 4

@onready var player_input = $InputSynchronizer
@onready var animation_tree = $AnimationTree
@onready var player_model = $PlayerModel
@onready var shoot_from = player_model.get_node("Robot_Skeleton/Skeleton3D/GunBone/ShootFrom")
@onready var crosshair = $Crosshair
@onready var fire_cooldown = $FireCooldown

@onready var sound_effects = $SoundEffects
@onready var sound_effect_jump = sound_effects.get_node("Jump")
@onready var sound_effect_land = sound_effects.get_node("Land")
@onready var sound_effect_shoot = sound_effects.get_node("Shoot")

@export var player_id := 1 :
	set(value):
		player_id = value
		$InputSynchronizer.set_multiplayer_authority(value)

@export var player_role := ROLES.PROP

@export var current_animation := ANIMATIONS.WALK

func _ready():
	# Pre-initialize orientation transform.
	orientation = player_model.global_transform
	orientation.origin = Vector3()
	if not multiplayer.is_server():
		set_process(false)


func _physics_process(delta: float):
	if multiplayer.is_server():
		apply_input(delta)
	else:
		animate(current_animation, delta)


func animate(anim: int, delta:=0.0):
	current_animation = anim

	if anim == ANIMATIONS.JUMP_UP:
		animation_tree["parameters/state/transition_request"] = "jump_up"

	elif anim == ANIMATIONS.JUMP_DOWN:
		animation_tree["parameters/state/transition_request"] = "jump_down"

	elif anim == ANIMATIONS.STRAFE:
		animation_tree["parameters/state/transition_request"] = "strafe"
		# Change aim according to camera rotation.
		animation_tree["parameters/aim/add_amount"] = player_input.get_aim_rotation()
		# The animation's forward/backward axis is reversed.
		animation_tree["parameters/strafe/blend_position"] = Vector2(motion.x, -motion.y)

	elif anim == ANIMATIONS.WALK:
		# Aim to zero (no aiming while walking).
		animation_tree["parameters/aim/add_amount"] = 0
		# Change state to walk.
		animation_tree["parameters/state/transition_request"] = "walk"
		# Blend position for walk speed based checked motion.
		animation_tree["parameters/walk/blend_position"] = Vector2(motion.length(), 0)


func apply_input(delta: float):
	if player_input.hunter_blindness: # dont process if we are blinded
		return
	motion = motion.lerp(player_input.motion, MOTION_INTERPOLATE_SPEED * delta)

	var camera_basis : Basis = player_input.get_camera_rotation_basis()
	var camera_z := camera_basis.z
	var camera_x := camera_basis.x

	camera_z.y = 0
	camera_z = camera_z.normalized()
	camera_x.y = 0
	camera_x = camera_x.normalized()

	# Jump/in-air logic.
	airborne_time += delta
	if is_on_floor():
		if airborne_time > 0.5:
			land.rpc()
		airborne_time = 0

	var on_air = airborne_time > MIN_AIRBORNE_TIME

	if not on_air and player_input.jumping:
		print("TEST")
		velocity.y = JUMP_SPEED
		on_air = true
		# Increase airborne time so next frame on_air is still true
		airborne_time = MIN_AIRBORNE_TIME
		jump.rpc()

	player_input.jumping = false

	if player_input.taking_damage:
		take_damage.rpc()

	if player_input.return_normal:
		#transform_to_normal()
		transform_to_normal.rpc()
	
	if player_input.change_role:
		change_role.rpc()
	
	if player_input.transforming:
		#transform_to_prop(player_input.currentProp)
		transform_to_prop.rpc(player_input.currentProp)

	if on_air:
		if (velocity.y > 0):
			animate(ANIMATIONS.JUMP_UP, delta)
		else:
			animate(ANIMATIONS.JUMP_DOWN, delta)
	elif player_input.aiming:
		# Convert orientation to quaternions for interpolating rotation.
		var q_from = orientation.basis.get_rotation_quaternion()
		var q_to = player_input.get_camera_base_quaternion()
		# Interpolate current rotation with desired one.
		orientation.basis = Basis(q_from.slerp(q_to, delta * ROTATION_INTERPOLATE_SPEED))

		# Change state to strafe.
		animate(ANIMATIONS.STRAFE, delta)

		root_motion = Transform3D(animation_tree.get_root_motion_rotation(), animation_tree.get_root_motion_position())
		

		if player_input.shooting and fire_cooldown.time_left == 0:
			var shoot_origin = shoot_from.global_transform.origin
			var shoot_dir = (player_input.shoot_target - shoot_origin).normalized()

			var bullet = preload("res://player/bullet/bullet.tscn").instantiate()
			get_parent().add_child(bullet, true)
			bullet.global_transform.origin = shoot_origin
			# If we don't rotate the bullets there is no useful way to control the particles ..
			bullet.look_at(shoot_origin + shoot_dir, Vector3.UP)
			bullet.add_collision_exception_with(self)
			shoot.rpc()

	if !player_input.aiming: # Not in air or aiming, idle.
		# Convert orientation to quaternions for interpolating rotation.
		var target = camera_x * motion.x + camera_z * motion.y
		if target.length() > 0.001:
			var q_from = orientation.basis.get_rotation_quaternion()
			var q_to = Transform3D().looking_at(target, Vector3.UP).basis.get_rotation_quaternion()
			# Interpolate current rotation with desired one.
			orientation.basis = Basis(q_from.slerp(q_to, delta * ROTATION_INTERPOLATE_SPEED))

		animate(ANIMATIONS.WALK, delta)

		root_motion = Transform3D(animation_tree.get_root_motion_rotation(), animation_tree.get_root_motion_position())

	# Apply root motion to orientation.
	orientation *= root_motion

	var h_velocity = orientation.origin / delta
	velocity.x = h_velocity.x
	velocity.z = h_velocity.z
	velocity += gravity * delta
	set_velocity(velocity)
	set_up_direction(Vector3.UP)
	move_and_slide()

	orientation.origin = Vector3() # Clear accumulated root motion displacement (was applied to speed).
	orientation = orientation.orthonormalized() # Orthonormalize orientation.

	if !player_input.rotation_lock:
		player_model.global_transform.basis = orientation.basis

	# If we're below -40, respawn (teleport to the initial position).
	if transform.origin.y < -40:
		transform.origin = initial_position


@rpc("call_local")
func jump():
	animate(ANIMATIONS.JUMP_UP)
	#sound_effect_jump.play()


@rpc("call_local")
func land():
	animate(ANIMATIONS.JUMP_DOWN)
	#sound_effect_land.play()

@rpc("call_local")
func transform_to_prop(prop):
	var propModel = get_node("PlayerModel/PropModel")
	var playerModel = get_node("PlayerModel/Robot_Skeleton")
	player_input.transforming = false
	
	var newProp = null
	
	# Check to see if we are already a prop
	if propModel.get_child_count() > 0:
		for child in propModel.get_children():
			child.queue_free()
	
	if PropsList.props_list.has(prop):
		playerModel.visible = false
		propModel.visible = true
		newProp = PropsList.props_list[prop].instantiate()
		newProp.transform = playerModel.transform
		print(prop)
		for child in newProp.get_children():
			if child is CollisionShape3D:
				child.disabled = true
		
		if multiplayer.is_server():
			propModel.scale = Vector3(1.2, 1.2, 1.2)
		propModel.add_child(newProp, true)
	

@rpc("call_local")
func transform_to_normal():
	print(name + " transforming to normal")
	var propModel = get_node("PlayerModel/PropModel")
	var playerModel = get_node("PlayerModel/Robot_Skeleton")
	player_input.return_normal = false
	
	if propModel.get_child_count() > 0:
		for child in propModel.get_children():
			child.queue_free()
	
	playerModel.visible = true
	propModel.visible = false

@rpc("call_local")
func change_role(role : int = 2):
	if role != 2:
		player_role = role
	else:
		
		player_input.change_role = false
		if player_role == ROLES.PROP:
			player_role = ROLES.HUNTER
			print(name + " is now a Hunter")
			get_node("HunterBlindnessTimer").start()
			player_input.hunter_blindness = true
		else:
			player_role = ROLES.PROP
			print(name + " is now a Prop")

@rpc("call_local")
func change_role_found():
	player_input.change_role = false
	if player_role == ROLES.PROP:
		player_role = ROLES.HUNTER
		print(name + " is now a Hunter")
	else:
		player_role = ROLES.PROP
		print(name + " is now a Prop")

@rpc("any_peer", "call_local")
func take_damage():
	print("Health before: " + str(health))
	if player_role == ROLES.HUNTER:
		print(name + " taking damage!")
		player_input.taking_damage = false
		health -= 1
		print("Health after: " + str(health))
	if player_role == ROLES.PROP:
		print(name + " has been found!")
		transform_to_normal.rpc()
		change_role_found.rpc()

@rpc("call_local", "any_peer")
func respawn():
	transform = get_parent().get_parent().get_node("Respawn Point").transform

@rpc("call_local")
func shoot():
	var shoot_particle = $PlayerModel/Robot_Skeleton/Skeleton3D/GunBone/ShootFrom/ShootParticle
	shoot_particle.restart()
	shoot_particle.emitting = true
	var muzzle_particle = $PlayerModel/Robot_Skeleton/Skeleton3D/GunBone/ShootFrom/MuzzleFlash
	muzzle_particle.restart()
	muzzle_particle.emitting = true
	fire_cooldown.start()
	sound_effect_shoot.play()
	add_camera_shake_trauma(0.35)


@rpc("call_local")
func hit():
	add_camera_shake_trauma(.75)


@rpc("call_local")
func add_camera_shake_trauma(amount):
	player_input.camera_camera.add_trauma(amount)

