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
end
