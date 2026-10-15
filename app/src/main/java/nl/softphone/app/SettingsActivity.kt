package nl.softphone.app

import android.annotation.SuppressLint
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.View
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.CheckBox
import android.widget.EditText
import android.widget.Spinner
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.textfield.TextInputLayout

class SettingsActivity : AppCompatActivity() {

    private lateinit var appliedTheme: AppTheme

    private val transports = listOf("UDP", "TCP", "TLS")

    override fun onCreate(savedInstanceState: Bundle?) {
        appliedTheme = Themes.apply(this, Themes.Kind.NORMAL)
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings)
        supportActionBar?.setDisplayHomeAsUpEnabled(true)

        val p = Prefs(this)
        val server = findViewById<EditText>(R.id.server)
        val port = findViewById<EditText>(R.id.port)
        val domain = findViewById<EditText>(R.id.domain)
        val transport = findViewById<Spinner>(R.id.transport)
        val username = findViewById<EditText>(R.id.username)
        val authId = findViewById<EditText>(R.id.authId)
        val password = findViewById<EditText>(R.id.password)
        val displayName = findViewById<EditText>(R.id.displayName)
        val stun = findViewById<EditText>(R.id.stun)
        val srtp = findViewById<CheckBox>(R.id.srtp)
        val themePicker = findViewById<Spinner>(R.id.theme)

        val themes = AppTheme.entries
        themePicker.adapter = ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item, themes.map { getString(it.label) })
        themePicker.setSelection(themes.indexOf(appliedTheme))
        themePicker.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, pos: Int, id: Long) {
                if (themes[pos] == appliedTheme) return
                p.theme = themes[pos].key
                recreate() // direct zichtbaar; het hoofdscherm volgt bij terugkeren
            }
            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }

        transport.adapter = ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item, transports)
        server.setText(p.server)
        port.setText(p.port)
        domain.setText(p.domain)
        transport.setSelection(transports.indexOf(p.transport).coerceAtLeast(0))
        username.setText(p.username)
        authId.setText(p.authId)
        password.setText(p.password)
        displayName.setText(p.displayName)
        stun.setText(p.stun)
        srtp.isChecked = p.srtp

        val serverLayout = findViewById<TextInputLayout>(R.id.serverLayout)
        val usernameLayout = findViewById<TextInputLayout>(R.id.usernameLayout)

        findViewById<View>(R.id.btnSave).setOnClickListener {
            // "sip:201@pbx", "pbx:5060" e.d. netjes uit elkaar halen.
            var host = clean(server.text).removePrefix("sip:").removePrefix("sips:").substringAfter('@')
            var portText = clean(port.text)
            if (host.count { it == ':' } == 1) {
                portText = portText.ifBlank { host.substringAfter(':') }
                host = host.substringBefore(':')
            }
            val user = clean(username.text).removePrefix("sip:").substringBefore('@')

            serverLayout.error = if (host.isEmpty()) getString(R.string.required) else null
            usernameLayout.error = if (user.isEmpty()) getString(R.string.required) else null
            if (host.isEmpty() || user.isEmpty()) {
                (if (host.isEmpty()) server else username).requestFocus()
                Toast.makeText(this, R.string.fill_required, Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            p.server = host
            p.port = portText
            p.domain = clean(domain.text)
            p.transport = transports[transport.selectedItemPosition]
            p.username = user
            p.authId = authId.text.toString()
            p.password = password.text.toString()
            p.displayName = displayName.text.toString()
            p.stun = stun.text.toString()
            p.srtp = srtp.isChecked
            Sip.applySettings()
            PhoneService.start(this)
            PhoneService.refresh()
            finish()
        }

        findViewById<View>(R.id.btnBattery).setOnClickListener { requestBatteryExemption() }
    }

    /** Spaties en onzichtbare tekens (bv. van plakken) verwijderen. */
    private fun clean(text: CharSequence?): String =
        text?.toString().orEmpty().filterNot { it.isWhitespace() || Character.isISOControl(it) || it == '​' || it == '﻿' }

    override fun onSupportNavigateUp(): Boolean {
        finish()
        return true
    }

    @SuppressLint("BatteryLife")
    private fun requestBatteryExemption() {
        val pm = getSystemService(PowerManager::class.java)
        if (pm.isIgnoringBatteryOptimizations(packageName)) {
            Toast.makeText(this, R.string.battery_already, Toast.LENGTH_SHORT).show()
            return
        }
        startActivity(
            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName"))
        )
    }
}
