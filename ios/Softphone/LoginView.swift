import SwiftUI

/// Inlogscherm: toestel@domein + wachtwoord, zoals de webapp. Serverinstellingen zijn standaard verborgen.
struct LoginView: View {
    @Environment(Session.self) private var session

    @State private var address = Settings.lastLogin?.address ?? ""
    @State private var password = ""
    @State private var server = Settings.lastLogin?.server ?? Account.defaultServer
    @State private var port = Settings.lastLogin?.port ?? ""
    @State private var transport = Settings.lastLogin?.transport ?? .udp
    @State private var showServer = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Theme.label("Got Your Six"))
                        .font(Theme.font(.semibold, size: 15, relativeTo: .subheadline))
                        .foregroundStyle(Theme.accent)
                    Text(Theme.label("Inloggen"))
                        .font(Theme.font(.bold, size: 34, relativeTo: .largeTitle))
                        .foregroundStyle(Theme.ink)
                    Text("Met uw toestel en wachtwoord van de telefooncentrale.")
                        .foregroundStyle(Theme.grey)
                }
                .padding(.top, 40)

                VStack(alignment: .leading, spacing: 12) {
                    TextField("Toestel@domein", text: $address)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("address")
                    Text(verbatim: "Bijvoorbeeld 102@test.gys-voip.nl")
                        .font(.footnote)
                        .foregroundStyle(Theme.grey)
                    SecureField("Wachtwoord", text: $password)
                        .textContentType(.password)
                        .accessibilityIdentifier("password")
                        .onSubmit(login)
                }
                .textFieldStyle(.roundedBorder)

                DisclosureGroup("Serverinstellingen", isExpanded: $showServer) {
                    VStack(spacing: 12) {
                        LabeledContent("Server") {
                            TextField(Account.defaultServer, text: $server)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Poort") {
                            TextField("standaard", text: $port)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                        Picker("Transport", selection: $transport) {
                            ForEach(Transport.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.top, 8)
                }
                .tint(Theme.grey)

                if let error = session.error {
                    Text(error)
                        .foregroundStyle(Theme.error)
                        .accessibilityIdentifier("error")
                }

                Button(action: login) {
                    if session.busy {
                        ProgressView().tint(.white)
                    } else {
                        Text("Inloggen")
                    }
                }
                .buttonStyle(PillButtonStyle())
                .disabled(session.busy)
                .accessibilityIdentifier("login")
            }
            .padding(24)
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    private func login() {
        Task {
            await session.login(input: address, password: password, server: server, port: port, transport: transport)
            if session.loggedIn { password = "" }
        }
    }
}
