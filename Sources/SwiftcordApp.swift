import SwiftUI

@main
struct SwiftcordApp: App {
    @StateObject private var session = Session()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var session: Session

    var body: some View {
        ZStack {
            Palette.ink.ignoresSafeArea()

            switch session.state {
            case .loading:
                ProgressView().tint(.white)
            case .loggedOut:
                HeroView()
            case .offline:
                VStack(spacing: 14) {
                    Image(systemName: "wifi.slash").font(.largeTitle)
                    Text("Can't reach Discord").font(.headline)
                    Button("Retry") { Task { await session.restore() } }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.violet)
                }
                .foregroundStyle(.white)
            case .loggedIn:
                if let token = session.token {
                    DMHome(token: token).environmentObject(session)
                }
            }
        }
        .task { await session.restore() }
    }
}

/// Owns the live Store for the session and hosts the DM experience.
struct DMHome: View {
    @StateObject private var store: Store
    @EnvironmentObject var session: Session

    init(token: String) {
        _store = StateObject(wrappedValue: Store(token: token))
    }

    var body: some View {
        NavigationStack {
            DMListView(store: store)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Menu {
                            if let me = store.me {
                                Text(me.displayName)
                                Text("@\(me.username)")
                            }
                            Button("Log out", role: .destructive) {
                                store.stop(); session.logout()
                            }
                        } label: {
                            Avatar(user: store.me, size: 30)
                        }
                    }
                }
        }
        .tint(Palette.lilac)
        .task { store.start() }
    }
}

enum Palette {
    static let ink = Color(red: 0.04, green: 0.04, blue: 0.07)
    static let ember = Color(red: 0.98, green: 0.42, blue: 0.24)
    static let violet = Color(red: 0.42, green: 0.36, blue: 0.95)
    static let lilac = Color(red: 0.78, green: 0.74, blue: 1.0)
    static let cyan = Color(red: 0.20, green: 0.75, blue: 0.95)
}
