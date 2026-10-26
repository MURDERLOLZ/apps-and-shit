import SwiftUI

struct ChatView: View {
    @ObservedObject var store: Store
    let channel: DMChannel

    @State private var draft = ""
    @State private var sending = false
    @FocusState private var inputFocused: Bool

    private var messages: [Message] { store.messages[channel.id] ?? [] }

    var body: some View {
        ZStack {
            Palette.ink.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(messages) { MessageRow(message: $0) }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .id("bottom-anchor")
                    }
                    .onChange(of: messages.count) { _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(messages.last?.id, anchor: .bottom)
                        }
                    }
                    .onAppear {
                        proxy.scrollTo(messages.last?.id, anchor: .bottom)
                    }
                }
                composer
            }
        }
        .navigationTitle(store.title(for: channel))
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadMessages(channel.id) }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Message", text: $draft, axis: .vertical)
                .focused($inputFocused)
                .lineLimit(1...5)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(.white.opacity(0.07), in: Capsule())
                .foregroundStyle(.white)

            Button {
                Task { await submit() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(draft.trimmingCharacters(in: .whitespaces).isEmpty
                                     ? .white.opacity(0.25) : Palette.violet)
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || sending)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.black.opacity(0.3))
    }

    private func submit() async {
        let text = draft
        draft = ""
        sending = true
        await store.send(channel.id, text)
        sending = false
    }
}

private struct MessageRow: View {
    let message: Message

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Avatar(user: message.author, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(message.author.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.lilac)
                    Text(message.time)
                        .font(.caption2).foregroundStyle(.white.opacity(0.3))
                }
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.9))
                        .textSelection(.enabled)
                }
                ForEach(message.attachments ?? [], id: \.url) { att in
                    if att.contentType?.hasPrefix("image") == true {
                        AsyncImage(url: URL(string: att.url)) { img in
                            img.resizable().scaledToFit()
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06)).frame(height: 120)
                        }
                        .frame(maxWidth: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        Label(att.filename, systemImage: "paperclip")
                            .font(.caption).foregroundStyle(Palette.cyan)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}
