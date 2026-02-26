require 'sinatra'
require 'slim'
require 'sqlite3'
require 'sinatra/reloader'
require 'bcrypt'
require 'time'
require 'json'

DB_PATH = 'databas.db'

helpers do
  def db
    @db ||= begin
      conn = SQLite3::Database.new(DB_PATH)
      conn.results_as_hash = true
      conn
    end
  end

  def piece_by_id(id)
    db.get_first_row(
      'SELECT * FROM pieces WHERE id = ? AND deleted_at IS NULL AND owner_id = 0 AND source_piece_id IS NULL',
      id
    )
  end

  def parse_power_ids_json(raw)
    JSON.parse(raw.to_s).map(&:to_i).uniq
  rescue JSON::ParserError
    []
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

  def parse_json_hash(raw)
    value = JSON.parse(raw.to_s)
    value.is_a?(Hash) ? value : {}
  rescue JSON::ParserError
    {}
  end

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

  def json_dump(value)
    JSON.generate(value)
  end

  def normalized_mode(value)
    mode = value.to_s
    %w[move capture both].include?(mode) ? mode : 'both'
  end

  def normalized_color_scope(value)
    color_scope = value.to_s
    %w[any white black].include?(color_scope) ? color_scope : 'any'
  end

  def parsed_ray_limit_for_method(method, raw_limit)
    return nil unless method['supports_ray_limit'].to_i == 1

    value = raw_limit.to_s.strip
    return nil if value.empty?

    number = value.to_i
    number.positive? ? number : nil
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
end

after do
  @db&.close
end

get '/' do
  redirect '/pieces'
end

get '/pieces' do
  @pieces = db.execute(<<~SQL)
    SELECT id, name, description, created_at
    FROM pieces
    WHERE deleted_at IS NULL
      AND owner_id = 0
      AND source_piece_id IS NULL
    ORDER BY id
  SQL

  slim :index
end

get '/pieces/new' do
  @movement_methods = db.execute('SELECT id, key, name, kind, vectors_json, supports_ray_limit, description FROM movement_methods ORDER BY id')
  @powers = db.execute('SELECT id, name, description FROM powers ORDER BY id')
  slim(:new)
end

post '/pieces' do
  name = params[:name].to_s.strip
  description = params[:description].to_s.strip
  method_ids = Array(params[:method_ids]).map(&:to_i).uniq
  selected_power_ids = Array(params[:power_ids]).map(&:to_i).uniq

  halt 422, 'Name is required' if name.empty?
  halt 422, 'Select at least one movement method' if method_ids.empty?

  method_map = movement_method_map(method_ids)

  halt 422, 'Invalid movement method selection' if method_map.empty?

  filtered_power_ids = valid_power_ids(selected_power_ids)

  now = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
  piece_id = nil

  db.transaction
  db.execute(
    'INSERT INTO pieces (owner_id, source_piece_id, name, description, power_ids, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
    [
      0,
      nil,
      name,
      (description.empty? ? nil : description),
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

post '/pieces/:id/update' do
  halt 404, 'Piece not found' unless params[:id] =~ /\A\d+\z/
  id = params[:id].to_i

  piece = piece_by_id(id)
  halt 404, 'Piece not found' unless piece

  name = params[:name].to_s.strip
  description = params[:description].to_s.strip
  method_ids = Array(params[:method_ids]).map(&:to_i).uniq
  selected_power_ids = Array(params[:power_ids]).map(&:to_i).uniq

  halt 422, 'Name is required' if name.empty?
  halt 422, 'Select at least one movement method' if method_ids.empty?

  method_map = movement_method_map(method_ids)
  halt 422, 'Invalid movement method selection' if method_map.empty?

  filtered_power_ids = valid_power_ids(selected_power_ids)
  now = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')

  db.transaction
  db.execute(
    'UPDATE pieces SET name = ?, description = ?, power_ids = ?, updated_at = ? WHERE id = ?',
    [name, (description.empty? ? nil : description), JSON.generate(filtered_power_ids), now, id]
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

post '/pieces/:id/delete' do
  halt 404, 'Piece not found' unless params[:id] =~ /\A\d+\z/
  id = params[:id].to_i

  piece = piece_by_id(id)
  halt 404, 'Piece not found' unless piece

  db.execute('DELETE FROM pieces WHERE id = ?', [id])
  redirect '/pieces'
end

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
