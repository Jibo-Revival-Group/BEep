package com.jiborevival.beep

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.inputmethod.EditorInfo
import android.widget.Button
import android.widget.EditText
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import com.jiborevival.beep.Look.dp
import com.jiborevival.beep.Look.pad
import com.jiborevival.beep.Look.style

/** Your robots, add one by IP, or convert a modded Jibo. With one robot, opens it straight away. */
class MainActivity : Activity() {
    private lateinit var finder: RobotFinder
    private lateinit var list: LinearLayout
    private lateinit var address: EditText
    private lateinit var hint: TextView
    // The emulator check sets this to photograph the home screen.
    private var opened = false

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        opened = intent.getBooleanExtra("BEepStayHome", false)
        finder = RobotFinder(this) { show(it) }

        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            pad(this@MainActivity, 20, 12)
        }
        val logo = ImageView(this).apply { setImageResource(R.drawable.logo) }
        column.addView(logo, LinearLayout.LayoutParams(MATCH_PARENT, dp(84)).apply { topMargin = dp(8) })
        column.addView(TextView(this).apply { text = "BEep"; gravity = Gravity.CENTER }.style(32, bold = true))
        column.addView(TextView(this).apply { text = "Your Jibo, in your pocket."; gravity = Gravity.CENTER }.style(15, Look.muted))

        column.addView(header("Your robots"))
        list = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        column.addView(list)

        column.addView(header("Add by IP address"))
        val row = LinearLayout(this).apply {
            gravity = Gravity.CENTER_VERTICAL
            background = Look.glass(this@MainActivity, 999)
            pad(this@MainActivity, 14, 6)
        }
        address = EditText(this).apply {
            hint = "192.168.1.20"; setHintTextColor(0x66FFFFFF); background = null
            inputType = InputType.TYPE_CLASS_PHONE; imeOptions = EditorInfo.IME_ACTION_DONE
            setOnEditorActionListener { _, _, _ -> add(); true }
        }.style(16) as EditText
        row.addView(address, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
        row.addView(greenButton("Add") { add() })
        column.addView(row)
        hint = TextView(this).apply { text = "Jibo's IP address is in Settings › Wi-Fi on his screen." }.style(13, Look.muted)
        column.addView(hint, spaced(6).apply { leftMargin = dp(6); rightMargin = dp(6) })

        column.addView(header("New to 5x1?"))
        column.addView(card("Convert a Jibo to 5x1", "For a modded Jibo: installs 5x1 over SSH.") {
            startActivity(Intent(this, ConvertActivity::class.java))
        })

        column.addView(TextView(this).apply {
            text = "Made by 5x1 · 5x1.com"; gravity = Gravity.CENTER
            setOnClickListener { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://5x1.com"))) }
        }.style(13, Look.muted), spaced(20))

        val scroll = ScrollView(this).apply { addView(column); isFillViewport = true; overScrollMode = View.OVER_SCROLL_IF_CONTENT_SCROLLS }
        scroll.setOnApplyWindowInsetsListener { view, insets ->
            @Suppress("DEPRECATION") view.setPadding(0, insets.systemWindowInsetTop, 0, insets.systemWindowInsetBottom); insets
        }
        setContentView(scroll)
        show(finder.robots)

        // The emulator check opens a robot or the converter straight away.
        intent.getStringExtra("BEepOpen")?.let { host -> finder.check(host) { it?.let(::open) } }
        if (intent.hasExtra("BEepConvert")) startActivity(Intent(this, ConvertActivity::class.java).putExtras(intent))
    }

    override fun onStart() { super.onStart(); finder.start() }
    override fun onStop() { finder.stop(); super.onStop() }

    private fun show(robots: List<Robot>) {
        list.removeAllViews()
        robots.forEach { robot ->
            val item = card(robot.name, robot.host) { open(robot) }
            item.setOnLongClickListener {
                AlertDialog.Builder(this).setMessage("Forget ${robot.name}?")
                    .setPositiveButton("Forget") { _, _ -> finder.forget(robot) }
                    .setNegativeButton("Cancel", null).show()
                true
            }
            list.addView(item, spaced(8))
        }
        if (robots.isEmpty()) {
            val waiting = LinearLayout(this).apply {
                gravity = Gravity.CENTER_VERTICAL; background = Look.glass(this@MainActivity, 24); pad(this@MainActivity, 16, 16)
                addView(ProgressBar(this@MainActivity), LinearLayout.LayoutParams(dp(22), dp(22)))
                addView(TextView(this@MainActivity).apply { text = "Looking for Jibo on this Wi-Fi…" }.style(15, Look.muted),
                    LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply { leftMargin = dp(12) })
            }
            list.addView(waiting, spaced(8))
        }
        // With one robot, skip this screen and open BEacon straight away (once per launch).
        if (!opened && robots.size == 1) { opened = true; open(robots[0]) }
    }

    private fun open(robot: Robot) {
        opened = true
        startActivity(Intent(this, RobotActivity::class.java).putExtra("name", robot.name).putExtra("host", robot.host)
            .putExtra("BEepPanel", intent.getStringExtra("BEepPanel")))
    }

    private fun add() {
        val host = address.text.toString().trim()
        if (host.isEmpty()) return
        hint.text = "Checking $host…"; hint.setTextColor(Look.muted)
        finder.check(host) { robot ->
            if (robot != null) { address.setText(""); hint.text = "Jibo's IP address is in Settings › Wi-Fi on his screen."; open(robot) }
            else { hint.text = "No Jibo with BEacon answered at $host. Check the address and that your phone is on the same Wi-Fi."; hint.setTextColor(Look.red) }
        }
    }

    private fun header(title: String) = TextView(this).apply { text = title }.style(17, bold = true)
        .also { it.layoutParams = spaced(18).apply { leftMargin = dp(4); bottomMargin = dp(8) } }

    private fun card(title: String, subtitle: String, tap: () -> Unit) = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
        background = Look.glass(this@MainActivity, 24); pad(this@MainActivity, 16, 14)
        isClickable = true; setOnClickListener { tap() }
        addView(ImageView(this@MainActivity).apply { setImageResource(R.drawable.logo) }, LinearLayout.LayoutParams(dp(34), dp(34)))
        val text = LinearLayout(this@MainActivity).apply {
            orientation = LinearLayout.VERTICAL
            addView(TextView(this@MainActivity).apply { this.text = title; maxLines = 1 }.style(16, bold = true))
            addView(TextView(this@MainActivity).apply { this.text = subtitle }.style(12, Look.muted))
        }
        addView(text, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f).apply { leftMargin = dp(14) })
        addView(TextView(this@MainActivity).apply { this.text = "›" }.style(24, Look.muted))
    }

    private fun greenButton(label: String, tap: () -> Unit) = Button(this).apply {
        text = label; isAllCaps = false; setTextColor(Look.onGreen); background = Look.pill(this@MainActivity, Look.green)
        minHeight = dp(40); minimumHeight = dp(40); pad(this@MainActivity, 18, 0); setOnClickListener { tap() }
    }

    private fun spaced(top: Int) = LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { topMargin = dp(top) }
}
