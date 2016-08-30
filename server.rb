require 'sinatra/base'
require 'yaml'

require "#{File.dirname(__FILE__)}/database/database"
require "#{File.dirname(__FILE__)}/parser"

$processing  = false
$cache       = []
$process_pid = nil
$config      = YAML::load_file("#{File.dirname(__FILE__)}/config.yml")


class Q3Match < Sinatra::Base
  set :port, 8081

  get '/match/maps' do
    date = Time.now.strftime('%d%m%y')
    maps = []
    filename = "#{$config['logs_dir']}#{$config['logs_base']}#{date}#{$config['logs_ext']}"
    shot = $config['shot_dir']

    if File.exist? filename
      File.open(filename, 'r') do |file|
        file.each_line do |line|
          if line.match(/mapname\\/i) # MAP NAME
            map_name = line.inspect.match(/mapname\\+.*\\+/i).to_s.split('\\')
            puts %x[cp #{shot}/#{map_name[2]}.jpg ./public]
            maps << map_name[2] unless maps.include? map_name[2]
          end
        end
      end
    end

    erb :maps, locals: {maps: maps, match_date: date}
  end

  get '/match/maps/:date' do
    maps     = []
    filename = "#{$config['logs_dir']}#{$config['logs_base']}#{date}#{$config['logs_ext']}"
    shot     = $config['shot_dir']

    if File.exist? filename
      File.open(filename, 'r') do |file|
        file.each_line do |line|
          if line.match(/mapname\\/i) # MAP NAME
            map_name = line.inspect.match(/mapname\\+.*\\+/i).to_s.split('\\')
            puts %x[cp #{shot}/#{map_name[2]}.jpg ./public]
            maps << map_name[2] unless maps.include? map_name[2]
          end
        end
      end
    end

    erb :maps, locals: {maps: maps, match_date: params['date']}
  end

  get '/match/:match_id/user/:user_id' do
    user = User.first(match_id: params['match_id'], id: params['user_id'])

    erb :user, locals: {user: user}
  end

  get '/match/date/:date' do
    exist_pid?($process_pid)

    match = nil
    match = Match.first(date: params[:date].to_s) unless $processing
    puts "==> DATE #{params[:date]}"
    puts "==> MATCH #{match.inspect}"

    if match.nil? or $processing
      users = parse(params[:date])
      #create_match(users, params[:date])

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
  # Salva a MATCH da data atual no DB
  #
  get '/match/save' do
    exist_pid?($process_pid)

    date = Time.now.strftime('%d%m%y')
    users = parse(date)
    create_match(users, date)

    match_simple = users.sort_by{|e| e.rank?}.reverse
    match_simple.delete_if{|e| e.kills.empty? and e.deaths.empty?}

    archie = achievements(users, date)

    erb :main_simple, locals: {match: match_simple, date: date, archie: archie}
  end

  #
  # Parsing do MATCH atual em HTML
  #
  get '/' do
    exist_pid?($process_pid)

    date = Time.now.strftime('%d%m%y')
    match = nil
    match = Match.first(date: date)    unless $processing

    if match.nil?
      users = parse(date)
      match_simple = users.sort_by{|e| e.rank?}.reverse
      match_simple.delete_if{|e| e.kills.empty? and e.deaths.empty?}

      archie = achievements(users, date)

      erb :main_simple, locals: {match: match_simple, date: date, archie: archie}
    else
      archie = achievements(match.users, date)
      erb :main, locals: {match: match, archie: archie, date: date}
    end
  end

  #
  # Procura o nick do match atual
  #
  get '/user/:id/date/:date' do
    date = params[:date]
    users = parse(date)
    user = users.select{|e| e.id == params['id']}.first

    puts "==> User: #{user.inspect}"

    list = {}
    users.each{|e| list[e.id] = e.nick}

    erb :user_simple, locals: {user: user, list: list, date: date}
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
    users = []
    nick_list = {}

    filename = "#{$config['logs_dir']}#{$config['logs_base']}#{date}#{$config['logs_ext']}"

    return []  unless File.exist? filename

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

        killer_nick = rest.match(/:\s*.*\w+.* killed/i).to_s.sub(' killed', '').sub(': ', '')
        dead_nick   = rest.match(/\s*killed\s*.*\w+.*\s*by/i).to_s.sub(/\s*killed/, '').sub(/\s*by/, '')

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

    puts "==> Finished in #{Time.now - start} second(s)"

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
          if next_line
            puts line
            next_line = false
            id = line.match(/client: \d+/).to_s.match(/\d+/).to_s
            user = users.select{|u| u.quake_id == id}.first

            if winner.has_key? user.nick
              winner[user.nick] += 1
            else
              winner[user.nick]  = 1
            end
          else
            next_line = true
          end
        end

        if line.match('bones/bones')
          next unless line.match(/ClientUserinfoChanged:\s*\d+/i)

          id = line.match(/ClientUserinfoChanged:\s+\d+/i).to_s.match(/\d+/).to_s

          user = users.select{|u| u.quake_id == id}.first

          unless info[:loser].has_key? :name
            info[:loser][:name]  = user.nick
            info[:loser][:total] = user.bullier(users)
          end

          if info[:loser][:name] != user.nick
            puts "if info[:loser].has_key? :double => #{info[:loser].has_key? :double}"
            if info[:loser].has_key? :double
              info[:loser][:double] << user.nick unless info[:loser][:double].include? user.nick
            else
              info[:loser][:double] = [user.nick]
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
      user = users.select{|e| e.quake_id == id}.first

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

    puts info.inspect

    info
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