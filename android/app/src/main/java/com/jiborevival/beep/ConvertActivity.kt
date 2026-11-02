package com.jiborevival.beep

import android.app.Activity
import android.os.Bundle
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.WindowManager
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.jiborevival.beep.Look.dp
import com.jiborevival.beep.Look.pad
import com.jiborevival.beep.Look.style
import kotlin.concurrent.thread

/** Turns a modded Jibo into a 5x1 Jibo by running the PM script on it over SSH (see Conversion). */
class ConvertActivity : Activity() {
    private lateinit var address: EditText
    private lateinit var convert: Button
    private lateinit var status: TextView
    private lateinit var log: TextView
    private lateinit var logScroll: ScrollView
    private var running = false

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        val column = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; pad(this@ConvertActivity, 20, 16) }
        column.addView(TextView(this).apply { text = "Convert a Jibo" }.style(24, bold = true))
        column.addView(TextView(this).apply {
            text = "Installs 5x1 (BEam and BEnch) on a Jibo that has already been modded, then restarts him. Keep BEep open; it takes several minutes."
        }.style(15, Look.muted), spaced(8))
        address = EditText(this).apply {
            hint = "Jibo's IP address"; setHintTextColor(0x66FFFFFF); inputType = InputType.TYPE_CLASS_PHONE
            background = Look.glass(this@ConvertActivity, 22); pad(this@ConvertActivity, 16, 14)
            setText(intent.getStringExtra("BEepConvert") ?: "")
        }.style(16) as EditText
        column.addView(address, spaced(16))
        convert = Button(this).apply {
            text = "Convert to 5x1"; isAllCaps = false; setTextColor(Look.onGreen); background = Look.pill(this@ConvertActivity, Look.green)
            setOnClickListener { start() }
        }
        column.addView(convert, spaced(14).apply { height = dp(50) })
        status = TextView(this).style(15, Look.muted) as TextView
        column.addView(status, spaced(14))
        log = TextView(this).apply { typeface = android.graphics.Typeface.MONOSPACE; setTextIsSelectable(true) }.style(11, Look.text) as TextView
        logScroll = ScrollView(this).apply {
            background = Look.glass(this@ConvertActivity, 22); pad(this@ConvertActivity, 14, 12); visibility = View.GONE
            addView(log)
        }
        column.addView(logScroll, LinearLayout.LayoutParams(MATCH_PARENT, dp(320)).apply { topMargin = dp(14) })

        val scroll = ScrollView(this).apply { addView(column); overScrollMode = View.OVER_SCROLL_IF_CONTENT_SCROLLS }
        scroll.setOnApplyWindowInsetsListener { view, insets ->
            @Suppress("DEPRECATION") view.setPadding(0, insets.systemWindowInsetTop, 0, insets.systemWindowInsetBottom); insets
        }
        setContentView(scroll)
        if (intent.hasExtra("BEepConvert")) start() // emulator check
    }

    private fun start() {
        val host = address.text.toString().trim()
        if (running || host.isEmpty()) return
        running = true; convert.isEnabled = false; convert.text = "Converting…"; address.isEnabled = false
        status.text = "Working on Jibo… keep BEep open."; status.setTextColor(Look.muted)
        log.text = ""; logScroll.visibility = View.VISIBLE
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) // the phone sleeping would drop the connection
        val port = intent.getIntExtra("BEepConvertPort", 22)
        val pm = intent.getStringExtra("BEepConvertPM") ?: Conversion.SCRIPT
        thread {
            val result = Conversion.run(host, port, pm) { line ->
                runOnUiThread { log.append(line + "\n"); logScroll.post { logScroll.fullScroll(View.FOCUS_DOWN) } }
            }
            runOnUiThread {
                running = false; convert.isEnabled = true; convert.text = "Convert to 5x1"; address.isEnabled = true
                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                when (result) {
                    Conversion.Outcome.Converted -> { status.text = "✓ Jibo is restarting into 5x1. He'll show up under Your robots in a couple of minutes."; status.setTextColor(Look.green) }
                    is Conversion.Outcome.Failed -> { status.text = "⚠ " + result.message; status.setTextColor(Look.red) }
                }
            }
        }
    }

    private fun spaced(top: Int) = LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { topMargin = dp(top) }
}
