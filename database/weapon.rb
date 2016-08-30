class Weapon
  include DataMapper::Resource

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
        '3'  => 1.5,
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

  property :id,         Serial    # An auto-increment integer key
  property :quake_id,   Integer
  property :count,      Integer

  belongs_to :victim, :required => false
  belongs_to :killer, :required => false

  def score
    (WEAPONS_SCORE[self.quake_id.to_s] * self.count)
  end

  def name
    WEAPONS[self.quake_id.to_s]
  end

  def real_name
    WEAPONS[self.quake_id.to_s]
  end
end