package nl.softphone.app

import android.content.Context

/** Accountinstellingen voor de Asterisk-centrale. */
class Prefs(context: Context) {
    private val sp = context.getSharedPreferences("account", Context.MODE_PRIVATE)

    var server: String
        get() = sp.getString("server", "")!!
        set(v) = sp.edit().putString("server", v.trim()).apply()
    var port: String
        get() = sp.getString("port", "")!!
        set(v) = sp.edit().putString("port", v.trim()).apply()
    /** Optioneel: SIP-domein als dat afwijkt van het serveradres. */
    var domain: String
        get() = sp.getString("domain", "")!!
        set(v) = sp.edit().putString("domain", v.trim()).apply()
    var transport: String
        get() = sp.getString("transport", "UDP")!!
        set(v) = sp.edit().putString("transport", v).apply()
    var username: String
        get() = sp.getString("username", "")!!
        set(v) = sp.edit().putString("username", v.trim()).apply()
    var authId: String
        get() = sp.getString("authId", "")!!
        set(v) = sp.edit().putString("authId", v.trim()).apply()
    var password: String
        get() = sp.getString("password", "")!!
        set(v) = sp.edit().putString("password", v).apply()
    var displayName: String
        get() = sp.getString("displayName", "")!!
        set(v) = sp.edit().putString("displayName", v.trim()).apply()
    var stun: String
        get() = sp.getString("stun", "")!!
        set(v) = sp.edit().putString("stun", v.trim()).apply()
    /** Gekozen thema: "gys", "lcars" of "starwars" (zie AppTheme). */
    var theme: String
        get() = sp.getString("theme", "gys")!!
        set(v) = sp.edit().putString("theme", v).apply()
    var srtp: Boolean
        get() = sp.getBoolean("srtp", false)
        set(v) = sp.edit().putBoolean("srtp", v).apply()

    val sipDomain: String get() = domain.ifBlank { server }
    val isConfigured: Boolean get() = server.isNotBlank() && username.isNotBlank()
}
