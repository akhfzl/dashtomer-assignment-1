require "../data/meta"

def databases(filename : Path | String)
    data = File.read(filename)
    DB.from_json(data)
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
    cheapest = nil
    min_cost = Float64::INFINITY
    best_rate = nil

    data.sailings.each do |sailing|
        next unless sailing.origin_port == origin && sailing.destination_port == dest

        rate = data.rates.find { |r| r.sailing_code == sailing.sailing_code }
        next unless rate

        rate_date = data.exchange_rates[sailing.departure_date]?
        cost = convert_to_eur(rate_date, rate)
        puts "cost minimal #{cost} - rate #{rate.rate_currency.downcase} - #{rate_date} | #{sailing.sailing_code}"
        if cost < min_cost
            min_cost = cost
            cheapest = sailing
            best_rate = rate
        end
    end

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