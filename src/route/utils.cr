require "../data/meta"
require "time"

# open db json
def databases(filename : Path | String)
    data = File.read(filename)
    DB.from_json(data)
end

# conv str to time object
def time_parsing(sailing : Sailing) : Hash(String, Time)
    {
        "departure_date" => Time.parse(sailing.departure_date, "%Y-%m-%d", Time::Location.local),
        "arrival_date"   => Time.parse(sailing.arrival_date, "%Y-%m-%d", Time::Location.local)
    }
end

#convert concurrency
def convert_to_eur(rate_date, rate : Rate) : Float64
    # check if eur
    currency = rate.rate_currency.downcase
    return rate.rate.to_f if currency == "eur"

    # check if rate_date is nill
    return rate.rate.to_f unless rate_date

    # if rate currency not found
    exchange = rate_date[currency]?
    return rate.rate.to_f unless exchange
    
    rate.rate.to_f / exchange
end

# check paths fastest or cheapest
def explore_paths(
  data : DB,
  current : String,
  dest : String,
  path : Array(Sailing),
  visited : Set(String),
  total_cost_time : Float64 | Int64,
  best_route : Array(Sailing),
  best_duration_cost : Float64 | Int64,
  is_fastest : Bool = false
)
    # count total time no more best_duration_cost
    if current == dest && !path.empty?
        if total_cost_time < best_duration_cost
            best_route.clear
            best_route.concat(path)
            return total_cost_time
        end
        return best_duration_cost
    end

    data.sailings.each do |transite|
        transite_parsing = time_parsing(transite)
        path_parsing = time_parsing(path.first)


        # if current point equal to continues origin port
        next unless current == transite.origin_port

        # the 2nd route ends at the requested final dest
        next unless transite_parsing["departure_date"] > path_parsing["arrival_date"]

        if is_fastest
            # count new total time then compare with best_duration_cost
            t_time = time_parsing(transite)
            p_time = time_parsing(path.first)
            new_total_cost_time = (t_time["arrival_date"] - p_time["departure_date"]).days rescue 0.0

        else
            # check rate of transite
            rate_transite = data.rates.find { |r| r.sailing_code == transite.sailing_code }
            next unless rate_transite 

            # check rate of path (first stage)
            rate_path = data.rates.find { |r| r.sailing_code == path.first.sailing_code }
            next unless rate_path

            # check rate date of transite and path (first stage)
            transite_rate_date = data.exchange_rates[transite.departure_date]?
            path_rate_date = data.exchange_rates[path.first.departure_date]?
            new_total_cost_time = convert_to_eur(path_rate_date, rate_path) - convert_to_eur(transite_rate_date, rate_transite)
        end

        # skip if new total time more best_duration_cost
        next if new_total_cost_time >= best_duration_cost

        path.push(transite)
        visited.add(transite.sailing_code)
        best_duration_cost = explore_paths(data, transite.destination_port, dest, path, visited, new_total_cost_time, best_route, best_duration_cost, is_fastest)
        path.pop
        visited.delete(transite.sailing_code)

        puts <<-INFO
            ORIGIN - first stage #{current} - continue stage #{transite.origin_port}
            DEST - continue stage #{transite.destination_port}
            cost/duration #{best_duration_cost}
        INFO
    end

    return best_duration_cost
end

# check cheapest and best direct 
def check_cheapest_direct(data : DB, origin : String, dest : String)
    # initial
    cheapest = nil
    min_cost = Float64::INFINITY
    best_rate = nil

    # data sailing loop for check and count minimal cost
    data.sailings.each do |sailing|
        next unless sailing.origin_port == origin && sailing.destination_port == dest

        rate = data.rates.find { |r| r.sailing_code == sailing.sailing_code }
        next unless rate

        #conv concurrency
        rate_date = data.exchange_rates[sailing.departure_date]?
        cost = convert_to_eur(rate_date, rate)
        puts "cost minimal #{cost} - rate #{rate.rate_currency.downcase} - #{rate_date} | #{sailing.sailing_code}"
        
        if cost < min_cost
            min_cost = cost
            cheapest = sailing
            best_rate = rate
        end
    end

    {cheapest, min_cost, best_rate}
end

# cheapest direct feature
def cheapest_direct(data : DB, origin : String, dest : String)
    output = [] of Hash(String, String)

    # no transit but cheap
    cheapest, min_cost, best_rate = check_cheapest_direct(data, origin, dest)

    # return object needed
    if cheapest && best_rate
        output << {
            "origin_port"      => cheapest.origin_port,
            "destination_port" => cheapest.destination_port,
            "departure_date"   => cheapest.departure_date,
            "arrival_date"     => cheapest.arrival_date,
            "sailing_code"     => cheapest.sailing_code,
            "rate"             => best_rate.rate,
            "rate_currency"    => best_rate.rate_currency
        }
    end 
    
    output
end

# fastest feature
def fastest(data : DB, origin : String, dest : String) 
    time_direct = Float64::INFINITY
    best_direct : Sailing? = nil
    best_multi_route = [] of Sailing
    shortest_time = Float64::INFINITY
    multi_duration = Float64::INFINITY

    # if directly
    data.sailings.each do |first_stage|
        next unless first_stage.origin_port == origin && first_stage.destination_port == dest

        f_time = time_parsing(first_stage)
        duration = f_time["arrival_date"] - f_time["departure_date"]
        if duration.days < time_direct
            time_direct = duration.days
            best_direct = first_stage
        end
    end

    # ---- multi-transite stage --------
    # browse sailing by origin
    data.sailings.select { |s| s.origin_port == origin }.each do |start|
        explore_paths(data, start.destination_port, dest, [start], Set{start.sailing_code}, 0.0, best_multi_route, shortest_time, true)
    end

    # looking for rate baseon sailing code
    find_rate = ->(code : String) do
        data.rates.find { |r| r.sailing_code == code }
    end

    # output final
    output = [] of Hash(String, String)

    # if best_direct available and time direct no more than multi-transit
    unless best_multi_route.empty?
        bmr_l = time_parsing(best_multi_route.last)
        bmr_f = time_parsing(best_multi_route.first)
        multi_duration = (bmr_l["arrival_date"] - bmr_f["departure_date"]).days
    end

    if best_direct && time_direct <= multi_duration
        puts "Directly - #{time_direct}"
        best = best_direct
        rate = find_rate.call(best.sailing_code)
        rate_value = rate.try(&.rate) || 0.0
        rate_currency = rate.try(&.rate_currency) || "N/A"

        output << {
            "origin_port"    => best.origin_port,
            "destination_port" => best.destination_port,
            "departure_date" => best.departure_date,
            "arrival_date"   => best.arrival_date,
            "sailing_code"   => best.sailing_code,
            "rate"           => rate_value.to_s,
            "rate_currency"  => rate_currency
        }

    # if best_multi_route is available
    elsif !best_multi_route.empty?
        total_time = multi_duration
        puts "Multi-Transit - #{total_time}"
        best_multi_route.each do |s|
            rate = find_rate.call(s.sailing_code)
            rate_value = rate.try(&.rate) || 0.0
            rate_currency = rate.try(&.rate_currency) || "N/A"

            output << {
                "origin_port"    => s.origin_port,
                "destination_port" => s.destination_port,
                "departure_date" => s.departure_date,
                "arrival_date"   => s.arrival_date,
                "sailing_code"   => s.sailing_code,
                "rate"           => rate_value.to_s,
                "rate_currency"  => rate_currency
            }
        end
    end

    output
end

# cheapest feature
def cheapest(data : DB, origin : String, dest : String) 
    # initial 
    best_multi_route = [] of Sailing
    best_cost_transite = Float64::INFINITY
    multi_cost_transite = 0
    output = [] of Hash(String, String)
    
    # no transit but cheap 
    cheapest, min_cost, best_rate = check_cheapest_direct(data, origin, dest)

    # ---- multi-transite stage --------
    # browse sailing by origin
    data.sailings.select { |s| s.origin_port == origin }.each do |start|
        explore_paths(data, start.destination_port, dest, [start], Set{start.sailing_code}, 0.0, best_multi_route, best_cost_transite, false)
    end

    # looking for rate baseon sailing code
    find_rate = ->(code : String) do
        data.rates.find { |r| r.sailing_code == code }
    end

    # output final
    output = [] of Hash(String, String)

    # if best_direct available and time direct no more than multi-transit
    unless best_multi_route.empty?
        best_multi_route.each do |sailings|
            # check rate each sailings
            rate = find_rate.call(sailings.sailing_code)
            next unless rate

            rate_date = data.exchange_rates[sailings.departure_date]?
            cost = convert_to_eur(rate_date, rate)
          
            multi_cost_transite += cost

            rate_value = rate.try(&.rate) || 0.0
            rate_currency = rate.try(&.rate_currency) || "N/A"

            output << {
                "origin_port"    => sailings.origin_port,
                "destination_port" => sailings.destination_port,
                "departure_date" => sailings.departure_date,
                "arrival_date"   => sailings.arrival_date,
                "sailing_code"   => sailings.sailing_code,
                "rate"           => rate_value.to_s,
                "rate_currency"  => rate_currency
            }     
        end 
    end

    puts "#{output}"
    # directly
    if min_cost <= multi_cost_transite 
        puts "Directly cost - #{min_cost}"
        {
            "origin_port"      => cheapest ? cheapest.origin_port : "",
            "destination_port" => cheapest ? cheapest.destination_port : "",
            "departure_date"   => cheapest ? cheapest.departure_date : "",
            "arrival_date"     => cheapest ? cheapest.arrival_date : "",
            "sailing_code"     => cheapest ? cheapest.sailing_code : "",
            "rate"             => best_rate ? best_rate.rate : "N/A",
            "rate_currency"    => best_rate ? best_rate.rate_currency : "N/A"
        }

    # transite
    elsif !best_multi_route.empty? && min_cost > multi_cost_transite
        puts "Multi-Transit - #{multi_cost_transite}"
        output
    
    else 
        ([] of Hash(String, String))
    end
end