require "kemal"
require "./utils"

get "/route" do |env|
    body = env.request.body.not_nil!.gets_to_end
    parsed = JSON.parse(body)

    orign = parsed["origin"].as_s
    dest = parsed["destination"].as_s
    type = parsed["type"].as_s

    json_path = Path[__DIR__] / ".." / "data" / "db_multi_transit.json"
    data = databases(json_path.expand)

    finals = [] of Hash(String, String)
    code = 200

    if type == "cheapest-direct"
        finals = cheapest_direct(data, orign, dest)
    elsif type == "cheapest"
        finals = cheapest(data, orign, dest)
    elsif type == "fastest"
        finals = fastest(data, orign, dest)
    end 

    puts ""#{finals}"
    if finals.empty?
        code = 400
    end

    {
        "code" => code,
        "data" => finals
    }.to_json
end