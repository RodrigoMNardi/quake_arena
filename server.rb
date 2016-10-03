require 'sinatra/base'
require 'sinatra/datamapper'
require 'yaml'
require 'logger'
require 'gruff'
require 'base64'

require "#{File.dirname(__FILE__)}/database/database"
require "#{File.dirname(__FILE__)}/parser"

$processing  = false
$cache       = []
$process_pid = nil
$config      = YAML::load_file("#{File.dirname(__FILE__)}/config.yml")
$logger      = Logger.new("#{File.dirname(__FILE__)}/server.log")

class Q3Match < Sinatra::Base
  set :port, 8081

  get '/reload' do
    $config = YAML::load_file("#{File.dirname(__FILE__)}/config.yml")
    $logger.info 'Reloading YAML FILE'
    $logger.info  $config.inspect

    redirect to('/')
  end

  get '/maps/today' do
    date               = Time.now.strftime('%d%m%y')
    maps, score, image = read_maps(date)

    erb :maps, locals: {maps: maps, match_date: date, score: score, image: image}
  end

  #
  # PT-BR: Mapas jogados por data
  # EN   : Played maps by date
  #
  get '/maps/:date' do
    maps, score, image = read_maps(params['date'])
    erb :maps, locals: {maps: maps, match_date: params['date'], score: score, image: image}
  end

  get '/match/:match_id/user/:user_id' do
    user = User.first(match_id: params['match_id'], id: params['user_id'])

    erb :user, locals: {user: user}
  end

  #
  # PT-BR: Procura uma partida por data e salva no banco de dados
  # EN   : Search a match by date and save
  #
  get '/match/date/:date' do
    match = nil
    match = Match.first(date: params[:date].to_s) unless $processing

    if match.nil?
      users = parse(params[:date])
      create_match(users, params[:date]) if $config.has_key? 'db_auto_save' and $config['db_auto_save'] == true

      match_simple = users.sort_by{|e| e.rank?}.reverse
      match_simple.delete_if{|e| e.kills.empty? and e.deaths.empty?}

      archie = achievements(users, params[:date])

      erb :main_simple, locals: {match: match_simple, date: params[:date], archie: archie}
    else
      archie = achievements(match.users, params[:date])
      erb :main, locals: {match: match, date: params[:date], archie: archie}
    end
  end

  #
  # PT-BR: Salva a MATCH da data atual no DB
  # EN   : Save daily match (DB)
  #
  get '/match/save' do
    redirect to('/') if exist_pid?($process_pid)

    date = Time.now.strftime('%d%m%y')
    users = parse(date)
    create_match(users, date)

    match_simple = users.sort_by{|e| e.rank?}.reverse
    match_simple.delete_if{|e| e.kills.empty? and e.deaths.empty?}

    archie = achievements(users, date)

    erb :main_simple, locals: {match: match_simple, date: date, archie: archie}
  end

  #
  # PT-BR: Parsing do MATCH atual em HTML
  # EN   : Daily match parser HTML
  #
  get '/' do
    date = Time.now.strftime('%d%m%y')
    match = nil
    match = Match.first(date: date)    unless $processing

    if match.nil?
      users = parse(date)
      match_simple = users.sort_by{|e| e.rank?}.reverse

      archie = achievements(users, date)

      erb :main_simple, locals: {match: match_simple, date: date, archie: archie}
    else
      archie = achievements(match.users, date)
      erb :main, locals: {match: match, archie: archie, date: date}
    end
  end

  #
  # PT-BR: Procura o nick do match atual
  # EN   : Find by NICK and Date
  #
  get '/user/:id/date/:date' do
    date = params[:date]
    users = parse(date)
    user = users.select{|e| e.id == params['id']}.first

    list = {}
    users.each{|e| list[e.id] = e.nick}

    g = Gruff::Pie.new
    g.title = 'Kills per weapons'
    theme = Gruff::Themes::THIRTYSEVEN_SIGNALS
    theme[:colors] =  []
    theme[:colors] << '#7FFF00'
    theme[:colors] << '#333300'
    theme[:colors] << '#999966'
    theme[:colors] << '#003300'
    theme[:colors] << '#009933'
    theme[:colors] << '#800000'
    theme[:colors] << '#cc0000'
    theme[:colors] << '#cc00ff'
    theme[:colors] << '#ff66ff'
    theme[:colors] << '#6600cc'
    theme[:colors] << '#000099'
    theme[:colors] << '#006666'
    theme[:colors] << '#00ffcc'
    theme[:colors] << '#cc3300'
    theme[:background_colors] = 'white'

    g.theme = theme

    ParserUser::WEAPONS.each_pair do |w_id, name|
      next if %w(16 17 22).include? w_id
      g.data(name.to_sym, [user.get_kill(name)])
    end

    erb :user_simple, locals: {user: user, list: list, date: date, image: g}
  end

  def exist_pid?(pid)
    return false if pid.nil?
    begin
      Process.getpgid(pid)
      $processing = true
    rescue Errno::ESRCH
      $processing = false
    end
  end

  def save_user(user, match)
    db_user = match.users.first(quake_id: user.id)

    if db_user.nil?
      db_user          = User.new(quake_id: user.id)
    end

    db_user.quake_id = user.id
    db_user.nick     = user.nick
    db_user.kill     = user.kill
    db_user.death    = user.death
    db_user.suicide  = user.suicide

    match.users << db_user

    user.each_weapon(:kill) do |user, weapon_stat|
      victim = db_user.victims.first(user_id: db_user.id, quake_id: user.to_i)
      if victim.nil?
        victim  = Victim.new(user_id: db_user.id, quake_id: user.to_i)
      end

      db_user.victims << victim
      victim.save
      weapon_stat.each_pair do |weapon, count|
        db_weapon           = Weapon.first_or_new(victim_id: victim.id, quake_id: weapon.to_i)
        db_weapon.count     = count
        victim.weapons     << db_weapon
        db_weapon.save
      end
    end

    user.each_weapon(:death) do |user, weapon_stat|
      killer = db_user.killers.first(user_id: db_user.id, quake_id: user.to_i)
      if killer.nil?
        killer  = Killer.new(user_id: db_user.id, quake_id: user.to_i)
      end

      db_user.killers << killer
      killer.save
      weapon_stat.each_pair do |weapon, count|
        db_weapon           = Weapon.first_or_new(killer_id: killer.id, quake_id: weapon)
        db_weapon.count     = count
        killer.weapons     << db_weapon
        db_weapon.save
      end
    end

    db_user.save
    match.save

    db_user
  end

  def create_match(users, date)
    return if $processing

    DataMapper::Model.raise_on_save_failure = true

    $processing = true

    pid = fork do
      match = Match.first(date: date)
      match = Match.new(date: date) if match.nil?
      match.save
      users.delete_if {|user| user.id == '1022' }

      users.each do |user|
        save_user(user, match)
      end

      $processing = false
    end

    $process_pid = pid

    Process.detach pid unless pid == 0
  end

  def weekdays
    date   = Date.today
    monday = nil
    friday = nil

    if date.wday == 1
      monday = date   # Monday
    end

    while date.wday != 1 or monday.nil?
      if date.wday == 1
        monday = date # Monday
        break
      else
        date = date - 1
      end
    end

    date = monday

    while date.wday != 5 or friday.nil?
      if date.wday == 5
        friday = date  # Friday
        break
      else
        date = date + 1
      end
    end

    [monday, friday]
  end

  def parse(date)
    users     = []
    nick_list = {}

    filename = "#{$config['logs_dir']}#{$config['logs_base']}#{date}#{$config['logs_ext']}"

    $logger.info "==> unless File.exist? filename # #{File.exist? filename}"
    unless File.exist? filename
      filename = "#{$config['logs_dir']}games.log"
      $logger.info "==> unless File.exist? filename # #{File.exist? filename}"

      unless File.exist? filename
        $logger.info 'Returning empty array'
        return []
      end
    end

    start = Time.now
    File.open(filename, 'r') do |file|
      file.each_line do |line|
        next unless line.match(/kill:/i)

        time, rest = line.split(/kill:/i)
        ids = rest.scan(/\d+ \d+ \d+/)
        killer, dead, weapon = ids.first.split(' ')

        user_k = users.select{|us| us.id == killer}.first
        user_d = users.select{|us| us.id == dead}.first

        if user_k.nil?
          user_k = ParserUser.new(killer)
          users << user_k
        end

        if user_d.nil?
          user_d = ParserUser.new(dead)
          users << user_d
        end

        killer_nick = rest.match(/\d+:\s+.*killed/i).to_s.sub(/\s+killed/, '').sub(/\d+: /, '')
        dead_nick   = rest.match(/\s*killed.*by/i).to_s.sub(/\s*killed/, '').sub(/\s*by/, '')

        if user_k == user_d or killer_nick.match('<world>')
          user_d.add_suicide
        else
          user_k.add_kill(weapon, dead)
          user_d.add_death(weapon, killer)

          nick_list[user_k.id] = killer_nick unless killer_nick.empty?
          nick_list[user_d.id] = dead_nick   unless dead_nick.empty?

          user_k.add_nick nick_list[user_k.id]
          user_d.add_nick nick_list[user_d.id]
        end
      end
    end

    users.delete_if{|e| e.invalid?}

    $logger.info "==> Finished in #{Time.now - start} second(s)"

    users
  end

  def achievements(users, date)
    info = {}
    # Weapons Badges
    info[:gauntlet]    = {icon: '/gauntlet.png',      title: 'Butcher',         weapon: 'GAUNTLET'}
    info[:sniper]      = {icon: '/sniper.png'  ,      title: 'American Sniper', weapon: 'RAILGUN'}
    info[:machine_gun] = {icon: '/minigun.png',       title: 'Gunner',          weapon: 'MACHINEGUN'}
    info[:telefrag]    = {icon: '/telefrag.jpg',      title: 'Star Trek',       weapon: 'TELEFRAG'}
    info[:shotgun]     = {icon: '/shotgun.png',       title: 'Bear Hunter',     weapon: 'SHOTGUN'}
    info[:lightning]   = {icon: '/lightninggun.png',  title: 'Ghostbuster',     weapon: 'LIGHTNING GUN'}
    info[:plasma]      = {icon: '/plasma.png',        title: 'Space Marine',    weapon: ['PLASMA', 'PLASMA SPLASH']}
    info[:rocket]      = {icon: '/rocket.jpg',        title: 'Rocket Troll',    weapon: ['ROCKET', 'ROCKET SPLASH']}

    # Skills Badges
    info[:kamikaze]    = {          icon: '/kamikaze.png',   title: 'Kamikaze'}
    info[:bullier]     = {total: 0, icon: '/bully.png',      title: 'Bullier'}
    info[:rage]        = {total: 0, icon: '/quad.png',       title: 'Hagen mode'}
    info[:gran_prix]   = {total: 0, icon: '/ChallengePerk.png', title: 'Victor'}

    # Loser Badge
    info[:loser]       = {icon: '/loser.png',    title: 'Wintard'}

    users.each do |user|
      info.keys.each do |key|
        if info[key].has_key? :weapon
          total = 0
          if info[key][:weapon].is_a? Array
            info[key][:weapon].each do |weapon|
              total += user.get_kill(weapon)
            end
          else
            total = user.get_kill(info[key][:weapon])
          end

          unless info[key].has_key? :name
            info[key][:name]  = user.nick
            info[key][:total] = total
          end

          if info[key][:name] != user.nick and info[key][:total] < total
            info[key][:name]   = user.nick
            info[key][:total]  = total
            info[key][:double] = []
          end

          if info[key][:name] != user.nick and info[key][:total] == total
            if info[key].has_key? :double
              info[key][:double] << user.nick
            else
              info[key][:double] = [user.nick]
            end
          end
        end
      end

      # KAMIKAZE
      unless info[:kamikaze].has_key? :name
        info[:kamikaze][:name]  = user.nick
        info[:kamikaze][:total] = user.suicide
      end

      if info[:kamikaze][:name] != user.nick and info[:kamikaze][:total] < user.suicide
        info[:kamikaze][:name]   = user.nick
        info[:kamikaze][:total]  = user.suicide
        info[:kamikaze][:double] = []
      end

      if info[:kamikaze][:name] != user.nick and info[:kamikaze][:total] == user.suicide
        if info[:kamikaze].has_key? :double
          info[:kamikaze][:double] << user.nick
        else
          info[:kamikaze][:double] = [user.nick]
        end
      end
      # --------

      # Bullier
      if !info[:bullier].has_key? :name and user.bullier(users) > 0
        info[:bullier][:name]  = user.nick
        info[:bullier][:total] = user.bullier(users)
      end

      if info[:bullier][:name] != user.nick and info[:bullier][:total] < user.bullier(users)
        info[:bullier][:name]   = user.nick
        info[:bullier][:total]  = user.bullier(users)
        info[:bullier][:double] = []
      end

      if info[:bullier][:name] != user.nick and info[:bullier][:total] == user.bullier(users)
        if info[:bullier].has_key? :double
          info[:bullier][:double] << user.nick
        else
          info[:bullier][:double] = [user.nick]
        end
      end
      # --------
    end

    filename = "#{$config['logs_dir']}#{$config['logs_base']}#{date}#{$config['logs_ext']}"

    id_total = {}
    winner   = {}
    teams    = {red: 0, blue: 0}

    if File.exist? filename

      File.open(filename, 'r') do |file|
        next_line = false
        file.each_line do |line|
          if line.match(/item_quad/)
            id = line.match(/Item:\s+\d+/).to_s.match(/\d+/).to_s
            if id_total.has_key? id
              id_total[id] += 1
            else
              id_total[id]  = 1
            end
          end

          if line.match(/Exit:\s+/) or next_line
            if line.match(/red:\d+\s*blue:\d+/)
              teams[:red]  += line.match(/red:\d+/).to_s.match(/\d+/).to_s.to_i
              teams[:blue] += line.match(/blue:\d+/).to_s.match(/\d+/).to_s.to_i
              next
            end

            if next_line
              next_line = false
              id = line.match(/client: \d+/).to_s.match(/\d+/).to_s
              user = users.select{|u| u.quake_id.to_i == id.to_i}.first

              if winner.has_key? user.nick
                winner[user.nick] += 1
              else
                winner[user.nick]  = 1
              end
            else
              next_line = true
            end
          end
        end
      end
    end

    winner.each_pair do |nick, total|
      unless info[:gran_prix].has_key? :name
        info[:gran_prix][:name]  = nick
        info[:gran_prix][:total] = total
      end

      if info[:gran_prix][:name] != nick and info[:gran_prix][:total] < total
        info[:gran_prix][:name]   = nick
        info[:gran_prix][:total]  = total
        info[:gran_prix][:double] = []
      end

      if info[:gran_prix][:name] != nick and info[:gran_prix][:total] == total
        if info[:gran_prix].has_key? :double
          info[:gran_prix][:double] << nick
        else
          info[:gran_prix][:double] = [nick]
        end
      end
    end

    id_total.each_pair do |id, total|
      user = users.select{|u| u.quake_id.to_i == id.to_i}.first

      if !info[:rage].has_key? :name and total > 0
        info[:rage][:name]  = user.nick
        info[:rage][:total] = total
      end

      if info[:rage][:name] != user.nick and info[:rage][:total] < total
        info[:rage][:name]   = user.nick
        info[:rage][:total]  = total
        info[:rage][:double] = []
      end

      if info[:rage][:name] != user.nick and info[:rage][:total] == total
        if info[:rage].has_key? :double
          info[:rage][:double] << user.nick
        else
          info[:rage][:double] = [user.nick]
        end
      end
    end

    info[:teams] = teams if teams[:red] > 0 or teams[:blue] > 0

    info
  end

  def read_maps(date)
    filename = "#{$config['logs_dir']}#{$config['logs_base']}#{date}#{$config['logs_ext']}"
    shot     = "#{$config['shot_dir']}"

    maps     = []
    score    = {}
    users    = {}
    match_id = 0

    if File.exist? filename
      File.open(filename, 'r') do |file|
        read_score = false

        file.each_line do |line|
          if line.match(/InitGame:/i) # MAP NAME
            read_score = true
            map_name = line.match(/mapname\\+.*\\+/i).to_s.split('\\')
            %x[cp #{shot}/#{map_name[1]}.jpg ./public]
            maps << map_name[1] unless maps.include? map_name[1]
            next
          end

          if read_score and line.match(/score:/)
            user  = line.match(/client: \d+ .*/).to_s.split(/\d+\s/).last
            kills = line.match(/score: \d+/).to_s.match(/\d+/).to_s

            if score.empty? or !score.has_key? match_id.to_s
              score[match_id.to_s] = [{user: user, kills: kills}]
            else
              score[match_id.to_s] << {user: user, kills: kills}
            end

            if users.empty? or !users.has_key? user
              kills = line.match(/score: \d+/).to_s.match(/\d+/).to_s
              users[user.to_s] = {}
              users[user.to_s][:match] = [match_id]
              users[user.to_s][:kills] = [kills.to_i]
            else
              kills = line.match(/score: \d+/).to_s.match(/\d+/).to_s
              users[user.to_s][:match] << match_id
              users[user.to_s][:kills] << kills.to_i
            end

            next
          end

          if line.match(/ShutdownGame:/) and read_score
            if score[match_id.to_s].nil?
              maps.delete_at(match_id)
            else
              match_id += 1
            end

            read_score  = false
          end
        end
      end
    end

    images = []

    g = Gruff::Line.new(1000)
    g.title = 'Score by Maps (All players)'
    g.legend_font_size = 15
    g.marker_font_size = 12
    g.y_axis_increment = 5

    m = {}
    maps.each_with_index do |name, index|
      m[index] = "#{name[0..8]}"
    end

    g.labels = m

    users.each_pair do |user, info|
      match_kills = []
      0.upto match_id - 1 do |i|
        if info[:match].include? i
          match_kills << info[:kills][i]
        else
          match_kills << 0
        end
      end

      g.data user, match_kills
    end

    images << Base64.encode64(g.to_blob).gsub(/\n/, '')

    users.each_pair do |user, info|
      g = Gruff::Line.new(1000)
      g.title = 'Score by Maps'
      g.legend_font_size = 15
      g.marker_font_size = 12
      g.y_axis_increment = 2
      g.labels = m

      match_kills = []
      puts "User: #{user}"
      puts info.inspect
      0.upto match_id - 1 do |i|
        unless info[:match].include? i
          match_kills << 0
        end
      end

      puts match_kills + info[:kills]

      g.data user, match_kills + info[:kills]
      images << Base64.encode64(g.to_blob).gsub(/\n/, '')
    end

    [maps, score, images]
  end
end


#get '/match/week' do
#  monday, friday = weekdays
#  matches = Match.all(date: (monday.strftime('%d%m%y')..friday.strftime('%d%m%y')))
#
#  matches.each do |m|
#    puts m.inspect
#  end
#
#  date = Time.now.strftime('%d%m%y')
#  match = Match.first(date: date)
#
#  erb :main, locals: {match: match}
#end