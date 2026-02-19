require 'sqlite3'
require 'json'
require 'time'

DB_PATH = 'databas.db'
MOVEMENT_JSON_PATH = File.join(__dir__, 'piece_movement.json')
DEFAULT_PREVIEW_BOARD_JSON = '{"size":8,"placed":[]}'
DEFAULT_POWER_IDS_JSON = '[]'

MOVEMENT_METHODS = [
  {
    id: 1,
    key: 'orthogonal_rays',
    name: 'Orthogonal Rays',
    kind: 'ray',
    supports_ray_limit: 1,
    description: 'Moves along rank/file rays with no fixed distance limit.',
    definition: {
      name: 'orthogonal_rays',
      rays: [[1, 0], [-1, 0], [0, 1], [0, -1]],
      ray_limit: nil
    }
  },
  {
    id: 2,
    key: 'diagonal_rays',
    name: 'Diagonal Rays',
    kind: 'ray',
    supports_ray_limit: 1,
    description: 'Moves along diagonal rays with no fixed distance limit.',
    definition: {
      name: 'diagonal_rays',
      rays: [[1, 1], [1, -1], [-1, 1], [-1, -1]],
      ray_limit: nil
    }
  },
  {
    id: 3,
    key: 'adjacent_any_direction',
    name: 'Adjacent Any Direction',
    kind: 'ray',
    supports_ray_limit: 1,
    description: 'One-square step in any direction.',
    definition: {
      name: 'adjacent_any_direction',
      rays: [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]],
      ray_limit: 1
    }
  },
  {
    id: 4,
    key: 'knight_leap',
    name: 'Knight Leap',
    kind: 'leap',
    supports_ray_limit: 0,
    description: 'L-shaped leap movement.',
    definition: {
      name: 'knight_leap',
      leaps: [[1, 2], [2, 1], [2, -1], [1, -2], [-1, -2], [-2, -1], [-2, 1], [-1, 2]]
    }
  },
  {
    id: 5,
    key: 'pawn_core_directional',
    name: 'Pawn Core Directional',
    kind: 'rule',
    supports_ray_limit: 0,
    description: 'Directional pawn movement and capture rules.',
    definition: {
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
  { id: 1, name: 'King', description: 'Moves one square in any direction.', power_ids: [] },
  { id: 2, name: 'Queen', description: 'Moves any number of squares in any direction.', power_ids: [] },
  { id: 3, name: 'Rook', description: 'Moves any number of squares orthogonally.', power_ids: [] },
  { id: 4, name: 'Bishop', description: 'Moves any number of squares diagonally.', power_ids: [] },
  { id: 5, name: 'Knight', description: 'Moves in an L-shape, jumping over pieces.', power_ids: [] },
  { id: 6, name: 'Pawn', description: 'Moves forward, captures diagonally; direction depends on color.', power_ids: [] }
].freeze

POWERS = [
  { id: 1, name: 'Doomfist Smash', description: 'Stuns on capture.' },
  { id: 2, name: 'Sniper Shot', description: 'Can capture while stationary.' },
  { id: 3, name: 'Juggernaut Charge', description: 'Must move to the furthest reachable square.' },
  { id: 4, name: 'Assassin Jump', description: 'Jump capture behavior.' },
  { id: 5, name: 'Catapult Launch', description: 'Can launch an adjacent ally.' },
  { id: 6, name: 'Wraith Possession', description: 'Possession behavior.' },
  { id: 7, name: 'Berserker Chain', description: 'Can chain captures.' }
].freeze

PIECE_MOVE_SEEDS = {
  1 => [{ movement_method_id: 3, ray_limit: 1, mode: 'both', color_scope: 'any', first_move_only: 0 }],
  2 => [
    { movement_method_id: 1, ray_limit: nil, mode: 'both', color_scope: 'any', first_move_only: 0 },
    { movement_method_id: 2, ray_limit: nil, mode: 'both', color_scope: 'any', first_move_only: 0 }
  ],
  3 => [{ movement_method_id: 1, ray_limit: nil, mode: 'both', color_scope: 'any', first_move_only: 0 }],
  4 => [{ movement_method_id: 2, ray_limit: nil, mode: 'both', color_scope: 'any', first_move_only: 0 }],
  5 => [{ movement_method_id: 4, ray_limit: nil, mode: 'both', color_scope: 'any', first_move_only: 0 }],
  6 => [{ movement_method_id: 5, ray_limit: nil, mode: 'both', color_scope: 'any', first_move_only: 0 }]
}.freeze

db = SQLite3::Database.new(DB_PATH)
db.execute('PRAGMA foreign_keys = ON')

def seed!(db)
  puts "Using db file: #{DB_PATH}"
  puts 'Dropping old tables...'
  drop_tables(db)
  puts 'Creating tables...'
  create_tables(db)
  puts 'Populating movement methods...'
  populate_movement_methods(db)
  puts 'Populating powers...'
  populate_powers(db)
  puts 'Populating pieces...'
  populate_pieces(db)
  puts 'Populating piece_moves...'
  populate_piece_moves(db)
  puts 'Writing piece_movement.json...'
  write_movement_json
  puts 'Done seeding the database!'
end

def drop_tables(db)
  db.execute('DROP TABLE IF EXISTS piece_powers')
  db.execute('DROP TABLE IF EXISTS powers')
  db.execute('DROP TABLE IF EXISTS piece_moves')
  db.execute('DROP TABLE IF EXISTS movement_methods')
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
      power_ids TEXT NOT NULL DEFAULT '[]',
      preview_board_json TEXT NOT NULL DEFAULT '{"size":8,"placed":[]}',
      deleted_at DATETIME,
      created_at DATETIME NOT NULL,
      updated_at DATETIME NOT NULL,
      FOREIGN KEY (source_piece_id) REFERENCES pieces(id) ON DELETE SET NULL
    )
  SQL

  db.execute <<~SQL
    CREATE TABLE IF NOT EXISTS movement_methods (
      id INTEGER PRIMARY KEY,
      key TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL UNIQUE,
      kind TEXT NOT NULL,
      vectors_json TEXT NOT NULL,
      supports_ray_limit INTEGER NOT NULL DEFAULT 0 CHECK (supports_ray_limit IN (0, 1)),
      description TEXT
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
    CREATE TABLE IF NOT EXISTS piece_moves (
      id INTEGER PRIMARY KEY,
      piece_id INTEGER NOT NULL,
      movement_method_id INTEGER,
      name TEXT NOT NULL,
      kind TEXT NOT NULL,
      vectors_json TEXT NOT NULL,
      ray_limit INTEGER,
      mode TEXT NOT NULL DEFAULT 'both' CHECK (mode IN ('move', 'capture', 'both')),
      color_scope TEXT NOT NULL DEFAULT 'any' CHECK (color_scope IN ('any', 'white', 'black')),
      first_move_only INTEGER NOT NULL DEFAULT 0 CHECK (first_move_only IN (0, 1)),
      created_at DATETIME NOT NULL,
      updated_at DATETIME NOT NULL,
      FOREIGN KEY (piece_id) REFERENCES pieces(id) ON DELETE CASCADE,
      FOREIGN KEY (movement_method_id) REFERENCES movement_methods(id) ON DELETE SET NULL
    )
  SQL
end

def populate_movement_methods(db)
  MOVEMENT_METHODS.each do |method|
    db.execute(
      'INSERT INTO movement_methods (id, key, name, kind, vectors_json, supports_ray_limit, description) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [method[:id], method[:key], method[:name], method[:kind], JSON.generate(method[:definition]), method[:supports_ray_limit], method[:description]]
    )
  end
end

def populate_powers(db)
  POWERS.each do |power|
    db.execute(
      'INSERT INTO powers (id, name, description) VALUES (?, ?, ?)',
      [power[:id], power[:name], power[:description]]
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
          power_ids, preview_board_json, deleted_at, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      [
        piece[:id],
        0,
        nil,
        piece[:name],
        piece[:description],
        nil,
        1,
        piece[:power_ids].empty? ? DEFAULT_POWER_IDS_JSON : JSON.generate(piece[:power_ids]),
        DEFAULT_PREVIEW_BOARD_JSON,
        nil,
        now,
        now
      ]
    )
  end
end

def populate_piece_moves(db)
  method_map = MOVEMENT_METHODS.each_with_object({}) { |method, memo| memo[method[:id]] = method }
  now = Time.now.utc.iso8601

  PIECE_MOVE_SEEDS.each do |piece_id, moves|
    moves.each do |move|
      method = method_map.fetch(move[:movement_method_id])
      db.execute(
        'INSERT INTO piece_moves (piece_id, movement_method_id, name, kind, vectors_json, ray_limit, mode, color_scope, first_move_only, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          piece_id,
          method[:id],
          method[:name],
          method[:kind],
          JSON.generate(method[:definition]),
          move[:ray_limit],
          move[:mode],
          move[:color_scope],
          move[:first_move_only],
          now,
          now
        ]
      )
    end
  end
end

def write_movement_json
  rules = MOVEMENT_METHODS.each_with_object({}) do |method, memo|
    memo[method[:id]] = method[:definition]
  end

  lines = rules.sort_by { |id, _| id.to_i }.map do |id, data|
    "  \"#{id}\": #{JSON.generate(data)}"
  end

  json = "{\n#{lines.join(",\n")}\n}\n"
  File.write(MOVEMENT_JSON_PATH, json)
end

seed!(db)
