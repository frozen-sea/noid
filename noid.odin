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
DEFAULT_PADDLE_WIDTH :: 50
PADDLE_HEIGHT :: 6
PADDLE_POS_Y :: SCREEN_SIZE_Y - 50
DEFAULT_BALL_SPEED :: 250
DEFAULT_BALL_OFFSET_X :: DEFAULT_PADDLE_WIDTH * 2 / 3
BALL_RADIUS :: 4
BALL_START_Y :: SCREEN_SIZE_Y / 3 * 2
NUM_BLOCKS_X :: 10
NUM_BLOCKS_Y :: 16
BLOCK_WIDTH :: PLAY_AREA_WIDTH / NUM_BLOCKS_X
BLOCK_HEIGHT :: 15
EXTRA_LIFE_SCORE :: 2500
PHYSICS_TICK_RATE :: 120
MOUSE_SENSITIVITY :: 50 // 0-100
POWERUP_SPEED :: 100
POWERUP_SIZE :: 5.25

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

Powerup_Type :: enum u8 {
  Barrier,
  Catch,
  Duplicate,
  Enlarge,
  Laser,
  Slow,
  Pierce,
}

Powerup :: struct {
  type: Powerup_Type,
  pos: rl.Vector2,
  color: rl.Color,
}

powerup_letter := [Powerup_Type]u8 {
  .Barrier = 'B',
  .Catch = 'C',
  .Duplicate = 'D',
  .Enlarge = 'E',
  .Laser = 'L',
  .Slow = 'S',
  .Pierce = 'P',
}

blocks: [NUM_BLOCKS_X][NUM_BLOCKS_Y]Block_Color
falling_powerups: [dynamic; 8]Powerup
active_powerups: [Powerup_Type]bool
paddle_width: f32
paddle_pos_x: f32
ball_pos: rl.Vector2
ball_dir: rl.Vector2
ball_speed: f32
ball_offset_x: f32
game_paused: bool
game_over: bool
waiting_for_launch: bool
blocks_left: int
score: int
extra_life: int
lives: int
accumulated_time: f32
previous_ball_pos: rl.Vector2
previous_paddle_pos_x: f32
chapter: int = 1
level: int = 2

move_ball_to_paddle :: proc() {
  ball_pos = {
    paddle_pos_x + ball_offset_x,
    PADDLE_POS_Y - BALL_RADIUS - 1,
  }
}

ball_hit_paddle :: proc() {
  hit_pos_x := linalg.unlerp(
    paddle_pos_x,
    paddle_pos_x + paddle_width,
    ball_pos.x,
  )
  ball_offset_x = paddle_width * hit_pos_x
  ball_dir = linalg.normalize(rl.Vector2{(hit_pos_x - 0.5) * 3.0, -1})
}

reset_paddle :: proc() {
  waiting_for_launch = true
  ball_speed = 0
  ball_offset_x = DEFAULT_BALL_OFFSET_X
  paddle_width = DEFAULT_PADDLE_WIDTH
	paddle_pos_x = LEFT_WALL_X + PLAY_AREA_WIDTH / 2 - paddle_width / 2
	previous_paddle_pos_x = paddle_pos_x
  clear(&falling_powerups)
  active_powerups = {}
  move_ball_to_paddle()
  previous_ball_pos = ball_pos
  ball_hit_paddle()
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
				block_id := char_to_block_color(row[x])
				blocks[x][y] = block_id
				if block_id != Block_Color.Empty && block_id != Block_Color.Adamantium {
					blocks_left += 1
				}
			}
			y += 1
		}
	} else {
		for x in 0 ..< NUM_BLOCKS_X {
			for y in 0 ..< NUM_BLOCKS_Y {
				blocks[x][y] = Block_Color.Empty
				blocks_left += 1
			}
		}
	}

	reset_paddle()
}

restart :: proc() {
  game_paused = false
	game_over = false
	score = 0
	extra_life = EXTRA_LIFE_SCORE
	lives = 2
	load_level(1, 1)
}

char_to_block_color :: proc(char: u8) -> Block_Color {
	switch char {
	case 'W':
		return Block_Color.White
	case 'C':
		return Block_Color.Cyan
	case 'B':
		return Block_Color.Blue
	case 'G':
		return Block_Color.Green
	case 'Y':
		return Block_Color.Yellow
	case 'R':
		return Block_Color.Red
	case 'P':
		return Block_Color.Pink
	case 'O':
		return Block_Color.Orange
	case 'S':
		return Block_Color.Steel
	case 'A':
		return Block_Color.Adamantium
	case:
		return Block_Color.Empty
	}
}

char_to_cstring :: proc(ch: u8) -> cstring {
  return fmt.ctprintf("%c", ch)
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

	return blocks[x][y] > Block_Color.Empty
}

draw_rect_w_outline :: proc(rect: rl.Rectangle, color: rl.Color) {
  top_left := rl.Vector2{rect.x, rect.y}
  top_right := rl.Vector2{rect.x + rect.width, rect.y}
  bottom_left := rl.Vector2{rect.x, rect.y + rect.height}
  bottom_right := rl.Vector2 {rect.x + rect.width, rect.y + rect.height}

  darker_color := rl.ColorBrightness(color, -0.5)
  lighter_color := rl.ColorBrightness(color, 0.5)

  rl.DrawRectangleRec(rect, color)
  rl.DrawLineEx(top_left, top_right, 1, lighter_color)
  rl.DrawLineEx(top_left, bottom_left, 1, lighter_color)
  rl.DrawLineEx(top_right, bottom_right, 1, darker_color)
  rl.DrawLineEx(bottom_left, bottom_right, 1, darker_color)
}

spawn_powerup :: proc(x, y: f32) {
  options : []u8 = {1, 3}
  type := Powerup_Type(rand.choice(options))
  append(&falling_powerups, Powerup {type, rl.Vector2 {x, y}, rl.BEIGE})
}

activate_powerup :: proc(type: Powerup_Type) {
  #partial switch type {
  case .Enlarge: {
    if active_powerups[.Enlarge] {break}
    paddle_pos_x -= paddle_width * (1 - 1/1.5)
    previous_paddle_pos_x = paddle_pos_x
    paddle_width = DEFAULT_PADDLE_WIDTH * 1.5
    active_powerups[.Catch] = false
  }
  case .Catch: {
    if active_powerups[.Enlarge] {
      paddle_width = DEFAULT_PADDLE_WIDTH
      paddle_pos_x += paddle_width * (1 - 1/1.5)
      previous_paddle_pos_x = paddle_pos_x
      active_powerups[.Enlarge] = false
    }
  }
  }

  active_powerups[type] = true
}

main :: proc() {
	rl.SetConfigFlags({.VSYNC_HINT})
	rl.InitWindow(SCREEN_SIZE_X * 2, SCREEN_SIZE_Y * 2, "noid")
	rl.InitAudioDevice()
	rl.SetTargetFPS(500)
	rl.DisableCursor()

	hit_block_sound := rl.LoadSound("assets/hit_block.wav")
	hit_paddle_sound := rl.LoadSound("assets/hit_paddle.wav")
	game_over_sound := rl.LoadSound("assets/game_over.wav")

	restart()

  for !rl.WindowShouldClose() {
    DT :: 1.0 / PHYSICS_TICK_RATE

    if rl.IsKeyPressed(.ESCAPE) {return}
    
    if rl.IsMouseButtonPressed(.LEFT) {
      if game_over {restart()}
      else if waiting_for_launch {
        ball_speed = DEFAULT_BALL_SPEED
        waiting_for_launch = false
      }
    }

    if !game_paused {
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
			mouse_dx := rl.GetMouseDelta().x * DT * MOUSE_SENSITIVITY
			if abs(mouse_dx) > 0 {
				paddle_pos_x += mouse_dx
			}

			previous_ball_pos = ball_pos
			previous_paddle_pos_x = paddle_pos_x

      if waiting_for_launch {
        move_ball_to_paddle()
      } else {
        ball_pos += ball_dir * ball_speed * DT

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
          if lives == 0 {
            game_over = true
            game_paused = true
            rl.PlaySound(game_over_sound)
          } else {
            lives -= 1
            reset_paddle()
          }
        }
      }

			// NOTE: Collision with paddle is a special snowflake that ignores incoming direction
			// and chooses outgoing direction based on where the ball hits the paddle.
			paddle_rect := rl.Rectangle{paddle_pos_x, PADDLE_POS_Y, paddle_width, PADDLE_HEIGHT}
			if rl.CheckCollisionCircleRec(ball_pos, BALL_RADIUS, paddle_rect) {
        ball_hit_paddle()

        if active_powerups[.Catch] {
          ball_speed = 0
          waiting_for_launch = true
        }

				rl.PlaySound(hit_paddle_sound)
			}

			block_x_loop: for x in 0 ..< NUM_BLOCKS_X {
				for y in 0 ..< NUM_BLOCKS_Y {
					if blocks[x][y] == Block_Color.Empty {
						continue
					}

					block_rect := calc_block_rect(x, y)

					if rl.CheckCollisionCircleRec(ball_pos, BALL_RADIUS, block_rect) {
						collision_normal: rl.Vector2

						// TODO: Resolve this so that we only ever collide once and with the correct edge
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

						block_score := block_color_score[Block_Color(blocks[x][y])]
						score += block_score
						extra_life -= block_score

						#partial switch blocks[x][y] {
						case Block_Color.Adamantium:
							break // unbreakable
						case Block_Color.Steel:
							blocks[x][y] = Block_Color.DamagedSteel
						case:
							{
								blocks[x][y] = Block_Color.Empty
								blocks_left -= 1
                if rand.float32() > 0.75 {
                  spawn_powerup(block_rect.x + block_rect.width/2, block_rect.y + block_rect.height)
                }
							}
						}

						rl.SetSoundPitch(hit_block_sound, rand.float32_range(0.8, 1.2))
						rl.PlaySound(hit_block_sound)

						break block_x_loop
					}
				}
			}

      for i := len(falling_powerups) - 1; i >= 0; i -= 1 {
        powerup := &falling_powerups[i]
        powerup.pos.y += POWERUP_SPEED * DT
        powerup_rect := rl.Rectangle {
          powerup.pos.x - POWERUP_SIZE, powerup.pos.y - POWERUP_SIZE,
          POWERUP_SIZE*2, POWERUP_SIZE*2
        }
        if rl.CheckCollisionRecs(paddle_rect, powerup_rect) {
          activate_powerup(powerup.type)
          ordered_remove(&falling_powerups, i)
        } else if powerup_rect.y > SCREEN_SIZE_Y {
          ordered_remove(&falling_powerups, i)
        }
      }

			paddle_pos_x = clamp(paddle_pos_x, LEFT_WALL_X, RIGHT_WALL_X - paddle_width)
			accumulated_time -= DT
		}

    // Clear out the leftover time
		blend := accumulated_time / DT
		ball_render_pos := math.lerp(previous_ball_pos, ball_pos, blend)
		paddle_render_pos_x := math.lerp(previous_paddle_pos_x, paddle_pos_x, blend)

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)

		camera := rl.Camera2D {
			zoom = f32(rl.GetScreenHeight() / SCREEN_SIZE_Y),
		}

		rl.BeginMode2D(camera)

    draw_rect_w_outline({paddle_render_pos_x, PADDLE_POS_Y, paddle_width, PADDLE_HEIGHT}, rl.DARKBLUE)
    
    rl.DrawCircleV(ball_render_pos, BALL_RADIUS, rl.GRAY)
    rl.DrawRing(ball_render_pos, BALL_RADIUS - 1, BALL_RADIUS, -45, 145, 4, rl.DARKGRAY)
    rl.DrawRing(ball_render_pos, BALL_RADIUS - 1, BALL_RADIUS, -225, -45, 4, rl.WHITE)

		for x in 0 ..< NUM_BLOCKS_X {
			for y in 0 ..< NUM_BLOCKS_Y {
				if blocks[x][y] == Block_Color.Empty {
					continue
				}

				block_rect := calc_block_rect(x, y)
				block_color := block_color_values[blocks[x][y]]
        draw_rect_w_outline(block_rect, block_color)
			}
		}

		rl.DrawRectangleRec({0,            0, WALL_THICKNESS, SCREEN_SIZE_Y},  rl.GRAY)
		rl.DrawRectangleRec({RIGHT_WALL_X, 0, WALL_THICKNESS, SCREEN_SIZE_Y},  rl.GRAY)
		rl.DrawRectangleRec({0,            0, SCREEN_SIZE_X,  WALL_THICKNESS}, rl.GRAY)

    for powerup in falling_powerups {
      powerup_rect := rl.Rectangle {
        powerup.pos.x - POWERUP_SIZE, powerup.pos.y - POWERUP_SIZE,
        POWERUP_SIZE*2, POWERUP_SIZE*2
      }

      draw_rect_w_outline(powerup_rect, powerup.color)
      x := i32(powerup.pos.x - POWERUP_SIZE + 2)
      y := i32(powerup.pos.y - POWERUP_SIZE + 1)
      cstr := char_to_cstring(powerup_letter[powerup.type])
      rl.DrawText(cstr, x+1, y+1, 2, rl.BLACK)
      rl.DrawText(cstr, x, y, 2, rl.WHITE)
    }

		left_offset: i32 = RIGHT_WALL_X + 20
		top_offset: i32 = 20
		TITLE_SIZE :: 20
    VALUE_SIZE :: 15

		rl.DrawText("SCORE", left_offset, top_offset, TITLE_SIZE, rl.WHITE)
		top_offset += 20
		score_text := fmt.ctprint(score)
		rl.DrawText(score_text, left_offset, top_offset, VALUE_SIZE, rl.WHITE)
		top_offset += 40

		rl.DrawText("EXTRA", left_offset, top_offset, TITLE_SIZE, rl.WHITE)
		top_offset += 20
		extra_text := fmt.ctprint(extra_life)
		rl.DrawText(extra_text, left_offset, top_offset, VALUE_SIZE, rl.WHITE)
		top_offset += 40

		rl.DrawText("LIVES", left_offset, top_offset, TITLE_SIZE, rl.WHITE)
		top_offset += 20
		lives_text := fmt.ctprint(lives)
		rl.DrawText(lives_text, left_offset, top_offset, VALUE_SIZE, rl.WHITE)
		top_offset += 40

		rl.DrawText("LEVEL", left_offset, top_offset, TITLE_SIZE, rl.WHITE)
		top_offset += 20
		level_text := fmt.ctprintf("%d-%d", chapter, level)
		rl.DrawText(level_text, left_offset, top_offset, VALUE_SIZE, rl.WHITE)
		top_offset += 40

		if waiting_for_launch {
			start_text := fmt.ctprint("Start: Left Click")
			start_text_width := rl.MeasureText(start_text, 15)
			rl.DrawText(
				start_text,
				LEFT_WALL_X + PLAY_AREA_WIDTH / 2 - start_text_width / 2,
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
				LEFT_WALL_X + PLAY_AREA_WIDTH / 2 - game_over_text_width / 2,
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
