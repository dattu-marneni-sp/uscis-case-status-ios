import Foundation
import WebKit

enum USCISError: LocalizedError {
    case invalidReceiptNumber
    case networkError(String)
    case parsingError
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidReceiptNumber:
            return "Invalid receipt number. It should be 3 letters followed by 10 digits (e.g., EAC2190000001)."
        case .networkError(let message):
            return "Network error: \(message)"
        case .parsingError:
            return "Could not read case status from the page. Please try again."
        case .timeout:
            return "Request timed out. The USCIS website may be slow — please try again."
        }
    }
}

@MainActor
final class USCISService: NSObject {
    static let shared = USCISService()

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<CaseStatus, Error>?

    private override init() {
        super.init()
    }

    func fetchCaseStatus(receiptNumber: String) async throws -> CaseStatus {
        let cleaned = receiptNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        guard isValidReceiptNumber(cleaned) else {
            throw USCISError.invalidReceiptNumber
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            loadCaseStatus(receiptNumber: cleaned)
        }
    }

    private func isValidReceiptNumber(_ number: String) -> Bool {
        let pattern = "^[A-Z]{3}\\d{10}$"
        return number.range(of: pattern, options: .regularExpression) != nil
    }

    private func loadCaseStatus(receiptNumber: String) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

        self.webView = wv

        let urlString = "https://egov.uscis.gov/casestatus/mycasestatus.do"
        guard let url = URL(string: urlString) else {
            continuation?.resume(throwing: USCISError.networkError("Invalid URL"))
            continuation = nil
            return
        }

        let body = "changeLocale=&completedActionsCurrentPage=0&upcomingActionsCurrentPage=0&appReceiptNum=\(receiptNumber)&caseStatusSearchBtn=CHECK+STATUS"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)
        request.timeoutInterval = 60

        wv.load(request)

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(45))
            if self.continuation != nil {
                self.continuation?.resume(throwing: USCISError.timeout)
                self.continuation = nil
                self.webView = nil
            }
        }
    }

    private func extractStatus() {
        let js = """
        (function() {
            var title = '';
            var details = '';

            // Try the h1 tag for status title
            var h1 = document.querySelector('.current-status-sec h1') || document.querySelector('h1');
            if (h1) title = h1.innerText.trim();

            // Try the paragraph in the text-center div for details
            var p = document.querySelector('.rows.text-center p');
            if (p) details = p.innerText.trim();

            // Fallback: look for any content area
            if (!title && !details) {
                var content = document.querySelector('.appointment-sec') || document.querySelector('.main-content');
                if (content) details = content.innerText.trim().substring(0, 500);
            }

            return JSON.stringify({ title: title || 'Status Unknown', details: details || 'No details available.' });
        })();
        """

        webView?.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self else { return }

            if let jsonString = result as? String,
               let data = jsonString.data(using: .utf8),
               let parsed = try? JSONDecoder().decode(CaseStatus.self, from: data) {
                let status = CaseStatus(
                    title: parsed.title.isEmpty ? "Status Unknown" : parsed.title,
                    details: parsed.details.isEmpty ? "No details available." : parsed.details
                )
                self.continuation?.resume(returning: status)
            } else {
                self.continuation?.resume(throwing: USCISError.parsingError)
            }

            self.continuation = nil
            self.webView = nil
        }
    }
}

extension USCISService: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            self.extractStatus()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.continuation?.resume(throwing: USCISError.networkError(error.localizedDescription))
            self.continuation = nil
            self.webView = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.continuation?.resume(throwing: USCISError.networkError(error.localizedDescription))
            self.continuation = nil
            self.webView = nil
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(.allow)
    }
}
