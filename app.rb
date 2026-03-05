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

ensure_pieces_icon_base_color_column!

helpers do
  # Returns a memoized DB connection configured to return row hashes.
  def db
    @db ||= begin
      conn = SQLite3::Database.new(DB_PATH)
      conn.results_as_hash = true
      conn
    end
  end

  # Finds one active, top-level piece by id.
  def piece_by_id(id)
    db.get_first_row(
      'SELECT * FROM pieces WHERE id = ? AND deleted_at IS NULL AND owner_id = 0 AND source_piece_id IS NULL',
      id
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

# Root redirects to pieces index.
get '/' do
  redirect '/pieces'
end

# Lists active pieces.
get '/pieces' do
  @pieces = db.execute(<<~SQL)
    SELECT id, name, description, image_path, icon_base_color, created_at
    FROM pieces
    WHERE deleted_at IS NULL
      AND owner_id = 0
      AND source_piece_id IS NULL
    ORDER BY id
  SQL

  slim :index
end

# Renders new piece form.
get '/pieces/new' do
  @movement_methods = db.execute('SELECT id, key, name, kind, vectors_json, supports_ray_limit, description FROM movement_methods ORDER BY id')
  @powers = db.execute('SELECT id, name, description FROM powers ORDER BY id')
  slim(:new)
end

# Creates a piece and its configured movement rows.
post '/pieces' do
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
      0,
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
  halt 404, 'Piece not found' unless params[:id] =~ /\A\d+\z/
  id = params[:id].to_i

  @piece = piece_by_id(id)
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
  halt 404, 'Piece not found' unless params[:id] =~ /\A\d+\z/
  id = params[:id].to_i

  piece = piece_by_id(id)
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
  halt 404, 'Piece not found' unless params[:id] =~ /\A\d+\z/
  id = params[:id].to_i

  piece = piece_by_id(id)
  halt 404, 'Piece not found' unless piece

  db.execute('DELETE FROM pieces WHERE id = ?', [id])
  redirect '/pieces'
end

# Shows one piece with powers, moves, and preview payload.
get '/pieces/:id' do
  halt 404, 'Piece not found' unless params[:id] =~ /\A\d+\z/
  id = params[:id].to_i

  @piece = piece_by_id(id)
  halt 404, 'Piece not found' unless @piece

  @piece_moves = db.execute(<<~SQL, [id])
    SELECT pm.id, pm.movement_method_id, pm.name, pm.kind, pm.ray_limit, pm.mode, pm.color_scope, pm.first_move_only, pm.vectors_json,
           mm.name AS method_name, mm.description AS method_description
    FROM piece_moves pm
    LEFT JOIN movement_methods mm ON mm.id = pm.movement_method_id
    WHERE pm.piece_id = ?
    ORDER BY pm.id
  SQL
  @preview_piece_moves = preview_piece_moves_payload(@piece_moves)

  power_ids = parse_power_ids_json(@piece['power_ids'])
  @special_powers = special_powers_by_ids(power_ids)

  slim :show
end
