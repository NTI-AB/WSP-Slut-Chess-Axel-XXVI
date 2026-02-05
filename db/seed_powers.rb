require 'sqlite3'

DB_PATH = 'databas.db'

db = SQLite3::Database.new(DB_PATH)
db.execute('PRAGMA foreign_keys = ON')

def seed!(db)
  puts "Using db file: #{DB_PATH}"
  puts "Seeding special powers..."
  create_tables(db)
  clear_tables(db)
  populate_powers(db)
  puts "Done seeding powers!"
end

def create_tables(db)
  db.execute <<~SQL
    CREATE TABLE IF NOT EXISTS powers (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
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
  powers = [
    { id: 1, name: 'Doomfist Smash', description: 'Special capture effect: applies a stun.' },
    { id: 2, name: 'Sniper Shot', description: 'Captures without moving.' },
    { id: 3, name: 'Assassin Jump', description: 'Jump-capture over adjacent piece.' },
    { id: 4, name: 'Catapult Launch', description: 'Launches an adjacent ally along a ray.' },
    { id: 5, name: 'Wraith Possession', description: 'Temporarily takes control of an enemy piece.' },
    { id: 6, name: 'Juggernaut Charge', description: 'Must move to the furthest reachable square.' },
    { id: 7, name: 'Berserker Chain', description: 'Allows chained captures under value rules.' }
  ]

  powers.each do |power|
    db.execute(
      'INSERT INTO powers (id, name, description) VALUES (?, ?, ?)',
      [power[:id], power[:name], power[:description]]
    )
  end
end

seed!(db)
