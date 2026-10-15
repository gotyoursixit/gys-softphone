package nl.softphone.app

import android.content.Context
import android.content.Intent
import android.widget.Toast
import org.linphone.core.Account
import org.linphone.core.Address
import org.linphone.core.AudioDevice
import org.linphone.core.Call
import org.linphone.core.Core
import org.linphone.core.CoreListenerStub
import org.linphone.core.Factory
import org.linphone.core.MediaEncryption
import org.linphone.core.RegistrationState
import org.linphone.core.TransportType

/** Eén Linphone-core voor de hele app; leeft zolang het proces (en PhoneService) leeft. */
object Sip {
    lateinit var core: Core
        private set
    private lateinit var appCtx: Context

    fun init(context: Context) {
        if (::core.isInitialized) return
        appCtx = context.applicationContext
        val factory = Factory.instance()
        factory.setDebugMode(true, "Softphone")
        LogBuffer.attachLinphone()
        LogBuffer.app("App gestart, versie ${BuildConfig.VERSION_NAME}")
        core = factory.createCore(null, null, appCtx)
        core.setUserAgent(appCtx.getString(R.string.app_name), BuildConfig.VERSION_NAME)
        core.setKeepAliveEnabled(true)
        // Beltoon en trillen regelt Ringer zelf (volgens de telefooninstellingen); Linphone belt niet mee.
        core.setNativeRingingEnabled(false)
        core.setRing(null)
        core.addListener(listener)
        core.start()
        applySettings()
    }

    /** (Her)configureert het SIP-account op basis van de opgeslagen instellingen. */
    fun applySettings() {
        val p = Prefs(appCtx)
        core.clearAccounts()
        core.clearAllAuthInfo()
        if (!p.isConfigured) {
            LogBuffer.app("Geen account ingesteld")
            return
        }
        LogBuffer.app("Account instellen: ${p.username}@${p.sipDomain} via ${p.server}" +
            (if (p.port.isNotBlank()) ":${p.port}" else "") + " (${p.transport})")

        val f = Factory.instance()
        val transport = when (p.transport) {
            "TCP" -> TransportType.Tcp
            "TLS" -> TransportType.Tls
            else -> TransportType.Udp
        }
        core.addAuthInfo(
            f.createAuthInfo(p.username, p.authId.ifBlank { null }, p.password, null, null, p.sipDomain)
        )

        val identity = f.createAddress("sip:${p.username}@${p.sipDomain}") ?: return
        if (p.displayName.isNotBlank()) identity.setDisplayName(p.displayName)
        val portPart = if (p.port.isNotBlank()) ":${p.port}" else ""
        val server = f.createAddress("sip:${p.server}$portPart") ?: return
        server.setTransport(transport)

        val params = core.createAccountParams()
        params.setIdentityAddress(identity)
        params.setServerAddress(server)
        params.setRegisterEnabled(true)
        params.setExpires(600)
        // Domein wijkt af van de server: alle verkeer via de server routeren.
        params.setOutboundProxyEnabled(p.domain.isNotBlank() && p.domain != p.server)

        val nat = core.createNatPolicy()
        if (p.stun.isNotBlank()) {
            nat.setStunServer(p.stun)
            nat.setStunEnabled(true)
        }
        params.setNatPolicy(nat)

        val account = core.createAccount(params)
        core.addAccount(account)
        core.setDefaultAccount(account)

        core.setMediaEncryption(if (p.srtp) MediaEncryption.SRTP else MediaEncryption.None)
        core.setMediaEncryptionMandatory(p.srtp)
        core.refreshRegisters()
    }

    fun registrationState(): RegistrationState =
        core.defaultAccount?.state ?: RegistrationState.None

    fun statusText(): String {
        val acc = core.defaultAccount ?: return appCtx.getString(R.string.status_not_configured)
        return when (acc.state) {
            RegistrationState.Ok -> appCtx.getString(R.string.status_ok, Prefs(appCtx).username)
            RegistrationState.Progress, RegistrationState.Refreshing -> appCtx.getString(R.string.status_progress)
            RegistrationState.Failed -> appCtx.getString(R.string.status_failed, acc.errorInfo?.phrase ?: "")
            else -> appCtx.getString(R.string.status_offline)
        }
    }

    fun dial(ctx: Context, number: String) {
        val n = number.trim()
        if (n.isEmpty()) return
        if (registrationState() != RegistrationState.Ok) {
            Toast.makeText(ctx, R.string.not_registered, Toast.LENGTH_SHORT).show()
        }
        val addr = core.interpretUrl(n, false)
        if (addr == null) {
            Toast.makeText(ctx, R.string.invalid_number, Toast.LENGTH_SHORT).show()
            return
        }
        val params = core.createCallParams(null) ?: return
        core.inviteAddressWithParams(addr, params)
    }

    fun label(address: Address?): String {
        if (address == null) return "?"
        // Volgorde: interne toestellenlijst, dan het telefoonboek van de telefoon, dan wat de centrale meestuurt.
        Contacts.nameFor(appCtx, address.username)?.let { return it }
        PhoneContacts.nameFor(appCtx, address.username)?.let { return it }
        return address.displayName?.takeIf { it.isNotBlank() } ?: address.username ?: address.asStringUriOnly()
    }

    fun setSpeaker(call: Call, on: Boolean) {
        val wanted = if (on) AudioDevice.Type.Speaker else AudioDevice.Type.Earpiece
        core.audioDevices.firstOrNull {
            it.type == wanted && it.hasCapability(AudioDevice.Capabilities.CapabilityPlay)
        }?.let { call.outputAudioDevice = it }
    }

    fun isSpeaker(call: Call) = call.outputAudioDevice?.type == AudioDevice.Type.Speaker

    private fun openCallScreen() {
        appCtx.startActivity(
            Intent(appCtx, CallActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    /** Uitleg in gewone taal bij de meest voorkomende registratiefouten. */
    private fun explain(code: Int, message: String): String = when {
        code == 401 || code == 407 -> "\n   → Wachtwoord of gebruikersnaam/Auth-ID wordt niet geaccepteerd."
        code == 403 -> "\n   → Geweigerd: verkeerd wachtwoord, of het IP-adres van de telefoon is niet toegestaan (ACL / permit)."
        code == 404 -> "\n   → Gebruiker/toestel bestaat niet in Asterisk (endpoint/aor-naam controleren)."
        code == 408 -> "\n   → Geen antwoord van de server: verkeerd transport/poort, of firewall."
        code == 503 -> "\n   → Server niet beschikbaar of niet bereikbaar."
        message.contains("io error", true) || code == 0 ->
            "\n   → Geen verbinding met de server (adres, netwerk, transport of poort). Druk op 'Verbinding testen'."
        else -> ""
    }

    private val listener = object : CoreListenerStub() {
        override fun onAccountRegistrationStateChanged(
            core: Core, account: Account, state: RegistrationState?, message: String
        ) {
            val err = account.errorInfo
            val detail = if (state == RegistrationState.Failed && err != null)
                " – SIP ${err.protocolCode} ${err.phrase ?: ""} (reden: ${err.reason})" + explain(err.protocolCode, message)
            else ""
            val line = "Registratie: $state \"$message\"$detail"
            if (state == RegistrationState.Failed) LogBuffer.appError(line) else LogBuffer.app(line)
            PhoneService.refresh()
        }

        override fun onCallStateChanged(core: Core, call: Call, state: Call.State?, message: String) {
            when (state) {
                Call.State.IncomingReceived -> {
                    Ringer.start(appCtx, callWaiting = core.callsNb > 1)
                    Notifs.showIncoming(appCtx, call)
                    if (App.inForeground) openCallScreen()
                }
                Call.State.OutgoingInit -> openCallScreen()
                Call.State.Connected, Call.State.StreamsRunning -> {
                    Notifs.cancelIncoming(appCtx)
                    PhoneService.setInCall(true)
                }
                Call.State.End, Call.State.Error -> Notifs.cancelIncoming(appCtx)
                Call.State.Released -> {
                    if (call.callLog.status == Call.Status.Missed) Notifs.showMissed(appCtx, call)
                    if (core.callsNb == 0) PhoneService.setInCall(false)
                }
                else -> {}
            }
            // Opgenomen, geweigerd of gemist: stoppen met bellen zodra er niets meer overgaat.
            if (core.calls.none { it.state == Call.State.IncomingReceived }) Ringer.stop()
            PhoneService.refresh()
        }
    }
}
