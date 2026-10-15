package nl.softphone.app

import android.Manifest
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.content.ContextCompat

/**
 * Foreground service die het proces (en dus de SIP-registratie) in leven houdt,
 * zodat gesprekken binnenkomen terwijl de app gesloten is.
 */
class PhoneService : Service() {

    private var inCall = false

    override fun onCreate() {
        super.onCreate()
        instance = this
        Sip.init(this)
        goForeground()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        goForeground()
        return START_STICKY
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun text() = if (inCall) getString(R.string.in_call) else Sip.statusText()

    private fun goForeground() {
        val n = Notifs.service(this, text())
        if (Build.VERSION.SDK_INT >= 34) {
            val micOk = ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED
            val base = ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            try {
                startForeground(
                    Notifs.ID_SERVICE, n,
                    if (inCall && micOk) base or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE else base
                )
            } catch (e: SecurityException) {
                // Microfoontype mag alleen vanuit de voorgrond; val terug op het basistype.
                startForeground(Notifs.ID_SERVICE, n, base)
            }
        } else {
            startForeground(Notifs.ID_SERVICE, n)
        }
    }

    private fun update() {
        getSystemService(NotificationManager::class.java).notify(Notifs.ID_SERVICE, Notifs.service(this, text()))
    }

    companion object {
        private var instance: PhoneService? = null

        fun start(ctx: Context) {
            if (!Prefs(ctx).isConfigured) return
            try {
                ContextCompat.startForegroundService(ctx, Intent(ctx, PhoneService::class.java))
            } catch (e: Exception) {
                // Starten vanuit de achtergrond kan geweigerd worden; volgende app-start probeert opnieuw.
            }
        }

        fun refresh() { instance?.update() }

        fun setInCall(value: Boolean) {
            val s = instance ?: return
            if (s.inCall == value) return
            s.inCall = value
            s.goForeground()
        }
    }
}
