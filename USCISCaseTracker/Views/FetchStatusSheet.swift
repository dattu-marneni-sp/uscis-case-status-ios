import SwiftUI

/// Sheet for pasting USCIS status when API fetch fails.
struct FetchStatusSheet: View {
    let receiptNumber: String
    let onComplete: (Result<CaseStatus, Error>) -> Void
    let onCancel: () -> Void

    @State private var pastedText = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    instructions
                    pasteSection
                }
                .padding()
            }
            .navigationTitle("Get Status")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") { savePastedStatus() }
                        .fontWeight(.semibold)
                        .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Paste status from USCIS", systemImage: "info.circle.fill")
                .font(.subheadline.weight(.medium))
            Text("Copy the status from egov.uscis.gov and paste below.")
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(white: 0.95))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var pasteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paste status from USCIS page")
                .font(.subheadline.weight(.medium))
            TextEditor(text: $pastedText)
                .font(.body)
                .frame(minHeight: 120)
                .padding(8)
                .background(Color(white: 0.98))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(white: 0.85), lineWidth: 1)
                )
                .focused($isTextFieldFocused)
        }
    }

    private func savePastedStatus() {
        let trimmed = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let status = USCISService.parsePastedStatus(trimmed) {
            onComplete(.success(status))
        } else {
            onComplete(.failure(USCISError.parsingError))
        }
    }
}
