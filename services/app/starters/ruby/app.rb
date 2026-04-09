require "webrick"

port = (ENV["PORT"] || "8080").to_i

server = WEBrick::HTTPServer.new(Port: port)

server.mount_proc "/health" do |_req, res|
  res["Content-Type"] = "application/json"
  res.body = '{"status":"ok"}'
end

trap("INT") { server.shutdown }
server.start
