class ParserUser
  attr_reader :id, :nick, :suicide, :kills, :kill, :deaths, :death
  WEAPONS = { '1'  => 'SHOTGUN',
              '2'  => 'GAUNTLET',
              '3'  => 'MACHINEGUN',
              '4'  => 'GRENADE',
              '5'  => 'GRENADE SPLASH',
              '6'  => 'ROCKET',
              '7'  => 'ROCKET SPLASH',
              '8'  => 'PLASMA GUN',
              '9'  => 'PLASMA SPLASH',
              '10' => 'RAILGUN',
              '11' => 'LIGHTNING GUN',
              '12' => 'BFG',
              '13' => 'BFG SPLASH',
              '16' => 'LAVA',
              '17' => 'CRUSH',
              '18' => 'TELEFRAG',
              '22' => 'SUICIDE',
              ''  => ''}

  WEAPONS_SCORE =
      { '1'  => 1,
        '2'  => 1.25,
        '3'  => 1.25,
        '4'  => 1.5,
        '5'  => 1,
        '6'  => 1,
        '7'  => 0.5,
        '8'  => 1,
        '9'  => 0.75,
        '10' => 1.5,
        '11' => 1,
        '12' => 0.5,
        '13' => 0.25,
        '16' => 0,
        '17' => 0,
        '18' => 5,
        '22' => 0,
        ''  => ''}

  def initialize(id)
    @id              = id
    @nick            = ''
    @suicide         = 0
    @kills           = {}
    @deaths          = {}
    @weapons         = {}
    @weapons[:kill]  = {}
    @weapons[:death] = {}
    @rank            = 0
    @kill            = 0
    @death           = 0
  end

  def quake_id
    @id
  end

  def add_nick(nick)
    @nick = nick
  end

  def add_suicide
    @suicide += 1
  end

  def add_kill(weapon, user)
    unless @weapons[:kill].has_key? user
      @weapons[:kill][user] = {}
    end

    if @weapons[:kill][user].has_key? weapon
      @weapons[:kill][user][weapon] += 1
    else
      @weapons[:kill][user][weapon] = 1
    end

    if @kills.has_key? user
      @kills[user] += 1
      @total_kill  += 1
    else
      @kills[user] = 1
      @total_kill  = 1
    end

    rank?
  end

  def get_kill(weapon)
    weapon_id = WEAPONS.select{|id, name| name.downcase == weapon.downcase}.keys.last

    count = 0

    @weapons[:kill].each_pair do |user, weapon|
      if @weapons[:kill][user].has_key? weapon_id
        count += @weapons[:kill][user][weapon_id]
      end
    end

    count
  end

  def add_death(weapon, user)
    unless @weapons[:death].has_key? user
      @weapons[:death][user] = {}
    end

    if @weapons[:death][user].has_key? weapon
      @weapons[:death][user][weapon] += 1
    else
      @weapons[:death][user][weapon] = 1
    end

    if @deaths.has_key? user
      @deaths[user] += 1
    else
      @deaths[user] = 1
    end

    rank?
  end

  def kill
    sum = 0
    @kills.each_pair do |user, count|
      sum += count
    end
    sum
  end

  def death
    sum = 0
    @deaths.each_pair do |user, count|
      sum += count
    end
    sum
  end

  def each_weapon(mode)
    @weapons[mode].each_pair do |user, weapon_stat|
      yield [user, weapon_stat] if block_given?
    end
  end

  #def report(users)
  #  puts "USER: #{@nick} (#{@id})"
  #  @kills.keys.each do |key|
  #    next if key == @id
  #    puts "==> USER #{users[key]} (#{key}) - KILL: #{@kills[key]} | DEATH #{@deaths[key]} | RATIO #{@kills[key] / @deaths[key].to_f}"
  #    puts 'WEAPONS:'
  #    puts '* KILL(s)'
  #    @weapons[:kill][key].each_pair {|weapon, count| puts "#{WEAPONS[weapon]} #{count}"}
  #    puts '* DEATH(s)'
  #    @weapons[:death][key].each_pair {|weapon, count| puts "#{WEAPONS[weapon]} #{count}"}
  #  end
  #end

  def bullier(users)
    bully_points = 0
    users.each do |key|
      next if key.id == @id
      kill = (@kills.has_key? key.id)? @kills[key.id] : 0
      death = (@deaths.has_key? key.id)? @deaths[key.id] : 0

      bully_points += 1 if kill - death >= 10
    end
    bully_points
  end

  def personal_result(users)
    page  =  "
<html>
<head>
  <title> REPORT - #{@nick} </title>
</head>
<body>
<table>
<tr>
<td> PLAYER </td>
<td> KILL </td>
<td> DEATH </td>
<td> RATIO </td>
<td> WEAPONS (KILL) </td>
<td> WEAPONS (DEATH) </td>

</tr>
"
    weapon_kill = {}
    weapon_death = {}

    users.keys.each do |key|
      next if key == '1022'
      next if key == @id
      page += '<tr>'
      css_color = 'win'  if @kills[key] > @deaths[key]
      css_color = 'lose' if @kills[key] < @deaths[key]
      css_color = 'draw' if @kills[key] == @deaths[key]
      page += "<td><div class='#{css_color}'>#{users[key]}"
      page += "<img src='/skull.png' title='Nemesis'/>" if @deaths[key] - @kills[key] >= 10
      page += "<img src='/target.png' title='Hunted'/>" if @kills[key]  - @deaths[key] >= 10
      page += '</div></td>'
      page += "<td>#{@kills[key]}</td>"
      page += "<td>#{@deaths[key]}</td>"
      page += "<td>#{(@deaths[key].nil?)? @kills[key] : (@kills[key] / @deaths[key].to_f).round(2)}</td>"

      buffer = ''

      weapons = []
      unless @weapons[:kill][key].nil?
        @weapons[:kill][key].each_pair do |weapon, count|
          if weapon_kill.include? WEAPONS[weapon]
            weapon_kill[WEAPONS[weapon]] += count
          else
            weapon_kill[WEAPONS[weapon]]  = count
          end

          weapons << [WEAPONS[weapon], count]
        end
      end

      weapons.sort_by{|f| f.last}.reverse.each do |weapon, count|
        buffer += "<div class='weapon #{weapon}'>#{weapon}: #{count}</div>"
      end

      page += "<td>#{buffer}</td>"

      buffer = ''

      weapons = []
      unless @weapons[:death][key].nil?
        @weapons[:death][key].each_pair do |weapon, count|
          if weapon_death.include? WEAPONS[weapon]
            weapon_death[WEAPONS[weapon]] += count
          else
            weapon_death[WEAPONS[weapon]]  = count
          end

          weapons << [WEAPONS[weapon], count]
        end
      end

      weapons.sort_by{|f| f.last}.reverse.each do |weapon, count|
        buffer += "<div class='weapon #{weapon}'>#{weapon}: #{count}</div>"
      end

      page += "<td>#{buffer}</td>"
      page += '</tr>'
    end

    page += '<td>TOTAL</td>'
    page += '<td></td>'
    page += '<td></td>'
    page += '<td></td>'
    page += '<td>'

    k_weapons = []
    weapon_kill.each_pair do |weapon, total|
      k_weapons << [weapon, total]
    end

    d_weapons = []
    weapon_death.each_pair do |weapon, total|
      d_weapons << [weapon, total]
    end

    k_weapons.sort_by{|f| f.last}.reverse.each do |weapon, total|
      page += "<div class='weapon #{weapon}'>#{weapon}: #{total}</div>"
    end
    page += '</td>'

    page += '<td>'
    d_weapons.sort_by{|f| f.last}.reverse.each do |weapon, total|
      page += "<div class='weapon #{weapon}'>#{weapon}: #{total}</div>"
    end
    page += '</td>'

    page
  end

  def rank?
    score_kill  = 0
    kills       = 0
    score_death = 0
    deaths      = 0

    @kills.keys.each do |key|
      next if key == @id
      if @weapons[:kill].has_key? key
        @weapons[:kill][key].each_pair do |weapon, count|
          unless WEAPONS_SCORE.include? weapon
            puts "==> #{weapon}"
          end
          score_kill += WEAPONS_SCORE[weapon] * count
          kills      += count
        end

      end

      if @weapons[:death].has_key? key
        @weapons[:death][key].each_pair do |weapon, count|
          score_death += WEAPONS_SCORE[weapon] * count
          deaths      += count
        end
      end
    end

    @rank  = kills - (0.5 * deaths) - @suicide
    @kill  = kills
    @death = deaths
    @rank
  end

  def main_html(podium, badges, date)
    case podium
      when 1
        medal = "<img width='20' height='20' src='/gold.png' title='Gold Medal'/>"
      when 2
        medal = "<img width='20' height='20' src='/silver.png' title='Silver Medal'/>"
      when 3
        medal = "<img width='20' height='20' src='/bronze.png' title='Bronze Medal'/>"
      else
        medal = ''
    end

    html_badge = ''

    badges.keys.each do |key|
      if badges[key][:name] == @nick
        html_badge += "<img width='60' height='60' src='#{badges[key][:icon]}' title='#{badges[key][:title]}'/>"
      end

      if badges[key].has_key? :double
        badges[key][:double].each do |nick|
          if @nick == nick
            html_badge += "<img width='60' height='60' src='#{badges[key][:icon]}' title='#{badges[key][:title]}'/>"
          end
        end
      end
    end

    "<td>#{@rank}</td>
<td><a href='/user/#{@id}/date/#{date}'>#{@nick}</a> #{medal} #{html_badge}</td>
<td>#{@kill}</td>
<td>#{@death}</td>
<td>#{@suicide}</td>
<td>#{(@death != 0)? "#{(@kill.to_f/@death.to_f).round(2)}" : @kill}</td>
"
  end
end


