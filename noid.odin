package noid

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:os"
import "core:strings"
import rl "vendor:raylib"

SCREEN_SIZE_X :: 512
SCREEN_SIZE_Y :: 448
SIDEBAR_WIDTH :: 102
WALL_THICKNESS :: 5
LEFT_WALL_X :: WALL_THICKNESS
RIGHT_WALL_X :: SCREEN_SIZE_X - SIDEBAR_WIDTH - WALL_THICKNESS
TOP_WALL_Y :: WALL_THICKNESS
PLAY_AREA_WIDTH :: RIGHT_WALL_X - LEFT_WALL_X // Must be evenly divisible by NUM_BLOCKS_X
PADDLE_WIDTH :: 50
PADDLE_HEIGHT :: 6
PADDLE_POS_Y :: SCREEN_SIZE_Y - 50
BALL_SPEED :: 250
BALL_RADIUS :: 4
BALL_START_Y :: SCREEN_SIZE_Y / 3 * 2
NUM_BLOCKS_X :: 10
NUM_BLOCKS_Y :: 16
BLOCK_WIDTH :: PLAY_AREA_WIDTH / NUM_BLOCKS_X
BLOCK_HEIGHT :: 15
EXTRA_LIFE_SCORE :: 2500
PHYSICS_TICK_RATE :: 120
MOUSE_SENSITIVITY :: 50 // 0-100

Block_Color :: enum u8 {
	Empty,
	White,
	Cyan,
	Blue,
	Green,
	Yellow,
	Red,
	Pink,
	Orange,
	Steel,
	DamagedSteel,
	Adamantium,
}

block_color_values := [Block_Color]rl.Color {
	.Empty        = rl.Color{0, 0, 0, 0},
	.White        = rl.LIGHTGRAY,
	.Cyan         = rl.SKYBLUE,
	.Blue         = rl.DARKBLUE,
	.Green        = rl.LIME,
	.Yellow       = rl.YELLOW,
	.Red          = rl.MAROON,
	.Pink         = rl.PINK,
	.Orange       = rl.ORANGE,
	.Steel        = rl.GRAY,
	.DamagedSteel = rl.DARKGRAY,
	.Adamantium   = rl.GOLD,
}

block_color_score := [Block_Color]int {
	.Empty        = 0,
	.White        = 10,
	.Cyan         = 20,
	.Blue         = 40,
	.Green        = 60,
	.Yellow       = 80,
	.Red          = 100,
	.Pink         = 150,
	.Orange       = 200,
	.Steel        = 10,
	.DamagedSteel = 250,
	.Adamantium   = 25,
}

blocks: [NUM_BLOCKS_X][NUM_BLOCKS_Y]u8
paddle_pos_x: f32
ball_pos: rl.Vector2
ball_dir: rl.Vector2
started: bool
game_over: bool
blocks_left: int
score: int
extra_life: int
lives: int
accumulated_time: f32
previous_ball_pos: rl.Vector2
previous_paddle_pos_x: f32
chapter: int = 1
level: int = 2

reset_paddle :: proc() {
	paddle_pos_x = PLAY_AREA_WIDTH / 2 - PADDLE_WIDTH / 2
	previous_paddle_pos_x = paddle_pos_x
	ball_pos = {PLAY_AREA_WIDTH / 2, BALL_START_Y}
	previous_ball_pos = ball_pos
	started = false
}

load_level :: proc(new_chapter, new_level: int) {
	blocks_left = 0
	chapter = new_chapter
	level = new_level

	level_path := fmt.tprintf("levels/%d/%d.txt", chapter, level)
	data, err := os.read_entire_file(level_path, context.allocator)
	defer delete(data, context.allocator)

	if err == nil {
		y := 0
		it := string(data)
		for row in strings.split_lines_iterator(&it) {
			assert(len(row) == NUM_BLOCKS_X)
			for x in 0 ..< NUM_BLOCKS_X {
				block_id := char_to_block_id(row[x])
				blocks[x][y] = block_id
				if block_id != u8(Block_Color.Empty) && block_id != u8(Block_Color.Adamantium) {
					blocks_left += 1
				}
			}
			y += 1
		}
	} else {
		for x in 0 ..< NUM_BLOCKS_X {
			for y in 0 ..< NUM_BLOCKS_Y {
				blocks[x][y] = 1
				blocks_left += 1
			}
		}
	}

	reset_paddle()
}

restart :: proc() {
	game_over = false
	score = 0
	extra_life = EXTRA_LIFE_SCORE
	lives = 2
	load_level(1, 1)
}

char_to_block_id :: proc(char: u8) -> u8 {
	switch char {
	case 'W':
		return u8(Block_Color.White)
	case 'C':
		return u8(Block_Color.Cyan)
	case 'B':
		return u8(Block_Color.Blue)
	case 'G':
		return u8(Block_Color.Green)
	case 'Y':
		return u8(Block_Color.Yellow)
	case 'R':
		return u8(Block_Color.Red)
	case 'P':
		return u8(Block_Color.Pink)
	case 'O':
		return u8(Block_Color.Orange)
	case 'S':
		return u8(Block_Color.Steel)
	case 'A':
		return u8(Block_Color.Adamantium)
	case:
		return u8(Block_Color.Empty)
	}
}

reflect :: proc(dir, normal: rl.Vector2) -> rl.Vector2 {
	new_direction := linalg.reflect(dir, linalg.normalize(normal))
	return linalg.normalize(new_direction)
}

negate :: proc(dir: rl.Vector2) -> rl.Vector2 {
	return dir * -1
}

calc_block_rect :: proc(x, y: int) -> rl.Rectangle {
	return {
		f32(LEFT_WALL_X + x * BLOCK_WIDTH),
		f32(TOP_WALL_Y + y * BLOCK_HEIGHT),
		BLOCK_WIDTH,
		BLOCK_HEIGHT,
	}
}

block_exists :: proc(x, y: int) -> bool {
	if x < 0 || y < 0 || x >= NUM_BLOCKS_X || y >= NUM_BLOCKS_Y {
		return false
	}

	return blocks[x][y] > 0
}

main :: proc() {
	rl.SetConfigFlags({.VSYNC_HINT})
	rl.InitWindow(SCREEN_SIZE_X * 2, SCREEN_SIZE_Y * 2, "noid")
	rl.InitAudioDevice()
	rl.SetTargetFPS(500)
	rl.DisableCursor()

	ball_texture := rl.LoadTexture("assets/ball.png")
	paddle_texture := rl.LoadTexture("assets/paddle.png")
	hit_block_sound := rl.LoadSound("assets/hit_block.wav")
	hit_paddle_sound := rl.LoadSound("assets/hit_paddle.wav")
	game_over_sound := rl.LoadSound("assets/game_over.wav")

	restart()

	for !rl.WindowShouldClose() {
		DT :: 1.0 / PHYSICS_TICK_RATE

		if rl.IsKeyPressed(.ESCAPE) {return}

		if !started {
			ball_pos = {
				PLAY_AREA_WIDTH / 2 + f32(math.cos(rl.GetTime()) * PLAY_AREA_WIDTH / 2.5),
				BALL_START_Y,
			}

			previous_ball_pos = ball_pos

			if rl.IsMouseButtonPressed(.LEFT) {
				paddle_middle := rl.Vector2{paddle_pos_x + PADDLE_WIDTH / 2, PADDLE_POS_Y}
				ball_to_paddle := paddle_middle - ball_pos
				ball_dir = linalg.normalize0(ball_to_paddle)
				started = true
			}
		} else if game_over {
			if rl.IsMouseButtonPressed(.LEFT) {
				restart()
			}
		} else {
			accumulated_time += rl.GetFrameTime()
		}

		if (extra_life <= 0) {
			extra_life += EXTRA_LIFE_SCORE
			lives += 1
		}

		if (blocks_left == 0) {
			level += 1
			load_level(chapter, level)
		}

		for accumulated_time >= DT {
			previous_ball_pos = ball_pos
			previous_paddle_pos_x = paddle_pos_x
			ball_pos += ball_dir * BALL_SPEED * DT

			if ball_pos.x + BALL_RADIUS > RIGHT_WALL_X {
				ball_pos.x = RIGHT_WALL_X - BALL_RADIUS
				ball_dir = reflect(ball_dir, {-1, 0})
			}

			if ball_pos.x - BALL_RADIUS < LEFT_WALL_X {
				ball_pos.x = LEFT_WALL_X + BALL_RADIUS
				ball_dir = reflect(ball_dir, {1, 0})
			}

			if ball_pos.y - BALL_RADIUS < TOP_WALL_Y {
				ball_pos.y = TOP_WALL_Y + BALL_RADIUS
				ball_dir = reflect(ball_dir, {0, 1})
			}

			if ball_pos.y > SCREEN_SIZE_Y + BALL_RADIUS * 5 {
				if !game_over && lives == 0 {
					game_over = true
					rl.PlaySound(game_over_sound)
				} else {
					lives -= 1
					reset_paddle()
				}
			}

			mouse_dx := rl.GetMouseDelta().x * DT * MOUSE_SENSITIVITY
			if abs(mouse_dx) > 0 {
				paddle_pos_x += mouse_dx
			}

			paddle_pos_x = clamp(paddle_pos_x, LEFT_WALL_X, RIGHT_WALL_X - PADDLE_WIDTH)

			paddle_rect := rl.Rectangle{paddle_pos_x, PADDLE_POS_Y, PADDLE_WIDTH, PADDLE_HEIGHT}

			// NOTE: Collision with paddle is a special snowflake that ignores incoming direction
			// and chooses outgoing direction based on where the ball hits the paddle.
			if rl.CheckCollisionCircleRec(ball_pos, BALL_RADIUS, paddle_rect) &&
			   ball_pos.y <= (paddle_rect.y + paddle_rect.height / 2) {
				hit_pos_x := linalg.unlerp(
					paddle_rect.x,
					paddle_rect.x + paddle_rect.width,
					ball_pos.x,
				)

				ball_dir = linalg.normalize(rl.Vector2{(hit_pos_x - 0.5) * 3.0, -1})

				rl.PlaySound(hit_paddle_sound)
			}

			block_x_loop: for x in 0 ..< NUM_BLOCKS_X {
				for y in 0 ..< NUM_BLOCKS_Y {
					if blocks[x][y] == 0 {
						continue
					}

					block_rect := calc_block_rect(x, y)

					if rl.CheckCollisionCircleRec(ball_pos, BALL_RADIUS, block_rect) {
						collision_normal: rl.Vector2

						// TODO: Resolve this so that we only ever collide with one edge
						if previous_ball_pos.y < block_rect.y {
							collision_normal += {0, -1}
						} else if previous_ball_pos.y > block_rect.y + block_rect.height {
							collision_normal += {0, 1}
						} else if previous_ball_pos.x < block_rect.x {
							collision_normal += {-1, 0}
						} else if previous_ball_pos.x > block_rect.x + block_rect.width {
							collision_normal += {1, 0}
						}

						if block_exists(x + int(collision_normal.x), y) {
							collision_normal.x = 0
						}

						if block_exists(x, y + int(collision_normal.y)) {
							collision_normal.y = 0
						}

						if collision_normal != 0 {
							ball_dir = reflect(ball_dir, collision_normal)
						}

						block_score := block_color_score[Block_Color(blocks[x][y])]
						score += block_score
						extra_life -= block_score

						#partial switch bc := Block_Color(blocks[x][y]); bc {
						case Block_Color.Adamantium:
							break // unbreakable
						case Block_Color.Steel:
							blocks[x][y] = u8(Block_Color.DamagedSteel)
						case:
							{
								blocks[x][y] = 0
								blocks_left -= 1
							}
						}

						rl.SetSoundPitch(hit_block_sound, rand.float32_range(0.8, 1.2))
						rl.PlaySound(hit_block_sound)

						break block_x_loop
					}
				}
			}

			accumulated_time -= DT
		}

		blend := accumulated_time / DT
		ball_render_pos := math.lerp(previous_ball_pos, ball_pos, blend)
		paddle_render_pos_x := math.lerp(previous_paddle_pos_x, paddle_pos_x, blend)

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)

		camera := rl.Camera2D {
			zoom = f32(rl.GetScreenHeight() / SCREEN_SIZE_Y),
		}

		rl.BeginMode2D(camera)

		rl.DrawRectangleRec({0, 0, WALL_THICKNESS, SCREEN_SIZE_Y}, rl.GRAY)
		rl.DrawRectangleRec({RIGHT_WALL_X, 0, WALL_THICKNESS, SCREEN_SIZE_Y}, rl.GRAY)
		rl.DrawRectangleRec({0, 0, SCREEN_SIZE_X, WALL_THICKNESS}, rl.GRAY)

		rl.DrawTextureV(paddle_texture, {paddle_render_pos_x, PADDLE_POS_Y}, rl.WHITE)
		rl.DrawTextureV(ball_texture, ball_render_pos - {BALL_RADIUS, BALL_RADIUS}, rl.WHITE)

		for x in 0 ..< NUM_BLOCKS_X {
			for y in 0 ..< NUM_BLOCKS_Y {
				if blocks[x][y] == 0 {
					continue
				}

				block_rect := calc_block_rect(x, y)
				top_left := rl.Vector2{block_rect.x, block_rect.y}
				top_right := rl.Vector2{block_rect.x + block_rect.width, block_rect.y}
				bottom_left := rl.Vector2{block_rect.x, block_rect.y + block_rect.height}
				bottom_right := rl.Vector2 {
					block_rect.x + block_rect.width,
					block_rect.y + block_rect.height,
				}

				rl.DrawRectangleRec(block_rect, block_color_values[Block_Color(blocks[x][y])])
				rl.DrawLineEx(top_left, top_right, 1, {255, 255, 150, 100})
				rl.DrawLineEx(top_left, bottom_left, 1, {255, 255, 150, 100})
				rl.DrawLineEx(top_right, bottom_right, 1, {0, 0, 50, 100})
				rl.DrawLineEx(bottom_left, bottom_right, 1, {0, 0, 50, 100})
			}
		}

		left_offset: i32 = PLAY_AREA_WIDTH + 15
		top_offset: i32 = 15
		font_size: i32 = 20

		rl.DrawText("SCORE", left_offset, top_offset, font_size, rl.WHITE)
		top_offset += 20
		score_text := fmt.ctprint(score)
		rl.DrawText(score_text, left_offset, top_offset, font_size, rl.WHITE)
		top_offset += 40

		rl.DrawText("EXTRA", left_offset, top_offset, font_size, rl.WHITE)
		top_offset += 20
		extra_text := fmt.ctprint(extra_life)
		rl.DrawText(extra_text, left_offset, top_offset, font_size, rl.WHITE)
		top_offset += 40

		rl.DrawText("LIVES", left_offset, top_offset, font_size, rl.WHITE)
		top_offset += 20
		lives_text := fmt.ctprint(lives)
		rl.DrawText(lives_text, left_offset, top_offset, font_size, rl.WHITE)
		top_offset += 40

		rl.DrawText("LEVEL", left_offset, top_offset, font_size, rl.WHITE)
		top_offset += 20
		level_text := fmt.ctprintf("%d-%d", chapter, level)
		rl.DrawText(level_text, left_offset, top_offset, font_size, rl.WHITE)
		top_offset += 40

		if !started {
			start_text := fmt.ctprint("Start: Left Click")
			start_text_width := rl.MeasureText(start_text, 15)
			rl.DrawText(
				start_text,
				PLAY_AREA_WIDTH / 2 - start_text_width / 2,
				BALL_START_Y - 30,
				15,
				rl.WHITE,
			)
		}

		if game_over {
			game_over_text := fmt.ctprintf("Score: %v. Reset: Left Click", score)
			game_over_text_width := rl.MeasureText(game_over_text, 15)
			rl.DrawText(
				game_over_text,
				PLAY_AREA_WIDTH / 2 - game_over_text_width / 2,
				BALL_START_Y - 30,
				15,
				rl.WHITE,
			)
		}

		rl.EndMode2D()
		rl.EndDrawing()

		free_all(context.temp_allocator)
	}

	rl.CloseAudioDevice()
	rl.CloseWindow()
}
