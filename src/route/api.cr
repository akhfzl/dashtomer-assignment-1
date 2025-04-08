require "kemal"
require "./utils"

get "/route" do |env|
    body = env.request.body.not_nil!.gets_to_end
    parsed = JSON.parse(body)

    orign = parsed["origin"].as_s
    dest = parsed["destination"].as_s
    type = parsed["type"].as_s

    if type == "cheapest-direct"
        json_path = Path[__DIR__] / ".." / "data" / "db.json"
        data = databases(json_path.expand)
        cheapest_direct(data, orign, dest)
    
    elsif type == "cheapest"
        puts "cheapest"
    
    else 
        puts "fastest"
    end
end