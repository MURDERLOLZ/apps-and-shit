import SwiftUI

struct ChannelView: View {
    let channel: Channel
    @EnvironmentObject var store: Store
    @State private var draft = ""
    @FocusState private var composerFocused: Bool

    private var msgs: [Message] { store.messages[channel.id] ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(msgs) { MessageRow(message: $0) }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .onChange(of: msgs.count) { _ in
                    if let last = msgs.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
                .onAppear {
                    if let last = msgs.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            composer
        }
        .background(Palette.ink)
        .navigationTitle(channel.title(myID: store.me?.id))
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadHistory(channel.id) }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Message", text: $draft, axis: .vertical)
                .focused($composerFocused)
                .lineLimit(1...5)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(.white.opacity(0.07), in: Capsule())
                .foregroundStyle(.white)

            Button {
                let text = draft; draft = ""
                Task { await store.send(text, to: channel.id) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(draft.trimmingCharacters(in: .whitespaces).isEmpty
                                     ? .white.opacity(0.25) : Palette.violet)
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.black.opacity(0.3))
    }
}

private struct MessageRow: View {
    let message: Message

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AsyncImage(url: message.author.avatarURL()) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(Palette.violet.opacity(0.4))
            }
            .frame(width: 34, height: 34)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(message.author.display).font(.subheadline.bold()).foregroundStyle(.white)
                    Text(message.time).font(.caption2).foregroundStyle(.white.opacity(0.4))
                }
                Text(message.content.isEmpty ? " " : message.content)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.9))
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
    }
}
