//
//  ChatView.swift
//  life247
//
//  Phase 4: in-circle messaging UI backed by CircleChatService (Firebase REST).
//

import SwiftUI

struct ChatView: View {
    /// Lowercased username of the signed-in operator, used to align bubbles.
    let currentUserId: String

    @EnvironmentObject var chat: CircleChatService
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messagesList
                Divider()
                composer
            }
            .navigationTitle("Circle Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { chat.isViewingChat = true }
        .onDisappear { chat.isViewingChat = false }
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if chat.messages.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.largeTitle).foregroundColor(.secondary)
                            Text("No messages yet").font(.subheadline).bold()
                            Text("Say hi to your circle.").font(.caption).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 60)
                    }

                    ForEach(chat.messages) { message in
                        bubble(for: message)
                            .id(message.id)
                    }
                }
                .padding(16)
            }
            .onChange(of: chat.messages.count) { _, _ in
                if let last = chat.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onAppear {
                if let last = chat.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func bubble(for message: ChatMessage) -> some View {
        let isMine = message.senderId == currentUserId
        return HStack {
            if isMine { Spacer(minLength: 40) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
                if !isMine {
                    Text(message.senderName)
                        .font(.caption2).bold()
                        .foregroundColor(MemberPalette.color(for: message.senderName))
                }
                Text(message.text)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isMine ? Color.purple : Color(.secondarySystemBackground))
                    )
                    .foregroundColor(isMine ? .white : .primary)
                Text(message.sentAt, style: .time)
                    .font(.caption2).foregroundColor(.secondary)
            }
            if !isMine { Spacer(minLength: 40) }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Message", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .purple)
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    private func send() {
        chat.send(draft)
        draft = ""
    }
}
