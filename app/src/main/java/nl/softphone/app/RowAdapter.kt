package nl.softphone.app

import android.content.Context
import android.content.res.ColorStateList
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.BaseAdapter
import android.widget.TextView
import androidx.annotation.AttrRes

/** Kleurstelling van de ronde avatar: zachte achtergrond met sterke letterkleur. */
enum class Tone(@AttrRes val bg: Int, @AttrRes val fg: Int) {
    ACCENT(R.attr.appAccentSoft, R.attr.appAccentDark),
    NEUTRAL(R.attr.appNeutralSoft, R.attr.appInkSoft),
    DANGER(R.attr.appDangerSoft, R.attr.appDanger),
}

data class Row(val title: String, val sub: String, val tone: Tone = Tone.ACCENT, val meta: String = "")

/** Initialen voor de avatar: "Jan de Vries" → "JV", "201" → "201". */
fun initials(name: String): String {
    val t = name.trim()
    if (t.isEmpty()) return "?"
    if (t.all { it.isDigit() || it == '+' }) return t.takeLast(3)
    val words = t.split(Regex("\\s+")).filter { it.first().isLetterOrDigit() }
    return when {
        words.size >= 2 -> "${words.first().first()}${words.last().first()}"
        else -> t.take(2)
    }.uppercase()
}

class RowAdapter(private val ctx: Context, private val rows: List<Row>) : BaseAdapter() {
    override fun getCount() = rows.size
    override fun getItem(position: Int) = rows[position]
    override fun getItemId(position: Int) = position.toLong()

    override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
        val v = convertView ?: LayoutInflater.from(ctx).inflate(R.layout.item_row, parent, false)
        val r = rows[position]
        v.findViewById<TextView>(R.id.rowAvatar).apply {
            text = initials(r.title)
            backgroundTintList = ColorStateList.valueOf(ctx.themeColor(r.tone.bg))
            setTextColor(ctx.themeColor(r.tone.fg))
        }
        v.findViewById<TextView>(R.id.rowTitle).text = r.title
        v.findViewById<TextView>(R.id.rowSub).apply {
            text = r.sub
            setTextColor(ctx.themeColor(if (r.tone == Tone.DANGER) R.attr.appDanger else R.attr.appMuted))
        }
        v.findViewById<TextView>(R.id.rowMeta).text = r.meta
        return v
    }
}
