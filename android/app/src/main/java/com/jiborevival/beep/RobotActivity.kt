package com.jiborevival.beep

import android.annotation.SuppressLint
import android.app.Activity
import android.app.DownloadManager
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.OvershootInterpolator
import android.webkit.JavascriptInterface
import android.webkit.URLUtil
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.TextView
import android.widget.Toast
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.jiborevival.beep.Look.dp
import com.jiborevival.beep.Look.pad
import com.jiborevival.beep.Look.style
import org.json.JSONObject

/**
 * One robot's BEacon page under native bars, like the iPhone app: the page is restyled in 5x1
 * colours with its own header and tabs hidden (theme.js), and reports its title, tab and toolbar
 * buttons (bridge.js) so the app can draw them.
 */
class RobotActivity : Activity() {
    private class Tab(val panel: String, val title: String, val icon: Int)
    private val main = listOf(
        Tab("status", "Status", R.drawable.ic_info), Tab("screen", "Screen", R.drawable.ic_desktop_windows),
        Tab("photos", "Photos", R.drawable.ic_photo_library), Tab("people", "People", R.drawable.ic_group),
        Tab("store", "Store", R.drawable.ic_storefront)
    )
    // Personal Reports is BETA-only for now (lazy: packageName needs the attached context).
    private val more by lazy {
        (if (packageName.endsWith(".beta")) listOf(Tab("reports", "Reports", R.drawable.ic_article)) else emptyList()) +
            listOf(Tab("server", "Server", R.drawable.ic_dns), Tab("etc", "Settings", R.drawable.ic_settings))
    }

    private lateinit var robot: Robot
    private lateinit var web: WebView
    private lateinit var title: TextView
    private lateinit var actions: LinearLayout
    private lateinit var bar: FrameLayout
    private lateinit var bubble: View
    private val items = mutableListOf<LinearLayout>()
    private var panel = ""
    private var startPanel: String? = null
    private var upload: ValueCallback<Array<Uri>>? = null

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        robot = Robot(intent.getStringExtra("name") ?: "Jibo", intent.getStringExtra("host") ?: "")
        startPanel = intent.getStringExtra("BEepPanel")
        val theme = assets.open("web/theme.js").bufferedReader().readText()
        val bridge = "window.webkit = { messageHandlers: { beep: { postMessage: function (s) { BEepAndroid.state(s); } } } };\n" +
            assets.open("web/bridge.js").bufferedReader().readText()

        web = WebView(this).apply {
            setBackgroundColor(Look.backdrop)
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.mediaPlaybackRequiresUserGesture = false
            addJavascriptInterface(Page(), "BEepAndroid")
        }
        val documentStart = WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)
        if (documentStart) WebViewCompat.addDocumentStartJavaScript(web, theme, setOf("*"))
        web.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView, url: String) {
                if (!url.startsWith(robot.url)) return
                if (!documentStart) view.evaluateJavascript(theme, null)
                view.evaluateJavascript(bridge, null)
            }
            // Links off the robot open in the browser.
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                if (request.url.host == robot.host) return false
                startActivity(Intent(Intent.ACTION_VIEW, request.url)); return true
            }
            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                if (request.isForMainFrame) cantReach()
            }
            // If the page's renderer dies (low memory), Android kills the whole app unless it's
            // handled here: start the robot screen afresh instead.
            override fun onRenderProcessGone(view: WebView, detail: android.webkit.RenderProcessGoneDetail): Boolean {
                if (isFinishing) return true
                (view.parent as? android.view.ViewGroup)?.removeView(view); view.destroy()
                val again = System.currentTimeMillis() - lastRendererCrash < 30_000
                lastRendererCrash = System.currentTimeMillis()
                if (again) { // crashing over and over: don't loop
                    Toast.makeText(this@RobotActivity, "This phone couldn't show BEacon. Try again in a moment.", Toast.LENGTH_LONG).show()
                    finish()
                } else recreate()
                return true
            }
        }
        web.webChromeClient = object : WebChromeClient() {
            override fun onShowFileChooser(view: WebView, callback: ValueCallback<Array<Uri>>, params: FileChooserParams): Boolean {
                upload?.onReceiveValue(null); upload = callback
                try { startActivityForResult(params.createIntent(), 7) } catch (_: Exception) { upload = null; return false }
                return true
            }
        }
        // Downloads (photos, backups) go to the phone's Downloads folder.
        web.setDownloadListener { url, agent, disposition, mime, _ ->
            val name = URLUtil.guessFileName(url, disposition, mime)
            val request = DownloadManager.Request(Uri.parse(url)).addRequestHeader("User-Agent", agent)
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, name)
            (getSystemService(DOWNLOAD_SERVICE) as DownloadManager).enqueue(request)
            Toast.makeText(this, "Saving $name to Downloads", Toast.LENGTH_SHORT).show()
        }

        // Top bar: page title, robot name, BEacon's toolbar buttons.
        title = TextView(this).apply { text = robot.name; maxLines = 1 }.style(17, bold = true) as TextView
        actions = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL }
        val top = LinearLayout(this).apply {
            gravity = Gravity.CENTER_VERTICAL; setBackgroundColor(Color.parseColor("#F2161C18")); pad(this@RobotActivity, 16, 10)
            addView(LinearLayout(this@RobotActivity).apply {
                orientation = LinearLayout.VERTICAL
                addView(title)
                addView(TextView(this@RobotActivity).apply { text = robot.name; maxLines = 1 }.style(12, Look.muted))
            }, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
            addView(actions)
        }

        // Bottom bar: a floating glass pill whose selection bubble slides between tabs.
        bar = FrameLayout(this).apply { background = Look.glass(this@RobotActivity, 999, 0xEE); pad(this@RobotActivity, 5, 5) }
        bubble = View(this).apply { background = Look.pill(this@RobotActivity, Color.argb(0x3D, 41, 215, 128)) }
        bar.addView(bubble, FrameLayout.LayoutParams(0, dp(52)))
        val row = LinearLayout(this)
        (main + Tab("more", "More", R.drawable.ic_more_vert)).forEach { tab ->
            val item = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER; isClickable = true
                addView(ImageView(this@RobotActivity).apply { setImageResource(tab.icon) }, LinearLayout.LayoutParams(dp(22), dp(22)))
                addView(TextView(this@RobotActivity).apply { text = tab.title; gravity = Gravity.CENTER }.style(10))
                setOnClickListener { if (tab.panel == "more") showMore(this) else show(tab.panel) }
            }
            items += item
            row.addView(item, LinearLayout.LayoutParams(0, dp(52), 1f))
        }
        bar.addView(row, FrameLayout.LayoutParams(MATCH_PARENT, dp(52)))
        bar.visibility = View.INVISIBLE

        val page = FrameLayout(this).apply {
            addView(web, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
            addView(bar, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT, Gravity.BOTTOM).apply {
                leftMargin = dp(14); rightMargin = dp(14); bottomMargin = dp(10)
            })
        }
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; setBackgroundColor(Look.backdrop)
            addView(top, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            addView(page, LinearLayout.LayoutParams(MATCH_PARENT, 0, 1f))
        }
        root.setOnApplyWindowInsetsListener { _, insets ->
            @Suppress("DEPRECATION") run {
                top.setPadding(dp(16), insets.systemWindowInsetTop + dp(10), dp(16), dp(10))
                (bar.layoutParams as FrameLayout.LayoutParams).bottomMargin = insets.systemWindowInsetBottom + dp(10)
                bar.requestLayout()
            }
            insets
        }
        bar.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> place(false) }
        setContentView(root)
        web.loadUrl(robot.url)
    }

    private fun show(panel: String) = web.evaluateJavascript("window.__beep && window.__beep.tab(${JSONObject.quote(panel)})", null)

    private fun showMore(anchor: View) {
        val menu = PopupMenu(this, anchor)
        more.forEachIndexed { i, tab -> menu.menu.add(0, i, i, tab.title) }
        menu.setOnMenuItemClickListener { show(more[it.itemId].panel); true }
        menu.show()
    }

    /** Moves the selection bubble to the current tab (More stands for Server and Settings). */
    private fun place(animate: Boolean) {
        val index = main.indexOfFirst { it.panel == panel }.let { if (it < 0 && more.any { m -> m.panel == panel }) main.size else it }
        items.forEachIndexed { i, item ->
            val color = if (i == index) Look.green else Look.text
            (item.getChildAt(0) as ImageView).setColorFilter(color)
            (item.getChildAt(1) as TextView).setTextColor(color)
        }
        if (index < 0 || items.isEmpty() || items[0].width == 0) { bubble.visibility = View.INVISIBLE; return }
        bubble.visibility = View.VISIBLE
        val width = items[0].width
        if (bubble.layoutParams.width != width) { bubble.layoutParams.width = width; bubble.requestLayout() }
        val x = (width * index).toFloat()
        if (animate) bubble.animate().translationX(x).setInterpolator(OvershootInterpolator(1.2f)).setDuration(320).start()
        else bubble.translationX = x
    }

    private fun cantReach() {
        title.text = robot.name; actions.removeAllViews(); bar.visibility = View.INVISIBLE
        val page = """
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <body style="font-family: sans-serif; text-align: center; padding: 120px 24px; color: #b0bbb2; background: #111513">
            <h3 style="color: #eef1ec">Can't reach ${robot.name}</h3>
            <p>Make sure Jibo is on and your phone is on the same Wi-Fi.</p>
            <p><a href="${robot.url}" style="color: #29d780; font-weight: bold">Try again</a></p></body>
        """.trimIndent()
        web.loadDataWithBaseURL(null, page, "text/html", "utf-8", null)
    }

    /** bridge.js reports {title, panel, actions} whenever BEacon's header or tab changes. */
    private inner class Page {
        @JavascriptInterface
        fun state(json: String) = runOnUiThread {
            val state = try { JSONObject(json) } catch (_: Exception) { return@runOnUiThread }
            title.text = state.optString("title").ifEmpty { robot.name }
            val previous = panel
            panel = state.optString("panel")
            actions.removeAllViews()
            val list = state.optJSONArray("actions")
            for (i in 0 until (list?.length() ?: 0)) {
                val action = list!!.getJSONObject(i)
                actions.addView(TextView(this@RobotActivity).apply {
                    text = action.optString("label"); isEnabled = !action.optBoolean("disabled"); alpha = if (isEnabled) 1f else 0.4f
                    pad(this@RobotActivity, 10, 8)
                    setOnClickListener { web.evaluateJavascript("window.__beep && window.__beep.act(${JSONObject.quote(action.optString("action"))})", null) }
                }.style(15, Look.green, bold = true))
            }
            if (bar.visibility != View.VISIBLE) {
                bar.visibility = View.VISIBLE
                startPanel?.let { show(it); startPanel = null } // emulator check
            }
            place(previous.isNotEmpty())
        }
    }

    @Deprecated("Activity result for the page's file picker")
    override fun onActivityResult(request: Int, result: Int, data: Intent?) {
        if (request == 7) { upload?.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(result, data)); upload = null }
        else super.onActivityResult(request, result, data)
    }

    companion object { private var lastRendererCrash = 0L }

    override fun onDestroy() { if (web.parent != null) web.destroy(); super.onDestroy() }
}
