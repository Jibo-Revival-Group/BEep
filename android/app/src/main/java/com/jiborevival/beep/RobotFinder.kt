package com.jiborevival.beep

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Handler
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

data class Robot(val name: String, val host: String) {
    val url get() = "http://$host:8123/"
}

/**
 * Finds Jibos on the Wi-Fi and remembers them, like the iPhone app: Jibo's avahi advertises SSH
 * under the robot's name, so browse that and keep only hosts whose BEacon answers /api/status.
 * Robots are saved under their IPv4 address, so a new DHCP address updates the robot in place.
 */
class RobotFinder(context: Context, private val changed: (List<Robot>) -> Unit) {
    private val prefs = context.getSharedPreferences("robots", Context.MODE_PRIVATE)
    private val nsd = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val main = Handler(Looper.getMainLooper())
    private val work = Executors.newCachedThreadPool()
    private val pending = ArrayDeque<NsdServiceInfo>()
    private var resolving = false
    private var listener: NsdManager.DiscoveryListener? = null

    var robots: List<Robot> = load()
        private set

    fun start() {
        if (listener != null) return
        val discovery = object : NsdManager.DiscoveryListener {
            override fun onServiceFound(service: NsdServiceInfo) { main.post { pending.addLast(service); resolveNext() } }
            override fun onServiceLost(service: NsdServiceInfo) {}
            override fun onDiscoveryStarted(type: String) {}
            override fun onDiscoveryStopped(type: String) {}
            override fun onStartDiscoveryFailed(type: String, code: Int) { listener = null }
            override fun onStopDiscoveryFailed(type: String, code: Int) {}
        }
        listener = discovery
        try { nsd.discoverServices("_ssh._tcp", NsdManager.PROTOCOL_DNS_SD, discovery) } catch (_: Exception) { listener = null }
        robots.forEach { check(it.host) {} } // saved robots may have new addresses
    }

    fun stop() {
        listener?.let { try { nsd.stopServiceDiscovery(it) } catch (_: Exception) {} }
        listener = null
    }

    // NsdManager resolves one service at a time.
    @Suppress("DEPRECATION")
    private fun resolveNext() {
        if (resolving) return
        val service = pending.removeFirstOrNull() ?: return
        resolving = true
        nsd.resolveService(service, object : NsdManager.ResolveListener {
            override fun onServiceResolved(info: NsdServiceInfo) {
                info.host?.hostAddress?.let { check(it) {} }
                main.post { resolving = false; resolveNext() }
            }
            override fun onResolveFailed(info: NsdServiceInfo, code: Int) { main.post { resolving = false; resolveNext() } }
        })
    }

    /** Asks BEacon at [host] who it is; saves and returns the robot, or null if it isn't one. */
    fun check(host: String, done: (Robot?) -> Unit) {
        work.execute {
            val robot = try { probe(host) } catch (_: Exception) { null }
            main.post {
                if (robot != null) save(robot)
                done(robot)
            }
        }
    }

    fun forget(robot: Robot) { robots = robots.filter { it != robot }; store() }

    private fun probe(host: String): Robot? {
        val connection = URL("http://$host:8123/api/status").openConnection() as HttpURLConnection
        connection.connectTimeout = 5000; connection.readTimeout = 5000
        try {
            val status = JSONObject(connection.inputStream.bufferedReader().readText())
            if (status.optString("name") != "BEacon") return null
            val addresses = status.optJSONArray("addresses") ?: JSONArray()
            var ip = host
            for (i in 0 until addresses.length()) {
                val address = addresses.getJSONObject(i).optString("address")
                if (address.contains('.')) { ip = address; break }
            }
            return Robot(status.optString("hostname").ifEmpty { host }, ip)
        } finally { connection.disconnect() }
    }

    private fun save(robot: Robot) {
        val index = robots.indexOfFirst { it.name == robot.name }
        if (index >= 0 && robots[index] == robot) return
        robots = if (index >= 0) robots.toMutableList().also { it[index] = robot } else robots + robot
        store()
    }

    private fun store() {
        val list = JSONArray()
        robots.forEach { list.put(JSONObject().put("name", it.name).put("host", it.host)) }
        prefs.edit().putString("robots", list.toString()).apply()
        changed(robots)
    }

    private fun load(): List<Robot> {
        val list = try { JSONArray(prefs.getString("robots", "[]")) } catch (_: Exception) { JSONArray() }
        return (0 until list.length()).map { list.getJSONObject(it).let { r -> Robot(r.getString("name"), r.getString("host")) } }
    }
}
