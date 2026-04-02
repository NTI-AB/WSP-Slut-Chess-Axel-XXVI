module SchemaModel
  module_function

  def setup_database!(db_path:)
    ensure_accounts_table!(db_path: db_path)
    ensure_accounts_role_column!(db_path: db_path)
    ensure_pieces_icon_base_color_column!(db_path: db_path)
    ensure_boards_table!(db_path: db_path)
    ensure_board_piece_links_table!(db_path: db_path)
    ensure_login_attempts_table!(db_path: db_path)
    rebuild_board_piece_links_from_boards!(db_path: db_path)
  end

  def ensure_accounts_table!(db_path:)
    conn = SQLite3::Database.new(db_path)
    conn.execute <<~SQL
      CREATE TABLE IF NOT EXISTS accounts (
        id INTEGER PRIMARY KEY,
        username TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        role TEXT NOT NULL DEFAULT 'user',
        password_hash TEXT NOT NULL,
        created_at DATETIME NOT NULL,
        updated_at DATETIME NOT NULL
      )
    SQL
  ensure
    conn&.close
  end

  def ensure_accounts_role_column!(db_path:)
    conn = SQLite3::Database.new(db_path)
    table_exists = conn.get_first_value("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'accounts' LIMIT 1")
    return unless table_exists

    columns = conn.execute('PRAGMA table_info(accounts)').map { |row| row[1] }
    conn.execute("ALTER TABLE accounts ADD COLUMN role TEXT NOT NULL DEFAULT 'user'") unless columns.include?('role')
    conn.execute("UPDATE accounts SET role = 'user' WHERE role IS NULL OR role = ''")
    conn.execute("UPDATE accounts SET role = 'admin' WHERE id = 1")
  ensure
    conn&.close
  end

  def ensure_pieces_icon_base_color_column!(db_path:)
    conn = SQLite3::Database.new(db_path)
    table_exists = conn.get_first_value("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'pieces' LIMIT 1")
    return unless table_exists

    columns = conn.execute('PRAGMA table_info(pieces)').map { |row| row[1] }
    return if columns.include?('icon_base_color')

    conn.execute("ALTER TABLE pieces ADD COLUMN icon_base_color TEXT NOT NULL DEFAULT 'black'")
    conn.execute("UPDATE pieces SET icon_base_color = 'black' WHERE icon_base_color IS NULL OR icon_base_color = ''")
  ensure
    conn&.close
  end

  def ensure_boards_table!(db_path:)
    conn = SQLite3::Database.new(db_path)
    conn.execute <<~SQL
      CREATE TABLE IF NOT EXISTS boards (
        id INTEGER PRIMARY KEY,
        owner_id INTEGER NOT NULL DEFAULT 0,
        name TEXT NOT NULL,
        description TEXT,
        board_size INTEGER NOT NULL DEFAULT 8,
        placements_json TEXT NOT NULL DEFAULT '[]',
        is_public INTEGER NOT NULL DEFAULT 0 CHECK (is_public IN (0, 1)),
        deleted_at DATETIME,
        created_at DATETIME NOT NULL,
        updated_at DATETIME NOT NULL
      )
    SQL
  ensure
    conn&.close
  end

  def ensure_board_piece_links_table!(db_path:)
    conn = SQLite3::Database.new(db_path)
    conn.execute <<~SQL
      CREATE TABLE IF NOT EXISTS board_piece_links (
        id INTEGER PRIMARY KEY,
        board_id INTEGER NOT NULL,
        piece_id INTEGER NOT NULL,
        created_at DATETIME NOT NULL,
        UNIQUE(board_id, piece_id),
        FOREIGN KEY (board_id) REFERENCES boards(id) ON DELETE CASCADE,
        FOREIGN KEY (piece_id) REFERENCES pieces(id) ON DELETE CASCADE
      )
    SQL
  ensure
    conn&.close
  end

  def ensure_login_attempts_table!(db_path:)
    conn = SQLite3::Database.new(db_path)
    conn.execute <<~SQL
      CREATE TABLE IF NOT EXISTS login_attempts (
        id INTEGER PRIMARY KEY,
        email TEXT NOT NULL,
        ip_address TEXT NOT NULL,
        success INTEGER NOT NULL CHECK (success IN (0, 1)),
        created_at DATETIME NOT NULL
      )
    SQL
    conn.execute('CREATE INDEX IF NOT EXISTS idx_login_attempts_email_ip_created_at ON login_attempts(email, ip_address, created_at)')
  ensure
    conn&.close
  end

  def rebuild_board_piece_links_from_boards!(db_path:)
    conn = SQLite3::Database.new(db_path)
    boards_exists = conn.get_first_value("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'boards' LIMIT 1")
    links_exists = conn.get_first_value("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'board_piece_links' LIMIT 1")
    return unless boards_exists && links_exists

    rows = conn.execute('SELECT id, placements_json FROM boards WHERE deleted_at IS NULL')
    now = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')

    conn.transaction
    conn.execute('DELETE FROM board_piece_links')

    rows.each do |board_id, placements_raw|
      parsed = begin
        value = JSON.parse(placements_raw.to_s)
        value.is_a?(Array) ? value : []
      rescue JSON::ParserError
        []
      end

      piece_ids = parsed.filter_map do |entry|
        next unless entry.is_a?(Hash)
        id = entry['piece_id']
        next if id.nil?
        number = id.to_i
        next unless number.positive?
        number
      end.uniq

      piece_ids.each do |piece_id|
        conn.execute(
          'INSERT OR IGNORE INTO board_piece_links (board_id, piece_id, created_at) VALUES (?, ?, ?)',
          [board_id.to_i, piece_id, now]
        )
      end
    end

    conn.commit
  rescue SQLite3::SQLException
    conn&.rollback
  ensure
    conn&.close
  end
end
