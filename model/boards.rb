module QueryModel
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

  def board_by_id_any(id)
    db.get_first_row(
      <<~SQL,
        SELECT id, owner_id, name, description, board_size, placements_json, is_public, created_at, updated_at
        FROM boards
        WHERE id = ?
          AND deleted_at IS NULL
      SQL
      [id]
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
end
