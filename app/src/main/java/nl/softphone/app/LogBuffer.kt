package nl.softphone.app

import android.os.Handler
import android.os.Looper
import org.linphone.core.Factory
import org.linphone.core.LogLevel
import org.linphone.core.LoggingService
import org.linphone.core.LoggingServiceListenerStub
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** In-app logboek: Linphone/SIP-logs plus eigen gebeurtenissen, voor het scherm Logboek. */
object LogBuffer {

    class Entry(val time: String, val level: LogLevel, val source: String, val text: String) {
        override fun toString() = "$time ${levelChar()} [$source] $text"
        private fun levelChar() = when (level) {
            LogLevel.Error, LogLevel.Fatal -> "E"
            LogLevel.Warning -> "W"
            LogLevel.Debug, LogLevel.Trace -> "D"
            else -> "I"
        }
    }

    private const val MAX = 4000
    private val entries = ArrayDeque<Entry>()
    private val fmt = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)
    private val main = Handler(Looper.getMainLooper())
    private val observers = mutableListOf<() -> Unit>()
    private var notifyPending = false

    /** Koppelt de Linphone-logging aan dit logboek. Aanroepen vóór het aanmaken van de core. */
    fun attachLinphone() {
        val ls = Factory.instance().loggingService
        ls.setLogLevel(LogLevel.Message)
        ls.addListener(object : LoggingServiceListenerStub() {
            override fun onLogMessageWritten(
                logService: LoggingService, domain: String, level: LogLevel, message: String
            ) {
                add(level, domain.ifBlank { "core" }, message)
            }
        })
    }

    fun app(text: String) = add(LogLevel.Message, "APP", text)
    fun appError(text: String) = add(LogLevel.Error, "APP", text)

    private fun add(level: LogLevel, source: String, text: String) {
        val e = Entry(fmt.format(Date()), level, source, text.trimEnd())
        synchronized(entries) {
            entries.addLast(e)
            while (entries.size > MAX) entries.removeFirst()
        }
        scheduleNotify()
    }

    fun snapshot(): List<Entry> = synchronized(entries) { entries.toList() }

    fun clear() {
        synchronized(entries) { entries.clear() }
        scheduleNotify()
    }

    fun observe(o: () -> Unit) { observers += o }
    fun unobserve(o: () -> Unit) { observers -= o }

    // UI hoogstens 3x per seconde verversen, logs komen in salvo's.
    private fun scheduleNotify() {
        synchronized(this) {
            if (notifyPending) return
            notifyPending = true
        }
        main.postDelayed({
            synchronized(this) { notifyPending = false }
            observers.toList().forEach { it() }
        }, 300)
    }

    private val relevant = Regex(
        "register|sip/2\\.0|registration|account|auth|dns|resolv|srv|channel|connect|socket|tls|ssl|" +
            "certificate|transport|refused|unreachable|timeout|timed out|io error|network",
        RegexOption.IGNORE_CASE
    )

    /** Filter voor "alleen aanmelden": eigen meldingen, fouten/waarschuwingen en SIP/netwerk-regels. */
    fun isRelevant(e: Entry) =
        e.source == "APP" || e.level == LogLevel.Error || e.level == LogLevel.Warning ||
            e.level == LogLevel.Fatal || relevant.containsMatchIn(e.text)
}
