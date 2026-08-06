package main

import hm "core:container/handle_map"
import "core:fmt"
import la "core:math/linalg"
import b3 "vendor:box3d"
import sdl "vendor:sdl3"

Game_Actions :: enum {
	Movement,
	Run,
	Look,
	Jump,
}

Player :: struct {
	entity:      Handle,
	camera:      Handle,
	cam_pitch:   f32,
	cam_yaw:     f32,
	move_speed:  f32,
	look_sens:   f32,
	jump_height: f32,
}

Game :: struct {
	player:      Player,
	main_camera: Handle,
	controls:    [len(Game_Actions)]Input_Action,
}

game_init :: proc(game: ^Game, scene: ^Scene, input: ^Input, win: ^Window, phys: ^Physics) {
	player := &game.player
	player_entity: ^Entity
	cam_entity: ^Entity

	it := hm.iterator_make(&scene.entities)

	for e, h in hm.iterate(&it) {
		if e.name == "Player" {
			player.entity = h
		} else if .Camera in e.flags {
			game.main_camera = h
			player.camera = h

		}
	}

	// game.player.entity, player_entity = scene_get_new_entity(scene)
	//
	// set_position(&player_entity.transform, {5.0, 25.0, 5.0})
	// player_entity.name = "Player"
	// capsule := b3.Capsule {
	// 	center1 = {0.0, 1.8, 0.0},
	// 	center2 = {0.0, 0.0, 0.0},
	// 	radius  = 0.5,
	// }
	//
	// entity_add_rigidbody(scene, phys, player_entity, &capsule, .dynamicBody)
	//
	// game.main_camera, cam_entity = scene_get_new_entity(scene)
	// entity_add_camera(cam_entity, win)
	//
	// cam := &cam_entity.camera
	//
	// player.camera = game.main_camera
	// player.move_speed = 10.0
	// player.look_sens = 0.1
	// player.jump_height = 10.0


	game.controls[Game_Actions.Movement].control = Control_Axis2 {
		x = {
			negative = &input.sdl_keys[sdl.Scancode.A],
			positive = &input.sdl_keys[sdl.Scancode.D],
		},
		y = {
			negative = &input.sdl_keys[sdl.Scancode.S],
			positive = &input.sdl_keys[sdl.Scancode.W],
		},
	}

	game.controls[Game_Actions.Look].control = Control_Pointer {
		x = &input.mouse_delta.x,
		y = &input.mouse_delta.y,
	}

	game.controls[Game_Actions.Run].control = &input.sdl_keys[sdl.Scancode.LSHIFT]
	game.controls[Game_Actions.Jump].control = &input.sdl_keys[sdl.Scancode.SPACE]
}

game_move_player :: proc(game: ^Game, scene: ^Scene, input: ^Input) {
	player := &game.player
	player_entity := hm.get(&scene.entities, player.entity)
	rigidbody := &player_entity.rigidbody
	cam_entity := hm.get(&scene.entities, player.camera)

	look := &game.controls[Game_Actions.Look]
	move := &game.controls[Game_Actions.Movement]
	jump := &game.controls[Game_Actions.Jump]


	player.cam_yaw += look.value.x * player.look_sens
	player.cam_pitch += look.value.y * player.look_sens
	rot: [3]f32 = {player.cam_pitch, player.cam_yaw, 0.0}

	forward := get_forward(&player_entity.transform)
	right := get_right(&cam_entity.transform)
	forward = la.cross(right, [3]f32{0.0, 1.0, 0.0})
	move_dir := (forward * move.value.y) + (right * move.value.x)
	vel: [3]f32 = move_dir * player.move_speed
	vel.y = b3.Body_GetLinearVelocity(rigidbody.body_id).y
	b3.Body_SetLinearVelocity(rigidbody.body_id, vel)

	body_pos := b3.Body_GetWorldCenter(rigidbody.body_id)

	if jump.state == .Started {
		// b3.Body_ApplyForceToCenter(rigidbody.body_id, {0.0, player.jump_height, 0.0}, true)
		mass := b3.Body_GetMassData(rigidbody.body_id).mass
		b3.Body_ApplyLinearImpulseToCenter(
			rigidbody.body_id,
			{0.0, player.jump_height * mass, 0.0},
			true,
		)
	}

	set_euler_angles(&cam_entity.transform, rot, scene)
	pos := b3.Body_GetPosition(rigidbody.body_id)
	pos.y += 1.3
	set_position(&cam_entity.transform, ([3]f32)(pos), scene)

	fmt.println("Moving playing: ", move_dir)
}

game_update_camera :: proc(game: ^Game, scene: ^Scene) {
	cam_entity := hm.get(&scene.entities, game.main_camera)
	cam := &cam_entity.camera

	cam.view = la.matrix4_inverse(cam_entity.transform.world_transform)
	cam.proj = la.matrix4_perspective_f32(
		la.to_radians(cam.fov),
		cam.aspect,
		cam.near,
		cam.far,
		false,
	)

	cam.proj[1][1] *= -1.0
}

game_update :: proc(game: ^Game, scene: ^Scene, input: ^Input) {
	profile_scoped()
	input_update_controls(game.controls[:])
	game_move_player(game, scene, input)
	game_update_camera(game, scene)
}
