require 'sqlite3'

DB_PATH = 'databas.db'

POWERS = [
  { id: 1, name: 'Doomfist Smash', description: 'Stuns on capture.' },
  { id: 2, name: 'Sniper Shot', description: 'Can capture while stationary.' },
  { id: 3, name: 'Juggernaut Charge', description: 'Must move to the furthest reachable square.' },
  { id: 4, name: 'Assassin Jump', description: 'Jump capture behavior.' },
  { id: 5, name: 'Catapult Launch', description: 'Can launch an adjacent ally.' },
  { id: 6, name: 'Wraith Possession', description: 'Possession behavior.' },
  { id: 7, name: 'Berserker Chain', description: 'Can chain captures.' }
].freeze

db = SQLite3::Database.new(DB_PATH)
db.execute('PRAGMA foreign_keys = ON')

def seed!(db)
  puts "Using db file: #{DB_PATH}"
  puts 'Seeding powers (special attributes)...'
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
  db.execute('DELETE FROM powers')
end

def populate_powers(db)
  POWERS.each do |power|
    db.execute(
      'INSERT INTO powers (id, name, description) VALUES (?, ?, ?)',
      [power[:id], power[:name], power[:description]]
    )
  end
end

seed!(db)
