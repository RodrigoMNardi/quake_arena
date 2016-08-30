#clients_id = {}
#
#File.open('./games-180816.log', 'r') do |file|
#  file.each_line do |line|
#    if line.match(/ClientUserinfo:/)
#      id = line.match(/cl_guid\\\w+/).to_s.split("\\").last
#      match_id = line.match(/ClientUserinfo:\s+\w+/).to_s.split(':').last
#
#      clients_id[id] = {match_id: match_id} unless clients_id.include? id
#    end
#  end
#end
#
#puts clients_id


x = [['a', 5], ['b', 1], ['c', 10]]
puts x.sort_by{|f| f.last}