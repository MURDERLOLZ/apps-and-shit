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
            case .loggedIn(let user):
                HomeView(user: user)
            }
        }
        .task { await session.restore() }
    }
}

struct HomeView: View {
    let user: DiscordUser
    @EnvironmentObject var session: Session

    var body: some View {
        VStack(spacing: 14) {
            AsyncImage(url: user.avatarURL) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(.white.opacity(0.1))
            }
            .frame(width: 88, height: 88)
            .clipShape(Circle())

            Text(user.displayName).font(.title2.bold())
            Text("@\(user.username)").foregroundStyle(.white.opacity(0.6))
            Text("DMs and servers land next.").font(.footnote).foregroundStyle(.white.opacity(0.4))

            Button("Log out", role: .destructive) { session.logout() }
                .buttonStyle(.bordered)
                .padding(.top, 8)
        }
        .foregroundStyle(.white)
    }
}

enum Palette {
    static let ink = Color(red: 0.04, green: 0.04, blue: 0.07)
    static let ember = Color(red: 0.98, green: 0.42, blue: 0.24)
    static let violet = Color(red: 0.42, green: 0.36, blue: 0.95)
    static let lilac = Color(red: 0.78, green: 0.74, blue: 1.0)
    static let cyan = Color(red: 0.20, green: 0.75, blue: 0.95)
}
