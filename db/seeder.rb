require 'sqlite3'
require 'json'
require 'time'

DB_PATH = 'databas.db'
MOVEMENT_JSON_PATH = File.join(__dir__, 'piece_movement.json')
DEFAULT_PREVIEW_BOARD_JSON = '{"size":8,"placed":[]}'

MOVEMENT_PATTERNS = [
  {
    id: 1,
    name: 'orthogonal_ray_unlimited',
    description: 'Moves along rank/file rays with no fixed distance limit.',
    movement: {
      name: 'orthogonal_ray_unlimited',
      rays: [[1, 0], [-1, 0], [0, 1], [0, -1]],
      ray_limit: nil
    }
  },
  {
    id: 2,
    name: 'diagonal_ray_unlimited',
    description: 'Moves along diagonal rays with no fixed distance limit.',
    movement: {
      name: 'diagonal_ray_unlimited',
      rays: [[1, 1], [1, -1], [-1, 1], [-1, -1]],
      ray_limit: nil
    }
  },
  {
    id: 3,
    name: 'king_step_any_direction',
    description: 'One-square step in any direction.',
    movement: {
      name: 'king_step_any_direction',
      rays: [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]],
      ray_limit: 1
    }
  },
  {
    id: 4,
    name: 'knight_leap',
    description: 'L-shaped leap movement.',
    movement: {
      name: 'knight_leap',
      leaps: [[1, 2], [2, 1], [2, -1], [1, -2], [-1, -2], [-2, -1], [-2, 1], [-1, 2]]
    }
  },
  {
    id: 5,
    name: 'pawn_core_directional',
    description: 'Directional pawn movement and capture rules.',
    movement: {
      name: 'pawn_core_directional',
      white: {
        move_only: [[0, -1]],
        capture_only: [[-1, -1], [1, -1]],
        first_move: { rays: [[0, -1]], ray_limit: 2 }
      },
      black: {
        move_only: [[0, 1]],
        capture_only: [[-1, 1], [1, 1]],
        first_move: { rays: [[0, 1]], ray_limit: 2 }
      }
    }
  }
].freeze

PIECE_SEEDS = [
  { id: 1, name: 'King', description: 'Moves one square in any direction.' },
  { id: 2, name: 'Queen', description: 'Moves any number of squares in any direction.' },
  { id: 3, name: 'Rook', description: 'Moves any number of squares orthogonally.' },
  { id: 4, name: 'Bishop', description: 'Moves any number of squares diagonally.' },
  { id: 5, name: 'Knight', description: 'Moves in an L-shape, jumping over pieces.' },
  { id: 6, name: 'Pawn', description: 'Moves forward, captures diagonally; direction depends on color.' }
].freeze

PIECE_POWER_SEEDS = {
  1 => [3],
  2 => [1, 2],
  3 => [1],
  4 => [2],
  5 => [4],
  6 => [5]
}.freeze

db = SQLite3::Database.new(DB_PATH)
db.execute('PRAGMA foreign_keys = ON')

def seed!(db)
  puts "Using db file: #{DB_PATH}"
  puts 'Dropping old tables...'
  drop_tables(db)
  puts 'Creating tables...'
  create_tables(db)
  puts 'Populating movement patterns...'
  populate_powers(db)
  puts 'Populating pieces...'
  populate_pieces(db)
  puts 'Populating piece_powers...'
  populate_piece_powers(db)
  puts 'Writing piece_movement.json...'
  write_movement_json
  puts 'Done seeding the database!'
end

def drop_tables(db)
  db.execute('DROP TABLE IF EXISTS piece_powers')
  db.execute('DROP TABLE IF EXISTS powers')
  db.execute('DROP TABLE IF EXISTS pieces')
end

def create_tables(db)
  db.execute <<~SQL
    CREATE TABLE IF NOT EXISTS pieces (
      id INTEGER PRIMARY KEY,
      owner_id INTEGER NOT NULL DEFAULT 0,
      source_piece_id INTEGER,
      name TEXT NOT NULL,
      description TEXT,
      image_path TEXT,
      is_public INTEGER NOT NULL DEFAULT 0 CHECK (is_public IN (0, 1)),
      preview_board_json TEXT NOT NULL DEFAULT '{"size":8,"placed":[]}',
      stun_on_capture INTEGER NOT NULL DEFAULT 0 CHECK (stun_on_capture IN (0, 1)),
      stationary_capture INTEGER NOT NULL DEFAULT 0 CHECK (stationary_capture IN (0, 1)),
      furthest_only INTEGER NOT NULL DEFAULT 0 CHECK (furthest_only IN (0, 1)),
      jump_capture INTEGER NOT NULL DEFAULT 0 CHECK (jump_capture IN (0, 1)),
      launch_ally INTEGER NOT NULL DEFAULT 0 CHECK (launch_ally IN (0, 1)),
      possession INTEGER NOT NULL DEFAULT 0 CHECK (possession IN (0, 1)),
      berserk_chain INTEGER NOT NULL DEFAULT 0 CHECK (berserk_chain IN (0, 1)),
      deleted_at DATETIME,
      created_at DATETIME NOT NULL,
      updated_at DATETIME NOT NULL,
      FOREIGN KEY (source_piece_id) REFERENCES pieces(id) ON DELETE SET NULL
    )
  SQL

  db.execute <<~SQL
    CREATE TABLE IF NOT EXISTS powers (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL UNIQUE,
      description TEXT
    )
  SQL

  db.execute <<~SQL
    CREATE TABLE IF NOT EXISTS piece_powers (
      piece_id INTEGER NOT NULL,
      power_id INTEGER NOT NULL,
      PRIMARY KEY (piece_id, power_id),
      FOREIGN KEY (piece_id) REFERENCES pieces(id) ON DELETE CASCADE,
      FOREIGN KEY (power_id) REFERENCES powers(id) ON DELETE CASCADE
    )
  SQL
end

def populate_powers(db)
  MOVEMENT_PATTERNS.each do |pattern|
    db.execute(
      'INSERT INTO powers (id, name, description) VALUES (?, ?, ?)',
      [pattern[:id], pattern[:name], pattern[:description]]
    )
  end
end

def populate_pieces(db)
  now = Time.now.utc.iso8601

  PIECE_SEEDS.each do |piece|
    db.execute(
      <<~SQL,
        INSERT INTO pieces (
          id, owner_id, source_piece_id, name, description, image_path, is_public,
          preview_board_json, stun_on_capture, stationary_capture, furthest_only,
          jump_capture, launch_ally, possession, berserk_chain, deleted_at,
          created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      [
        piece[:id],
        0,
        nil,
        piece[:name],
        piece[:description],
        nil,
        1,
        DEFAULT_PREVIEW_BOARD_JSON,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        nil,
        now,
        now
      ]
    )
  end
end

def populate_piece_powers(db)
  PIECE_POWER_SEEDS.each do |piece_id, power_ids|
    power_ids.each do |power_id|
      db.execute(
        'INSERT INTO piece_powers (piece_id, power_id) VALUES (?, ?)',
        [piece_id, power_id]
      )
    end
  end
end

def write_movement_json
  rules = MOVEMENT_PATTERNS.each_with_object({}) do |pattern, memo|
    memo[pattern[:id]] = pattern[:movement]
  end

  lines = rules.sort_by { |id, _| id.to_i }.map do |id, data|
    "  \"#{id}\": #{JSON.generate(data)}"
  end

  json = "{\n#{lines.join(",\n")}\n}\n"
  File.write(MOVEMENT_JSON_PATH, json)
end

seed!(db)
