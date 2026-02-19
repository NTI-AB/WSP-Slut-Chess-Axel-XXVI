require 'sqlite3'

DB_PATH = 'databas.db'

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

db = SQLite3::Database.new(DB_PATH)
db.execute('PRAGMA foreign_keys = ON')

def seed!(db)
  puts "Using db file: #{DB_PATH}"
  puts 'Seeding movement-pattern powers...'
  create_tables(db)
  clear_tables(db)
  populate_powers(db)
  puts 'Done seeding powers!'
end

def create_tables(db)
  db.execute <<~SQL
    CREATE TABLE IF NOT EXISTS powers (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL UNIQUE,
      description TEXT
    )
  SQL
end

def clear_tables(db)
  begin
    db.execute('DELETE FROM piece_powers')
  rescue SQLite3::SQLException
  end

  db.execute('DELETE FROM powers')
end

def populate_powers(db)
  MOVEMENT_PATTERNS.each do |pattern|
    db.execute(
      'INSERT INTO powers (id, name, description) VALUES (?, ?, ?)',
      [pattern[:id], pattern[:name], pattern[:description]]
    )
  end
end

seed!(db)
