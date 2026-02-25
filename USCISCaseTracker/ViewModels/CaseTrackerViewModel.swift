import Foundation
import SwiftUI

@MainActor
final class CaseTrackerViewModel: ObservableObject {
    @Published var cases: [CaseItem] = []
    @Published var showAddSheet = false
    @Published var errorMessage: String?
    @Published var showError = false

    private let persistence = PersistenceService.shared
    private let uscisService = USCISService.shared

    init() {
        cases = persistence.loadCases()
    }

    func addCase(receiptNumber: String, nickname: String) {
        let cleaned = receiptNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleaned.isEmpty else { return }

        if cases.contains(where: { $0.receiptNumber == cleaned }) {
            errorMessage = "Case \(cleaned) is already being tracked."
            showError = true
            return
        }

        let newCase = CaseItem(
            receiptNumber: cleaned,
            nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        cases.append(newCase)
        save()

        Task {
            await refreshCase(id: newCase.id)
        }
    }

    func deleteCase(at offsets: IndexSet) {
        cases.remove(atOffsets: offsets)
        save()
    }

    func deleteCase(id: UUID) {
        cases.removeAll { $0.id == id }
        save()
    }

    func updateNickname(id: UUID, nickname: String) {
        guard let index = cases.firstIndex(where: { $0.id == id }) else { return }
        cases[index].nickname = nickname
        save()
    }

    func refreshCase(id: UUID) async {
        guard let index = cases.firstIndex(where: { $0.id == id }) else { return }
        cases[index].isLoading = true

        do {
            let status = try await uscisService.fetchCaseStatus(receiptNumber: cases[index].receiptNumber)
            if let idx = cases.firstIndex(where: { $0.id == id }) {
                cases[idx].status = status
                cases[idx].lastRefreshed = Date()
                cases[idx].isLoading = false
            }
        } catch {
            if let idx = cases.firstIndex(where: { $0.id == id }) {
                cases[idx].isLoading = false
            }
            errorMessage = error.localizedDescription
            showError = true
        }

        save()
    }

    func refreshAllCases() async {
        for caseItem in cases {
            await refreshCase(id: caseItem.id)
        }
    }

    private func save() {
        persistence.saveCases(cases)
    }
}
