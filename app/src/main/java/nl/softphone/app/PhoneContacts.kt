package nl.softphone.app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.ContactsContract
import android.provider.ContactsContract.CommonDataKinds.Phone
import androidx.core.content.ContextCompat

/** Een nummer uit het telefoonboek van de telefoon. */
data class PhoneContact(val name: String, val number: String, val type: String)

/** Leest de contacten van de telefoon (alleen met toestemming READ_CONTACTS). */
object PhoneContacts {
    private val nameCache = HashMap<String, String?>()

    fun hasPermission(ctx: Context) =
        ContextCompat.checkSelfPermission(ctx, Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED

    /** Alle telefoonnummers, op naam gesorteerd; een contact met twee nummers geeft twee regels. */
    fun all(ctx: Context): List<PhoneContact> {
        if (!hasPermission(ctx)) return emptyList()
        val out = ArrayList<PhoneContact>()
        val seen = HashSet<String>()
        ctx.contentResolver.query(
            Phone.CONTENT_URI,
            arrayOf(Phone.DISPLAY_NAME_PRIMARY, Phone.NUMBER, Phone.TYPE, Phone.LABEL),
            null, null,
            "${Phone.DISPLAY_NAME_PRIMARY} COLLATE NOCASE ASC",
        )?.use { c ->
            while (c.moveToNext()) {
                val name = c.getString(0) ?: continue
                val number = c.getString(1)?.let(::dialable) ?: continue
                if (!seen.add("$name|$number")) continue // dubbele invoer (bijv. WhatsApp-koppeling) overslaan
                val type = Phone.getTypeLabel(ctx.resources, c.getInt(2), c.getString(3)).toString()
                out += PhoneContact(name, number, type)
            }
        }
        return out
    }

    /** Naam bij een nummer, of null. Snel genoeg voor het belscherm; resultaten worden onthouden. */
    fun nameFor(ctx: Context, number: String?): String? {
        if (number.isNullOrBlank() || !hasPermission(ctx)) return null
        val key = dialable(number)
        if (key.length < 3) return null // korte interne toestelnummers niet opzoeken
        synchronized(nameCache) { if (nameCache.containsKey(key)) return nameCache[key] }
        val name = try {
            ctx.contentResolver.query(
                Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(key)),
                arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME), null, null, null,
            )?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
        } catch (e: Exception) {
            null
        }
        synchronized(nameCache) { nameCache[key] = name }
        return name
    }

    fun clearCache() = synchronized(nameCache) { nameCache.clear() }

    /** "06 - 1234 5678" → "0612345678"; een + aan het begin blijft staan. */
    fun dialable(n: String): String {
        val t = n.trim()
        val digits = t.filter { it.isDigit() || it == '*' || it == '#' }
        return if (t.startsWith("+")) "+$digits" else digits
    }
}
