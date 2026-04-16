# frozen_string_literal: true

# YARD-only API documentation for schema setup methods.
module SchemaModel
  # Create/upgrade all required tables and compatibility migrations.
  # @param db_path [String] Path to SQLite database file.
  # @return [void]
  def self.setup_database!(db_path:); end

  # Ensure accounts table exists.
  # @param db_path [String]
  # @return [void]
  def self.ensure_accounts_table!(db_path:); end

  # Ensure accounts.role column exists and normalize existing values.
  # @param db_path [String]
  # @return [void]
  def self.ensure_accounts_role_column!(db_path:); end

  # Ensure pieces.icon_base_color column exists.
  # @param db_path [String]
  # @return [void]
  def self.ensure_pieces_icon_base_color_column!(db_path:); end

  # Ensure boards table exists.
  # @param db_path [String]
  # @return [void]
  def self.ensure_boards_table!(db_path:); end

  # Ensure board_piece_links relation table exists.
  # @param db_path [String]
  # @return [void]
  def self.ensure_board_piece_links_table!(db_path:); end

  # Ensure login_attempts table and index exist.
  # @param db_path [String]
  # @return [void]
  def self.ensure_login_attempts_table!(db_path:); end

  # Rebuild relation rows from boards.placements_json for old databases.
  # @param db_path [String]
  # @return [void]
  def self.rebuild_board_piece_links_from_boards!(db_path:); end
end

# YARD-only API documentation for query methods used by controllers/helpers.
module QueryModel
  # Run SQL statements inside a DB transaction.
  # @yield Transaction body.
  # @return [Object] The yielded result.
  def with_transaction; end

  # Fetch current logged-in account from session.
  # @return [Hash, nil] Account row or nil when guest.
  def current_account; end

  # Find account by email.
  # @param email [String]
  # @return [Hash, nil]
  def find_account_by_email(email); end

  # Check if account email already exists.
  # @param email [String]
  # @return [Boolean]
  def account_exists_by_email?(email); end

  # Insert account row and return created id.
  # @param username [String]
  # @param email [String]
  # @param password_hash [String]
  # @param now [String]
  # @return [Integer]
  def create_account!(username:, email:, password_hash:, now:); end

  # Insert one login attempt event.
  # @param email [String]
  # @param ip_address [String]
  # @param success [Boolean]
  # @param now [String]
  # @return [void]
  def log_login_attempt!(email:, ip_address:, success:, now:); end

  # Count failed login attempts in a time window.
  # @param email [String]
  # @param ip_address [String]
  # @param since [String]
  # @return [Integer]
  def recent_failed_login_attempts(email:, ip_address:, since:); end

  # List all accounts for admin panel.
  # @return [Array<Hash>]
  def admin_accounts_list; end

  # Fetch one account by id.
  # @param id [Integer]
  # @return [Hash, nil]
  def account_by_id(id); end

  # List pieces owned by one account.
  # @param owner_id [Integer]
  # @return [Array<Hash>]
  def pieces_owned_by_account(owner_id); end

  # List boards owned by one account.
  # @param owner_id [Integer]
  # @return [Array<Hash>]
  def boards_owned_by_account(owner_id); end

  # Delete account and clean up owned boards/pieces.
  # @param account_id [Integer]
  # @param now [String]
  # @return [void]
  def delete_account_and_owned_content!(account_id:, now:); end

  # Fetch any piece by id (ignores ownership, excludes deleted/clones).
  # @param id [Integer]
  # @return [Hash, nil]
  def piece_by_id_any(id); end

  # Fetch one piece if visible to current owner (default/public/own).
  # @param id [Integer]
  # @param owner_id [Integer]
  # @return [Hash, nil]
  def piece_visible_by_id_for_owner(id, owner_id); end

  # Fetch one piece owned by owner id.
  # @param id [Integer]
  # @param owner_id [Integer]
  # @return [Hash, nil]
  def piece_owned_by_id_for_owner(id, owner_id); end

  # List pieces visible in list page.
  # @param owner_id [Integer]
  # @param show_public [Boolean]
  # @return [Array<Hash>]
  def pieces_for_owner(owner_id, show_public: false); end

  # List selectable pieces for editor forms.
  # @param owner_id [Integer]
  # @return [Array<Hash>]
  def available_pieces_for_owner(owner_id); end

  # Fetch many pieces by id list.
  # @param piece_ids [Array<Integer>]
  # @return [Array<Hash>]
  def pieces_by_ids(piece_ids); end

  # Fetch power rows by ids.
  # @param power_ids [Array<Integer>]
  # @return [Array<Hash>]
  def special_powers_by_ids(power_ids); end

  # Build id=>movement_method hash map.
  # @param method_ids [Array<Integer>]
  # @return [Hash{Integer=>Hash}]
  def movement_method_map(method_ids); end

  # Keep only power ids that exist in DB.
  # @param selected_power_ids [Array<Integer>]
  # @return [Array<Integer>]
  def valid_power_ids(selected_power_ids); end

  # Insert one row in piece_moves.
  # @param piece_id [Integer]
  # @param method [Hash]
  # @param ray_limit [Integer, nil]
  # @param mode [String]
  # @param color_scope [String]
  # @param first_move_only [Integer]
  # @param now [String]
  # @return [void]
  def insert_piece_move_row!(piece_id:, method:, ray_limit:, mode:, color_scope:, first_move_only:, now:); end

  # List all movement methods.
  # @return [Array<Hash>]
  def movement_methods_all; end

  # List all powers.
  # @return [Array<Hash>]
  def powers_all; end

  # List raw piece move rows for edit form grouping.
  # @param piece_id [Integer]
  # @return [Array<Hash>]
  def piece_move_rows_for_piece(piece_id); end

  # List piece moves with movement method join for show page.
  # @param piece_id [Integer]
  # @return [Array<Hash>]
  def piece_moves_for_show(piece_id); end

  # Insert piece row and return id.
  # @param owner_id [Integer]
  # @param name [String]
  # @param description [String, nil]
  # @param image_path [String, nil]
  # @param icon_base_color [String]
  # @param is_public [Integer]
  # @param power_ids_json [String]
  # @param now [String]
  # @return [Integer]
  def create_piece_record!(owner_id:, name:, description:, image_path:, icon_base_color:, is_public:, power_ids_json:, now:); end

  # Update piece row.
  # @param id [Integer]
  # @param name [String]
  # @param description [String, nil]
  # @param image_path [String, nil]
  # @param icon_base_color [String]
  # @param is_public [Integer]
  # @param power_ids_json [String]
  # @param now [String]
  # @return [void]
  def update_piece_record!(id:, name:, description:, image_path:, icon_base_color:, is_public:, power_ids_json:, now:); end

  # Remove all move rows for one piece.
  # @param piece_id [Integer]
  # @return [void]
  def delete_piece_moves_for_piece!(piece_id); end

  # Mark piece as detached (kept for boards) by setting owner_id = -1.
  # @param piece_id [Integer]
  # @param now [String]
  # @return [void]
  def mark_piece_as_detached!(piece_id:, now:); end

  # Permanently delete piece row.
  # @param piece_id [Integer]
  # @return [void]
  def hard_delete_piece!(piece_id); end

  # Extract unique piece ids from placements JSON structure.
  # @param placements [Array<Hash>]
  # @return [Array<Integer>]
  def piece_ids_from_placements(placements); end

  # Sync board_piece_links rows from current placements.
  # @param board_id [Integer]
  # @param placements [Array<Hash>]
  # @param now [String]
  # @return [void]
  def sync_board_piece_links!(board_id, placements, now: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')); end

  # Remove all board_piece_links for one board.
  # @param board_id [Integer]
  # @return [void]
  def delete_board_piece_links!(board_id); end

  # Check if piece is linked by any board.
  # @param piece_id [Integer]
  # @return [Boolean]
  def piece_linked_to_any_board?(piece_id); end

  # List boards visible in list page.
  # @param owner_id [Integer]
  # @param show_public [Boolean]
  # @return [Array<Hash>]
  def boards_for_owner(owner_id, show_public: false); end

  # Fetch one board if visible to current owner (default/public/own).
  # @param id [Integer]
  # @param owner_id [Integer]
  # @return [Hash, nil]
  def board_visible_by_id_for_owner(id, owner_id); end

  # Fetch any board by id (ignores ownership).
  # @param id [Integer]
  # @return [Hash, nil]
  def board_by_id_any(id); end

  # Fetch one board owned by owner id.
  # @param id [Integer]
  # @param owner_id [Integer]
  # @return [Hash, nil]
  def board_owned_by_id_for_owner(id, owner_id); end

  # Create board row and sync relation links.
  # @param owner_id [Integer]
  # @param name [String]
  # @param description [String, nil]
  # @param board_size [Integer]
  # @param placements [Array<Hash>]
  # @param is_public [Integer]
  # @param now [String]
  # @return [Integer]
  def create_board_with_links!(owner_id:, name:, description:, board_size:, placements:, is_public:, now:); end

  # Update board row and sync relation links.
  # @param id [Integer]
  # @param name [String]
  # @param description [String, nil]
  # @param board_size [Integer]
  # @param placements [Array<Hash>]
  # @param is_public [Integer]
  # @param now [String]
  # @return [void]
  def update_board_with_links!(id:, name:, description:, board_size:, placements:, is_public:, now:); end

  # Soft-delete board and remove relation links.
  # @param id [Integer]
  # @param now [String]
  # @return [void]
  def soft_delete_board_with_links!(id:, now:); end
end
