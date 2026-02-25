import Foundation
import SwiftUI

@MainActor
final class CaseTrackerViewModel: ObservableObject {
    @Published var cases: [CaseItem] = []
    @Published var showAddSheet = false
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var refreshingCaseId: UUID?

    private let persistence = PersistenceService.shared

    init() {
        cases = persistence.loadCases()
    }

    func addCase(receiptNumber: String, nickname: String) {
        let cleaned = receiptNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleaned.isEmpty else { return }

        guard USCISService.isValidReceiptNumber(cleaned) else {
            errorMessage = USCISError.invalidReceiptNumber.localizedDescription
            showError = true
            return
        }

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

        refreshingCaseId = newCase.id
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

    func startRefresh(id: UUID) {
        guard let index = cases.firstIndex(where: { $0.id == id }) else { return }
        cases[index].isLoading = true
        refreshingCaseId = id
    }

    func completeRefresh(id: UUID, status: CaseStatus) {
        guard let index = cases.firstIndex(where: { $0.id == id }) else { return }
        cases[index].status = status
        cases[index].lastRefreshed = Date()
        cases[index].isLoading = false
        refreshingCaseId = nil
        save()
    }

    func failRefresh(id: UUID, error: String) {
        if let index = cases.firstIndex(where: { $0.id == id }) {
            cases[index].isLoading = false
        }
        refreshingCaseId = nil
        errorMessage = error
        showError = true
    }

    func cancelRefresh() {
        if let id = refreshingCaseId,
           let index = cases.firstIndex(where: { $0.id == id }) {
            cases[index].isLoading = false
        }
        refreshingCaseId = nil
    }

    private func save() {
        persistence.saveCases(cases)
    }
}
