package com.jiborevival.beep

import com.jcraft.jsch.ChannelExec
import com.jcraft.jsch.JSch

/**
 * Converts a modded Jibo to 5x1: logs in over SSH and runs the PM script (BEach PM/post-mod.sh,
 * served at scripts.5x1.com/pm), streaming its output. Same robot-side command as the iPhone
 * app: PM runs detached with its output in /run/5x1-pm.log, so it finishes if the phone locks or
 * BEep closes, and connecting again only follows the log.
 */
object Conversion {
    const val SCRIPT = "jibo-mount --rw && curl -fsSL -k https://scripts.5x1.com/pm -o /run/5x1-pm.sh && sh /run/5x1-pm.sh"
    const val PASSWORD = "jibo" // every modded Jibo's root password

    sealed class Outcome {
        object Converted : Outcome()
        data class Failed(val message: String) : Outcome()
    }

    fun command(pm: String = SCRIPT) = listOf(
        "L=/run/5x1-pm.log",
        "if [ ! -f /run/5x1-pm.started ]; then",
        "  touch /run/5x1-pm.started",
        "  sh -c 'trap \"\" HUP; ($pm); echo \"5X1_PM_EXIT \$?\"; rm -f /run/5x1-pm.started' </dev/null >\$L 2>&1 &",
        "  sleep 1",
        "fi",
        "exec tail -n +1 -f \$L"
    ).joinToString("\n")

    /** What a line of PM output means, if anything. */
    fun outcome(line: String): Outcome? {
        if (line.contains("Rebooting now")) return Outcome.Converted
        if (line.startsWith("5X1_PM_EXIT ")) {
            val code = line.removePrefix("5X1_PM_EXIT ").trim()
            return if (code == "0") Outcome.Converted
            else Outcome.Failed("The 5x1 script stopped with an error (exit $code). Its output is above.")
        }
        return null
    }

    /** Blocking: call from a background thread. */
    fun run(host: String, port: Int = 22, pm: String = SCRIPT, output: (String) -> Unit): Outcome {
        val session = try {
            JSch().getSession("root", host, port).apply {
                setPassword(PASSWORD)
                setConfig("StrictHostKeyChecking", "no") // a freshly modded Jibo has a host key we can't know in advance
                setConfig("PreferredAuthentications", "password,keyboard-interactive")
                connect(15000)
            }
        } catch (error: Exception) {
            return Outcome.Failed("Couldn't log in to $host over SSH. Check the address and that Jibo has been modded (${error.message}).")
        }
        var result: Outcome? = null
        try {
            val channel = session.openChannel("exec") as ChannelExec
            channel.setCommand(command(pm))
            val reader = channel.inputStream.bufferedReader()
            channel.connect(15000)
            while (true) {
                val line = reader.readLine() ?: break
                output(line)
                outcome(line)?.let { result = it }
                if (result is Outcome.Failed || line.startsWith("5X1_PM_EXIT ")) return result!!
            }
        } catch (error: Exception) {
            // PM ends by rebooting Jibo, which drops the connection.
            if (result == Outcome.Converted) return Outcome.Converted
            return Outcome.Failed("Lost the connection to Jibo before the 5x1 script finished. Open this again to keep following it (${error.message}).")
        } finally {
            session.disconnect()
        }
        return result ?: Outcome.Failed("The connection closed before the 5x1 script finished. Open this again to keep following it.")
    }
}
