package nl.softphone.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.format.DateUtils
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.EditText
import android.widget.GridLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.annotation.AttrRes
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.button.MaterialButton
import org.linphone.core.Call
import org.linphone.core.Core
import org.linphone.core.CoreListenerStub
import org.linphone.core.Reason

class CallActivity : AppCompatActivity() {

    private lateinit var appliedTheme: AppTheme

    private lateinit var name: TextView
    private lateinit var sub: TextView
    private lateinit var timer: TextView
    private lateinit var state: TextView
    private lateinit var avatar: TextView
    private lateinit var heldText: TextView
    private lateinit var lblMute: TextView
    private lateinit var lblHold: TextView
    private lateinit var cellSwap: View
    private lateinit var incomingPanel: View
    private lateinit var activePanel: View
    private lateinit var consultPanel: View
    private lateinit var keypad: GridLayout
    private lateinit var btnMute: MaterialButton
    private lateinit var btnSpeaker: MaterialButton
    private lateinit var btnKeypad: MaterialButton
    private lateinit var btnHold: MaterialButton

    private val handler = Handler(Looper.getMainLooper())
    private val ticker = object : Runnable {
        override fun run() {
            refresh()
            handler.postDelayed(this, 1000)
        }
    }
    private var answerWhenPermitted = false

    /** Na "Annuleer" bij overleg: dit gesprek hervatten zodra het overleggesprek weg is. */
    private var resumeAfterConsult: Call? = null

    private val coreListener = object : CoreListenerStub() {
        override fun onCallStateChanged(core: Core, call: Call, state: Call.State?, message: String) {
            if (state == Call.State.Released) {
                resumeAfterConsult?.let { held ->
                    if (call.callLog.callId != held.callLog.callId && held.state == Call.State.Paused) held.resume()
                    resumeAfterConsult = null
                }
            }
            if (core.callsNb == 0) finish() else refresh()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        appliedTheme = Themes.apply(this, Themes.Kind.CALL)
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setContentView(R.layout.activity_call)

        name = findViewById(R.id.callName)
        sub = findViewById(R.id.callSub)
        timer = findViewById(R.id.callTimer)
        state = findViewById(R.id.callState)
        avatar = findViewById(R.id.callAvatar)
        heldText = findViewById(R.id.heldText)
        lblMute = findViewById(R.id.lblMute)
        lblHold = findViewById(R.id.lblHold)
        cellSwap = findViewById(R.id.cellSwap)
        incomingPanel = findViewById(R.id.incomingPanel)
        activePanel = findViewById(R.id.activePanel)
        consultPanel = findViewById(R.id.consultPanel)
        keypad = findViewById(R.id.keypad)
        btnMute = findViewById(R.id.btnMute)
        btnSpeaker = findViewById(R.id.btnSpeaker)
        btnKeypad = findViewById(R.id.btnKeypad)
        btnHold = findViewById(R.id.btnHold)

        Dialpad.build(keypad, R.attr.appCallButton, R.attr.appCallText) { c -> Sip.core.currentCall?.sendDtmf(c) }

        findViewById<View>(R.id.btnAnswer).setOnClickListener { answer() }
        findViewById<View>(R.id.btnDecline).setOnClickListener { incoming()?.decline(Reason.Declined) }
        findViewById<View>(R.id.btnHangup).setOnClickListener {
            (Sip.core.currentCall ?: Sip.core.calls.firstOrNull())?.terminate()
        }
        btnMute.setOnClickListener {
            Sip.core.setMicEnabled(!Sip.core.isMicEnabled)
            refresh()
        }
        btnSpeaker.setOnClickListener {
            Sip.core.currentCall?.let { Sip.setSpeaker(it, !Sip.isSpeaker(it)) }
            refresh()
        }
        btnKeypad.setOnClickListener {
            keypad.visibility = if (keypad.visibility == View.VISIBLE) View.GONE else View.VISIBLE
            refresh()
        }
        btnHold.setOnClickListener {
            val c = mainCall() ?: return@setOnClickListener
            if (c.state == Call.State.Paused) c.resume() else c.pause()
        }
        findViewById<View>(R.id.btnTransfer).setOnClickListener { showTransferSheet() }
        findViewById<View>(R.id.btnSwap).setOnClickListener { held()?.resume() }
        findViewById<View>(R.id.btnMerge).setOnClickListener {
            // Attended transfer: wachtende beller doorverbinden met het overleggesprek.
            val held = held()
            val consult = Sip.core.currentCall
            if (held != null && consult != null) {
                LogBuffer.app("Doorverbinden (na overleg): ${Sip.label(held.remoteAddress)} → ${Sip.label(consult.remoteAddress)}")
                held.transferToAnother(consult)
                toast(getString(R.string.transfer_done, Sip.label(consult.remoteAddress)))
            }
        }
        findViewById<View>(R.id.btnCancelConsult).setOnClickListener {
            val held = held() ?: return@setOnClickListener
            resumeAfterConsult = held
            Sip.core.currentCall?.terminate() ?: held.resume()
        }

        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent?.getBooleanExtra(EXTRA_ANSWER, false) == true) answer()
    }

    override fun onResume() {
        super.onResume()
        if (Sip.core.callsNb == 0) {
            finish()
            return
        }
        Sip.core.addListener(coreListener)
        handler.post(ticker)
    }

    override fun onPause() {
        handler.removeCallbacks(ticker)
        Sip.core.removeListener(coreListener)
        super.onPause()
    }

    private fun incoming() = Sip.core.calls.firstOrNull { it.state == Call.State.IncomingReceived }
    private fun held() = Sip.core.calls.firstOrNull { it.state == Call.State.Paused }

    /** Het gesprek waar het scherm over gaat: actief, anders het eerste. */
    private fun mainCall(): Call? = Sip.core.currentCall ?: Sip.core.calls.firstOrNull()

    private fun answer() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            answerWhenPermitted = true
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 1)
            return
        }
        incoming()?.accept()
        Notifs.cancelIncoming(this)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (answerWhenPermitted) {
            answerWhenPermitted = false
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) answer()
        }
    }

    private fun color(@AttrRes id: Int) = this.themeColor(id)

    private fun setHeader(text: String, @AttrRes c: Int) {
        state.text = text
        state.setTextColor(color(c))
    }

    /** Ronde knop oranje kleuren als de functie aan staat. */
    private fun toggle(btn: MaterialButton, on: Boolean) {
        btn.backgroundTintList = ColorStateList.valueOf(color(if (on) R.attr.appAccent else R.attr.appCallButton))
    }

    private fun refresh() {
        val ringing = incoming()
        val call = ringing ?: mainCall() ?: return
        val held = held()
        val current = Sip.core.currentCall
        val consulting = held != null && current != null && held.callLog.callId != current.callLog.callId

        name.text = Sip.label(call.remoteAddress)
        avatar.text = initials(name.text.toString())
        sub.text = call.remoteAddress.username ?: ""

        val running = call.state in setOf(
            Call.State.StreamsRunning, Call.State.Connected, Call.State.Updating, Call.State.UpdatedByRemote
        )
        timer.text = if (running || call.state == Call.State.Paused) DateUtils.formatElapsedTime(call.duration.toLong()) else ""

        when (call.state) {
            Call.State.IncomingReceived -> setHeader(getString(R.string.incoming_call), R.attr.appAccent)
            Call.State.OutgoingInit, Call.State.OutgoingProgress -> setHeader(getString(R.string.calling), R.attr.appCallTextDim)
            Call.State.OutgoingRinging, Call.State.OutgoingEarlyMedia -> setHeader(getString(R.string.ringing), R.attr.appCallTextDim)
            Call.State.Paused, Call.State.Pausing -> setHeader(getString(R.string.on_hold), R.attr.appAccent)
            Call.State.PausedByRemote -> setHeader(getString(R.string.held_by_remote), R.attr.appAccent)
            Call.State.End, Call.State.Released -> setHeader(getString(R.string.ended), R.attr.appDanger)
            Call.State.Error -> setHeader(getString(R.string.call_failed), R.attr.appDanger)
            else -> setHeader(
                getString(if (consulting) R.string.state_consult else R.string.state_active), R.attr.appOk
            )
        }

        // Inkomend (ook een wachtend tweede gesprek tijdens een lopend gesprek).
        val isOnlyIncoming = ringing != null && Sip.core.callsNb == 1
        incomingPanel.visibility = if (ringing != null) View.VISIBLE else View.GONE
        activePanel.visibility = if (isOnlyIncoming) View.GONE else View.VISIBLE

        heldText.visibility = if (consulting) View.VISIBLE else View.GONE
        cellSwap.visibility = if (consulting) View.VISIBLE else View.INVISIBLE
        consultPanel.visibility = if (consulting) View.VISIBLE else View.GONE
        if (consulting) heldText.text = getString(R.string.held_label, Sip.label(held!!.remoteAddress))

        val muted = !Sip.core.isMicEnabled
        lblMute.text = getString(if (muted) R.string.unmute else R.string.mute)
        toggle(btnMute, muted)
        toggle(btnSpeaker, Sip.isSpeaker(call))
        toggle(btnKeypad, keypad.visibility == View.VISIBLE)
        val onHold = call.state == Call.State.Paused
        lblHold.text = getString(if (onHold) R.string.resume else R.string.hold)
        toggle(btnHold, onHold)
    }

    // ── Doorverbinden ────────────────────────────────────────────────────────

    private fun showTransferSheet() {
        val call = mainCall() ?: return
        val sheet = BottomSheetDialog(this)
        val v = LayoutInflater.from(this).inflate(R.layout.sheet_transfer, null)
        val input = v.findViewById<EditText>(R.id.transferNumber)
        v.findViewById<TextView>(R.id.sheetSub).text = getString(R.string.transfer_sub, Sip.label(call.remoteAddress))

        fun go(number: String, attended: Boolean) {
            if (number.isBlank()) return
            sheet.dismiss()
            if (attended) startConsult(call, number) else blindTransfer(call, number)
        }
        v.findViewById<View>(R.id.btnDirect).setOnClickListener { go(input.text.toString().trim(), false) }
        v.findViewById<View>(R.id.btnConsult).setOnClickListener { go(input.text.toString().trim(), true) }

        val list = v.findViewById<LinearLayout>(R.id.transferList)
        val contacts = Contacts.all(this)
        v.findViewById<View>(R.id.transferEmpty).visibility = if (contacts.isEmpty()) View.VISIBLE else View.GONE
        for (c in contacts) {
            val row = LayoutInflater.from(this).inflate(R.layout.item_transfer, list, false)
            row.findViewById<TextView>(R.id.tAvatar).text = initials(c.name)
            row.findViewById<TextView>(R.id.tName).text = c.name
            row.findViewById<TextView>(R.id.tNumber).text = c.number
            row.findViewById<View>(R.id.tDirect).setOnClickListener { go(c.number, false) }
            row.findViewById<View>(R.id.tConsult).setOnClickListener { go(c.number, true) }
            list.addView(row)
        }

        sheet.setContentView(v)
        sheet.show()
    }

    /** Direct (blind) doorverbinden: beller gaat meteen naar het andere toestel. */
    private fun blindTransfer(call: Call, number: String) {
        val addr = Sip.core.interpretUrl(number, false)
        if (addr == null) {
            toast(getString(R.string.invalid_number))
            return
        }
        val target = Contacts.nameFor(this, number) ?: number
        LogBuffer.app("Direct doorverbinden: ${Sip.label(call.remoteAddress)} → $target")
        call.transferTo(addr)
        toast(getString(R.string.transfer_done, target))
    }

    /** Overleg: beller in de wacht, eerst zelf het andere toestel bellen. */
    private fun startConsult(call: Call, number: String) {
        val target = Contacts.nameFor(this, number) ?: number
        LogBuffer.app("Overleg gestart: ${Sip.label(call.remoteAddress)} in de wacht, bellen naar $target")
        if (call.state != Call.State.Paused) call.pause()
        Sip.dial(this, number)
        toast(getString(R.string.transfer_consulting, target, Sip.label(call.remoteAddress)))
    }

    private fun toast(msg: String) = Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()

    companion object {
        const val EXTRA_ANSWER = "answer"
    }
}
