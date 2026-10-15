package nl.softphone.app

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import android.view.View
import android.widget.Button
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.materialswitch.MaterialSwitch
import org.linphone.core.LogLevel

class LogActivity : AppCompatActivity() {

    private lateinit var appliedTheme: AppTheme

    private lateinit var text: TextView
    private lateinit var scroll: ScrollView
    private lateinit var showAll: MaterialSwitch
    private lateinit var btnTest: Button
    private val observer: () -> Unit = { render() }

    override fun onCreate(savedInstanceState: Bundle?) {
        appliedTheme = Themes.apply(this, Themes.Kind.NORMAL)
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_log)
        supportActionBar?.setDisplayHomeAsUpEnabled(true)

        text = findViewById(R.id.logText)
        scroll = findViewById(R.id.logScroll)
        showAll = findViewById(R.id.showAll)
        btnTest = findViewById(R.id.btnTest)

        showAll.setOnCheckedChangeListener { _, _ -> render() }
        btnTest.setOnClickListener {
            btnTest.isEnabled = false
            Thread {
                try {
                    Diagnostics.run(applicationContext)
                } catch (e: Exception) {
                    LogBuffer.appError("Test afgebroken: ${e.javaClass.simpleName}: ${e.message}")
                }
                runOnUiThread { btnTest.isEnabled = true }
            }.start()
        }
        findViewById<View>(R.id.btnShare).setOnClickListener { share() }
        findViewById<View>(R.id.btnCopy).setOnClickListener {
            getSystemService(ClipboardManager::class.java)
                .setPrimaryClip(ClipData.newPlainText("Softphone log", exportText()))
            Toast.makeText(this, R.string.log_copied, Toast.LENGTH_SHORT).show()
        }
        findViewById<View>(R.id.btnClear).setOnClickListener { LogBuffer.clear() }
    }

    override fun onResume() {
        super.onResume()
        if (Themes.current(this) != appliedTheme) {
            recreate()
            return
        }
        LogBuffer.observe(observer)
        render()
    }

    override fun onPause() {
        LogBuffer.unobserve(observer)
        super.onPause()
    }

    override fun onSupportNavigateUp(): Boolean {
        finish()
        return true
    }

    private fun visibleEntries() =
        LogBuffer.snapshot().let { all -> if (showAll.isChecked) all else all.filter(LogBuffer::isRelevant) }

    private fun render() {
        val atBottom = !scroll.canScrollVertically(1)
        val sb = SpannableStringBuilder()
        for (e in visibleEntries().takeLast(800)) {
            val start = sb.length
            sb.append(e.toString()).append('\n')
            val color = when {
                e.level == LogLevel.Error || e.level == LogLevel.Fatal -> Color.rgb(0xEF, 0x53, 0x50)
                e.level == LogLevel.Warning -> Color.rgb(0xFF, 0xA7, 0x26)
                e.source == "APP" -> Color.rgb(0x64, 0xB5, 0xF6)
                else -> null
            }
            color?.let { sb.setSpan(ForegroundColorSpan(it), start, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE) }
            if (e.source == "APP") sb.setSpan(StyleSpan(android.graphics.Typeface.BOLD), start, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        if (sb.isEmpty()) sb.append(getString(R.string.log_empty))
        text.text = sb
        if (atBottom) scroll.post { scroll.fullScroll(View.FOCUS_DOWN) }
    }

    private fun exportText(): String {
        val p = Prefs(this)
        val header = "Softphone ${BuildConfig.VERSION_NAME} – Android ${android.os.Build.VERSION.RELEASE} " +
            "(${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL})\n" +
            "Server ${p.server} poort ${p.port.ifBlank { "standaard" }} ${p.transport}, gebruiker ${p.username}\n\n"
        // Laatste ~300 kB; deelapps weigeren grotere teksten.
        return header + visibleEntries().joinToString("\n").takeLast(300_000)
    }

    private fun share() {
        startActivity(
            Intent.createChooser(
                Intent(Intent.ACTION_SEND)
                    .setType("text/plain")
                    .putExtra(Intent.EXTRA_SUBJECT, "Softphone logboek")
                    .putExtra(Intent.EXTRA_TEXT, exportText()),
                getString(R.string.log_share)
            )
        )
    }
}
