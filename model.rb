require 'sqlite3'
require 'json'
require 'time'

module SchemaModel
  module_function

  def setup_database!(db_path:)
    ensure_accounts_table!(db_path: db_path)
    ensure_pieces_icon_base_color_column!(db_path: db_path)
    ensure_boards_table!(db_path: db_path)
    ensure_board_piece_links_table!(db_path: db_path)
    rebuild_board_piece_links_from_boards!(db_path: db_path)
  end

  def ensure_accounts_table!(db_path:)
    conn = SQLite3::Database.new(db_path)
    conn.execute <<~SQL
      CREATE TABLE IF NOT EXISTS accounts (
        id INTEGER PRIMARY KEY,
        username TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        created_at DATETIME NOT NULL,
        updated_at DATETIME NOT NULL
      )
    SQL
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

module QueryModel
  def with_transaction
    db.transaction
    result = yield
    db.commit
    result
  rescue SQLite3::SQLException
    db.rollback
    raise
  end

  def current_account
    return @current_account if defined?(@current_account_loaded) && @current_account_loaded
    @current_account_loaded = true
    @current_account = nil
    return nil unless session[:account_id]

    @current_account = db.get_first_row(
      'SELECT id, username, email FROM accounts WHERE id = ?',
      [session[:account_id].to_i]
    )
  rescue SQLite3::SQLException
    @current_account = nil
  end

  def piece_visible_by_id_for_owner(id, owner_id)
    default_owner_id = default_premade_piece_owner_id
    db.get_first_row(
      <<~SQL,
        SELECT *
        FROM pieces
        WHERE id = ?
          AND deleted_at IS NULL
          AND source_piece_id IS NULL
          AND (
            owner_id = ?
            OR (? > 0 AND owner_id = ?)
            OR is_public = 1
          )
      SQL
      [id, default_owner_id, owner_id, owner_id]
    )
  end

  def piece_owned_by_id_for_owner(id, owner_id)
    db.get_first_row(
      'SELECT * FROM pieces WHERE id = ? AND deleted_at IS NULL AND source_piece_id IS NULL AND owner_id = ?',
      [id, owner_id]
    )
  end

  def pieces_for_owner(owner_id, show_public: false)
    default_owner_id = default_premade_piece_owner_id
    show_public_int = show_public ? 1 : 0
    db.execute(
      <<~SQL,
        SELECT id, name, description, image_path, icon_base_color, created_at, owner_id, is_public
        FROM pieces
        WHERE deleted_at IS NULL
          AND source_piece_id IS NULL
          AND (
            owner_id = ?
            OR (? > 0 AND owner_id = ?)
            OR (? = 1 AND is_public = 1 AND owner_id != ? AND owner_id != ?)
          )
        ORDER BY id
      SQL
      [default_owner_id, owner_id, owner_id, show_public_int, default_owner_id, owner_id]
    )
  end

  def available_pieces_for_owner(owner_id)
    default_owner_id = default_premade_piece_owner_id
    db.execute(
      <<~SQL,
        SELECT id, name, image_path, icon_base_color
        FROM pieces
        WHERE deleted_at IS NULL
          AND source_piece_id IS NULL
          AND (
            owner_id = ?
            OR (? > 0 AND owner_id = ?)
          )
        ORDER BY LOWER(name), id
      SQL
      [default_owner_id, owner_id, owner_id]
    )
  end

  def pieces_by_ids(piece_ids)
    return [] if piece_ids.empty?

    placeholders = (['?'] * piece_ids.length).join(',')
    db.execute(
      "SELECT id, name, image_path, icon_base_color FROM pieces WHERE id IN (#{placeholders}) AND deleted_at IS NULL",
      piece_ids
    )
  end

  def piece_ids_from_placements(placements)
    placements.filter_map do |entry|
      next unless entry.is_a?(Hash)
      raw_id = entry['piece_id'] || entry[:piece_id]
      next if raw_id.nil?
      id = raw_id.to_i
      next unless id.positive?
      id
    end.uniq
  end

  def sync_board_piece_links!(board_id, placements, now: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'))
    ids = piece_ids_from_placements(placements)
    db.execute('DELETE FROM board_piece_links WHERE board_id = ?', [board_id])
    ids.each do |piece_id|
      db.execute(
        'INSERT OR IGNORE INTO board_piece_links (board_id, piece_id, created_at) VALUES (?, ?, ?)',
        [board_id, piece_id, now]
      )
    end
  end

  def delete_board_piece_links!(board_id)
    db.execute('DELETE FROM board_piece_links WHERE board_id = ?', [board_id])
  end

  def piece_linked_to_any_board?(piece_id)
    value = db.get_first_value('SELECT 1 FROM board_piece_links WHERE piece_id = ? LIMIT 1', [piece_id])
    !value.nil?
  end

  def boards_for_owner(owner_id, show_public: false)
    default_owner_id = default_premade_piece_owner_id
    show_public_int = show_public ? 1 : 0
    db.execute(
      <<~SQL,
        SELECT id, name, description, board_size, is_public, created_at, updated_at, owner_id
        FROM boards
        WHERE deleted_at IS NULL
          AND (
            owner_id = ?
            OR (? > 0 AND owner_id = ?)
            OR (? = 1 AND is_public = 1 AND owner_id != ? AND owner_id != ?)
          )
        ORDER BY id DESC
      SQL
      [default_owner_id, owner_id, owner_id, show_public_int, default_owner_id, owner_id]
    )
  end

  def board_visible_by_id_for_owner(id, owner_id)
    default_owner_id = default_premade_piece_owner_id
    db.get_first_row(
      <<~SQL,
        SELECT id, owner_id, name, description, board_size, placements_json, is_public, created_at, updated_at
        FROM boards
        WHERE id = ?
          AND deleted_at IS NULL
          AND (
            owner_id = ?
            OR (? > 0 AND owner_id = ?)
            OR is_public = 1
          )
      SQL
      [id, default_owner_id, owner_id, owner_id]
    )
  end

  def board_owned_by_id_for_owner(id, owner_id)
    db.get_first_row(
      <<~SQL,
        SELECT id, owner_id, name, description, board_size, placements_json, is_public, created_at, updated_at
        FROM boards
        WHERE id = ?
          AND deleted_at IS NULL
          AND owner_id = ?
      SQL
      [id, owner_id]
    )
  end

  def special_powers_by_ids(power_ids)
    return [] if power_ids.empty?

    placeholders = (['?'] * power_ids.length).join(',')
    db.execute("SELECT id, name, description FROM powers WHERE id IN (#{placeholders}) ORDER BY id", power_ids)
  end

  def movement_method_map(method_ids)
    return {} if method_ids.empty?

    placeholders = (['?'] * method_ids.length).join(',')
    methods = db.execute("SELECT id, name, kind, vectors_json, supports_ray_limit FROM movement_methods WHERE id IN (#{placeholders})", method_ids)
    methods.each_with_object({}) { |method, memo| memo[method['id']] = method }
  end

  def valid_power_ids(selected_power_ids)
    return [] if selected_power_ids.empty?

    placeholders = (['?'] * selected_power_ids.length).join(',')
    db.execute("SELECT id FROM powers WHERE id IN (#{placeholders})", selected_power_ids).map { |row| row['id'].to_i }
  end

  def insert_piece_move_row!(piece_id:, method:, ray_limit:, mode:, color_scope:, first_move_only:, now:)
    db.execute(
      'INSERT INTO piece_moves (piece_id, movement_method_id, name, kind, vectors_json, ray_limit, mode, color_scope, first_move_only, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        piece_id,
        method['id'],
        method['name'],
        method['kind'],
        method['vectors_json'],
        ray_limit,
        mode,
        color_scope,
        first_move_only,
        now,
        now
      ]
    )
  end

  def find_account_by_email(email)
    db.get_first_row('SELECT id, username, email, password_hash FROM accounts WHERE email = ?', [email])
  end

  def account_exists_by_email?(email)
    !db.get_first_row('SELECT id FROM accounts WHERE email = ?', [email]).nil?
  end

  def create_account!(username:, email:, password_hash:, now:)
    db.execute(
      'INSERT INTO accounts (username, email, password_hash, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
      [username, email, password_hash, now, now]
    )
    db.last_insert_row_id
  end

  def movement_methods_all
    db.execute('SELECT id, key, name, kind, vectors_json, supports_ray_limit, description FROM movement_methods ORDER BY id')
  end

  def powers_all
    db.execute('SELECT id, name, description FROM powers ORDER BY id')
  end

  def piece_move_rows_for_piece(piece_id)
    db.execute(
      'SELECT id, movement_method_id, ray_limit, mode, color_scope, first_move_only FROM piece_moves WHERE piece_id = ? ORDER BY id',
      [piece_id]
    )
  end

  def piece_moves_for_show(piece_id)
    db.execute(<<~SQL, [piece_id])
      SELECT pm.id, pm.movement_method_id, pm.name, pm.kind, pm.ray_limit, pm.mode, pm.color_scope, pm.first_move_only, pm.vectors_json,
             mm.name AS method_name, mm.description AS method_description
      FROM piece_moves pm
      LEFT JOIN movement_methods mm ON mm.id = pm.movement_method_id
      WHERE pm.piece_id = ?
      ORDER BY pm.id
    SQL
  end

  def create_board_with_links!(owner_id:, name:, description:, board_size:, placements:, is_public:, now:)
    board_id = nil
    db.transaction
    db.execute(
      'INSERT INTO boards (owner_id, name, description, board_size, placements_json, is_public, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [owner_id, name, description, board_size, JSON.generate(placements), is_public, now, now]
    )
    board_id = db.last_insert_row_id
    sync_board_piece_links!(board_id, placements, now: now)
    db.commit
    board_id
  rescue SQLite3::SQLException
    db.rollback
    raise
  end

  def update_board_with_links!(id:, name:, description:, board_size:, placements:, is_public:, now:)
    db.transaction
    db.execute(
      'UPDATE boards SET name = ?, description = ?, board_size = ?, placements_json = ?, is_public = ?, updated_at = ? WHERE id = ?',
      [name, description, board_size, JSON.generate(placements), is_public, now, id]
    )
    sync_board_piece_links!(id, placements, now: now)
    db.commit
  rescue SQLite3::SQLException
    db.rollback
    raise
  end

  def soft_delete_board_with_links!(id:, now:)
    db.transaction
    db.execute('UPDATE boards SET deleted_at = ?, updated_at = ? WHERE id = ?', [now, now, id])
    delete_board_piece_links!(id)
    db.commit
  rescue SQLite3::SQLException
    db.rollback
    raise
  end

  def create_piece_record!(owner_id:, name:, description:, image_path:, icon_base_color:, is_public:, power_ids_json:, now:)
    db.execute(
      'INSERT INTO pieces (owner_id, source_piece_id, name, description, image_path, icon_base_color, is_public, power_ids, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [owner_id, nil, name, description, image_path, icon_base_color, is_public, power_ids_json, now, now]
    )
    db.last_insert_row_id
  end

  def update_piece_record!(id:, name:, description:, image_path:, icon_base_color:, is_public:, power_ids_json:, now:)
    db.execute(
      'UPDATE pieces SET name = ?, description = ?, image_path = ?, icon_base_color = ?, is_public = ?, power_ids = ?, updated_at = ? WHERE id = ?',
      [name, description, image_path, icon_base_color, is_public, power_ids_json, now, id]
    )
  end

  def delete_piece_moves_for_piece!(piece_id)
    db.execute('DELETE FROM piece_moves WHERE piece_id = ?', [piece_id])
  end

  def mark_piece_as_detached!(piece_id:, now:)
    db.execute('UPDATE pieces SET owner_id = -1, is_public = 0, updated_at = ? WHERE id = ?', [now, piece_id])
  end

  def hard_delete_piece!(piece_id)
    db.execute('DELETE FROM pieces WHERE id = ?', [piece_id])
  end
end
