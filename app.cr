require "./src/main"

Signal::INT.trap do
  puts "Stopping app..."
  exit
end

Kemal.run