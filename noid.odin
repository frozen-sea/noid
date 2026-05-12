package noid

import "core:fmt"
import "core:os"
import "core:strings"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import rl "vendor:raylib"

SCREEN_SIZE_X :: 512
SCREEN_SIZE_Y :: 448
SIDEBAR_WIDTH :: 132
PLAY_AREA_WIDTH :: SCREEN_SIZE_X - SIDEBAR_WIDTH
PADDLE_WIDTH :: 50
PADDLE_HEIGHT :: 6
PADDLE_POS_Y :: SCREEN_SIZE_Y - 50
PADDLE_SPEED :: 200
BALL_SPEED :: 200
BALL_RADIUS :: 4
BALL_START_Y :: SCREEN_SIZE_Y/3*2
NUM_BLOCKS_X :: 10
NUM_BLOCKS_Y :: 10
BLOCK_WIDTH :: (SCREEN_SIZE_X - SIDEBAR_WIDTH)/NUM_BLOCKS_X
BLOCK_HEIGHT :: 15

Block_Color :: enum {
  Empty,
  White,
  Cyan,
  Green,
  Yellow,
  Red,
  Pink,
  Orange,
  Steel,
  Brass,
}

block_color_values := [Block_Color]rl.Color {
  .Empty = rl.Color {0,0,0,0},
  .White = rl.WHITE,
  .Cyan = rl.BLUE,
  .Green = rl.GREEN,
  .Yellow = rl.YELLOW,
  .Red = rl.RED,
  .Pink = rl.PINK,
  .Orange = rl.ORANGE,
  .Steel = rl.GRAY,
  .Brass = rl.GOLD,
}

block_color_score := [Block_Color]int {
  .Empty = 0,
  .White = 1,
  .Cyan = 2,
  .Green = 4,
  .Yellow = 6,
  .Red = 8,
  .Pink = 10,
  .Orange = 20,
  .Steel = 50,
  .Brass = 100,
}

blocks: [NUM_BLOCKS_X][NUM_BLOCKS_Y]u8
paddle_pos_x: f32
ball_pos: rl.Vector2
ball_dir: rl.Vector2
started: bool
game_over: bool
score: int
accumulated_time: f32
previous_ball_pos: rl.Vector2
previous_paddle_pos_x: f32

restart :: proc() {
	paddle_pos_x = PLAY_AREA_WIDTH / 2 - PADDLE_WIDTH / 2
	previous_paddle_pos_x = paddle_pos_x
	ball_pos = {PLAY_AREA_WIDTH / 2, BALL_START_Y}
	previous_ball_pos = ball_pos
	started = false
	game_over = false
	score = 0

  data, err := os.read_entire_file("levels/level1.txt", context.allocator)
  defer delete(data, context.allocator)

  if err != nil {
    for x in 0 ..< NUM_BLOCKS_X {
      for y in 0 ..< NUM_BLOCKS_Y {
        blocks[x][y] = 1
      }
    }
  } else {
    y := 0
    it := string(data)
    for row in strings.split_lines_iterator(&it) {
      assert(len(row) == NUM_BLOCKS_X)
      for x in 0..< NUM_BLOCKS_X {
        blocks[x][y] = char_to_block_id(row[x])
      }
      y += 1
    }
    assert(y == NUM_BLOCKS_Y)
  }
}

char_to_block_id :: proc(char: u8) -> u8 {
  switch char {
  case 'W': return u8(Block_Color.White)
  case 'C': return u8(Block_Color.Cyan)
  case 'G': return u8(Block_Color.Green)
  case 'Y': return u8(Block_Color.Yellow)
  case 'R': return u8(Block_Color.Red)
  case 'P': return u8(Block_Color.Pink)
  case 'O': return u8(Block_Color.Orange)
  case 'S': return u8(Block_Color.Steel)
  case 'B': return u8(Block_Color.Brass)
  case: return u8(Block_Color.Empty)
  }
}

reflect :: proc(dir, normal: rl.Vector2) -> rl.Vector2 {
	new_direction := linalg.reflect(dir, linalg.normalize(normal))
	return linalg.normalize(new_direction)
}

negate :: proc(dir: rl.Vector2) -> rl.Vector2 {
	new_direction := dir * -1
	return linalg.normalize(new_direction)
}

calc_block_rect :: proc(x, y: int) -> rl.Rectangle {
	return {f32(x * BLOCK_WIDTH), f32(BLOCK_HEIGHT + y * BLOCK_HEIGHT), BLOCK_WIDTH, BLOCK_HEIGHT}
}

block_exists :: proc(x, y: int) -> bool {
	if x < 0 || y < 0 || x >= NUM_BLOCKS_X || y >= NUM_BLOCKS_Y {
		return false
	}

	return blocks[x][y] > 0
}

main :: proc() {
	rl.SetConfigFlags({.VSYNC_HINT})
	rl.InitWindow(SCREEN_SIZE_X*2, SCREEN_SIZE_Y*2, "noid")
	rl.InitAudioDevice()
	rl.SetTargetFPS(500)
  rl.DisableCursor()

	ball_texture := rl.LoadTexture("assets/ball.png")
	paddle_texture := rl.LoadTexture("assets/paddle.png")
	hit_block_sound := rl.LoadSound("assets/hit_block.wav")
	hit_paddle_sound := rl.LoadSound("assets/hit_paddle_soundddle.wav")
	game_over_sound := rl.LoadSound("assets/game_over.wav")

	restart()

	for !rl.WindowShouldClose() {
		DT :: 1.0 / 120

		if rl.IsKeyPressed(.ESCAPE) {return}

		if !started {
			ball_pos = {
				PLAY_AREA_WIDTH / 2 + f32(math.cos(rl.GetTime()) * PLAY_AREA_WIDTH / 2.5),
				BALL_START_Y,
			}

			previous_ball_pos = ball_pos

			if rl.IsKeyPressed(.SPACE) || rl.IsMouseButtonPressed(.LEFT) {
				paddle_middle := rl.Vector2{paddle_pos_x + PADDLE_WIDTH / 2, PADDLE_POS_Y}
				ball_to_paddle := paddle_middle - ball_pos
				ball_dir = linalg.normalize0(ball_to_paddle)
				started = true
			}
		} else if game_over {
			if rl.IsKeyPressed(.SPACE) || rl.IsMouseButtonPressed(.LEFT) {
				restart()
			}
		} else {
			accumulated_time += rl.GetFrameTime()
		}

		for accumulated_time >= DT {
			previous_ball_pos = ball_pos
			previous_paddle_pos_x = paddle_pos_x
			ball_pos += ball_dir * BALL_SPEED * DT

			if ball_pos.x + BALL_RADIUS > PLAY_AREA_WIDTH {
				ball_pos.x = PLAY_AREA_WIDTH - BALL_RADIUS
				ball_dir = reflect(ball_dir, {-1, 0})
			}

			if ball_pos.x - BALL_RADIUS < 0 {
				ball_pos.x = BALL_RADIUS
				ball_dir = reflect(ball_dir, {1, 0})
			}

			if ball_pos.y - BALL_RADIUS < 0 {
				ball_pos.y = BALL_RADIUS
				ball_dir = reflect(ball_dir, {0, 1})
			}

			if !game_over && ball_pos.y > SCREEN_SIZE_Y + BALL_RADIUS * 6 {
				game_over = true
				rl.PlaySound(game_over_sound)
			}

      mouse_dx := rl.GetMouseDelta().x * 0.5
      if abs(mouse_dx) > 0.1 {
        paddle_pos_x += mouse_dx
      }

			paddle_pos_x = clamp(paddle_pos_x, 0, PLAY_AREA_WIDTH - PADDLE_WIDTH)

			paddle_rect := rl.Rectangle{paddle_pos_x, PADDLE_POS_Y, PADDLE_WIDTH, PADDLE_HEIGHT}

      // NOTE: Collision with paddle is a special snowflake that ignores incoming direction
      // and chooses outgoing direction based on where the ball hits the paddle.
			if rl.CheckCollisionCircleRec(ball_pos, BALL_RADIUS, paddle_rect) && ball_pos.y <= (paddle_rect.y + paddle_rect.height/2) {
        hit_pos_x := linalg.unlerp(paddle_rect.x, paddle_rect.x + paddle_rect.width, ball_pos.x)
        
        ball_dir = linalg.normalize(rl.Vector2 {(hit_pos_x - 0.5)*3.0, -1})

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

						if previous_ball_pos.y < block_rect.y {
							collision_normal += {0, -1}
						}

						if previous_ball_pos.y > block_rect.y + block_rect.height {
							collision_normal += {0, 1}
						}

						if previous_ball_pos.x < block_rect.x {
							collision_normal += {-1, 0}
						}

						if previous_ball_pos.x > block_rect.x + block_rect.width {
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

						score += block_color_score[Block_Color(blocks[x][y])]
						blocks[x][y] = 0
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
    
    rl.DrawRectangleRec({PLAY_AREA_WIDTH + 0.5, 0, 5, SCREEN_SIZE_Y}, rl.GRAY)

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
				bottom_right := rl.Vector2 {block_rect.x + block_rect.width, block_rect.y + block_rect.height}

				rl.DrawRectangleRec(block_rect, block_color_values[Block_Color(blocks[x][y])])
				rl.DrawLineEx(top_left, top_right, 2, {255, 255, 150, 100})
				rl.DrawLineEx(top_left, bottom_left, 2, {255, 255, 150, 100})
				rl.DrawLineEx(top_right, bottom_right, 2, {0, 0, 50, 100})
				rl.DrawLineEx(bottom_left - 1, bottom_right - 1, 2, {0, 0, 50, 100})
			}
		}

		score_text := fmt.ctprint(score)
		rl.DrawText(score_text, PLAY_AREA_WIDTH + 15, 10, 20, rl.WHITE)

		if !started {
			start_text := fmt.ctprint("Start: SPACE")
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
			game_over_text := fmt.ctprintf("Score: %v. Reset: SPACE", score)
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
