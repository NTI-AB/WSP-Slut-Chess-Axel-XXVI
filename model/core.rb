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
      'SELECT id, username, email, role FROM accounts WHERE id = ?',
      [session[:account_id].to_i]
    )
  rescue SQLite3::SQLException
    @current_account = nil
  end
end
