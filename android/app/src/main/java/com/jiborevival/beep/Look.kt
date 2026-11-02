package com.jiborevival.beep

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.view.View
import android.widget.TextView

/** 5x1 colours (5x1.com) and BEep's glass surfaces, shared by every screen. */
object Look {
    val backdrop = Color.parseColor("#111513")
    val green = Color.parseColor("#29D780")
    val onGreen = Color.parseColor("#0D2015")
    val text = Color.parseColor("#EEF1EC")
    val muted = Color.parseColor("#B0BBB2")
    val red = Color.parseColor("#FF8A80")

    fun Context.dp(value: Number) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value.toFloat(), resources.displayMetrics).toInt()

    /** Translucent green-grey with a light edge: Android's take on the iPhone app's Liquid Glass. */
    fun glass(context: Context, radius: Number, alpha: Int = 0xD9) = GradientDrawable().apply {
        cornerRadius = context.dp(radius).toFloat()
        setColor(Color.argb(alpha, 30, 44, 35))
        setStroke(context.dp(1), Color.argb(0x1F, 255, 255, 255))
    }

    fun pill(context: Context, color: Int) = GradientDrawable().apply { cornerRadius = context.dp(999).toFloat(); setColor(color) }

    fun TextView.style(size: Number, color: Int = Look.text, bold: Boolean = false): TextView {
        setTextSize(TypedValue.COMPLEX_UNIT_SP, size.toFloat())
        setTextColor(color)
        typeface = if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
        return this
    }

    fun View.pad(context: Context, horizontal: Number, vertical: Number) =
        setPadding(context.dp(horizontal), context.dp(vertical), context.dp(horizontal), context.dp(vertical))
}
