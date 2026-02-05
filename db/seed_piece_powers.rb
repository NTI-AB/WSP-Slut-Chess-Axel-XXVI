require 'sqlite3'

DB_PATH = 'databas.db'

db = SQLite3::Database.new(DB_PATH)
db.execute('PRAGMA foreign_keys = ON')

def seed!(db)
  puts "Using db file: #{DB_PATH}"
  puts "Seeding piece_powers (empty)..."
  create_tables(db)
  clear_table(db)
  puts "Done seeding piece_powers!"
end

def create_tables(db)
  db.execute <<~SQL
    CREATE TABLE IF NOT EXISTS piece_powers (
      piece_id INTEGER NOT NULL,
      power_id INTEGER NOT NULL,
      PRIMARY KEY (piece_id, power_id),
      FOREIGN KEY (piece_id) REFERENCES pieces(id),
      FOREIGN KEY (power_id) REFERENCES powers(id)
    )
  SQL
end

def clear_table(db)
  db.execute('DELETE FROM piece_powers')
end

seed!(db)
