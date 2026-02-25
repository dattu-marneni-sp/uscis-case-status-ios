import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = CaseTrackerViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if viewModel.cases.isEmpty {
                    emptyState
                } else {
                    caseList
                }
            }
            .navigationTitle("USCIS Tracker")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { viewModel.showAddSheet = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }

                if !viewModel.cases.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            Task { await viewModel.refreshAllCases() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .sheet(isPresented: $viewModel.showAddSheet) {
                AddCaseSheet { receipt, nickname in
                    viewModel.addCase(receiptNumber: receipt, nickname: nickname)
                }
                .presentationDetents([.medium])
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred.")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("No Cases Yet")
                .font(.title2.weight(.semibold))

            Text("Add your USCIS receipt number to\ntrack your case status.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                viewModel.showAddSheet = true
            } label: {
                Label("Add Your First Case", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(Capsule())
            .padding(.top, 8)
        }
        .padding()
    }

    // MARK: - Case List

    private var caseList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(viewModel.cases) { caseItem in
                    CaseCardView(
                        caseItem: caseItem,
                        onRefresh: {
                            Task { await viewModel.refreshCase(id: caseItem.id) }
                        },
                        onDelete: {
                            withAnimation { viewModel.deleteCase(id: caseItem.id) }
                        },
                        onNicknameChange: { newName in
                            viewModel.updateNickname(id: caseItem.id, nickname: newName)
                        }
                    )
                }
            }
            .padding(.vertical)
        }
        .refreshable {
            await viewModel.refreshAllCases()
        }
    }
}

#Preview {
    ContentView()
}
