package nl.softphone.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.linphone.core.Call
import org.linphone.core.Reason

/** Start de service na een herstart van de telefoon of een app-update. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // Application.onCreate start de service al; deze receiver zorgt dat het proces opstart.
        PhoneService.start(context)
    }
}

/** Knop "Weigeren" in de melding van een inkomend gesprek. */
class CallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_DECLINE) {
            Sip.core.calls.firstOrNull { it.state == Call.State.IncomingReceived }?.decline(Reason.Declined)
            Notifs.cancelIncoming(context)
        }
    }

    companion object {
        const val ACTION_DECLINE = "nl.softphone.app.DECLINE"
    }
}
