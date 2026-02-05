require 'sqlite3'
require 'json'
require 'time'

DB_PATH = 'databas.db'
MOVEMENT_JSON_PATH = File.join(__dir__, 'piece_movement.json')

db = SQLite3::Database.new(DB_PATH)
db.execute('PRAGMA foreign_keys = ON')

def seed!(db)
  puts "Using db file: #{DB_PATH}"
  puts "Dropping old tables..."
  drop_tables(db)
  puts "Creating tables..."
  create_tables(db)
  puts "Populating tables..."
  populate_pieces(db)
  write_movement_json
  puts "Done seeding the database!"
end

def drop_tables(db)
  db.execute('DROP TABLE IF EXISTS piece_powers')
  db.execute('DROP TABLE IF EXISTS pieces')
end

def create_tables(db)
  db.execute <<~SQL
    CREATE TABLE IF NOT EXISTS pieces (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      description TEXT,
      created_at DATETIME
    )
  SQL
end

def populate_pieces(db)
  now = Time.now.utc.iso8601
  pieces = [
    { id: 1, name: 'King', description: 'Moves one square in any direction.', created_at: now },
    { id: 2, name: 'Queen', description: 'Moves any number of squares in any direction.', created_at: now },
    { id: 3, name: 'Rook', description: 'Moves any number of squares orthogonally.', created_at: now },
    { id: 4, name: 'Bishop', description: 'Moves any number of squares diagonally.', created_at: now },
    { id: 5, name: 'Knight', description: 'Moves in an L-shape, jumping over pieces.', created_at: now },
    { id: 6, name: 'Pawn', description: 'Moves forward, captures diagonally; direction depends on color.', created_at: now }
  ]

  pieces.each do |piece|
    db.execute(
      'INSERT INTO pieces (id, name, description, created_at) VALUES (?, ?, ?, ?)',
      [piece[:id], piece[:name], piece[:description], piece[:created_at]]
    )
  end
end

def write_movement_json
  rules = {
    1 => {
      name: 'King',
      rays: [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]],
      ray_limit: 1
    },
    2 => {
      name: 'Queen',
      rays: [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]],
      ray_limit: nil
    },
    3 => {
      name: 'Rook',
      rays: [[1, 0], [-1, 0], [0, 1], [0, -1]],
      ray_limit: nil
    },
    4 => {
      name: 'Bishop',
      rays: [[1, 1], [1, -1], [-1, 1], [-1, -1]],
      ray_limit: nil
    },
    5 => {
      name: 'Knight',
      leaps: [[1, 2], [2, 1], [2, -1], [1, -2], [-1, -2], [-2, -1], [-2, 1], [-1, 2]]
    },
    6 => {
      name: 'Pawn',
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

  lines = rules.sort_by { |id, _| id.to_i }.map do |id, data|
    "  \"#{id}\": #{JSON.generate(data)}"
  end
  json = "{\n#{lines.join(",\n")}\n}\n"
  File.write(MOVEMENT_JSON_PATH, json)
end

seed!(db)
