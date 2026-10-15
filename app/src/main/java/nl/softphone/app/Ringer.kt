package nl.softphone.app

import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings

/**
 * Beltoon en trillen bij een inkomend gesprek, volgens de instellingen van de telefoon:
 * geluidsmodus (normaal / trillen / stil), "trillen bij bellen" en Niet storen.
 */
object Ringer {
    private var ringtone: Ringtone? = null
    private var vibrator: Vibrator? = null
    private var active = false

    private val ringAttributes: AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()

    /** [callWaiting]: er loopt al een gesprek, dan alleen een korte tril in plaats van de beltoon. */
    fun start(ctx: Context, callWaiting: Boolean) {
        if (active) return
        active = true
        val mode = ctx.getSystemService(AudioManager::class.java).ringerMode
        val vib = vibratorOf(ctx)

        if (callWaiting) {
            vib.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 200, 150, 200), -1))
            LogBuffer.app("Wisselgesprek: korte tril")
            return
        }
        if (!callsAllowedByDnd(ctx)) {
            LogBuffer.app("Inkomend gesprek: Niet storen staat aan, geen beltoon")
            return
        }

        if (mode == AudioManager.RINGER_MODE_NORMAL) {
            val uri = RingtoneManager.getActualDefaultRingtoneUri(ctx, RingtoneManager.TYPE_RINGTONE)
                ?: Settings.System.DEFAULT_RINGTONE_URI
            ringtone = RingtoneManager.getRingtone(ctx, uri)?.apply {
                audioAttributes = ringAttributes
                if (Build.VERSION.SDK_INT >= 28) isLooping = true
                play()
            }
        }
        val shake = mode != AudioManager.RINGER_MODE_SILENT && shouldVibrate(ctx, mode)
        if (shake) {
            vibrator = vib
            val pattern = VibrationEffect.createWaveform(longArrayOf(0, 800, 800), 0)
            if (Build.VERSION.SDK_INT >= 33) {
                vib.vibrate(pattern, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_RINGTONE))
            } else {
                @Suppress("DEPRECATION")
                vib.vibrate(pattern, ringAttributes)
            }
        }
        LogBuffer.app("Beltoon gestart (geluid: ${ringtone != null}, trillen: $shake)")
    }

    fun stop() {
        if (!active) return
        active = false
        ringtone?.stop()
        ringtone = null
        vibrator?.cancel()
        vibrator = null
    }

    private fun shouldVibrate(ctx: Context, mode: Int): Boolean = when {
        mode == AudioManager.RINGER_MODE_VIBRATE -> true
        // Vanaf Android 13 past het systeem zelf de trilinstelling voor beltonen toe (USAGE_RINGTONE).
        Build.VERSION.SDK_INT >= 33 -> true
        else -> @Suppress("DEPRECATION")
            Settings.System.getInt(ctx.contentResolver, Settings.System.VIBRATE_WHEN_RINGING, 0) == 1
    }

    /** Niet storen: alleen bellen als oproepen van iedereen zijn toegestaan (bij twijfel stil). */
    private fun callsAllowedByDnd(ctx: Context): Boolean {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        return when (nm.currentInterruptionFilter) {
            NotificationManager.INTERRUPTION_FILTER_ALL, NotificationManager.INTERRUPTION_FILTER_UNKNOWN -> true
            NotificationManager.INTERRUPTION_FILTER_PRIORITY -> try {
                val p = nm.notificationPolicy
                (p.priorityCategories and NotificationManager.Policy.PRIORITY_CATEGORY_CALLS) != 0 &&
                    p.priorityCallSenders == NotificationManager.Policy.PRIORITY_SENDERS_ANY
            } catch (e: SecurityException) {
                false
            }
            else -> false
        }
    }

    private fun vibratorOf(ctx: Context): Vibrator =
        if (Build.VERSION.SDK_INT >= 31) ctx.getSystemService(VibratorManager::class.java).defaultVibrator
        else @Suppress("DEPRECATION") ctx.getSystemService(Vibrator::class.java)
}
