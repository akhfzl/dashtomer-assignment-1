require "json"

struct Sailing
  include JSON::Serializable
  property origin_port : String
  property destination_port : String
  property departure_date : String
  property arrival_date : String
  property sailing_code : String
end

struct Rate
  include JSON::Serializable
  property sailing_code : String
  property rate : String
  property rate_currency : String
end

struct DB
  include JSON::Serializable
  property sailings : Array(Sailing)
  property rates : Array(Rate)
  property exchange_rates : Hash(String, Hash(String, Float64))
end