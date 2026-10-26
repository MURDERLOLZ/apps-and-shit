import SwiftUI

struct TokenPasteSheet: View {
    @EnvironmentObject var session: Session
    @Environment(\.dismiss) private var dismiss

    @State private var token = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Paste your user token. It's checked against Discord before anything is saved.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))

                    SecureField("Token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .padding(14)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.12)))
                        .foregroundStyle(.white)

                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Palette.ember)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if busy { ProgressView().tint(.white) }
                            Text(busy ? "Checking…" : "Log in")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .background(Palette.violet.opacity(token.isEmpty ? 0.4 : 1),
                                in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
                    .disabled(token.isEmpty || busy)

                    DisclosureGroup("Where do I find it?") {
                        Text("Discord web → open DevTools → Application → Local Storage → copy the \"token\" value. The in-app login does this for you without exposing it.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.top, 6)
                    }
                    .tint(Palette.lilac)
                    .font(.subheadline)
                }
                .padding(20)
            }
            .background(Palette.ink)
            .navigationTitle("Token login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.tint(Palette.lilac)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func submit() async {
        busy = true; error = nil
        do {
            try await session.login(with: token)
            dismiss()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Login failed."
        }
        busy = false
    }
}
