import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

@MainActor
final class CaseTrackerViewModel: ObservableObject {
    @Published var cases: [CaseItem] = []
    @Published var showAddSheet = false
    @Published var showSettings = false
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var lastFailedReceiptNumber: String?
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
        let newCase = CaseItem(receiptNumber: cleaned, nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines))
        cases.append(newCase)
        save()
        startRefresh(id: newCase.id)
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
        let receipt = cases[index].receiptNumber

        Task { @MainActor in
            do {
                let status = try await USCISAPIClient.fetchStatus(receiptNumber: receipt)
                completeRefresh(id: id, status: status)
            } catch let err as USCISError where err == .caseNotFound {
                let status = CaseStatus(
                    title: "Case Not Found",
                    details: "The receipt number may be invalid or not in the system."
                )
                completeRefresh(id: id, status: status)
            } catch {
                lastFailedReceiptNumber = receipt
                failRefresh(id: id, error: error.localizedDescription)
            }
        }
    }

    func completeRefresh(id: UUID, status: CaseStatus) {
        guard let index = cases.firstIndex(where: { $0.id == id }) else { return }
        cases[index].status = status
        cases[index].lastRefreshed = Date()
        cases[index].isLoading = false
        save()
    }

    func failRefresh(id: UUID, error: String) {
        if let index = cases.firstIndex(where: { $0.id == id }) {
            cases[index].isLoading = false
        }
        errorMessage = error
        showError = true
    }

    func openUSCISInBrowser(receiptNumber: String? = nil) {
        let receipt = receiptNumber ?? lastFailedReceiptNumber ?? ""
        lastFailedReceiptNumber = nil
        // Use GET URL with receipt for direct status link (Safari may pass Cloudflare via PAT)
        let urlString: String
        if !receipt.isEmpty, let encoded = receipt.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlString = "https://egov.uscis.gov/?lng=en-US&appReceiptNum=\(encoded)"
        } else {
            urlString = "https://egov.uscis.gov/casestatus/landing.do"
        }
        guard let url = URL(string: urlString) else { return }
        #if os(iOS)
        UIApplication.shared.open(url)
        #else
        NSWorkspace.shared.open(url)
        #endif
    }

    private func save() {
        persistence.saveCases(cases)
    }
}
