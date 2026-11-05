package com.jiborevival.beep

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test

class ConversionTest {
    @Test fun outcomes() {
        assertEquals(Conversion.Outcome.Converted, Conversion.outcome("Mode change requires a reboot. Rebooting now..."))
        assertEquals(Conversion.Outcome.Converted, Conversion.outcome("5X1_PM_EXIT 0"))
        assertTrue(Conversion.outcome("5X1_PM_EXIT 23") is Conversion.Outcome.Failed)
        assertNull(Conversion.outcome("=== Step 2: Stage and install BEam and BEnch ==="))
        assertEquals(Conversion.Outcome.Updating, Conversion.outcome("run this script again to install BEam and BEnch."))
    }

    @Test fun neverSetUpRobotsGetTheOobeScript() {
        assertTrue(Conversion.SCRIPT.startsWith("if [ -f /var/jibo/5x1-pm-oobe-state.json ] || [ ! -s /var/jibo/credentials.json ] || grep -q oobe /var/jibo/mode.json; then "))
        assertTrue(Conversion.SCRIPT.contains("BEach/master/PM/post-oobe-mod.sh"))
        assertTrue(Conversion.SCRIPT.contains("else jibo-mount --rw && curl -fsSL -k https://scripts.5x1.com/pm"))
        assertTrue("runs inside sh -c '...'", !Conversion.SCRIPT.contains("'"))
    }

    @Test fun commandMatchesTheIPhoneApp() {
        val command = Conversion.command("echo hi")
        assertTrue(command.contains("(echo hi); echo \"5X1_PM_EXIT \$?\""))
        assertTrue(command.endsWith("exec tail -n +1 -f \$L"))
    }

    /** JIBO_HOST=<ip> runs a harmless stand-in for PM on a real robot over SSH (no install, no reboot). */
    @Test fun realRobot() {
        val host = System.getenv("JIBO_HOST")
        assumeTrue(host != null)
        val lines = mutableListOf<String>()
        val result = Conversion.run(host!!, pm = "echo \"=== Step 1 ===\"; sleep 1; echo \"Rebooting now...\"") { lines += it }
        assertEquals(Conversion.Outcome.Converted, result)
        assertEquals(listOf("=== Step 1 ===", "Rebooting now...", "5X1_PM_EXIT 0"), lines)
        val failed = Conversion.run(host, pm = "echo x; exit 3") {}
        assertTrue(failed is Conversion.Outcome.Failed)
    }
}
