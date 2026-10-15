import Foundation

/// Beheerserver (telefonie-API, server/ in deze repo) op api.gys-voip.nl; zelfde aanroepen als web/src/beheer.ts.
/// Inloggen controleert toestel + wachtwoord zonder SIP-verkeer, zodat een fout wachtwoord niet meetelt
/// voor Event Guard/fail2ban op de centrale.
enum BeheerClient {
    static let baseURL = URL(string: "https://api.gys-voip.nl")!

    enum LoginResult {
        /// Toestel en wachtwoord kloppen.
        case ok(token: String, role: String)
        /// Wachtwoord fout of te veel pogingen: niet doorgaan naar de centrale.
        case rejected(String)
        /// Beheerserver niet bereikbaar of domein (nog) niet aangesloten: verder met alleen de centrale.
        case unavailable(String)
    }

    struct Failure: Error {
        /// HTTP-status; 0 = niet bereikbaar.
        let status: Int
        let message: String
    }

    private struct LoginResponse: Decodable { let token: String; let role: String? }
    private struct ErrorResponse: Decodable { let error: String? }

    static func login(user: String, domain: String, password: String) async -> LoginResult {
        var req = URLRequest(url: baseURL.appending(path: "auth/toestel"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["user": user, "domain": domain, "password": password])
        req.timeoutInterval = 10
        let data: Data
        let status: Int
        do {
            let (d, res) = try await URLSession.shared.data(for: req)
            data = d
            status = (res as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            return .unavailable("Beheerserver niet bereikbaar (\(error.localizedDescription))")
        }
        if status == 200, let r = try? JSONDecoder().decode(LoginResponse.self, from: data) {
            return .ok(token: r.token, role: r.role ?? "gebruiker")
        }
        let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error ?? "Fout \(status)"
        switch status {
        case 401, 429: return .rejected(message)
        case 400: return .rejected("Controleer toestel en domein (bijvoorbeeld 102@test.gys-voip.nl).")
        default: return .unavailable(message)
        }
    }

    /// Token intrekken; ook de niet-storen-stand vervalt dan bij collega's.
    static func logout(token: String) async {
        var req = URLRequest(url: baseURL.appending(path: "auth/logout"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 5
        _ = try? await URLSession.shared.data(for: req)
    }

    /// Aanvraag met het opgeslagen token; is dat verlopen (401), dan één keer opnieuw inloggen.
    static func authed<T: Decodable>(_ path: String, method: String = "GET", as type: T.Type) async throws -> T {
        guard let token = Settings.beheerToken else { throw Failure(status: 401, message: "Niet ingelogd bij de beheerserver") }
        do {
            return try await send(path, method: method, token: token)
        } catch let f as Failure where f.status == 401 {
            guard let acc = Settings.account, let password = Settings.password,
                  case .ok(let fresh, let role) = await login(user: acc.user, domain: acc.domain, password: password)
            else { throw f }
            Settings.beheerToken = fresh
            Settings.beheerRole = role
            return try await send(path, method: method, token: fresh)
        }
    }

    private static func send<T: Decodable>(_ path: String, method: String, token: String) async throws -> T {
        var req = URLRequest(url: baseURL.appending(path: path))
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 10
        let data: Data
        let status: Int
        do {
            let (d, res) = try await URLSession.shared.data(for: req)
            data = d
            status = (res as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            throw Failure(status: 0, message: "Beheerserver niet bereikbaar")
        }
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error ?? "Fout \(status)"
            throw Failure(status: status, message: message)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw Failure(status: status, message: "Onverwacht antwoord van de beheerserver")
        }
    }
}
