package nl.softphone.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.Person
import org.linphone.core.Call

object Notifs {
    private const val CH_SERVICE = "service"
    private const val CH_INCOMING = "incoming"
    private const val CH_MISSED = "missed"
    const val ID_SERVICE = 1
    private const val ID_INCOMING = 2
    private const val ID_MISSED = 3
    private const val FLAGS = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT

    private fun nm(ctx: Context) = ctx.getSystemService(NotificationManager::class.java)

    fun createChannels(ctx: Context) {
        nm(ctx).createNotificationChannels(
            listOf(
                NotificationChannel(CH_SERVICE, ctx.getString(R.string.ch_service), NotificationManager.IMPORTANCE_LOW)
                    .apply { setShowBadge(false) },
                // Geen kanaalgeluid: de Linphone-core speelt de beltoon zelf af.
                NotificationChannel(CH_INCOMING, ctx.getString(R.string.ch_incoming), NotificationManager.IMPORTANCE_HIGH)
                    .apply {
                        setSound(null, null)
                        lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    },
                NotificationChannel(CH_MISSED, ctx.getString(R.string.ch_missed), NotificationManager.IMPORTANCE_DEFAULT),
            )
        )
    }

    private fun mainIntent(ctx: Context) = PendingIntent.getActivity(
        ctx, 10, Intent(ctx, MainActivity::class.java), FLAGS
    )

    fun service(ctx: Context, text: String): Notification =
        NotificationCompat.Builder(ctx, CH_SERVICE)
            .setSmallIcon(R.drawable.ic_stat_phone)
            .setContentTitle(ctx.getString(R.string.app_name))
            .setContentText(text)
            .setOngoing(true)
            .setContentIntent(mainIntent(ctx))
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()

    fun showIncoming(ctx: Context, call: Call) {
        val name = Sip.label(call.remoteAddress)
        val fullScreen = PendingIntent.getActivity(
            ctx, 0, Intent(ctx, CallActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK), FLAGS
        )
        val answer = PendingIntent.getActivity(
            ctx, 1,
            Intent(ctx, CallActivity::class.java)
                .putExtra(CallActivity.EXTRA_ANSWER, true)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            FLAGS
        )
        val decline = PendingIntent.getBroadcast(
            ctx, 2,
            Intent(ctx, CallActionReceiver::class.java).setAction(CallActionReceiver.ACTION_DECLINE),
            FLAGS
        )
        val caller = Person.Builder().setName(name).setImportant(true).build()
        val n = NotificationCompat.Builder(ctx, CH_INCOMING)
            .setSmallIcon(R.drawable.ic_stat_phone)
            .setContentTitle(name)
            .setContentText(ctx.getString(R.string.incoming_call))
            .setStyle(NotificationCompat.CallStyle.forIncomingCall(caller, decline, answer))
            .setFullScreenIntent(fullScreen, true)
            .setContentIntent(fullScreen)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setOngoing(true)
            .build()
        nm(ctx).notify(ID_INCOMING, n)
    }

    fun cancelIncoming(ctx: Context) = nm(ctx).cancel(ID_INCOMING)

    fun showMissed(ctx: Context, call: Call) {
        cancelIncoming(ctx)
        val n = NotificationCompat.Builder(ctx, CH_MISSED)
            .setSmallIcon(R.drawable.ic_stat_phone)
            .setContentTitle(ctx.getString(R.string.missed_call))
            .setContentText(Sip.label(call.remoteAddress))
            .setContentIntent(mainIntent(ctx))
            .setAutoCancel(true)
            .build()
        nm(ctx).notify(ID_MISSED, n)
    }
}
