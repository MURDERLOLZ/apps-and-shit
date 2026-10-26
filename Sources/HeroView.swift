import SwiftUI

private struct Feature: Identifiable {
    let icon: String
    let title: String
    let detail: String
    var soon = false
    var id: String { title }
}

private let features: [Feature] = [
    Feature(icon: "bolt.fill", title: "Truly native",
            detail: "Pure SwiftUI, no React Native layer. Light on RAM and battery."),
    Feature(icon: "eye.slash.fill", title: "Zero telemetry",
            detail: "No analytics or tracking. It only talks to Discord to chat."),
    Feature(icon: "nosign", title: "No upsells",
            detail: "No Nitro nags, no shop tab, no quests. Just your chats."),
    Feature(icon: "chevron.left.forwardslash.chevron.right", title: "Open source",
            detail: "Read every line that touches your account."),
    Feature(icon: "faceid", title: "Face ID lock",
            detail: "Lock the whole app behind Face ID or your passcode.", soon: true),
    Feature(icon: "paintpalette.fill", title: "Free themes",
            detail: "Any accent, true AMOLED black, compact mode. No Nitro.", soon: true),
]

struct HeroView: View {
    @EnvironmentObject var session: Session
    @State private var showLogin = false
    @State private var showToken = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(spacing: 34) {
                    header
                    actions
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(features) { FeatureCard(feature: $0) }
                    }
                    Text("SwiftCord v0.1 · Built with Swift")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.35))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 56)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $showLogin) { DiscordLoginSheet().environmentObject(session) }
        .sheet(isPresented: $showToken) { TokenPasteSheet().environmentObject(session) }
    }

    private var header: some View {
        VStack(spacing: 18) {
            AppGlyph()
            VStack(spacing: 8) {
                Text("SwiftCord")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [Palette.lilac, Palette.ember],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                Text("Discord, the way it should feel on iPhone.")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button { showLogin = true } label: {
                Label("Log in with Discord", systemImage: "lock.shield.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.plain)
            .background(
                LinearGradient(colors: [Palette.violet, Palette.ember],
                               startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .foregroundStyle(.white)

            Button { showToken = true } label: {
                Label("Paste a token instead", systemImage: "key.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            )
            .foregroundStyle(.white.opacity(0.9))

            Text("Your token is validated, then stored only in this device's Keychain. It's sent to discord.com and nowhere else.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
    }
}

private struct FeatureCard: View {
    let feature: Feature

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: feature.icon)
                    .font(.title3)
                    .foregroundStyle(Palette.lilac)
                Spacer()
                if feature.soon {
                    Text("SOON")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Palette.ember.opacity(0.22), in: Capsule())
                        .foregroundStyle(Palette.ember)
                }
            }
            Text(feature.title).font(.headline).foregroundStyle(.white)
            Text(feature.detail)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct AppGlyph: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [Palette.violet, Palette.ember],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 96, height: 96)
        .shadow(color: Palette.violet.opacity(0.5), radius: 24, y: 10)
    }
}

private struct AuroraBackground: View {
    var body: some View {
        ZStack {
            Palette.ink
            Circle().fill(Palette.violet.opacity(0.35))
                .frame(width: 420).blur(radius: 140)
                .offset(x: -140, y: -260)
            Circle().fill(Palette.ember.opacity(0.28))
                .frame(width: 380).blur(radius: 150)
                .offset(x: 160, y: 300)
            Circle().fill(Palette.cyan.opacity(0.18))
                .frame(width: 300).blur(radius: 130)
                .offset(x: 120, y: -120)
        }
        .ignoresSafeArea()
    }
}
