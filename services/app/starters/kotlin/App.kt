import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress

fun main() {
    val port = System.getenv("PORT")?.toIntOrNull() ?: 8080
    val server = HttpServer.create(InetSocketAddress(port), 0)

    server.createContext("/health") { exchange ->
        val response = """{"status":"ok"}"""
        exchange.responseHeaders.add("Content-Type", "application/json")
        exchange.sendResponseHeaders(200, response.length.toLong())
        exchange.responseBody.use { it.write(response.toByteArray()) }
    }

    server.executor = null
    server.start()
    println("Server listening on port $port")
}
