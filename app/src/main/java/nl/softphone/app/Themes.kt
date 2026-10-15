package nl.softphone.app

import android.app.Activity
import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.util.TypedValue
import androidx.annotation.AttrRes
import androidx.annotation.ColorInt
import androidx.annotation.StringRes
import androidx.annotation.StyleRes
import androidx.core.content.res.ResourcesCompat
import com.google.android.material.color.MaterialColors

/** De drie thema's; [key] wordt bewaard in de instellingen. */
enum class AppTheme(
    val key: String,
    @StringRes val label: Int,
    @StyleRes val normal: Int,
    @StyleRes val noActionBar: Int,
    @StyleRes val call: Int,
) {
    GYS("gys", R.string.theme_gys, R.style.Theme_Softphone, R.style.Theme_Softphone_NoActionBar, R.style.Theme_Softphone_Call),
    LCARS("lcars", R.string.theme_lcars, R.style.Theme_Lcars, R.style.Theme_Lcars_NoActionBar, R.style.Theme_Lcars_Call),
    STAR_WARS("starwars", R.string.theme_starwars, R.style.Theme_StarWars, R.style.Theme_StarWars_NoActionBar, R.style.Theme_StarWars_Call),
}

object Themes {
    enum class Kind { NORMAL, NO_ACTION_BAR, CALL }

    fun current(ctx: Context): AppTheme =
        AppTheme.entries.firstOrNull { it.key == Prefs(ctx).theme } ?: AppTheme.GYS

    /** Aanroepen in onCreate vóór super.onCreate; geeft het toegepaste thema terug. */
    fun apply(activity: Activity, kind: Kind): AppTheme {
        val t = current(activity)
        activity.setTheme(
            when (kind) {
                Kind.NORMAL -> t.normal
                Kind.NO_ACTION_BAR -> t.noActionBar
                Kind.CALL -> t.call
            }
        )
        return t
    }
}

/** Kleur uit het actieve thema (thema-variabele uit attrs.xml). */
@ColorInt
fun Context.themeColor(@AttrRes attr: Int): Int = MaterialColors.getColor(this, attr, Color.MAGENTA)

fun Context.themeFont(@AttrRes attr: Int): Typeface? {
    val tv = TypedValue()
    return if (theme.resolveAttribute(attr, tv, true) && tv.resourceId != 0) ResourcesCompat.getFont(this, tv.resourceId) else null
}

fun Context.themeDimen(@AttrRes attr: Int, fallbackPx: Int): Int {
    val tv = TypedValue()
    return if (theme.resolveAttribute(attr, tv, true)) TypedValue.complexToDimensionPixelSize(tv.data, resources.displayMetrics) else fallbackPx
}
