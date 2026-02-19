require 'sqlite3'
require 'json'

DB_PATH = 'databas.db'
PIECE_POWER_SEEDS = {
  1 => [],
  2 => [],
  3 => [],
  4 => [],
  5 => [],
  6 => []
}.freeze

db = SQLite3::Database.new(DB_PATH)
db.execute('PRAGMA foreign_keys = ON')

def seed!(db)
  puts "Using db file: #{DB_PATH}"
  puts 'Seeding piece power_ids JSON column...'
  ensure_column_exists(db)
  populate_piece_power_ids(db)
  puts 'Done seeding piece power_ids!'
end

def ensure_column_exists(db)
  columns = db.execute('PRAGMA table_info(pieces)').map { |row| row[1] }
  return if columns.include?('power_ids')

  db.execute("ALTER TABLE pieces ADD COLUMN power_ids TEXT NOT NULL DEFAULT '[]'")
end

def populate_piece_power_ids(db)
  PIECE_POWER_SEEDS.each do |piece_id, power_ids|
    db.execute(
      'UPDATE pieces SET power_ids = ? WHERE id = ?',
      [JSON.generate(power_ids), piece_id]
    )
  end
end

seed!(db)
