# frozen_string_literal: true

# YARD-only route reference for Sinatra endpoints in app.rb.
# These methods are documentation stubs only (not runtime code).
module RouteDocs
  # Redirect root path to pieces index.
  # @return [void]
  def get_root; end

  # Render login form.
  # @return [String] HTML
  def get_login; end

  # Login account and create session.
  # @param email [String]
  # @param password [String]
  # @return [void]
  def post_login(email:, password:); end

  # Render register form.
  # @return [String] HTML
  def get_register; end

  # Register account and login directly.
  # @param username [String]
  # @param email [String]
  # @param password [String]
  # @param confirm [String]
  # @return [void]
  def post_register(username:, email:, password:, confirm:); end

  # Logout current account.
  # @return [void]
  def post_logout; end

  # Render current account settings.
  # Route: GET /account
  # @return [String] HTML
  def get_account; end

  # Delete current account and owned content.
  # Route: POST /account/delete
  # @return [void]
  def post_account_delete; end

  # Admin: list accounts.
  # Route: GET /admin/accounts
  # @return [String] HTML
  def get_admin_accounts; end

  # Admin: list one account's pieces.
  # Route: GET /admin/accounts/:id/pieces
  # @param id [Integer]
  # @return [String] HTML
  def get_admin_account_pieces(id:); end

  # Admin: list one account's boards.
  # Route: GET /admin/accounts/:id/boards
  # @param id [Integer]
  # @return [String] HTML
  def get_admin_account_boards(id:); end

  # Admin: delete one account and owned content.
  # Route: POST /admin/accounts/:id/delete
  # @param id [Integer]
  # @return [void]
  def post_admin_account_delete(id:); end

  # List visible boards.
  # Route: GET /boards
  # @param show_public [String, nil]
  # @return [String] HTML
  def get_boards(show_public: nil); end

  # Render board create form.
  # Route: GET /boards/new
  # @return [String] HTML
  def get_new_board; end

  # Create board.
  # Route: POST /boards
  # @param name [String]
  # @param description [String]
  # @param board_size [Integer]
  # @param placements_json [String]
  # @param is_public [String, nil]
  # @return [void]
  def post_boards(name:, description:, board_size:, placements_json:, is_public: nil); end

  # Show board.
  # Route: GET /boards/:id
  # @param id [Integer]
  # @return [String] HTML
  def get_board(id:); end

  # Render board edit form.
  # Route: GET /boards/:id/edit
  # @param id [Integer]
  # @return [String] HTML
  def get_edit_board(id:); end

  # Update board.
  # Route: POST /boards/:id/update
  # @param id [Integer]
  # @param name [String]
  # @param description [String]
  # @param board_size [Integer]
  # @param placements_json [String]
  # @param is_public [String, nil]
  # @return [void]
  def post_update_board(id:, name:, description:, board_size:, placements_json:, is_public: nil); end

  # Soft-delete board.
  # Route: POST /boards/:id/delete
  # @param id [Integer]
  # @return [void]
  def post_delete_board(id:); end

  # List visible pieces.
  # Route: GET /pieces
  # @param show_public [String, nil]
  # @return [String] HTML
  def get_pieces(show_public: nil); end

  # Render piece create form.
  # Route: GET /pieces/new
  # @return [String] HTML
  def get_new_piece; end

  # Create piece.
  # Route: POST /pieces
  # @param name [String]
  # @param description [String]
  # @param icon_file [Hash, nil]
  # @param icon_base_color [String, nil]
  # @param is_public [String, nil]
  # @param method_ids [Array<String>]
  # @param power_ids [Array<String>]
  # @return [void]
  def post_pieces(name:, description:, icon_file: nil, icon_base_color: nil, is_public: nil, method_ids: [], power_ids: []); end

  # Render piece edit form.
  # Route: GET /pieces/:id/edit
  # @param id [Integer]
  # @return [String] HTML
  def get_edit_piece(id:); end

  # Update piece.
  # Route: POST /pieces/:id/update
  # @param id [Integer]
  # @param name [String]
  # @param description [String]
  # @param icon_file [Hash, nil]
  # @param icon_base_color [String, nil]
  # @param is_public [String, nil]
  # @param method_ids [Array<String>]
  # @param power_ids [Array<String>]
  # @return [void]
  def post_update_piece(id:, name:, description:, icon_file: nil, icon_base_color: nil, is_public: nil, method_ids: [], power_ids: []); end

  # Delete piece (or detach if linked by boards).
  # Route: POST /pieces/:id/delete
  # @param id [Integer]
  # @return [void]
  def post_delete_piece(id:); end

  # Show one piece.
  # Route: GET /pieces/:id
  # @param id [Integer]
  # @return [String] HTML
  def get_piece(id:); end
end
