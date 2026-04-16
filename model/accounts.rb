module QueryModel
  def find_account_by_email(email)
    db.get_first_row('SELECT id, username, email, role, password_hash FROM accounts WHERE email = ?', [email])
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

  def log_login_attempt!(email:, ip_address:, success:, now:)
    db.execute(
      'INSERT INTO login_attempts (email, ip_address, success, created_at) VALUES (?, ?, ?, ?)',
      [email, ip_address, success ? 1 : 0, now]
    )
  end

  def recent_failed_login_attempts(email:, ip_address:, since:)
    db.get_first_value(
      'SELECT COUNT(*) FROM login_attempts WHERE email = ? AND ip_address = ? AND success = 0 AND created_at >= ?',
      [email, ip_address, since]
    ).to_i
  end

  def admin_accounts_list
    db.execute('SELECT id, username, email, role, created_at, updated_at FROM accounts ORDER BY id')
  end

  def account_by_id(id)
    db.get_first_row(
      'SELECT id, username, email, role, created_at, updated_at FROM accounts WHERE id = ?',
      [id]
    )
  end

  def pieces_owned_by_account(owner_id)
    db.execute(
      <<~SQL,
        SELECT id, name, is_public, created_at, updated_at
        FROM pieces
        WHERE deleted_at IS NULL
          AND source_piece_id IS NULL
          AND owner_id = ?
        ORDER BY id DESC
      SQL
      [owner_id]
    )
  end

  def boards_owned_by_account(owner_id)
    db.execute(
      <<~SQL,
        SELECT id, name, board_size, is_public, created_at, updated_at
        FROM boards
        WHERE deleted_at IS NULL
          AND owner_id = ?
        ORDER BY id DESC
      SQL
      [owner_id]
    )
  end

  # Deletes an account and cleans up owned boards/pieces.
  # Boards are removed first, then pieces:
  # - piece linked by remaining boards => detach owner (owner_id = -1)
  # - piece not linked by any board   => hard delete (+ piece_moves cleanup)
  def delete_account_and_owned_content!(account_id:, now:)
    db.transaction

    board_ids = db.execute(
      'SELECT id FROM boards WHERE owner_id = ? AND deleted_at IS NULL',
      [account_id]
    ).map { |row| row['id'].to_i }

    unless board_ids.empty?
      placeholders = (['?'] * board_ids.length).join(',')
      db.execute(
        "UPDATE boards SET deleted_at = ?, updated_at = ? WHERE id IN (#{placeholders})",
        [now, now, *board_ids]
      )
      db.execute(
        "DELETE FROM board_piece_links WHERE board_id IN (#{placeholders})",
        board_ids
      )
    end

    piece_ids = db.execute(
      'SELECT id FROM pieces WHERE owner_id = ? AND deleted_at IS NULL',
      [account_id]
    ).map { |row| row['id'].to_i }

    piece_ids.each do |piece_id|
      linked_elsewhere = !db.get_first_value(
        'SELECT 1 FROM board_piece_links WHERE piece_id = ? LIMIT 1',
        [piece_id]
      ).nil?

      if linked_elsewhere
        db.execute(
          'UPDATE pieces SET owner_id = -1, is_public = 0, updated_at = ? WHERE id = ?',
          [now, piece_id]
        )
      else
        db.execute('DELETE FROM piece_moves WHERE piece_id = ?', [piece_id])
        db.execute('DELETE FROM pieces WHERE id = ?', [piece_id])
      end
    end

    db.execute('DELETE FROM accounts WHERE id = ?', [account_id])
    db.commit
  rescue SQLite3::SQLException
    db.rollback
    raise
  end
end
