import SwiftUI

struct CaseCardView: View {
    let caseItem: CaseItem
    let onRefresh: () -> Void
    let onDelete: () -> Void
    let onNicknameChange: (String) -> Void

    @State private var isEditing = false
    @State private var editedNickname = ""
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            if isExpanded {
                Divider().padding(.horizontal)
                statusSection
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
        .padding(.horizontal)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if !caseItem.nickname.isEmpty {
                        Text(caseItem.nickname)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    Text(caseItem.receiptNumber)
                        .font(caseItem.nickname.isEmpty ? .headline : .subheadline)
                        .foregroundStyle(caseItem.nickname.isEmpty ? .primary : .secondary)
                        .monospaced()
                }

                Spacer()

                HStack(spacing: 12) {
                    Button { onRefresh() } label: {
                        if caseItem.isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.body.weight(.semibold))
                        }
                    }
                    .disabled(caseItem.isLoading)
                    .tint(.blue)

                    Menu {
                        Button { startEditing() } label: {
                            Label("Edit Nickname", systemImage: "pencil")
                        }
                        Button(role: .destructive) { onDelete() } label: {
                            Label("Remove Case", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if isEditing {
                nicknameEditor
            }

            if let lastRefreshed = caseItem.lastRefreshed {
                Text("Updated \(lastRefreshed, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
    }

    // MARK: - Status

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let status = caseItem.status {
                HStack(spacing: 8) {
                    statusIcon(for: status.title)
                    Text(status.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(statusColor(for: status.title))
                }

                Text(status.details)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            } else if caseItem.isLoading {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Fetching status...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            } else {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Tap refresh to fetch the latest status")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }

    // MARK: - Nickname Editor

    private var nicknameEditor: some View {
        HStack {
            TextField("Enter nickname", text: $editedNickname)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)
                .submitLabel(.done)
                .onSubmit { saveNickname() }

            Button("Save") { saveNickname() }
                .font(.subheadline.weight(.medium))

            Button("Cancel") { isEditing = false }
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private var cardBackground: Color {
        #if os(iOS)
        Color(.systemBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    private func startEditing() {
        editedNickname = caseItem.nickname
        isEditing = true
    }

    private func saveNickname() {
        onNicknameChange(editedNickname)
        isEditing = false
    }

    private func statusIcon(for title: String) -> some View {
        let lowered = title.lowercased()
        let (icon, color): (String, Color) = {
            if lowered.contains("approved") { return ("checkmark.seal.fill", .green) }
            if lowered.contains("denied") || lowered.contains("rejected") { return ("xmark.seal.fill", .red) }
            if lowered.contains("received") || lowered.contains("accepted") { return ("tray.and.arrow.down.fill", .blue) }
            if lowered.contains("produced") || lowered.contains("mailed") || lowered.contains("delivered") { return ("envelope.fill", .teal) }
            if lowered.contains("transferred") || lowered.contains("moved") { return ("arrow.right.arrow.left", .orange) }
            if lowered.contains("request") && lowered.contains("evidence") { return ("doc.text.fill", .orange) }
            if lowered.contains("fingerprint") || lowered.contains("biometric") { return ("touchid", .purple) }
            if lowered.contains("interview") { return ("person.2.fill", .indigo) }
            return ("clock.fill", .yellow)
        }()

        return Image(systemName: icon)
            .foregroundStyle(color)
            .font(.subheadline)
    }

    private func statusColor(for title: String) -> Color {
        let lowered = title.lowercased()
        if lowered.contains("approved") { return .green }
        if lowered.contains("denied") || lowered.contains("rejected") { return .red }
        if lowered.contains("produced") || lowered.contains("mailed") || lowered.contains("delivered") { return .teal }
        if lowered.contains("request") && lowered.contains("evidence") { return .orange }
        return .primary
    }
}
