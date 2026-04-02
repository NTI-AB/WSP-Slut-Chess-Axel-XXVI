module QueryModel
  def piece_by_id_any(id)
    db.get_first_row(
      'SELECT * FROM pieces WHERE id = ? AND deleted_at IS NULL AND source_piece_id IS NULL',
      [id]
    )
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
