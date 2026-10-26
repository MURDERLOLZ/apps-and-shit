import SwiftUI
import WebKit

/// Loads Discord's real login page in a web view and reads the Authorization
/// header off Discord's own API requests once sign-in completes. 2FA, captcha
/// and passkeys all run on Discord's page — we never build a fake login form.
struct DiscordLoginSheet: View {
    @EnvironmentObject var session: Session
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.ink.ignoresSafeArea()
                DiscordWebLogin(
                    onToken: { token in
                        Task {
                            do { try await session.login(with: token); dismiss() }
                            catch { self.error = (error as? LocalizedError)?.errorDescription }
                        }
                    },
                    onError: { error = $0 }
                )
                .ignoresSafeArea(edges: .bottom)

                if let error {
                    VStack {
                        Spacer()
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .padding(12)
                            .background(.black.opacity(0.7), in: Capsule())
                            .foregroundStyle(Palette.ember)
                            .padding()
                    }
                }
            }
            .navigationTitle("Log in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.tint(Palette.lilac)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct DiscordWebLogin: UIViewRepresentable {
    let onToken: (String) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onToken: onToken) }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "token")

        // Hook fetch/XHR in the page so we catch the Authorization header Discord
        // attaches to its own API calls after a successful login.
        let js = """
        (function () {
          function post(t) { try { if (t) window.webkit.messageHandlers.token.postMessage(String(t)); } catch (e) {} }
          // Only accept values shaped like a real user token (dotted, no Bearer).
          function ok(v) { return v && v.indexOf(' ') < 0 && v.split('.').length === 3; }

          // 1) Live sniff: Discord puts the token on the Authorization header of its own API calls.
          try {
            const origFetch = window.fetch;
            window.fetch = function (resource, init) {
              try {
                const h = (init && init.headers) || (resource && resource.headers);
                if (h) {
                  const auth = (h.get ? h.get('Authorization') : h['Authorization']);
                  if (ok(auth)) post(auth);
                }
              } catch (e) {}
              return origFetch.apply(this, arguments);
            };
            const origSet = XMLHttpRequest.prototype.setRequestHeader;
            XMLHttpRequest.prototype.setRequestHeader = function (k, v) {
              try { if (String(k).toLowerCase() === 'authorization' && ok(v)) post(v); } catch (e) {}
              return origSet.apply(this, arguments);
            };
          } catch (e) {}

          // 2) Deterministic grab from Discord's own module store, in case the sniff misses.
          let tries = 0;
          const timer = setInterval(function () {
            tries++;
            try {
              const chunk = window.webpackChunkdiscord_app;
              if (chunk) {
                let token;
                chunk.push([[Math.random()], {}, function (req) {
                  for (const id in req.c) {
                    try {
                      const mod = req.c[id].exports;
                      const t = (mod && mod.default && mod.default.getToken && mod.default.getToken())
                             || (mod && mod.getToken && mod.getToken());
                      if (t) { token = t; break; }
                    } catch (e) {}
                  }
                }]);
                if (ok(token)) { clearInterval(timer); post(token); }
              }
            } catch (e) {}
            if (tries > 40) clearInterval(timer); // give up after ~20s
          }, 500);
        })();
        """
        contentController.addUserScript(
            WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.websiteDataStore = .nonPersistent() // no cookies left behind after logout

        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.load(URLRequest(url: URL(string: "https://discord.com/login")!))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let onToken: (String) -> Void
        private var fired = false
        init(onToken: @escaping (String) -> Void) { self.onToken = onToken }

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard !fired, let token = message.body as? String,
                  !token.isEmpty, token.lowercased() != "null" else { return }
            fired = true
            onToken(token)
        }
    }
}
