package nl.softphone.app

import android.content.res.ColorStateList
import android.widget.GridLayout
import androidx.annotation.AttrRes
import androidx.core.graphics.ColorUtils
import com.google.android.material.button.MaterialButton

object Dialpad {
    private const val KEYS = "123456789*0#"

    /** Vult [grid] met 12 toetsen; lang drukken op 0 geeft '+'. */
    fun build(
        grid: GridLayout,
        @AttrRes keyColor: Int = R.attr.appBgAlt,
        @AttrRes textColor: Int = R.attr.appInk,
        onKey: (Char) -> Unit,
    ) {
        val ctx = grid.context
        val dp = ctx.resources.displayMetrics.density
        val ripple = ColorUtils.setAlphaComponent(ctx.themeColor(R.attr.appAccent), 70)
        val font = ctx.themeFont(R.attr.appFontMedium)
        val margin = (5 * dp).toInt()

        grid.removeAllViews()
        grid.columnCount = 3
        for (k in KEYS) {
            val b = MaterialButton(ctx)
            b.text = k.toString()
            b.textSize = 26f
            b.typeface = font
            b.setTextColor(ctx.themeColor(textColor))
            b.backgroundTintList = ColorStateList.valueOf(ctx.themeColor(keyColor))
            b.rippleColor = ColorStateList.valueOf(ripple)
            b.cornerRadius = ctx.themeDimen(R.attr.appKeyCorner, (14 * dp).toInt())
            b.layoutParams = GridLayout.LayoutParams(
                GridLayout.spec(GridLayout.UNDEFINED, 1f),
                GridLayout.spec(GridLayout.UNDEFINED, 1f)
            ).apply {
                width = 0
                height = (60 * dp).toInt()
                setMargins(margin, margin, margin, margin)
            }
            b.setOnClickListener { onKey(k) }
            if (k == '0') b.setOnLongClickListener { onKey('+'); true }
            grid.addView(b)
        }
    }
}
