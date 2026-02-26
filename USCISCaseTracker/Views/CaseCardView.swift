import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

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
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.body.weight(.semibold))
                        }
                    }
                    .disabled(caseItem.isLoading)
                    .tint(.blue)

                    Menu {
                        Button { copyReceiptNumber() } label: {
                            Label("Copy Receipt Number", systemImage: "doc.on.doc")
                        }
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
                        withAnimation(.easeInOut(duration: 0.25)) { isExpanded.toggle() }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if isEditing { nicknameEditor }
            if let lastRefreshed = caseItem.lastRefreshed {
                Text("Updated \(lastRefreshed, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
    }

    private var statusSection: some View {
        let title = caseItem.status?.title.lowercased() ?? ""
        let isApproved = title.contains("approved")
        let isDenied = title.contains("denied") || title.contains("rejected")
        return VStack(alignment: .leading, spacing: 10) {
            if let status = caseItem.status {
                HStack(spacing: 8) {
                    statusIcon(for: status.title)
                    Text(status.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(statusColor(for: status.title))
                }
                Text(status.details)
                    .font(.callout)
                    .foregroundStyle(detailsColor(isApproved: isApproved, isDenied: isDenied))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                if status.title.lowercased().contains("case not found") {
                    Button { onDelete() } label: {
                        Label("Remove Case", systemImage: "trash")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(.red)
                    .padding(.top, 4)
                }
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
        .background(statusSectionBackground(isApproved: isApproved, isDenied: isDenied))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func detailsColor(isApproved: Bool, isDenied: Bool) -> Color {
        if isApproved { return Color.green.opacity(0.9) }
        if isDenied { return Color.red.opacity(0.9) }
        return .secondary
    }

    private func statusSectionBackground(isApproved: Bool, isDenied: Bool) -> Color {
        if isApproved { return Color.green.opacity(0.15) }
        if isDenied { return Color.red.opacity(0.15) }
        return Color.clear
    }

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

    private var cardBackground: Color {
        let title = caseItem.status?.title.lowercased() ?? ""
        if title.contains("approved") { return Color.green.opacity(0.2) }
        if title.contains("denied") || title.contains("rejected") { return Color.red.opacity(0.2) }
        #if os(iOS)
        return Color(.systemBackground)
        #else
        return Color(nsColor: .controlBackgroundColor)
        #endif
    }

    private func copyReceiptNumber() {
        #if os(iOS)
        UIPasteboard.general.string = caseItem.receiptNumber
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(caseItem.receiptNumber, forType: .string)
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
            if lowered.contains("case not found") { return ("questionmark.circle.fill", .orange) }
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
        if lowered.contains("case not found") { return .orange }
        if lowered.contains("approved") { return .green }
        if lowered.contains("denied") || lowered.contains("rejected") { return .red }
        if lowered.contains("produced") || lowered.contains("mailed") || lowered.contains("delivered") { return .teal }
        if lowered.contains("request") && lowered.contains("evidence") { return .orange }
        return .primary
    }
}
