import SwiftUI

struct DMListView: View {
    @ObservedObject var store: Store

    var body: some View {
        ZStack {
            Palette.ink.ignoresSafeArea()

            if !store.ready {
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text(store.connected ? "Loading your DMs…" : "Connecting…")
                        .font(.footnote).foregroundStyle(.white.opacity(0.5))
                }
            } else {
                List {
                    ForEach(store.dms) { ch in
                        NavigationLink(value: ch) {
                            DMRow(store: store, channel: ch)
                        }
                        .listRowBackground(Color.white.opacity(0.03))
                        .listRowSeparatorTint(.white.opacity(0.06))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: DMChannel.self) { ch in
            ChatView(store: store, channel: ch)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 6) {
                    Circle().fill(store.connected ? Palette.cyan : Palette.ember).frame(width: 8, height: 8)
                    Text(store.connected ? "online" : "offline")
                        .font(.caption2).foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }
}

private struct DMRow: View {
    @ObservedObject var store: Store
    let channel: DMChannel

    var body: some View {
        HStack(spacing: 12) {
            Avatar(user: store.avatarUser(for: channel), size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.title(for: channel))
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(channel.type == 3 ? "Group" : "Direct message")
                    .font(.caption).foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct Avatar: View {
    let user: GatewayUser?
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let url = user?.avatarURL(size: Int(size * 2)) {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: { fallback }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var fallback: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Palette.violet, Palette.ember],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(user?.initial ?? "?")
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}
