require 'sinatra'
require 'slim'
require 'sqlite3'
require 'sinatra/reloader'
require 'bcrypt'
require 'time'
require 'json'
require 'fileutils'
require 'securerandom'

DB_PATH = 'databas.db'
ICON_UPLOAD_DIR = File.join('public', 'icons', 'pieces', 'uploads')
SESSION_SECRET_MIN_LENGTH = 64
DEFAULT_PREMADE_PIECE_OWNER_ID = 1

session_secret = ENV['SESSION_SECRET']
if session_secret.nil? || session_secret.bytesize < SESSION_SECRET_MIN_LENGTH
  warn "SESSION_SECRET missing/too short (#{session_secret&.bytesize || 0}); using temporary secret."
  session_secret = SecureRandom.hex(64)
end

enable :sessions
set :session_secret, session_secret

# Ensures accounts table exists for login/register.
def ensure_accounts_table!
  conn = SQLite3::Database.new(DB_PATH)
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

# Ensures older DB files get the icon base color column before app logic runs.
def ensure_pieces_icon_base_color_column!
  conn = SQLite3::Database.new(DB_PATH)
  columns = conn.execute('PRAGMA table_info(pieces)').map { |row| row[1] }
  return if columns.include?('icon_base_color')

  conn.execute("ALTER TABLE pieces ADD COLUMN icon_base_color TEXT NOT NULL DEFAULT 'black'")
  conn.execute("UPDATE pieces SET icon_base_color = 'black' WHERE icon_base_color IS NULL OR icon_base_color = ''")
ensure
  conn&.close
end

ensure_accounts_table!
ensure_pieces_icon_base_color_column!

# Ensures boards table exists for board CRUD.
def ensure_boards_table!
  conn = SQLite3::Database.new(DB_PATH)
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

ensure_boards_table!

helpers do
  # Returns currently signed-in account row (or nil).
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

  # Returns owner id used by premade piece library.
  def default_premade_piece_owner_id
    DEFAULT_PREMADE_PIECE_OWNER_ID
  end

  # Returns a memoized DB connection configured to return row hashes.
  def db
    @db ||= begin
      conn = SQLite3::Database.new(DB_PATH)
      conn.results_as_hash = true
      conn
    end
  end

  # Finds one visible piece by id (defaults + current owner's pieces).
  def piece_visible_by_id_for_owner(id, owner_id)
    default_owner_id = default_premade_piece_owner_id
    if owner_id.zero?
      db.get_first_row(
        'SELECT * FROM pieces WHERE id = ? AND deleted_at IS NULL AND source_piece_id IS NULL AND owner_id = ?',
        [id, default_owner_id]
      )
    else
      db.get_first_row(
        'SELECT * FROM pieces WHERE id = ? AND deleted_at IS NULL AND source_piece_id IS NULL AND owner_id IN (?, ?)',
        [id, default_owner_id, owner_id]
      )
    end
  end

  # Finds one piece by id owned by current owner.
  def piece_owned_by_id_for_owner(id, owner_id)
    db.get_first_row(
      'SELECT * FROM pieces WHERE id = ? AND deleted_at IS NULL AND source_piece_id IS NULL AND owner_id = ?',
      [id, owner_id]
    )
  end

  # Lists pieces visible for one owner (defaults + own).
  def pieces_for_owner(owner_id)
    default_owner_id = default_premade_piece_owner_id
    if owner_id.zero?
      db.execute(
        <<~SQL,
          SELECT id, name, description, image_path, icon_base_color, created_at, owner_id
          FROM pieces
          WHERE deleted_at IS NULL
            AND source_piece_id IS NULL
            AND owner_id = ?
          ORDER BY id
        SQL
        [default_owner_id]
      )
    else
      db.execute(
        <<~SQL,
          SELECT id, name, description, image_path, icon_base_color, created_at, owner_id
          FROM pieces
          WHERE deleted_at IS NULL
            AND source_piece_id IS NULL
            AND owner_id IN (?, ?)
          ORDER BY id
        SQL
        [default_owner_id, owner_id]
      )
    end
  end

  # Lists piece rows available for board editing (defaults + current owner pieces).
  def available_pieces_for_owner(owner_id)
    default_owner_id = default_premade_piece_owner_id
    if owner_id.zero?
      db.execute(
        <<~SQL,
          SELECT id, name, image_path, icon_base_color
          FROM pieces
          WHERE deleted_at IS NULL
            AND source_piece_id IS NULL
            AND owner_id = ?
          ORDER BY LOWER(name), id
        SQL
        [default_owner_id]
      )
    else
      db.execute(
        <<~SQL,
          SELECT id, name, image_path, icon_base_color
          FROM pieces
          WHERE deleted_at IS NULL
            AND source_piece_id IS NULL
            AND owner_id IN (?, ?)
          ORDER BY LOWER(name), id
        SQL
        [default_owner_id, owner_id]
      )
    end
  end

  # Returns active boards for one owner.
  def boards_for_owner(owner_id)
    default_owner_id = default_premade_piece_owner_id
    if owner_id.zero?
      db.execute(
        <<~SQL,
          SELECT id, name, description, board_size, is_public, created_at, updated_at, owner_id
          FROM boards
          WHERE deleted_at IS NULL
            AND owner_id = ?
          ORDER BY id DESC
        SQL
        [default_owner_id]
      )
    else
      db.execute(
        <<~SQL,
          SELECT id, name, description, board_size, is_public, created_at, updated_at, owner_id
          FROM boards
          WHERE deleted_at IS NULL
            AND owner_id IN (?, ?)
          ORDER BY id DESC
        SQL
        [default_owner_id, owner_id]
      )
    end
  end

  # Finds one board visible to owner (default + own).
  def board_visible_by_id_for_owner(id, owner_id)
    default_owner_id = default_premade_piece_owner_id
    if owner_id.zero?
      db.get_first_row(
        <<~SQL,
          SELECT id, owner_id, name, description, board_size, placements_json, is_public, created_at, updated_at
          FROM boards
          WHERE id = ?
            AND deleted_at IS NULL
            AND owner_id = ?
        SQL
        [id, default_owner_id]
      )
    else
      db.get_first_row(
        <<~SQL,
          SELECT id, owner_id, name, description, board_size, placements_json, is_public, created_at, updated_at
          FROM boards
          WHERE id = ?
            AND deleted_at IS NULL
            AND owner_id IN (?, ?)
        SQL
        [id, default_owner_id, owner_id]
      )
    end
  end

  # Finds one board by id owned by current owner.
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

  # Parses power_ids JSON safely into unique integer ids.
  def parse_power_ids_json(raw)
    JSON.parse(raw.to_s).map(&:to_i).uniq
  rescue JSON::ParserError
    []
  end

  # Fetches power rows for a set of ids.
  def special_powers_by_ids(power_ids)
    return [] if power_ids.empty?

    placeholders = (['?'] * power_ids.length).join(',')
    db.execute("SELECT id, name, description FROM powers WHERE id IN (#{placeholders}) ORDER BY id", power_ids)
  end

  # Loads movement methods and indexes them by id.
  def movement_method_map(method_ids)
    return {} if method_ids.empty?

    placeholders = (['?'] * method_ids.length).join(',')
    methods = db.execute("SELECT id, name, kind, vectors_json, supports_ray_limit FROM movement_methods WHERE id IN (#{placeholders})", method_ids)
    methods.each_with_object({}) { |method, memo| memo[method['id']] = method }
  end

  # Filters selected power ids to ids that exist in DB.
  def valid_power_ids(selected_power_ids)
    return [] if selected_power_ids.empty?

    placeholders = (['?'] * selected_power_ids.length).join(',')
    db.execute("SELECT id FROM powers WHERE id IN (#{placeholders})", selected_power_ids).map { |row| row['id'].to_i }
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

  # Inserts one piece_moves row from normalized config values.
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

# Root redirects to pieces index.
get '/' do
  redirect '/pieces'
end

# Shows login page.
get '/login' do
  slim :login
end

# Authenticates user and stores account id in session.
post '/login' do
  email = params[:email].to_s.strip.downcase
  password = params[:password].to_s

  if email.empty? || password.empty?
    set_flash('error', 'Fill in email and password.')
    redirect '/login'
  end

  account = db.get_first_row('SELECT id, username, email, password_hash FROM accounts WHERE email = ?', [email])
  authenticated = false

  if account && account['password_hash']
    begin
      authenticated = BCrypt::Password.new(account['password_hash']) == password
    rescue BCrypt::Errors::InvalidHash
      authenticated = false
    end
  end

  if account && authenticated
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

# Shows register page.
get '/register' do
  slim :register
end

# Creates account and logs in directly.
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

  existing = db.get_first_row('SELECT id FROM accounts WHERE email = ?', [email])
  if existing
    set_flash('error', 'Email is already in use.')
    redirect '/register'
  end

  now = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
  password_hash = BCrypt::Password.create(password)
  db.execute(
    'INSERT INTO accounts (username, email, password_hash, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
    [username, email, password_hash, now, now]
  )

  session[:account_id] = db.last_insert_row_id
  set_flash('success', 'Account created and logged in.')
  redirect '/pieces'
rescue SQLite3::SQLException
  set_flash('error', 'Could not create account due to a database error.')
  redirect '/register'
end

# Clears login session.
post '/logout' do
  session.delete(:account_id)
  set_flash('success', 'Logged out.')
  redirect '/pieces'
end

# Lists active boards for current owner.
get '/boards' do
  owner_id = current_owner_id
  @boards = boards_for_owner(owner_id)
  slim :boards_index
end

# Renders board creation form with simple click placement editor.
get '/boards/new' do
  require_login!
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

# Creates a board from submitted editor JSON.
post '/boards' do
  require_login!
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

  db.execute(
    'INSERT INTO boards (owner_id, name, description, board_size, placements_json, is_public, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    [
      owner_id,
      name,
      (description.empty? ? nil : description),
      board_size,
      JSON.generate(placements),
      is_public,
      now,
      now
    ]
  )

  board_id = db.last_insert_row_id
  redirect "/boards/#{board_id}"
end

# Shows one board in read-only mode.
get '/boards/:id' do
  halt 404, 'Board not found' unless params[:id] =~ /\A\d+\z/
  owner_id = current_owner_id
  id = params[:id].to_i

  @board = board_visible_by_id_for_owner(id, owner_id)
  halt 404, 'Board not found' unless @board

  @available_pieces = available_pieces_for_owner(owner_id)
  @piece_by_id = @available_pieces.each_with_object({}) { |row, memo| memo[row['id'].to_i] = row }
  @placements = parse_placements_for_view(@board['placements_json'])
  @flipped_placements = flipped_placements_for_view(@placements, @board['board_size'])
  @combined_placements_map = placements_map_for_view(@placements + @flipped_placements)

  slim :boards_show
end

# Renders board edit form with current placements loaded.
get '/boards/:id/edit' do
  require_login!
  halt 404, 'Board not found' unless params[:id] =~ /\A\d+\z/
  owner_id = current_owner_id
  id = params[:id].to_i

  @board = board_owned_by_id_for_owner(id, owner_id)
  halt 404, 'Board not found' unless @board

  @available_pieces = available_pieces_for_owner(owner_id)
  @editor_mode = :edit
  slim :boards_edit
end

# Updates a board and replaces its placements JSON.
post '/boards/:id/update' do
  require_login!
  halt 404, 'Board not found' unless params[:id] =~ /\A\d+\z/
  owner_id = current_owner_id
  id = params[:id].to_i

  board = board_owned_by_id_for_owner(id, owner_id)
  halt 404, 'Board not found' unless board

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
  db.execute(
    'UPDATE boards SET name = ?, description = ?, board_size = ?, placements_json = ?, is_public = ?, updated_at = ? WHERE id = ?',
    [
      name,
      (description.empty? ? nil : description),
      board_size,
      JSON.generate(placements),
      is_public,
      now,
      id
    ]
  )

  redirect "/boards/#{id}"
end

# Soft deletes one board.
post '/boards/:id/delete' do
  require_login!
  halt 404, 'Board not found' unless params[:id] =~ /\A\d+\z/
  owner_id = current_owner_id
  id = params[:id].to_i

  board = board_owned_by_id_for_owner(id, owner_id)
  halt 404, 'Board not found' unless board

  now = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
  db.execute('UPDATE boards SET deleted_at = ?, updated_at = ? WHERE id = ?', [now, now, id])
  redirect '/boards'
end

# Lists active pieces.
get '/pieces' do
  @pieces = pieces_for_owner(current_owner_id)

  slim :index
end

# Renders new piece form.
get '/pieces/new' do
  require_login!
  @movement_methods = db.execute('SELECT id, key, name, kind, vectors_json, supports_ray_limit, description FROM movement_methods ORDER BY id')
  @powers = db.execute('SELECT id, name, description FROM powers ORDER BY id')
  slim(:new)
end

# Creates a piece and its configured movement rows.
post '/pieces' do
  require_login!
  owner_id = current_owner_id
  name = params[:name].to_s.strip
  description = params[:description].to_s.strip
  icon_upload = params[:icon_file]
  image_path = nil
  icon_base_color = normalized_icon_base_color(params[:icon_base_color])
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

  db.transaction
  db.execute(
    'INSERT INTO pieces (owner_id, source_piece_id, name, description, image_path, icon_base_color, power_ids, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      owner_id,
      nil,
      name,
      (description.empty? ? nil : description),
      image_path,
      icon_base_color,
      JSON.generate(filtered_power_ids),
      now,
      now
    ]
  )
  piece_id = db.last_insert_row_id

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
  db.commit

  redirect "/pieces/#{piece_id}"
rescue SQLite3::SQLException => e
  db.rollback
  halt 500, "Could not create piece: #{e.message}"
end

# Renders edit form with current move config grouped per method.
get '/pieces/:id/edit' do
  require_login!
  halt 404, 'Piece not found' unless params[:id] =~ /\A\d+\z/
  id = params[:id].to_i
  owner_id = current_owner_id

  @piece = piece_owned_by_id_for_owner(id, owner_id)
  halt 404, 'Piece not found' unless @piece

  @movement_methods = db.execute('SELECT id, key, name, kind, vectors_json, supports_ray_limit, description FROM movement_methods ORDER BY id')
  @powers = db.execute('SELECT id, name, description FROM powers ORDER BY id')
  @selected_power_ids = parse_power_ids_json(@piece['power_ids'])
  @move_config_by_method_id = {}
  @secondary_move_config_by_method_id = {}
  move_rows_by_method_id = Hash.new { |hash, key| hash[key] = [] }

  db.execute(
    'SELECT id, movement_method_id, ray_limit, mode, color_scope, first_move_only FROM piece_moves WHERE piece_id = ? ORDER BY id',
    [id]
  ).each do |row|
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

# Updates piece fields and rewrites its movement rows.
post '/pieces/:id/update' do
  require_login!
  halt 404, 'Piece not found' unless params[:id] =~ /\A\d+\z/
  id = params[:id].to_i
  owner_id = current_owner_id

  piece = piece_owned_by_id_for_owner(id, owner_id)
  halt 404, 'Piece not found' unless piece

  name = params[:name].to_s.strip
  description = params[:description].to_s.strip
  icon_upload = params[:icon_file]
  image_path = piece['image_path']
  icon_base_color = normalized_icon_base_color(params[:icon_base_color])
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

  db.transaction
  db.execute(
    'UPDATE pieces SET name = ?, description = ?, image_path = ?, icon_base_color = ?, power_ids = ?, updated_at = ? WHERE id = ?',
    [name, (description.empty? ? nil : description), image_path, icon_base_color, JSON.generate(filtered_power_ids), now, id]
  )

  db.execute('DELETE FROM piece_moves WHERE piece_id = ?', [id])

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
  db.commit

  redirect "/pieces/#{id}"
rescue SQLite3::SQLException => e
  db.rollback
  halt 500, "Could not update piece: #{e.message}"
end

# Deletes one piece.
post '/pieces/:id/delete' do
  require_login!
  halt 404, 'Piece not found' unless params[:id] =~ /\A\d+\z/
  id = params[:id].to_i
  owner_id = current_owner_id

  piece = piece_owned_by_id_for_owner(id, owner_id)
  halt 404, 'Piece not found' unless piece

  db.execute('DELETE FROM pieces WHERE id = ?', [id])
  redirect '/pieces'
end

# Shows one piece with powers, moves, and preview payload.
get '/pieces/:id' do
  halt 404, 'Piece not found' unless params[:id] =~ /\A\d+\z/
  id = params[:id].to_i
  owner_id = current_owner_id

  @piece = piece_visible_by_id_for_owner(id, owner_id)
  halt 404, 'Piece not found' unless @piece

  power_ids = parse_power_ids_json(@piece['power_ids'])
  @preview_power_ids = power_ids

  @piece_moves = db.execute(<<~SQL, [id])
    SELECT pm.id, pm.movement_method_id, pm.name, pm.kind, pm.ray_limit, pm.mode, pm.color_scope, pm.first_move_only, pm.vectors_json,
           mm.name AS method_name, mm.description AS method_description
    FROM piece_moves pm
    LEFT JOIN movement_methods mm ON mm.id = pm.movement_method_id
    WHERE pm.piece_id = ?
    ORDER BY pm.id
  SQL
  @preview_piece_moves = preview_piece_moves_payload(@piece_moves)

  @special_powers = special_powers_by_ids(power_ids)

  slim :show
end
