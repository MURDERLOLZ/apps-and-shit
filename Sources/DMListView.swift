import SwiftUI

struct DMListView: View {
    @EnvironmentObject var session: Session
    @StateObject private var store = Store()

    var body: some View {
        NavigationStack {
            Group {
                if store.dms.isEmpty {
                    VStack(spacing: 12) {
                        if store.connected {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.largeTitle).foregroundStyle(.white.opacity(0.4))
                            Text("No DMs yet").foregroundStyle(.white.opacity(0.6))
                        } else {
                            ProgressView().tint(.white)
                            Text("Connecting…").font(.footnote).foregroundStyle(.white.opacity(0.5))
                        }
                    }
                } else {
                    List(store.dms) { dm in
                        NavigationLink {
                            ChannelView(channel: dm).environmentObject(store)
                        } label: {
                            DMRow(channel: dm, myID: store.me?.id)
                        }
                        .listRowBackground(Color.white.opacity(0.03))
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.ink)
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 6) {
                        Circle().fill(store.connected ? .green : .orange).frame(width: 8, height: 8)
                        Text(store.me?.display ?? "…").font(.subheadline).foregroundStyle(.white.opacity(0.7))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { session.logout() } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                    }.tint(Palette.lilac)
                }
            }
        }
        .task {
            if let token = session.token { store.start(token: token) }
        }
    }
}

private struct DMRow: View {
    let channel: Channel
    let myID: String?

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: channel.iconURL(myID: myID)) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(Palette.violet.opacity(0.4))
                    .overlay(Image(systemName: "person.fill").foregroundStyle(.white.opacity(0.7)))
            }
            .frame(width: 42, height: 42)
            .clipShape(Circle())

            Text(channel.title(myID: myID))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
