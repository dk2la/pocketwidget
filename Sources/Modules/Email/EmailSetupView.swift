import SwiftUI

/// Account form for the Settings → Accounts page: provider preset prefills
/// hosts, password goes straight to the Keychain on save.
struct EmailSetupView: View {
    var service: EmailService

    @State private var draft = MailSetupDraft()
    @State private var checkState: SetupCheckState = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingRow(title: L10n.t(.mailProvider)) {
                WindowSegmented(
                    options: EmailProvider.allCases.map { ($0, $0.title) },
                    selection: Binding(
                        get: { draft.provider },
                        set: {
                            draft.select($0)
                            checkState = .idle
                        }
                    )
                )
            }
            if draft.provider.isPasswordAuthUnreliable {
                Text(L10n.t(.mailOutlookWarning))
                    .font(Theme.subFont)
                    .foregroundStyle(Theme.critical.opacity(0.9))
                    .padding(.bottom, 8)
            }
            Hairline(color: Palette.hairline)
            SetupFieldRow(title: L10n.t(.mailAddress)) {
                TextField("name@example.com", text: $draft.email)
            }
            Hairline(color: Palette.hairline)
            SetupFieldRow(title: L10n.t(.mailPassword), subtitle: L10n.t(.mailPasswordHint), width: 200) {
                SecureField("", text: $draft.password)
            }
            if draft.provider == .custom {
                Hairline(color: Palette.hairline)
                SetupFieldRow(title: L10n.t(.mailImapHost)) {
                    TextField("imap.example.com", text: $draft.imapHost)
                    TextField("993", text: $draft.imapPort).frame(width: 56)
                }
                Hairline(color: Palette.hairline)
                SetupFieldRow(title: L10n.t(.mailSmtpHost)) {
                    TextField("smtp.example.com", text: $draft.smtpHost)
                    TextField("465", text: $draft.smtpPort).frame(width: 56)
                }
            }
            Hairline(color: Palette.hairline)
            SetupActionRow(
                checkState: checkState,
                canCheck: draft.isComplete,
                canSave: draft.isComplete && !draft.password.isEmpty,
                showRemove: service.config != nil,
                onCheck: runCheck,
                onRemove: {
                    service.removeAccount()
                    draft.password = ""
                },
                onSave: { service.saveAccount(draft.config, password: draft.password) }
            )
        }
        .onAppear(perform: loadExisting)
        // The account can also be added in the Mail module while this page
        // is open.
        .onChange(of: service.config) { loadExisting() }
    }

    // MARK: - State

    /// Shows the saved account. A form that already matches it — the one
    /// just saved here, password still typed in — is left alone.
    private func loadExisting() {
        guard let config = service.config, config != draft.config else { return }
        draft = MailSetupDraft(config: config)
        checkState = .idle
    }

    private func runCheck() {
        let config = draft.config
        let secret = draft.password
        probeSetup($checkState) { await EmailService.testConnection(config, password: secret) }
    }
}
