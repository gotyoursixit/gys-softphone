package nl.softphone.app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

data class Contact(val name: String, val number: String)

/** Eenvoudige lokale toestellenlijst, opgeslagen als JSON. */
object Contacts {
    private fun sp(ctx: Context) = ctx.getSharedPreferences("contacts", Context.MODE_PRIVATE)

    fun all(ctx: Context): List<Contact> {
        val arr = JSONArray(sp(ctx).getString("list", "[]"))
        return (0 until arr.length()).map {
            val o = arr.getJSONObject(it)
            Contact(o.getString("name"), o.getString("number"))
        }.sortedBy { it.name.lowercase() }
    }

    fun save(ctx: Context, list: List<Contact>) {
        val arr = JSONArray()
        list.forEach { arr.put(JSONObject().put("name", it.name).put("number", it.number)) }
        sp(ctx).edit().putString("list", arr.toString()).apply()
    }

    fun upsert(ctx: Context, old: Contact?, new: Contact) =
        save(ctx, all(ctx).filter { it != old } + new)

    fun remove(ctx: Context, c: Contact) = save(ctx, all(ctx).filter { it != c })

    fun nameFor(ctx: Context, number: String?): String? =
        number?.let { n -> all(ctx).firstOrNull { it.number == n }?.name }
}
