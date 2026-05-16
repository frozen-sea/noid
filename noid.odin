package noid

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:os"
import "core:reflect"
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
NORMAL_BALL_SPEED :: 250
SLOW_BALL_SPEED :: NORMAL_BALL_SPEED * 0.7
DEFAULT_BALL_OFFSET :: 0.7
BALL_RADIUS :: 4
BALL_START_Y :: SCREEN_SIZE_Y / 0.7
NUM_BLOCKS_X :: 10
NUM_BLOCKS_Y :: 16
BLOCK_WIDTH :: PLAY_AREA_WIDTH / NUM_BLOCKS_X
BLOCK_HEIGHT :: 15
EXTRA_LIFE_SCORE :: 2500
PHYSICS_TICK_RATE :: 120
DT :: 1.0 / PHYSICS_TICK_RATE
MOUSE_SENSITIVITY :: 50 // 0-100
POWERUP_SPEED :: 100
POWERUP_SIZE :: 5.25
DEFAULT_PADDLE_COLOR :: rl.DARKBLUE
DEFAULT_BALL_COLOR :: rl.WHITE
BARRIER_RECT :: rl.Rectangle {LEFT_WALL_X, PADDLE_POS_Y + PADDLE_HEIGHT/2, PLAY_AREA_WIDTH, 5}
MAX_LASER_COUNT :: 2
LASER_SHOT_SPEED :: 2
LASER_SHOT_LENGTH :: 20
LASER_SHOT_WIDTH :: 1
BALL_TRAIL_LENGTH :: 16
BALL_TRAIL_STEP :: 1.0/BALL_TRAIL_LENGTH
MULTIBALL_EXTRA_BALLS :: 6

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
  Multiball,
  Enlarge,
  Laser,
  Slow,
  Pierce,
}

Powerup :: struct {
  type: Powerup_Type,
  pos: rl.Vector2,
}

powerup_letter := [Powerup_Type]u8 {
  .Barrier = 'B',
  .Catch = 'C',
  .Enlarge = 'E',
  .Laser = 'L',
  .Multiball = 'M',
  .Slow = 'S',
  .Pierce = 'P',
}

Laser :: struct {
  origins: [2]rl.Vector2,
}

Ball_Trail :: struct {
  pos: rl.Vector2,
  opacity: f32,
}

Ball :: struct {
  pos, prev_pos: rl.Vector2,
  dir: rl.Vector2,
  speed: f32,
  last_hit_offset: f32
}

MegaStruct :: struct {
  waiting_for_launch: bool,
  game_over: bool,
  paddle_width: f32,
  paddle_pos_x: f32,
  balls: [dynamic; MULTIBALL_EXTRA_BALLS + 1]Ball,
  falling_powerups: [dynamic; 8]Powerup,
  active_powerups: [Powerup_Type]bool,
  lasers: [MAX_LASER_COUNT]Laser,
  next_laser_to_fire: int,
  ball_trails: [dynamic; BALL_TRAIL_LENGTH]Ball_Trail,
  next_ball_trail_tick_time: f64
}

MS := MegaStruct {}

blocks: [NUM_BLOCKS_X][NUM_BLOCKS_Y]Block_Color
game_paused: bool
blocks_left: int
score: int
extra_life: int
lives: int
accumulated_time: f32
chapter: int = 1
level: int = 1
paddle_color: rl.Color
ball_color: rl.Color
hit_block_sound: rl.Sound
hit_paddle_sound: rl.Sound
game_over_sound: rl.Sound

move_ball_to_paddle :: proc(default: bool = false) {
  hit_pos_x := default ? DEFAULT_BALL_OFFSET : MS.balls[0].last_hit_offset
  MS.balls[0].pos = {
    MS.paddle_pos_x + hit_pos_x * MS.paddle_width,
    PADDLE_POS_Y - BALL_RADIUS - 1,
  }
}

ball_hit_paddle :: proc(ball_index: int = 0) {
  hit_pos_x := linalg.unlerp(
    MS.paddle_pos_x,
    MS.paddle_pos_x + MS.paddle_width,
    MS.balls[ball_index].pos.x,
  )
  MS.balls[ball_index].last_hit_offset = hit_pos_x
  MS.balls[ball_index].dir = linalg.normalize(rl.Vector2{(hit_pos_x - 0.5) * 3.0, -1})
}

reset_paddle :: proc() {
  MS.waiting_for_launch = true
  paddle_color = DEFAULT_PADDLE_COLOR
  MS.paddle_width = DEFAULT_PADDLE_WIDTH
	MS.paddle_pos_x = LEFT_WALL_X + PLAY_AREA_WIDTH / 2 - MS.paddle_width / 2
  MS.active_powerups = {}
  MS.lasers = {}
  clear(&MS.falling_powerups)
  clear(&MS.ball_trails)
  clear(&MS.balls)
  append(&MS.balls, Ball {})
  ball_color = DEFAULT_BALL_COLOR
  move_ball_to_paddle(default = true)
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

restart_game :: proc() {
  game_paused = false
	MS.game_over = false
	score = 0
	extra_life = EXTRA_LIFE_SCORE
	lives = 2
  chapter = 1
  level = 1
	load_level(chapter, level)
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

reflect_ball :: proc(dir, normal: rl.Vector2) -> rl.Vector2 {
	new_direction := linalg.reflect(dir, linalg.normalize(normal))
	return linalg.normalize(new_direction)
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
  type := Powerup_Type(rand.choice(reflect.enum_field_values(Powerup_Type)))
  append(&MS.falling_powerups, Powerup {type, rl.Vector2 {x, y}})
}

activate_powerup :: proc(type: Powerup_Type) {
  #partial switch type {
  case .Enlarge: {
    if MS.active_powerups[.Enlarge] {
      break
    }
    MS.paddle_pos_x -= MS.paddle_width * (1 - 1/1.5)
    MS.paddle_width = DEFAULT_PADDLE_WIDTH * 1.5
    if MS.active_powerups[.Catch] {
      paddle_color = DEFAULT_PADDLE_COLOR
      MS.waiting_for_launch = false
      MS.balls[0].speed = MS.active_powerups[.Slow] ? SLOW_BALL_SPEED : NORMAL_BALL_SPEED
      MS.active_powerups[.Catch] = false
    }
  }
  case .Catch: {
    if MS.active_powerups[.Pierce] {
      clear(&MS.ball_trails)
      ball_color = DEFAULT_BALL_COLOR
      MS.active_powerups[.Pierce] = false
    }
    if MS.active_powerups[.Laser] {
      MS.active_powerups[.Laser] = false
      MS.lasers = {}
    }
    if MS.active_powerups[.Enlarge] {
      MS.paddle_width = DEFAULT_PADDLE_WIDTH
      MS.paddle_pos_x += MS.paddle_width * (1 - 1/1.5)
      MS.active_powerups[.Enlarge] = false
    }
    paddle_color = rl.DARKGREEN
  }
  case .Slow: {
    if MS.active_powerups[.Pierce] {
      clear(&MS.ball_trails)
      MS.active_powerups[.Pierce] = false
    }
    if MS.active_powerups[.Slow] {
      MS.balls[0].speed = NORMAL_BALL_SPEED
      ball_color = DEFAULT_BALL_COLOR
      MS.active_powerups[.Slow] = false
    } else {
      MS.balls[0].speed = SLOW_BALL_SPEED
      ball_color = rl.GOLD
    }
  }
  case .Barrier: {}
  case .Laser: {
    paddle_color = rl.MAROON
    if MS.active_powerups[.Catch] {
      MS.waiting_for_launch = false
      MS.balls[0].speed = MS.active_powerups[.Slow] ? SLOW_BALL_SPEED : NORMAL_BALL_SPEED
      MS.active_powerups[.Catch] = false
    }
    if MS.active_powerups[.Pierce] {
      clear(&MS.ball_trails)
      ball_color = DEFAULT_BALL_COLOR
      MS.active_powerups[.Pierce] = false
    }
  }
  case .Pierce: {
    ball_color = rl.GREEN
    if MS.active_powerups[.Slow] {
      MS.balls[0].speed = NORMAL_BALL_SPEED
      MS.active_powerups[.Slow] = false
    }
    if MS.active_powerups[.Catch] {
      MS.waiting_for_launch = false
      paddle_color = DEFAULT_PADDLE_COLOR
      MS.balls[0].speed = MS.active_powerups[.Slow] ? SLOW_BALL_SPEED : NORMAL_BALL_SPEED
      MS.active_powerups[.Catch] = false
    }
    if MS.active_powerups[.Laser] {
      MS.lasers = {}
      paddle_color = DEFAULT_PADDLE_COLOR
      MS.active_powerups[.Laser] = false
    }
  }
  case .Multiball: {
    if MS.active_powerups[.Pierce] {
      clear(&MS.ball_trails)
      ball_color = DEFAULT_BALL_COLOR
      MS.active_powerups[.Pierce] = false
    }
    if !MS.active_powerups[.Multiball] {
      for i in 0..<MULTIBALL_EXTRA_BALLS {
        append(&MS.balls, Ball {
          pos = MS.balls[0].pos,
          dir = {rand.float32_range(-1, 1), -1},
          speed = MS.active_powerups[.Slow] ? SLOW_BALL_SPEED : NORMAL_BALL_SPEED,
        })
      }
    }
  }
  }

  MS.active_powerups[type] = true
}

damage_block_at_index :: proc(x, y: int) {
  block_rect := calc_block_rect(x, y)
  block_score := block_color_score[blocks[x][y]]
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
}

block_at_point :: proc(point: rl.Vector2) -> (x, y: int, empty: bool) {
  // HACK: Stupid fudge factor to make hitting the very bottom right corner of a block work
  x = (int(point.x) - LEFT_WALL_X - 1) / BLOCK_WIDTH
  y = (int(point.y) - TOP_WALL_Y - 1) / BLOCK_HEIGHT
  empty = !block_exists(x, y)
  return
}

render_ball :: proc(pos: rl.Vector2, opacity: f32) {
  color := ball_color
  color.a = u8(255*opacity)
  darker_color := rl.ColorBrightness(color, -0.5)
  lighter_color := rl.ColorBrightness(color, 0.5)
  rl.DrawCircleV(pos, BALL_RADIUS, color)
  rl.DrawRing(pos, BALL_RADIUS - 1, BALL_RADIUS, -45, 145, 4, darker_color)
  rl.DrawRing(pos, BALL_RADIUS - 1, BALL_RADIUS, -225, -45, 4, lighter_color)
}

main :: proc() {
	rl.SetConfigFlags({.VSYNC_HINT})
	rl.InitWindow(SCREEN_SIZE_X * 2, SCREEN_SIZE_Y * 2, "noid")
	rl.InitAudioDevice()
	rl.SetTargetFPS(500)
	rl.DisableCursor()

	hit_block_sound = rl.LoadSound("assets/hit_block.wav")
	hit_paddle_sound = rl.LoadSound("assets/hit_paddle.wav")
	game_over_sound = rl.LoadSound("assets/game_over.wav")

	restart_game()

  for !rl.WindowShouldClose() {
    should_exit := input()
    if should_exit {
      return
    }

    if !game_paused {
      accumulated_time += rl.GetFrameTime()

      for accumulated_time >= DT {
        tick()
        accumulated_time -= DT
      }

      if (extra_life <= 0) {
        extra_life += EXTRA_LIFE_SCORE
        lives += 1
      }

      if (blocks_left == 0) {
        level += 1
        load_level(chapter, level)
      }
    }

    render()
    free_all(context.temp_allocator)
  }

  rl.CloseAudioDevice()
  rl.CloseWindow()
}

input :: proc() -> (should_exit: bool) {
  if rl.IsKeyPressed(.ESCAPE) {
    return true
  }

  mouse_dx := rl.GetMouseDelta().x * DT * MOUSE_SENSITIVITY
  if abs(mouse_dx) > 0 {
    MS.paddle_pos_x += mouse_dx
  }

  if rl.IsMouseButtonPressed(.LEFT) {
    if MS.game_over {
      restart_game()
    }
    else if MS.waiting_for_launch {
      MS.balls[0].speed = MS.active_powerups[.Slow] ? SLOW_BALL_SPEED : NORMAL_BALL_SPEED
      MS.waiting_for_launch = false
    }
    else if MS.active_powerups[.Laser] {
      if MS.lasers[MS.next_laser_to_fire] == {} {
        MS.lasers[MS.next_laser_to_fire] = Laser {
          origins = {
            { MS.paddle_pos_x + LASER_SHOT_WIDTH,                   PADDLE_POS_Y },
            { MS.paddle_pos_x - LASER_SHOT_WIDTH + MS.paddle_width, PADDLE_POS_Y },
          }
        }
        MS.next_laser_to_fire = (MS.next_laser_to_fire + 1) % MAX_LASER_COUNT
      }
    } 
  }

  return false
}

tick :: proc() {
  paddle_rect := rl.Rectangle {MS.paddle_pos_x, PADDLE_POS_Y, MS.paddle_width, PADDLE_HEIGHT}

  for i := len(MS.balls) - 1; i >= 0; i -= 1 {
    ball := &MS.balls[i]
    ball.prev_pos = ball.pos

    // Move ball
    if !MS.waiting_for_launch {
      ball.pos += ball.dir * ball.speed * DT

      if ball.pos.x + BALL_RADIUS > RIGHT_WALL_X {
        ball.pos.x = RIGHT_WALL_X - BALL_RADIUS
        ball.dir = reflect_ball(ball.dir, {-1, 0})
      }

      if ball.pos.x - BALL_RADIUS < LEFT_WALL_X {
        ball.pos.x = LEFT_WALL_X + BALL_RADIUS
        ball.dir = reflect_ball(ball.dir, {1, 0})
      }

      if ball.pos.y - BALL_RADIUS < TOP_WALL_Y {
        ball.pos.y = TOP_WALL_Y + BALL_RADIUS
        ball.dir = reflect_ball(ball.dir, {0, 1})
      }

      if ball.pos.y > SCREEN_SIZE_Y + BALL_RADIUS * 5 {
        unordered_remove(&MS.balls, i)
        switch len(MS.balls) {
        case 1: {
          MS.active_powerups[.Multiball] = false
        }
        case 0: {
          if lives == 0 {
            MS.game_over = true
            game_paused = true
            rl.PlaySound(game_over_sound)
          }
          else {
            lives -= 1
            reset_paddle()
          }
        }
        }
      }
    }

    // NOTE: Snowflake physics for ball-paddle collison
    if rl.CheckCollisionCircleRec(ball.pos, BALL_RADIUS, paddle_rect) {
      ball_hit_paddle(i)

      if MS.active_powerups[.Catch] {
        ball.speed = 0
        MS.waiting_for_launch = true
      }

      rl.PlaySound(hit_paddle_sound)
    }

    // Check for ball-block collision
    block_x_loop: for x in 0 ..< NUM_BLOCKS_X {
      for y in 0 ..< NUM_BLOCKS_Y {
        if blocks[x][y] == Block_Color.Empty {
          continue
        }

        block_rect := calc_block_rect(x, y)

        if rl.CheckCollisionCircleRec(ball.pos, BALL_RADIUS, block_rect) {
          collision_normal: rl.Vector2

          // TODO: Resolve this so that we only ever collide once and with the correct edge
          if ball.prev_pos.y < block_rect.y {


            collision_normal += {0, -1}
          } 
          if ball.prev_pos.y > block_rect.y + block_rect.height {
            collision_normal += {0, 1}
          } 
          if ball.prev_pos.x < block_rect.x {
            collision_normal += {-1, 0}
          } 
          if ball.prev_pos.x > block_rect.x + block_rect.width {
            collision_normal += {1, 0}
          }

          if block_exists(x + int(collision_normal.x), y) {
            collision_normal.x = 0
          }
          if block_exists(x, y + int(collision_normal.y)) {
            collision_normal.y = 0
          }
          if MS.active_powerups[.Pierce] && blocks[x][y] != Block_Color.Adamantium {
            collision_normal = 0
          }

          if collision_normal != 0 {
            ball.dir = reflect_ball(ball.dir, collision_normal)
          }

          damage_block_at_index(x, y)
          break block_x_loop
        }
      }
    }

    if MS.active_powerups[.Barrier] && rl.CheckCollisionCircleRec(ball.pos, BALL_RADIUS, BARRIER_RECT) {
      ball.dir = reflect_ball(ball.dir, {0, -1})
      MS.active_powerups[.Barrier] = false
    }

    if MS.active_powerups[.Pierce] {
      time := rl.GetTime()
      if (time > MS.next_ball_trail_tick_time) {
        append(&MS.ball_trails, Ball_Trail {ball.prev_pos, BALL_TRAIL_STEP*(BALL_TRAIL_LENGTH-1)})
        MS.next_ball_trail_tick_time = time + 0.01

        for i := len(MS.ball_trails) - 1; i >= 0; i -= 1 {
          trail := &MS.ball_trails[i]
          trail.opacity -= BALL_TRAIL_STEP
          if trail.opacity <= 0 {
            unordered_remove(&MS.ball_trails, i)
          } 
        }
      }
    }
  }

  // Move falling powerups and check if picked up
  for i := len(MS.falling_powerups) - 1; i >= 0; i -= 1 {
    powerup := &MS.falling_powerups[i]
    powerup.pos.y += POWERUP_SPEED * DT
    powerup_rect := rl.Rectangle {
      powerup.pos.x - POWERUP_SIZE, powerup.pos.y - POWERUP_SIZE,
      POWERUP_SIZE*2, POWERUP_SIZE*2
    }
    if rl.CheckCollisionRecs(paddle_rect, powerup_rect) {
      activate_powerup(powerup.type)
      unordered_remove(&MS.falling_powerups, i)
    } else if powerup_rect.y > SCREEN_SIZE_Y {
      unordered_remove(&MS.falling_powerups, i)
    }
  }

  for &laser in MS.lasers {
    for &origin in laser.origins {
      laser_hit_point := rl.Vector2 {
        origin.x,
        origin.y - LASER_SHOT_LENGTH
      }
      x, y, empty := block_at_point(laser_hit_point)
      if !empty {
        damage_block_at_index(x, y)
        origin = {}
      }
      else if laser_hit_point.y <= 0 {
        origin = {}
      }
      else {
        origin.y -= LASER_SHOT_SPEED
      }
    }
  }

  MS.paddle_pos_x = clamp(MS.paddle_pos_x, LEFT_WALL_X, RIGHT_WALL_X - MS.paddle_width)
  if MS.waiting_for_launch { move_ball_to_paddle() }
}

render :: proc() {
  rl.BeginDrawing()
  rl.ClearBackground(rl.BLACK)

  camera := rl.Camera2D {
    zoom = f32(rl.GetScreenHeight() / SCREEN_SIZE_Y),
  }

  rl.BeginMode2D(camera)

  if MS.active_powerups[.Laser] {
    for laser in MS.lasers {
      for origin in laser.origins {
        rect := rl.Rectangle {
          origin.x - LASER_SHOT_WIDTH, origin.y - LASER_SHOT_LENGTH,
          2*LASER_SHOT_WIDTH + 1, LASER_SHOT_LENGTH
        }
        rl.DrawRectangleRec(rect, rl.RED)
      }
    }
  }

  if MS.active_powerups[.Barrier] {
    barrier_color := rl.SKYBLUE
    barrier_color.a = u8(math.cos(rl.GetTime()) * 64 + 128)
    rl.DrawRectangleRec(BARRIER_RECT, barrier_color)
  }

  draw_rect_w_outline({MS.paddle_pos_x, PADDLE_POS_Y, MS.paddle_width, PADDLE_HEIGHT}, paddle_color)

  for ball in MS.balls {
    render_ball(ball.pos, 1.0)
  }

  if MS.active_powerups[.Pierce] {
    for &ball_trail in MS.ball_trails {
      render_ball(ball_trail.pos, ball_trail.opacity)
    }
  }

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

  for powerup in MS.falling_powerups {
    powerup_rect := rl.Rectangle {
      powerup.pos.x - POWERUP_SIZE, powerup.pos.y - POWERUP_SIZE,
      POWERUP_SIZE*2, POWERUP_SIZE*2
    }

    draw_rect_w_outline(powerup_rect, rl.BEIGE)
    x := i32(powerup.pos.x - POWERUP_SIZE + 2)
    y := i32(powerup.pos.y - POWERUP_SIZE + 1)
    str := char_to_cstring(powerup_letter[powerup.type])
    if powerup.type == .Slow && MS.active_powerups[.Slow] {
      str = "F"
    }
    rl.DrawText(str, x+1, y+1, 2, rl.BLACK)
    rl.DrawText(str, x, y, 2, rl.WHITE)
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

  if MS.waiting_for_launch {
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

  if MS.game_over {
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
}
