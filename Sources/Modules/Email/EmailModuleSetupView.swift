import AppKit
import SwiftUI

/// "Add mail" inside the Mail module: provider, address, password, Connect.
/// Everything typed lives in `MailSetupFlow`, so the form is the same when
/// the panel is opened again after a trip to the browser.
struct EmailModuleSetupView: View {
    var flow: MailSetupFlow

    private var card: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
    }

    var body: some View {
        let draft = Bindable(flow).draft
        let provider = flow.draft.provider
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                providerRow
                if provider.isPasswordAuthUnreliable {
                    note(L10n.t(.mailOutlookWarning), color: Theme.critical.opacity(0.9))
                }
                VStack(spacing: 0) {
                    SetupLine {
                        TextField(L10n.t(.mailAddress), text: draft.email)
                    }
                    Hairline()
                    SetupLine {
                        SecureField(L10n.t(.mailPassword), text: draft.password)
                    }
                }
                .background(Theme.cardFill, in: card)
                if provider == .custom {
                    VStack(spacing: 0) {
                        SetupLine(caption: "IMAP") {
                            TextField("imap.example.com", text: draft.imapHost)
                            TextField("993", text: draft.imapPort).frame(width: 44)
                        }
                        Hairline()
                        SetupLine(caption: "SMTP") {
                            TextField("smtp.example.com", text: draft.smtpHost)
                            TextField("465", text: draft.smtpPort).frame(width: 44)
                        }
                    }
                    .background(Theme.cardFill, in: card)
                }
                if let url = provider.appPasswordURL {
                    VStack(alignment: .leading, spacing: 6) {
                        ModuleButton(label: L10n.t(.mailGetAppPassword), systemName: "arrow.up.forward") {
                            NSWorkspace.shared.open(url)
                        }
                        if flow.passwordWasPickedUp {
                            Label(L10n.t(.mailPasswordPickedUp), systemImage: "checkmark")
                                .font(Theme.subFont)
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 4)
                        } else {
                            note(L10n.t(.mailAppPasswordStep), color: Theme.textTertiary)
                        }
                    }
                }
                if case .failed(let failure) = flow.phase {
                    note(Self.text(for: failure), color: Theme.critical)
                }
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    ModuleButton(label: L10n.t(.mailCancel)) {
                        flow.cancel()
                    }
                    ModuleButton(
                        label: flow.phase == .connecting ? L10n.t(.mailChecking) : L10n.t(.mailConnect),
                        kind: .light,
                        enabled: flow.canConnect
                    ) {
                        Task { await flow.connect() }
                    }
                }
            }
        }
        .animation(Theme.stateSpring, value: flow.passwordWasPickedUp)
        .animation(Theme.stateSpring, value: flow.phase)
        .animation(Theme.stateSpring, value: provider)
    }

    private var providerRow: some View {
        HStack(spacing: 6) {
            ForEach(EmailProvider.allCases) { provider in
                let selected = provider == flow.draft.provider
                let shape = RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                Button {
                    flow.select(provider)
                } label: {
                    Text(provider.title)
                        .font(Theme.subFont)
                        .fontWeight(selected ? .semibold : .medium)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(selected ? Theme.inkOnAccent : Theme.textSecondary)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(shape.fill(selected ? Theme.lightFill : Theme.cardFill))
                        .overlay(shape.stroke(Theme.hairlineSoft, lineWidth: selected ? 0 : 1))
                        .contentShape(shape)
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    private func note(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Theme.subFont)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    private static func text(for failure: MailSetupFailure) -> String {
        switch failure {
        case .rejected: L10n.t(.mailErrorRejected)
        case .unreachable: L10n.t(.mailErrorUnreachable)
        case .notSaved: L10n.t(.mailErrorNotSaved)
        case .other(let message): message
        }
    }
}

/// One line of the setup form: an optional short caption and its fields.
private struct SetupLine<Fields: View>: View {
    var caption: String?
    @ViewBuilder var fields: () -> Fields

    var body: some View {
        HStack(spacing: 10) {
            if let caption {
                Text(caption)
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textQuaternary)
                    .frame(width: 36, alignment: .leading)
            }
            fields()
        }
        .textFieldStyle(.plain)
        .font(Theme.bodyFont)
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}
