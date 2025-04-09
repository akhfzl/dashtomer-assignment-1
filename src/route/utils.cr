require "../data/meta"
require "time"

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

def cheapest_direct(data : DB, origin : String, dest : String)
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

    # return object needed
    if cheapest && best_rate
        {
            "origin_port"      => cheapest.origin_port,
            "destination_port" => cheapest.destination_port,
            "departure_date"   => cheapest.departure_date,
            "arrival_date"     => cheapest.arrival_date,
            "sailing_code"     => cheapest.sailing_code,
            "rate"             => best_rate.rate,
            "rate_currency"    => best_rate.rate_currency
        }.to_json
    else
        ({} of String => String).to_json
    end
end

def explore_paths(data : DB, current : String, dest : String, path : Array(Sailing), visited : Set(String), total_time : Float64 | Int64, best_route : Array(Sailing), best_duration : Float64 | Int64)
    # count total time no more best_duration
    if current == dest && !path.empty?
        if total_time < best_duration
            best_route.clear
            best_route.concat(path)
            return total_time
        end
        return best_duration
    end

    data.sailings.each do |transite|
        transite_parsing = time_parsing(transite)
        path_parsing = time_parsing(path.last)


        # if current point equal to continues origin port
        next unless current == transite.origin_port
    
        puts <<-INFO
            ORIGIN - first stage #{current} - continue stage #{transite.origin_port}
            DEST - continue stage #{transite.destination_port}
            continue departure_date: #{transite_parsing["departure_date"]}
            first stage arrival_date: #{path_parsing["arrival_date"]}
            transite.departure > path.arrival? #{transite_parsing["departure_date"] > path_parsing["arrival_date"]}
        INFO

        # the 2nd route ends at the requested final dest
        next unless transite_parsing["departure_date"] > path_parsing["arrival_date"]

        # count new total time then compare with best_duration
        t_time = time_parsing(transite)
        p_time = time_parsing(path.first)
        new_total_time = (t_time["arrival_date"] - p_time["departure_date"]).days rescue 0.0

        # skip if new total time more best_duration
        next if new_total_time >= best_duration

        path.push(transite)
        visited.add(transite.sailing_code)
        best_duration = explore_paths(data, transite.destination_port, dest, path, visited, new_total_time, best_route, best_duration)
        path.pop
        visited.delete(transite.sailing_code)
    end

    return best_duration
end

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
        explore_paths(data, start.destination_port, dest, [start], Set{start.sailing_code}, 0.0, best_multi_route, shortest_time)
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
    
    puts "multi-duration #{multi_duration} - best_multi_route #{best_multi_route}"

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

    output.to_json
end
