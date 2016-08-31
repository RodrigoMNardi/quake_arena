class User
  include DataMapper::Resource

  property :id,         Serial    # An auto-increment integer key
  property :quake_id,   Integer
  property :nick,       String
  property :kill,       Integer
  property :death,      Integer
  property :suicide,    Integer

  has n, :victims
  has n, :killers

  def rank
    score_kill = 0

    self.victims.each do |victim|
      victim.weapons.each do |weapon|
        score_kill += weapon.score
      end
    end

    self.kill - 0.5 * self.death - self.suicide
  end

  def get_kill(weapon_name)
    total = 0
    self.victims.each do |victim|
      victim.weapons.each do |weapon|
        next if weapon.name.downcase != weapon_name.downcase
        total += weapon.count
      end
    end

    total
  end

  def bullier(users)
    bully_points = 0

    users.each do |user|
      next if user.id == self.id
      kills  = 0
      deaths = 0

      user_victim = self.victims.select{|e| e.quake_id == user.quake_id}.first
      user_killer = self.killers.select{|e| e.quake_id == user.quake_id}.first

      user_victim.weapons.each{|weapon| kills += weapon.count}
      user_killer.weapons.each{|weapon| deaths += weapon.count}

      bully_points += 1 if kills - deaths >= 10
    end

    bully_points
  end

  def main_html(podium, badges, match_id)
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
      if badges[key][:name] == self.nick
        html_badge += "<img width='60' height='60' src='#{badges[key][:icon]}' title='#{badges[key][:title]}'/>"
      end

      if badges[key].has_key? :double
        badges[key][:double].each do |nick|
          if self.nick == nick
            html_badge += "<img width='60' height='60' src='#{badges[key][:icon]}' title='#{badges[key][:title]}'/>"
          end
        end
      end
    end

    "<td>#{rank}</td>
<td>
<div>
  <a style='vertical-align:middle' href='/match/#{match_id}/user/#{self.id}'> #{self.nick}</a>
  <span style=''> #{medal} #{html_badge} </span>
</div>
</td>
<td>#{self.kill}</td>
<td>#{self.death}</td>
<td>#{self.suicide}</td>
<td>#{(self.death != 0)? "#{(self.kill.to_f/self.death.to_f).round(2)}" : self.kill}</td>
"
  end
end