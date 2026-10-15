package nl.softphone.app

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.net.SocketTimeoutException
import java.security.cert.X509Certificate
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocket
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager
import kotlin.random.Random

/**
 * "Verbinding testen": controleert stap voor stap of de centrale bereikbaar is
 * en schrijft de uitkomst in gewone taal naar het logboek. Draait op een achtergrondthread.
 */
object Diagnostics {

    private const val TIMEOUT_MS = 4000

    fun run(ctx: Context) {
        val p = Prefs(ctx)
        val log = LogBuffer::app
        log("════════ VERBINDINGSTEST ════════")
        log("Server: '${p.server}'  poort: '${p.port.ifBlank { "standaard" }}'  transport: ${p.transport}")
        log("Gebruiker: '${p.username}'  domein: '${p.sipDomain}'  wachtwoord: " +
            if (p.password.isEmpty()) "LEEG" else "ingevuld (${p.password.length} tekens)")
        if (!p.isConfigured) {
            LogBuffer.appError("Geen server of gebruikersnaam ingesteld.")
            return
        }

        // 1. Netwerk van de telefoon
        val cm = ctx.getSystemService(ConnectivityManager::class.java)
        val caps = cm.getNetworkCapabilities(cm.activeNetwork)
        val net = when {
            caps == null -> "GEEN netwerk"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "VPN"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobiel (4G/5G)"
            else -> "anders"
        }
        val localIps = cm.getLinkProperties(cm.activeNetwork)?.linkAddresses
            ?.joinToString { it.address.hostAddress ?: "?" } ?: "-"
        log("1. Telefoon zit op: $net, eigen IP: $localIps")

        // 2. Adres opzoeken
        val addrs = try {
            InetAddress.getAllByName(p.server).toList()
        } catch (e: Exception) {
            LogBuffer.appError("2. Adres '${p.server}' NIET gevonden (DNS): ${e.message}. " +
                "Controleer de spelling of gebruik het IP-adres.")
            return
        }
        log("2. Adres gevonden: ${addrs.joinToString { it.hostAddress ?: "?" }}")
        val target = addrs.first()
        if (target.isSiteLocalAddress && net.startsWith("mobiel")) {
            LogBuffer.appError("   Let op: ${target.hostAddress} is een intern adres, maar de telefoon zit op mobiel " +
                "internet. Verbind met het kantoor-wifi of VPN.")
        }

        // 3. Elk transport proberen, zodat zichtbaar is wat Asterisk wel/niet aanbiedt.
        val udpTcpPort = p.port.toIntOrNull()?.takeIf { p.transport != "TLS" } ?: 5060
        val tlsPort = p.port.toIntOrNull()?.takeIf { p.transport == "TLS" } ?: 5061
        val results = linkedMapOf(
            "UDP" to testUdp(target, udpTcpPort, p),
            "TCP" to testTcp(target, udpTcpPort, p, tls = false),
            "TLS" to testTcp(target, tlsPort, p, tls = true),
        )
        log("3. Resultaat per transport:")
        results.forEach { (t, r) -> log("   $t: $r") }

        // 4. Conclusie
        val chosen = results[p.transport] ?: ""
        val working = results.filterValues { it.startsWith("OK") }.keys
        when {
            chosen.startsWith("OK") ->
                log("4. Conclusie: server bereikbaar via ${p.transport}. Zie hieronder de REGISTER-poging " +
                    "voor de aanmelding zelf (401/403 = gebruikersnaam/wachtwoord).")
            working.isNotEmpty() ->
                LogBuffer.appError("4. Conclusie: ${p.transport} werkt NIET, maar ${working.joinToString()} wel. " +
                    "Kies in Instellingen transport ${working.first()}.")
            else ->
                LogBuffer.appError("4. Conclusie: de server reageert op geen enkel transport. Mogelijke oorzaken: " +
                    "verkeerd adres, telefoon op ander netwerk, firewall, of Asterisk luistert op een andere poort.")
        }

        log("Aanmelden opnieuw proberen...")
        android.os.Handler(android.os.Looper.getMainLooper()).post { Sip.core.refreshRegisters() }
    }

    private fun options(host: String, transport: String, localIp: String, localPort: Int, p: Prefs): String {
        val branch = "z9hG4bK" + Random.nextLong(1, Long.MAX_VALUE).toString(16)
        val tag = Random.nextInt(1, Int.MAX_VALUE).toString(16)
        val callId = Random.nextLong(1, Long.MAX_VALUE).toString(16) + "@softphone"
        return "OPTIONS sip:$host SIP/2.0\r\n" +
            "Via: SIP/2.0/$transport $localIp:$localPort;branch=$branch;rport\r\n" +
            "Max-Forwards: 70\r\n" +
            "From: <sip:${p.username}@${p.sipDomain}>;tag=$tag\r\n" +
            "To: <sip:$host>\r\n" +
            "Call-ID: $callId\r\n" +
            "CSeq: 1 OPTIONS\r\n" +
            "Contact: <sip:${p.username}@$localIp:$localPort;transport=${transport.lowercase()}>\r\n" +
            "User-Agent: Softphone-diagnose\r\n" +
            "Content-Length: 0\r\n\r\n"
    }

    private fun firstLine(resp: String) = resp.lineSequence().firstOrNull()?.trim().orEmpty()

    private fun testUdp(addr: InetAddress, port: Int, p: Prefs): String = try {
        DatagramSocket().use { s ->
            s.soTimeout = TIMEOUT_MS
            s.connect(addr, port)
            val msg = options(addr.hostAddress!!, "UDP", s.localAddress.hostAddress!!, s.localPort, p)
            s.send(DatagramPacket(msg.toByteArray(), msg.length))
            val buf = ByteArray(8192)
            val pkt = DatagramPacket(buf, buf.size)
            s.receive(pkt)
            "OK op poort $port – antwoord: ${firstLine(String(buf, 0, pkt.length))}"
        }
    } catch (e: SocketTimeoutException) {
        "GEEN antwoord op poort $port binnen ${TIMEOUT_MS / 1000}s (UDP uit, firewall, of Asterisk negeert onbekende afzenders)"
    } catch (e: Exception) {
        "FOUT op poort $port: ${e.javaClass.simpleName}: ${e.message}"
    }

    private fun testTcp(addr: InetAddress, port: Int, p: Prefs, tls: Boolean): String {
        val name = if (tls) "TLS" else "TCP"
        val raw = Socket()
        return try {
            raw.connect(InetSocketAddress(addr, port), TIMEOUT_MS)
            raw.soTimeout = TIMEOUT_MS
            var certNote = ""
            val sock: Socket = if (tls) {
                // Alleen voor de diagnose: certificaat accepteren en apart rapporteren.
                val ctx = SSLContext.getInstance("TLS")
                ctx.init(null, arrayOf<TrustManager>(object : X509TrustManager {
                    override fun checkClientTrusted(c: Array<X509Certificate>, a: String) {}
                    override fun checkServerTrusted(c: Array<X509Certificate>, a: String) {}
                    override fun getAcceptedIssuers() = arrayOf<X509Certificate>()
                }), null)
                (ctx.socketFactory.createSocket(raw, p.server, port, true) as SSLSocket).also { ssl ->
                    ssl.startHandshake()
                    val cert = ssl.session.peerCertificates.firstOrNull() as? X509Certificate
                    certNote = " (certificaat: ${cert?.subjectX500Principal?.name ?: "?"})"
                }
            } else raw
            val msg = options(addr.hostAddress!!, name, raw.localAddress.hostAddress!!, raw.localPort, p)
            sock.getOutputStream().apply { write(msg.toByteArray()); flush() }
            val buf = ByteArray(8192)
            val n = try { sock.getInputStream().read(buf) } catch (e: SocketTimeoutException) { -1 }
            sock.close()
            if (n > 0) "OK op poort $port – antwoord: ${firstLine(String(buf, 0, n))}$certNote"
            else "OK verbinding op poort $port, maar geen SIP-antwoord$certNote"
        } catch (e: java.net.ConnectException) {
            "GEWEIGERD op poort $port (Asterisk luistert hier niet op $name)"
        } catch (e: SocketTimeoutException) {
            "TIME-OUT op poort $port (geblokkeerd door firewall of server onbereikbaar)"
        } catch (e: Exception) {
            "FOUT op poort $port: ${e.javaClass.simpleName}: ${e.message}"
        } finally {
            try { raw.close() } catch (_: Exception) {}
        }
    }
}
