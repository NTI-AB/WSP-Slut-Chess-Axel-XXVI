require 'sinatra'
require 'slim'
require 'sqlite3'
require 'sinatra/reloader'
require 'bcrypt'
require 'time'
require 'json'
require 'fileutils'
require 'securerandom'

DB_PATH = 'db/databas.db'
ICON_UPLOAD_DIR = File.join('public', 'icons', 'pieces', 'uploads')
SESSION_SECRET_MIN_LENGTH = 64
DEFAULT_PREMADE_PIECE_OWNER_ID = 1
LOGIN_RATE_LIMIT_MAX_ATTEMPTS = 5
LOGIN_RATE_LIMIT_WINDOW_SECONDS = 600

require_relative 'model'

if settings.development?
  also_reload './model.rb'
end

session_secret = ENV['SESSION_SECRET']
if session_secret.nil? || session_secret.bytesize < SESSION_SECRET_MIN_LENGTH
  warn "SESSION_SECRET missing/too short (#{session_secret&.bytesize || 0}); using temporary secret."
  session_secret = SecureRandom.hex(64)
end

enable :sessions
set :session_secret, session_secret

SchemaModel.setup_database!(db_path: DB_PATH)

helpers QueryModel

helpers do
  # Stores one flash message in session.
  def set_flash(type, message)
    session[:flash] = { 'type' => type.to_s, 'message' => message.to_s }
  end

  # Reads and clears one flash message from session.
  def take_flash
    session.delete(:flash)
  end

  # Redirects to login when no account is signed in.
  def require_login!
    return if current_account
    set_flash('error', 'You need to login first.')
    redirect '/login'
  end

  # Returns current owner id (0 for guest).
  def current_owner_id
    account = current_account
    account ? account['id'].to_i : 0
  end

  # Returns current permission role.
  def current_role
    account = current_account
    return 'guest' unless account

    role = account['role'].to_s
    %w[admin user].include?(role) ? role : 'user'
  end

  # Returns true when current account has admin role.
  def admin?
    current_role == 'admin'
  end

  # Reads the list-page toggle for including other users' public content.
  def show_public_enabled_param?(value)
    value.to_s == '1'
  end

  # Returns owner id used by premade default library.
  def default_premade_piece_owner_id
    DEFAULT_PREMADE_PIECE_OWNER_ID
  end

  # Checks if the resource owner is the default admin library owner.
  def default_owner_resource?(owner_id)
    owner_id.to_i == default_premade_piece_owner_id
  end

  # Checks if current account is owner of the resource.
  def own_resource?(owner_id)
    current_owner_id.positive? && owner_id.to_i == current_owner_id
  end

  # Central permission check used by all actions.
  def permitted?(permission, owner_id: nil, is_public: false)
    return true if admin?

    case permission
    when :piece_read, :board_read
      default_owner_resource?(owner_id) || is_public || own_resource?(owner_id)
    when :piece_create, :board_create
      current_role == 'user'
    when :piece_update, :piece_delete, :board_update, :board_delete
      own_resource?(owner_id)
    when :admin_panel
      false
    else
      false
    end
  end

  # Aborts request when permission check fails.
  def require_permission!(permission, owner_id: nil, is_public: false, on_fail: 403)
    return if permitted?(permission, owner_id: owner_id, is_public: is_public)
    if current_role == 'guest' && on_fail != 404
      set_flash('error', 'You need to login first.')
      redirect '/login'
    end
    halt(on_fail, on_fail == 404 ? 'Not found' : 'Forbidden')
  end

  # Returns true when login attempts are above threshold for this email+IP window.
  def login_rate_limited?(email, ip_address)
    since = (Time.now.utc - LOGIN_RATE_LIMIT_WINDOW_SECONDS).strftime('%Y-%m-%dT%H:%M:%SZ')
    failed_count = recent_failed_login_attempts(email: email, ip_address: ip_address, since: since)
    failed_count >= LOGIN_RATE_LIMIT_MAX_ATTEMPTS
  end

  # Returns a memoized DB connection configured to return row hashes.
  def db
    @db ||= begin
      conn = SQLite3::Database.new(DB_PATH)
      conn.results_as_hash = true
      conn
    end
  end

  # Parses power_ids JSON safely into unique integer ids.
  def parse_power_ids_json(raw)
    JSON.parse(raw.to_s).map(&:to_i).uniq
  rescue JSON::ParserError
    []
  end

  # Parses JSON and returns only hash values.
  def parse_json_hash(raw)
    value = JSON.parse(raw.to_s)
    value.is_a?(Hash) ? value : {}
  rescue JSON::ParserError
    {}
  end

  # Shapes piece move rows into preview payload consumed by JS.
  def preview_piece_moves_payload(piece_moves)
    piece_moves.map do |move|
      {
        id: move['id'],
        movement_method_id: move['movement_method_id'],
        name: move['name'],
        kind: move['kind'],
        vectors: parse_json_hash(move['vectors_json']),
        ray_limit: move['ray_limit'],
        mode: move['mode'],
        color_scope: move['color_scope'],
        first_move_only: move['first_move_only'].to_i == 1
      }
    end
  end

  # JSON helper used inside Slim partials.
  def json_dump(value)
    JSON.generate(value)
  end

  # Clamps board size into supported preview/editor range.
  def normalized_board_size(value)
    size = value.to_i
    size = 8 if size <= 0
    size = 4 if size < 4
    size = 20 if size > 20
    size
  end

  # Parses board placements JSON and validates coordinates, color and piece ids.
  def parse_and_validate_placements_json(raw_json, board_size:, allowed_piece_ids:)
    json = raw_json.to_s.strip
    json = '[]' if json.empty?
    parsed = JSON.parse(json)
    parsed = [] unless parsed.is_a?(Array)

    placements = []
    errors = []
    seen_coords = {}
    player_zone_start = board_size / 2

    parsed.each_with_index do |entry, idx|
      unless entry.is_a?(Hash)
        errors << "Placement ##{idx + 1} must be an object."
        next
      end

      x = begin Integer(entry['x']); rescue StandardError; nil; end
      y = begin Integer(entry['y']); rescue StandardError; nil; end
      piece_id = begin Integer(entry['piece_id']); rescue StandardError; nil; end
      color = entry['color'].to_s

      if x.nil? || y.nil?
        errors << "Placement ##{idx + 1} must have integer x and y."
        next
      end

      unless x.between?(0, board_size - 1) && y.between?(0, board_size - 1)
        errors << "Placement ##{idx + 1} is outside board size #{board_size}."
        next
      end

      if piece_id.nil? || !allowed_piece_ids.include?(piece_id)
        errors << "Placement ##{idx + 1} has invalid piece_id."
        next
      end

      unless color == 'white'
        errors << "Placement ##{idx + 1} must use white color."
        next
      end

      if y < player_zone_start
        errors << "Placement ##{idx + 1} must be on the bottom half."
        next
      end

      key = "#{x},#{y}"
      if seen_coords[key]
        errors << "Duplicate square used at #{key}."
        next
      end
      seen_coords[key] = true

      placements << { 'x' => x, 'y' => y, 'piece_id' => piece_id, 'color' => color }
    end

    [placements, errors]
  rescue JSON::ParserError
    [[], ['placements_json must be valid JSON.']]
  end

  # Parses stored placements JSON into an array for views.
  def parse_placements_for_view(raw_json)
    parsed = JSON.parse(raw_json.to_s)
    return parsed if parsed.is_a?(Array)
    []
  rescue JSON::ParserError
    []
  end

  # Creates a hash map by "x,y" to speed up board rendering in Slim.
  def placements_map_for_view(placements)
    map = {}
    placements.each do |entry|
      next unless entry.is_a?(Hash)
      key = "#{entry['x']},#{entry['y']}"
      map[key] = entry
    end
    map
  end

  # Mirrors placements 180 degrees for opposite-side board preview.
  def flipped_placements_for_view(placements, board_size)
    size = normalized_board_size(board_size)
    flipped = []

    placements.each do |entry|
      next unless entry.is_a?(Hash)

      x = entry['x'].to_i
      y = entry['y'].to_i
      piece_id = entry['piece_id'].to_i
      next unless x.between?(0, size - 1) && y.between?(0, size - 1)

      flipped << {
        'x' => x,
        'y' => (size - 1) - y,
        'piece_id' => piece_id,
        'color' => 'black'
      }
    end

    flipped
  end

  # Normalizes mode input to accepted enum values.
  def normalized_mode(value)
    mode = value.to_s
    %w[move capture both].include?(mode) ? mode : 'both'
  end

  # Normalizes color scope input to accepted enum values.
  def normalized_color_scope(value)
    color_scope = value.to_s
    %w[any white black].include?(color_scope) ? color_scope : 'any'
  end

  # Parses optional ray limit if method supports ray limits.
  def parsed_ray_limit_for_method(method, raw_limit)
    return nil unless method['supports_ray_limit'].to_i == 1

    value = raw_limit.to_s.strip
    return nil if value.empty?

    number = value.to_i
    number.positive? ? number : nil
  end

  # Normalizes icon base color input.
  def normalized_icon_base_color(value)
    color = value.to_s
    %w[black white].include?(color) ? color : 'black'
  end

  # Whitelists supported icon filename extensions.
  def allowed_icon_extension(filename)
    ext = File.extname(filename.to_s).downcase
    %w[.png .jpg .jpeg .webp .gif .svg].include?(ext) ? ext : nil
  end

  # Stores uploaded icon file under public icons directory and returns public path.
  def save_uploaded_icon(upload, prefix:)
    return nil unless upload && upload[:tempfile] && upload[:filename]

    ext = allowed_icon_extension(upload[:filename])
    return nil unless ext

    FileUtils.mkdir_p(ICON_UPLOAD_DIR)
    safe_prefix = prefix.to_s.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/\A_+|_+\z/, '')
    safe_prefix = 'piece' if safe_prefix.empty?
    file_name = "#{safe_prefix}_#{Time.now.utc.strftime('%Y%m%d%H%M%S')}_#{SecureRandom.hex(4)}#{ext}"
    absolute_path = File.join(ICON_UPLOAD_DIR, file_name)

    upload[:tempfile].rewind
    File.open(absolute_path, 'wb') { |f| IO.copy_stream(upload[:tempfile], f) }
    "/icons/pieces/uploads/#{file_name}"
  end

  # Deletes previously uploaded icons when they are replaced by a new upload.
  def remove_uploaded_icon_if_present(path)
    return if path.to_s.empty?
    return unless path.start_with?('/icons/pieces/uploads/')

    absolute_path = File.join('public', path.sub(%r{\A/}, ''))
    File.delete(absolute_path) if File.file?(absolute_path)
  end

end

# Closes DB connection after each request.
after do
  @db&.close
end

# Exposes flash and current account to all views.
before do
  @flash = take_flash
  @current_account = current_account
end

# @route GET /
# Redirect root to the pieces list.
# @return [void]
get '/' do
  redirect '/pieces'
end

# @route GET /login
# Render login form.
# @return [String] HTML login page
get '/login' do
  slim :login
end

# @route POST /login
# Authenticate account credentials and set session.
# @param [String] email Account email
# @param [String] password Plain text password
# @return [void]
post '/login' do
  email = params[:email].to_s.strip.downcase
  password = params[:password].to_s
  ip_address = request.ip.to_s

  if email.empty? || password.empty?
    set_flash('error', 'Fill in email and password.')
    redirect '/login'
  end

  if login_rate_limited?(email, ip_address)
    set_flash('error', 'Too many failed login attempts. Try again in a few minutes.')
    redirect '/login'
  end

  account = find_account_by_email(email)
  authenticated = false

  if account && account['password_hash']
    begin
      authenticated = BCrypt::Password.new(account['password_hash']) == password
    rescue BCrypt::Errors::InvalidHash
      authenticated = false
    end
  end

  now = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
  login_success = account && authenticated
  log_login_attempt!(email: email, ip_address: ip_address, success: login_success, now: now)

  if login_success
    session[:account_id] = account['id'].to_i
    set_flash('success', 'Logged in.')
    redirect '/pieces'
  else
    set_flash('error', 'Incorrect email or password.')
    redirect '/login'
  end
rescue SQLite3::SQLException
  set_flash('error', 'Login failed due to a database error.')
  redirect '/login'
end

# @route GET /register
# Render registration form.
# @return [String] HTML register page
get '/register' do
  slim :register
end

# @route POST /register
# Create a new account and login directly.
# @param [String] username Account username
# @param [String] email Account email
# @param [String] password Plain text password
# @param [String] confirm Password confirmation
# @return [void]
post '/register' do
  username = params[:username].to_s.strip
  email = params[:email].to_s.strip.downcase
  password = params[:password].to_s
  confirm = params[:confirm].to_s

  if username.empty? || email.empty? || password.empty? || confirm.empty?
    set_flash('error', 'Fill in all fields.')
    redirect '/register'
  end

  if password != confirm
    set_flash('error', 'Passwords do not match.')
    redirect '/register'
  end

  if password.length < 6
    set_flash('error', 'Password must be at least 6 characters.')
    redirect '/register'
  end

  if account_exists_by_email?(email)
    set_flash('error', 'Email is already in use.')
    redirect '/register'
  end

  now = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
  password_hash = BCrypt::Password.create(password)
  session[:account_id] = create_account!(username: username, email: email, password_hash: password_hash, now: now)
  set_flash('success', 'Account created and logged in.')
  redirect '/pieces'
rescue SQLite3::SQLException
  set_flash('error', 'Could not create account due to a database error.')
  redirect '/register'
end

# @route POST /logout
# Clear current login session.
# @return [void]
post '/logout' do
  session.delete(:account_id)
  set_flash('success', 'Logged out.')
  redirect '/pieces'
end

# @route GET /account
# Show current account settings page.
# @return [String] HTML account page
get '/account' do
  require_login!
  @account = current_account
  slim :account
end

# @route POST /account/delete
# Delete current account and owned content.
# @return [void]
post '/account/delete' do
  require_login!
  account = current_account
  account_id = account['id'].to_i

  if account_id == default_premade_piece_owner_id
    set_flash('error', 'Default admin account cannot be deleted.')
    redirect '/account'
  end

  now = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
  delete_account_and_owned_content!(account_id: account_id, now: now)
  session.delete(:account_id)
  set_flash('success', 'Account deleted.')
  redirect '/pieces'
rescue SQLite3::SQLException => e
  set_flash('error', "Could not delete account: #{e.message}")
  redirect '/account'
end

# @route GET /admin/accounts
# List all accounts in admin panel.
# @return [String] HTML admin account list
get '/admin/accounts' do
  require_permission!(:admin_panel)
  @accounts = admin_accounts_list
  slim :admin_accounts
end

# @route GET /admin/accounts/:id/pieces
# Show pieces owned by one account.
# @param [String] id Account id path param
# @return [String] HTML admin pieces list
get '/admin/accounts/:id/pieces' do
  require_permission!(:admin_panel)
  halt 404, 'Account not found' unless params[:id] =~ /\A\d+\z/
  account_id = params[:id].to_i

  @account = account_by_id(account_id)
  halt 404, 'Account not found' unless @account

  @pieces = pieces_owned_by_account(account_id)
  slim :admin_account_pieces
end

# @route GET /admin/accounts/:id/boards
# Show boards owned by one account.
# @param [String] id Account id path param
# @return [String] HTML admin boards list
get '/admin/accounts/:id/boards' do
  require_permission!(:admin_panel)
  halt 404, 'Account not found' unless params[:id] =~ /\A\d+\z/
  account_id = params[:id].to_i

  @account = account_by_id(account_id)
  halt 404, 'Account not found' unless @account

  @boards = boards_owned_by_account(account_id)
  slim :admin_account_boards
end

# @route POST /admin/accounts/:id/delete
# Delete one account and owned content from admin panel.
# @param [String] id Account id path param
# @return [void]
post '/admin/accounts/:id/delete' do
  require_permission!(:admin_panel)
  halt 404, 'Account not found' unless params[:id] =~ /\A\d+\z/
  account_id = params[:id].to_i

  account = account_by_id(account_id)
  halt 404, 'Account not found' unless account

  if account_id == default_premade_piece_owner_id
    set_flash('error', 'Default admin account cannot be deleted.')
    redirect '/admin/accounts'
  end

  now = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
  delete_account_and_owned_content!(account_id: account_id, now: now)
  session.delete(:account_id) if session[:account_id].to_i == account_id
  set_flash('success', "Deleted account ##{account_id}.")
  redirect '/admin/accounts'
rescue SQLite3::SQLException => e
  set_flash('error', "Could not delete account: #{e.message}")
  redirect '/admin/accounts'
end

# @route GET /boards
# List visible boards for current role and toggle.
# @param [String, nil] show_public Optional toggle query ("1" enables public feed)
# @return [String] HTML board list
get '/boards' do
  require_permission!(:board_read, owner_id: default_premade_piece_owner_id, is_public: true)
  owner_id = current_owner_id
  @show_public = show_public_enabled_param?(params[:show_public])
  @boards = boards_for_owner(owner_id, show_public: @show_public)
  slim :boards_index
end

# @route GET /boards/new
# Render board creation form.
# @return [String] HTML new board form
get '/boards/new' do
  require_permission!(:board_create)
  owner_id = current_owner_id
  @available_pieces = available_pieces_for_owner(owner_id)
  @board = {
    'name' => '',
    'description' => '',
    'board_size' => 8,
    'placements_json' => '[]',
    'is_public' => 0
  }
  @editor_mode = :new
  slim :boards_new
end

# @route POST /boards
# Create board and sync related board_piece_links.
# @param [String] name Board name
# @param [String] description Board description
# @param [String] board_size Board size input
# @param [String] placements_json JSON placements payload
# @param [String, nil] is_public "1" if board should be public
# @return [void]
post '/boards' do
  require_permission!(:board_create)
  owner_id = current_owner_id
  available_piece_ids = available_pieces_for_owner(owner_id).map { |row| row['id'].to_i }

  name = params[:name].to_s.strip
  description = params[:description].to_s.strip
  board_size = normalized_board_size(params[:board_size])
  placements_raw = params[:placements_json].to_s
  is_public = params[:is_public].to_s == '1' ? 1 : 0

  halt 422, 'Board name is required.' if name.empty?

  placements, errors = parse_and_validate_placements_json(
    placements_raw,
    board_size: board_size,
    allowed_piece_ids: available_piece_ids
  )
  halt 422, errors.join(' ') unless errors.empty?

  now = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
  board_id = create_board_with_links!(
    owner_id: owner_id,
    name: name,
    description: (description.empty? ? nil : description),
    board_size: board_size,
    placements: placements,
    is_public: is_public,
    now: now
  )

  redirect "/boards/#{board_id}"
rescue SQLite3::SQLException => e
  halt 500, "Could not create board: #{e.message}"
end

# @route GET /boards/:id
# Show one board in read-only mode.
# @param [String] id Board id path param
# @return [String] HTML board page
get '/boards/:id' do
  halt 404, 'Board not found' unless params[:id] =~ /\A\d+\z/
  owner_id = current_owner_id
  id = params[:id].to_i

  @board = admin? ? board_by_id_any(id) : board_visible_by_id_for_owner(id, owner_id)
  halt 404, 'Board not found' unless @board
  require_permission!(
    :board_read,
    owner_id: @board['owner_id'].to_i,
    is_public: @board['is_public'].to_i == 1,
    on_fail: 404
  )

  @placements = parse_placements_for_view(@board['placements_json'])
  piece_ids = @placements.map { |placement| placement['piece_id'].to_i }.uniq
  @piece_by_id = pieces_by_ids(piece_ids).each_with_object({}) { |row, memo| memo[row['id'].to_i] = row }
  @flipped_placements = flipped_placements_for_view(@placements, @board['board_size'])
  @combined_placements_map = placements_map_for_view(@placements + @flipped_placements)

  slim :boards_show
end

# @route GET /boards/:id/edit
# Render board edit form.
# @param [String] id Board id path param
# @return [String] HTML edit board form
get '/boards/:id/edit' do
  halt 404, 'Board not found' unless params[:id] =~ /\A\d+\z/
  id = params[:id].to_i

  @board = board_by_id_any(id)
  halt 404, 'Board not found' unless @board
  require_permission!(:board_update, owner_id: @board['owner_id'].to_i, on_fail: 404)

  owner_scope_id = admin? ? @board['owner_id'].to_i : current_owner_id
  @available_pieces = available_pieces_for_owner(owner_scope_id)
  @editor_mode = :edit
  slim :boards_edit
end

# @route POST /boards/:id/update
# Update board fields and resync board_piece_links.
# @param [String] id Board id path param
# @param [String] name Board name
# @param [String] description Board description
# @param [String] board_size Board size input
# @param [String] placements_json JSON placements payload
# @param [String, nil] is_public "1" if board should be public
# @return [void]
post '/boards/:id/update' do
  halt 404, 'Board not found' unless params[:id] =~ /\A\d+\z/
  id = params[:id].to_i

  board = board_by_id_any(id)
  halt 404, 'Board not found' unless board
  require_permission!(:board_update, owner_id: board['owner_id'].to_i, on_fail: 404)

  owner_scope_id = admin? ? board['owner_id'].to_i : current_owner_id
  available_piece_ids = available_pieces_for_owner(owner_scope_id).map { |row| row['id'].to_i }
  name = params[:name].to_s.strip
  description = params[:description].to_s.strip
  board_size = normalized_board_size(params[:board_size])
  placements_raw = params[:placements_json].to_s
  is_public = params[:is_public].to_s == '1' ? 1 : 0

  halt 422, 'Board name is required.' if name.empty?

  placements, errors = parse_and_validate_placements_json(
    placements_raw,
    board_size: board_size,
    allowed_piece_ids: available_piece_ids
  )
  halt 422, errors.join(' ') unless errors.empty?

  now = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
  update_board_with_links!(
    id: id,
    name: name,
    description: (description.empty? ? nil : description),
    board_size: board_size,
    placements: placements,
    is_public: is_public,
    now: now
  )

  redirect "/boards/#{id}"
rescue SQLite3::SQLException => e
  halt 500, "Could not update board: #{e.message}"
end

# @route POST /boards/:id/delete
# Soft delete a board and remove board_piece_links.
# @param [String] id Board id path param
# @return [void]
post '/boards/:id/delete' do
  halt 404, 'Board not found' unless params[:id] =~ /\A\d+\z/
  id = params[:id].to_i

  board = board_by_id_any(id)
  halt 404, 'Board not found' unless board
  require_permission!(:board_delete, owner_id: board['owner_id'].to_i, on_fail: 404)

  now = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
  soft_delete_board_with_links!(id: id, now: now)
  redirect '/boards'
rescue SQLite3::SQLException => e
  halt 500, "Could not delete board: #{e.message}"
end

# @route GET /pieces
# List visible pieces for current role and toggle.
# @param [String, nil] show_public Optional toggle query ("1" enables public feed)
# @return [String] HTML piece list
get '/pieces' do
  require_permission!(:piece_read, owner_id: default_premade_piece_owner_id, is_public: true)
  owner_id = current_owner_id
  @show_public = show_public_enabled_param?(params[:show_public])
  @pieces = pieces_for_owner(owner_id, show_public: @show_public)

  slim :index
end

# @route GET /pieces/new
# Render new piece form.
# @return [String] HTML new piece form
get '/pieces/new' do
  require_permission!(:piece_create)
  @movement_methods = movement_methods_all
  @powers = powers_all
  slim(:new)
end

# @route POST /pieces
# Create piece and related piece_moves rows.
# @param [String] name Piece name
# @param [String] description Piece description
# @param [Hash, nil] icon_file Optional uploaded icon file
# @param [String, nil] icon_base_color Base icon color ("black" or "white")
# @param [String, nil] is_public "1" if piece should be public
# @param [Array<String>, nil] method_ids Selected movement method ids
# @param [Array<String>, nil] power_ids Selected power ids
# @return [void]
post '/pieces' do
  require_permission!(:piece_create)
  owner_id = current_owner_id
  name = params[:name].to_s.strip
  description = params[:description].to_s.strip
  icon_upload = params[:icon_file]
  image_path = nil
  icon_base_color = normalized_icon_base_color(params[:icon_base_color])
  is_public = params[:is_public].to_s == '1' ? 1 : 0
  method_ids = Array(params[:method_ids]).map(&:to_i).uniq
  selected_power_ids = Array(params[:power_ids]).map(&:to_i).uniq

  halt 422, 'Name is required' if name.empty?
  halt 422, 'Select at least one movement method' if method_ids.empty?
  if icon_upload && !icon_upload[:filename].to_s.strip.empty?
    image_path = save_uploaded_icon(icon_upload, prefix: name)
    halt 422, 'Unsupported icon format. Use png, jpg, jpeg, webp, gif, or svg.' if image_path.nil?
  end

  method_map = movement_method_map(method_ids)

  halt 422, 'Invalid movement method selection' if method_map.empty?

  filtered_power_ids = valid_power_ids(selected_power_ids)

  now = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
  piece_id = nil

  with_transaction do
    piece_id = create_piece_record!(
      owner_id: owner_id,
      name: name,
      description: (description.empty? ? nil : description),
      image_path: image_path,
      icon_base_color: icon_base_color,
      is_public: is_public,
      power_ids_json: JSON.generate(filtered_power_ids),
      now: now
    )

    method_ids.each do |method_id|
      method = method_map[method_id]
      next unless method

      ray_limit = parsed_ray_limit_for_method(method, params.fetch('ray_limit', {}).fetch(method_id.to_s, ''))
      mode = normalized_mode(params.dig('mode', method_id.to_s))
      color_scope = normalized_color_scope(params.dig('color_scope', method_id.to_s))
      first_move_only = params.dig('first_move_only', method_id.to_s) == '1' ? 1 : 0

      insert_piece_move_row!(
        piece_id: piece_id,
        method: method,
        ray_limit: ray_limit,
        mode: mode,
        color_scope: color_scope,
        first_move_only: first_move_only,
        now: now
      )

      secondary_enabled = params.dig('secondary_mode_enabled', method_id.to_s) == '1'
      next unless secondary_enabled
      next unless method['supports_ray_limit'].to_i == 1
      next unless %w[move capture].include?(mode)

      secondary_mode = (mode == 'move' ? 'capture' : 'move')
      secondary_ray_limit = parsed_ray_limit_for_method(method, params.fetch('secondary_ray_limit', {}).fetch(method_id.to_s, ''))

      insert_piece_move_row!(
        piece_id: piece_id,
        method: method,
        ray_limit: secondary_ray_limit,
        mode: secondary_mode,
        color_scope: color_scope,
        first_move_only: first_move_only,
        now: now
      )
    end
  end

  redirect "/pieces/#{piece_id}"
rescue SQLite3::SQLException => e
  halt 500, "Could not create piece: #{e.message}"
end

# @route GET /pieces/:id/edit
# Render edit form for one piece.
# @param [String] id Piece id path param
# @return [String] HTML edit piece form
get '/pieces/:id/edit' do
  halt 404, 'Piece not found' unless params[:id] =~ /\A\d+\z/
  id = params[:id].to_i

  @piece = piece_by_id_any(id)
  halt 404, 'Piece not found' unless @piece
  require_permission!(:piece_update, owner_id: @piece['owner_id'].to_i, on_fail: 404)

  @movement_methods = movement_methods_all
  @powers = powers_all
  @selected_power_ids = parse_power_ids_json(@piece['power_ids'])
  @move_config_by_method_id = {}
  @secondary_move_config_by_method_id = {}
  move_rows_by_method_id = Hash.new { |hash, key| hash[key] = [] }

  piece_move_rows_for_piece(id).each do |row|
    method_id = row['movement_method_id']
    next if method_id.nil?
    move_rows_by_method_id[method_id.to_i] << row
  end

  move_rows_by_method_id.each do |method_id, rows|
    next if rows.empty?

    primary = rows.first
    secondary = nil

    if %w[move capture].include?(primary['mode'].to_s)
      secondary = rows.find do |row|
        row['id'] != primary['id'] && row['mode'].to_s == (primary['mode'].to_s == 'move' ? 'capture' : 'move')
      end
    end

    @move_config_by_method_id[method_id] = primary
    @secondary_move_config_by_method_id[method_id] = secondary if secondary
  end

  slim :edit
end

# @route POST /pieces/:id/update
# Update piece and fully rewrite piece_moves rows.
# @param [String] id Piece id path param
# @param [String] name Piece name
# @param [String] description Piece description
# @param [Hash, nil] icon_file Optional uploaded icon file
# @param [String, nil] icon_base_color Base icon color ("black" or "white")
# @param [String, nil] is_public "1" if piece should be public
# @param [Array<String>, nil] method_ids Selected movement method ids
# @param [Array<String>, nil] power_ids Selected power ids
# @return [void]
post '/pieces/:id/update' do
  halt 404, 'Piece not found' unless params[:id] =~ /\A\d+\z/
  id = params[:id].to_i

  piece = piece_by_id_any(id)
  halt 404, 'Piece not found' unless piece
  require_permission!(:piece_update, owner_id: piece['owner_id'].to_i, on_fail: 404)

  name = params[:name].to_s.strip
  description = params[:description].to_s.strip
  icon_upload = params[:icon_file]
  image_path = piece['image_path']
  icon_base_color = normalized_icon_base_color(params[:icon_base_color])
  is_public = params[:is_public].to_s == '1' ? 1 : 0
  method_ids = Array(params[:method_ids]).map(&:to_i).uniq
  selected_power_ids = Array(params[:power_ids]).map(&:to_i).uniq

  halt 422, 'Name is required' if name.empty?
  halt 422, 'Select at least one movement method' if method_ids.empty?
  if icon_upload && !icon_upload[:filename].to_s.strip.empty?
    uploaded_path = save_uploaded_icon(icon_upload, prefix: name)
    halt 422, 'Unsupported icon format. Use png, jpg, jpeg, webp, gif, or svg.' if uploaded_path.nil?
    remove_uploaded_icon_if_present(piece['image_path'])
    image_path = uploaded_path
  end

  method_map = movement_method_map(method_ids)
  halt 422, 'Invalid movement method selection' if method_map.empty?

  filtered_power_ids = valid_power_ids(selected_power_ids)
  now = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')

  with_transaction do
    update_piece_record!(
      id: id,
      name: name,
      description: (description.empty? ? nil : description),
      image_path: image_path,
      icon_base_color: icon_base_color,
      is_public: is_public,
      power_ids_json: JSON.generate(filtered_power_ids),
      now: now
    )

    delete_piece_moves_for_piece!(id)

    method_ids.each do |method_id|
      method = method_map[method_id]
      next unless method

      ray_limit = parsed_ray_limit_for_method(method, params.fetch('ray_limit', {}).fetch(method_id.to_s, ''))
      mode = normalized_mode(params.dig('mode', method_id.to_s))
      color_scope = normalized_color_scope(params.dig('color_scope', method_id.to_s))
      first_move_only = params.dig('first_move_only', method_id.to_s) == '1' ? 1 : 0

      insert_piece_move_row!(
        piece_id: id,
        method: method,
        ray_limit: ray_limit,
        mode: mode,
        color_scope: color_scope,
        first_move_only: first_move_only,
        now: now
      )

      secondary_enabled = params.dig('secondary_mode_enabled', method_id.to_s) == '1'
      next unless secondary_enabled
      next unless method['supports_ray_limit'].to_i == 1
      next unless %w[move capture].include?(mode)

      secondary_mode = (mode == 'move' ? 'capture' : 'move')
      secondary_ray_limit = parsed_ray_limit_for_method(method, params.fetch('secondary_ray_limit', {}).fetch(method_id.to_s, ''))

      insert_piece_move_row!(
        piece_id: id,
        method: method,
        ray_limit: secondary_ray_limit,
        mode: secondary_mode,
        color_scope: color_scope,
        first_move_only: first_move_only,
        now: now
      )
    end
  end

  redirect "/pieces/#{id}"
rescue SQLite3::SQLException => e
  halt 500, "Could not update piece: #{e.message}"
end

# @route POST /pieces/:id/delete
# Delete piece or detach owner when piece is linked by boards.
# @param [String] id Piece id path param
# @return [void]
post '/pieces/:id/delete' do
  halt 404, 'Piece not found' unless params[:id] =~ /\A\d+\z/
  id = params[:id].to_i

  piece = piece_by_id_any(id)
  halt 404, 'Piece not found' unless piece
  require_permission!(:piece_delete, owner_id: piece['owner_id'].to_i, on_fail: 404)

  now = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')

  if piece_linked_to_any_board?(id)
    mark_piece_as_detached!(piece_id: id, now: now)
  else
    hard_delete_piece!(id)
  end

  redirect '/pieces'
end

# @route GET /pieces/:id
# Show one piece with powers, move rows, and preview payload.
# @param [String] id Piece id path param
# @return [String] HTML piece detail page
get '/pieces/:id' do
  halt 404, 'Piece not found' unless params[:id] =~ /\A\d+\z/
  id = params[:id].to_i
  owner_id = current_owner_id

  @piece = admin? ? piece_by_id_any(id) : piece_visible_by_id_for_owner(id, owner_id)
  halt 404, 'Piece not found' unless @piece
  require_permission!(
    :piece_read,
    owner_id: @piece['owner_id'].to_i,
    is_public: @piece['is_public'].to_i == 1,
    on_fail: 404
  )

  power_ids = parse_power_ids_json(@piece['power_ids'])
  @preview_power_ids = power_ids

  @piece_moves = piece_moves_for_show(id)
  @preview_piece_moves = preview_piece_moves_payload(@piece_moves)

  @special_powers = special_powers_by_ids(power_ids)

  slim :show
end
