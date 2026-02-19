require 'sqlite3'

DB_PATH = 'databas.db'
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
  puts 'Seeding piece_powers...'
  create_tables(db)
  clear_table(db)
  populate_piece_powers(db)
  puts "Done seeding piece_powers!"
end

def create_tables(db)
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

def clear_table(db)
  db.execute('DELETE FROM piece_powers')
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

seed!(db)
