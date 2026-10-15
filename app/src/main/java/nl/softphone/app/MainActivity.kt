package nl.softphone.app

import android.Manifest
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.text.format.DateUtils
import android.content.res.ColorStateList
import android.view.View
import android.widget.EditText
import android.widget.PopupMenu
import android.widget.GridLayout
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.TextView
import androidx.core.widget.doAfterTextChanged
import com.google.android.material.button.MaterialButtonToggleGroup
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import com.google.android.material.bottomnavigation.BottomNavigationView
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import org.linphone.core.Account
import org.linphone.core.Call
import org.linphone.core.Core
import org.linphone.core.CoreListenerStub
import org.linphone.core.RegistrationState

class MainActivity : AppCompatActivity() {

    private lateinit var appliedTheme: AppTheme

    private lateinit var status: TextView
    private lateinit var statusChip: View
    private lateinit var statusDot: View
    private lateinit var number: EditText
    private lateinit var pageDial: View
    private lateinit var pageContacts: View
    private lateinit var pageHistory: View
    private lateinit var listContacts: ListView
    private lateinit var listHistory: ListView

    private var contacts: List<Contact> = emptyList()
    private var showPhone = false
    private var phoneAll: List<PhoneContact> = emptyList()
    private var phoneShown: List<PhoneContact> = emptyList()
    private lateinit var contactSearch: EditText
    private lateinit var contactSearchLayout: View
    private lateinit var phonePermission: View
    private lateinit var btnAddContact: View
    private var historyNumbers: List<String> = emptyList()

    private val coreListener = object : CoreListenerStub() {
        override fun onAccountRegistrationStateChanged(
            core: Core, account: Account, state: RegistrationState?, message: String
        ) = refreshStatus()

        override fun onCallStateChanged(core: Core, call: Call, state: Call.State?, message: String) {
            if (state == Call.State.Released) refreshHistory()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        appliedTheme = Themes.apply(this, Themes.Kind.NO_ACTION_BAR)
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        status = findViewById(R.id.status)
        statusChip = findViewById(R.id.statusChip)
        statusDot = findViewById(R.id.statusDot)
        number = findViewById(R.id.number)
        pageDial = findViewById(R.id.pageDial)
        pageContacts = findViewById(R.id.pageContacts)
        pageHistory = findViewById(R.id.pageHistory)
        listContacts = findViewById(R.id.listContacts)
        listHistory = findViewById(R.id.listHistory)

        Dialpad.build(findViewById<GridLayout>(R.id.dialpad)) { number.append(it.toString()) }
        findViewById<View>(R.id.btnCall).setOnClickListener { Sip.dial(this, number.text.toString()) }
        findViewById<View>(R.id.btnBack).apply {
            setOnClickListener { number.text.let { if (it.isNotEmpty()) it.delete(it.length - 1, it.length) } }
            setOnLongClickListener { number.text.clear(); true }
        }
        statusChip.setOnClickListener {
            if (Sip.registrationState() == RegistrationState.Failed) {
                startActivity(Intent(this, LogActivity::class.java))
            }
            Sip.core.refreshRegisters()
        }

        contactSearch = findViewById(R.id.contactSearch)
        contactSearchLayout = findViewById(R.id.contactSearchLayout)
        phonePermission = findViewById(R.id.phonePermission)
        btnAddContact = findViewById(R.id.btnAddContact)

        listContacts.setOnItemClickListener { _, _, pos, _ ->
            Sip.dial(this, if (showPhone) phoneShown[pos].number else contacts[pos].number)
        }
        listContacts.setOnItemLongClickListener { _, _, pos, _ ->
            if (showPhone) {
                // Telefooncontact overnemen in de eigen toestellenlijst (bijv. een collega's mobiel).
                val pc = phoneShown[pos]
                editContact(null, Contact(pc.name, pc.number))
            } else editContact(contacts[pos])
            true
        }
        btnAddContact.setOnClickListener { editContact(null) }
        findViewById<MaterialButtonToggleGroup>(R.id.contactSource).addOnButtonCheckedListener { _, id, checked ->
            if (!checked) return@addOnButtonCheckedListener
            showPhone = id == R.id.srcPhone
            if (showPhone) phoneAll = PhoneContacts.all(this)
            refreshContacts()
        }
        contactSearch.doAfterTextChanged { if (showPhone) refreshContacts() }
        findViewById<View>(R.id.btnContactsPermission).setOnClickListener { askContactsPermission() }
        listHistory.setOnItemClickListener { _, _, pos, _ -> Sip.dial(this, historyNumbers[pos]) }

        findViewById<BottomNavigationView>(R.id.nav).setOnItemSelectedListener {
            pageDial.visibility = if (it.itemId == R.id.nav_dial) View.VISIBLE else View.GONE
            pageContacts.visibility = if (it.itemId == R.id.nav_contacts) View.VISIBLE else View.GONE
            pageHistory.visibility = if (it.itemId == R.id.nav_history) View.VISIBLE else View.GONE
            true
        }

        findViewById<View>(R.id.btnMenu).setOnClickListener { v ->
            PopupMenu(this, v).apply {
                menu.add(0, 1, 0, R.string.settings)
                menu.add(0, 2, 1, R.string.log)
                setOnMenuItemClickListener {
                    val target = if (it.itemId == 1) SettingsActivity::class.java else LogActivity::class.java
                    startActivity(Intent(this@MainActivity, target))
                    true
                }
            }.show()
        }

        requestPermissionsIfNeeded()
        if (!Prefs(this).isConfigured) startActivity(Intent(this, SettingsActivity::class.java))
    }

    override fun onResume() {
        super.onResume()
        if (Themes.current(this) != appliedTheme) {
            recreate()
            return
        }
        Sip.core.addListener(coreListener)
        PhoneService.start(this)
        refreshStatus()
        if (showPhone) phoneAll = PhoneContacts.all(this)
        refreshContacts()
        refreshHistory()
        // Terug naar een lopend gesprek.
        if (Sip.core.callsNb > 0) startActivity(Intent(this, CallActivity::class.java))
    }

    override fun onPause() {
        Sip.core.removeListener(coreListener)
        super.onPause()
    }

    private fun refreshStatus() {
        status.text = Sip.statusText()
        val (soft, strong) = when (Sip.registrationState()) {
            RegistrationState.Ok -> R.attr.appOkSoft to R.attr.appOk
            RegistrationState.Failed -> R.attr.appDangerSoft to R.attr.appDanger
            RegistrationState.Progress, RegistrationState.Refreshing -> R.attr.appAccentSoft to R.attr.appAccentDark
            else -> R.attr.appNeutralSoft to R.attr.appMuted
        }
        val strongColor = this.themeColor(strong)
        statusChip.backgroundTintList = ColorStateList.valueOf(this.themeColor(soft))
        statusDot.backgroundTintList = ColorStateList.valueOf(strongColor)
        status.setTextColor(strongColor)
    }

    private fun refreshContacts() {
        btnAddContact.visibility = if (showPhone) View.GONE else View.VISIBLE
        if (!showPhone) {
            contactSearchLayout.visibility = View.GONE
            phonePermission.visibility = View.GONE
            contacts = Contacts.all(this)
            listContacts.adapter = RowAdapter(this, contacts.map { Row(it.name, it.number, Tone.ACCENT) })
            return
        }
        val allowed = PhoneContacts.hasPermission(this)
        phonePermission.visibility = if (allowed) View.GONE else View.VISIBLE
        contactSearchLayout.visibility = if (allowed) View.VISIBLE else View.GONE
        val q = contactSearch.text.toString().trim().lowercase()
        val digits = PhoneContacts.dialable(q)
        phoneShown = phoneAll.filter {
            q.isEmpty() || it.name.lowercase().contains(q) || (digits.length >= 2 && it.number.contains(digits))
        }
        listContacts.adapter = RowAdapter(this, phoneShown.map { Row(it.name, "${it.type} · ${it.number}", Tone.NEUTRAL) })
    }

    /** Toegang tot contacten vragen; na een definitieve weigering naar de app-instellingen. */
    private fun askContactsPermission() {
        val ui = getSharedPreferences("ui", MODE_PRIVATE)
        val askedBefore = ui.getBoolean("askedContacts", false)
        if (askedBefore && !shouldShowRequestPermissionRationale(Manifest.permission.READ_CONTACTS)) {
            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
            return
        }
        ui.edit().putBoolean("askedContacts", true).apply()
        requestPermissions(arrayOf(Manifest.permission.READ_CONTACTS), REQ_CONTACTS)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_CONTACTS && PhoneContacts.hasPermission(this)) {
            PhoneContacts.clearCache()
            phoneAll = PhoneContacts.all(this)
            refreshContacts()
            refreshHistory() // namen van bellers uit het telefoonboek
        }
    }

    private fun refreshHistory() {
        val logs = Sip.core.callLogs.toList()
        historyNumbers = logs.map { it.remoteAddress.username ?: it.remoteAddress.asStringUriOnly() }
        val rows = logs.map { log ->
            val (arrow, tone) = when {
                log.status == Call.Status.Missed -> "✕ Gemist" to Tone.DANGER
                log.dir == Call.Dir.Incoming -> "↙ Inkomend" to Tone.NEUTRAL
                else -> "↗ Uitgaand" to Tone.ACCENT
            }
            val whenText = DateUtils.getRelativeTimeSpanString(log.startDate * 1000L).toString()
            val dur = if (log.duration > 0) DateUtils.formatElapsedTime(log.duration.toLong()) else ""
            Row(Sip.label(log.remoteAddress), "$arrow · $whenText", tone, dur)
        }
        listHistory.adapter = RowAdapter(this, rows)
    }

    private fun editContact(existing: Contact?, prefill: Contact? = null) {
        val pad = (20 * resources.displayMetrics.density).toInt()
        val name = EditText(this).apply { hint = getString(R.string.name); setText(existing?.name ?: prefill?.name) }
        val num = EditText(this).apply {
            hint = getString(R.string.number)
            inputType = android.text.InputType.TYPE_CLASS_PHONE
            setText(existing?.number ?: prefill?.number)
        }
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(pad, pad / 2, pad, 0)
            addView(name)
            addView(num)
        }
        val dlg = MaterialAlertDialogBuilder(this)
            .setTitle(if (existing == null) R.string.add_contact else R.string.edit_contact)
            .setView(box)
            .setPositiveButton(R.string.save) { _, _ ->
                if (name.text.isNotBlank() && num.text.isNotBlank()) {
                    Contacts.upsert(this, existing, Contact(name.text.toString().trim(), num.text.toString().trim()))
                    refreshContacts()
                }
            }
            .setNegativeButton(R.string.cancel, null)
        if (existing != null) dlg.setNeutralButton(R.string.delete) { _, _ ->
            Contacts.remove(this, existing)
            refreshContacts()
        }
        dlg.show()
    }

    private fun requestPermissionsIfNeeded() {
        val wanted = mutableListOf(Manifest.permission.RECORD_AUDIO)
        if (Build.VERSION.SDK_INT >= 33) wanted += Manifest.permission.POST_NOTIFICATIONS
        if (Build.VERSION.SDK_INT >= 31) wanted += Manifest.permission.BLUETOOTH_CONNECT
        val missing = wanted.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isNotEmpty()) requestPermissions(missing.toTypedArray(), 1)

        // Android 14+: schermvullende beloproep vereist een aparte toestemming.
        if (Build.VERSION.SDK_INT >= 34 &&
            !getSystemService(NotificationManager::class.java).canUseFullScreenIntent()
        ) {
            MaterialAlertDialogBuilder(this)
                .setMessage(R.string.fullscreen_permission)
                .setPositiveButton(R.string.open_settings) { _, _ ->
                    startActivity(
                        Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, Uri.parse("package:$packageName"))
                    )
                }
                .setNegativeButton(R.string.cancel, null)
                .show()
        }
    }

    companion object {
        private const val REQ_CONTACTS = 2
    }
}
