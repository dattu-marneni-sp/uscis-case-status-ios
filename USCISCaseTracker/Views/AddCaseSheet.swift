import SwiftUI

struct AddCaseSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (String, String) -> Void

    @State private var receiptNumber = ""
    @State private var nickname = ""
    @FocusState private var focusedField: Field?

    private enum Field { case receipt, nickname }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. EAC2190000001", text: $receiptNumber)
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        #endif
                        .autocorrectionDisabled()
                        .monospaced()
                        .focused($focusedField, equals: .receipt)
                } header: {
                    Text("Receipt Number")
                } footer: {
                    Text("13 characters: 3 letters + 10 digits")
                        .font(.caption2)
                }

                Section {
                    TextField("e.g. My H1B, Wife's EAD", text: $nickname)
                        .focused($focusedField, equals: .nickname)
                } header: {
                    Text("Nickname (Optional)")
                } footer: {
                    Text("A friendly label to identify this case")
                        .font(.caption2)
                }
            }
            .navigationTitle("Add Case")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(receiptNumber, nickname)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(receiptNumber.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                focusedField = .receipt
            }
        }
    }
}
