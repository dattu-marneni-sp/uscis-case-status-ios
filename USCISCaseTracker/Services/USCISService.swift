import Foundation

enum USCISError: LocalizedError {
    case invalidReceiptNumber
    case networkError(String)
    case parsingError
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidReceiptNumber:
            return "Invalid receipt number. It should be 3 letters followed by 10 digits (e.g., EAC2190000001)."
        case .networkError(let message):
            return "Network error: \(message)"
        case .parsingError:
            return "Unable to parse the case status response."
        case .serverError(let code):
            return "Server returned error code \(code)."
        }
    }
}

actor USCISService {
    static let shared = USCISService()
    private let baseURL = "https://egov.uscis.gov/casestatus/mycasestatus.do"

    private init() {}

    func fetchCaseStatus(receiptNumber: String) async throws -> CaseStatus {
        let cleaned = receiptNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        guard isValidReceiptNumber(cleaned) else {
            throw USCISError.invalidReceiptNumber
        }

        let body = "appReceiptNum=\(cleaned)&caseStatusSearchBtn=CHECK+STATUS"

        guard let url = URL(string: baseURL) else {
            throw USCISError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.httpBody = body.data(using: .utf8)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw USCISError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            throw USCISError.serverError(httpResponse.statusCode)
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw USCISError.parsingError
        }

        return try parseHTML(html)
    }

    private func isValidReceiptNumber(_ number: String) -> Bool {
        let pattern = "^[A-Z]{3}\\d{10}$"
        return number.range(of: pattern, options: .regularExpression) != nil
    }

    private func parseHTML(_ html: String) throws -> CaseStatus {
        let title = extractContent(from: html, tag: "h1") ?? "Status Unknown"
        let details = extractContent(from: html, tag: "p", containedIn: "rows text-center") ?? "No details available."

        if title == "Status Unknown" && details == "No details available." {
            let altTitle = extractFirstMatch(from: html, pattern: "<div class=\"current-status-sec\">.*?<h1>(.*?)</h1>", group: 1)
            let altDetails = extractFirstMatch(from: html, pattern: "<div class=\"rows text-center\">.*?<p>(.*?)</p>", group: 1)

            if let t = altTitle ?? altDetails {
                return CaseStatus(
                    title: cleanHTML(altTitle ?? "Status Unknown"),
                    details: cleanHTML(altDetails ?? t)
                )
            }
        }

        return CaseStatus(title: cleanHTML(title), details: cleanHTML(details))
    }

    private func extractContent(from html: String, tag: String, containedIn divClass: String? = nil) -> String? {
        var searchHTML = html

        if let divClass = divClass {
            let divPattern = "<div class=\"\(divClass)\">(.*?)</div>"
            if let range = searchHTML.range(of: divPattern, options: [.regularExpression, .dotMatchesLineSeparators]) {
                searchHTML = String(searchHTML[range])
            }
        }

        let pattern = "<\(tag)[^>]*>(.*?)</\(tag)>"
        guard let range = searchHTML.range(of: pattern, options: [.regularExpression, .dotMatchesLineSeparators]) else {
            return nil
        }

        let match = String(searchHTML[range])
        let content = match
            .replacingOccurrences(of: "<\(tag)[^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "</\(tag)>", with: "")
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractFirstMatch(from html: String, pattern: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else {
            return nil
        }
        let nsRange = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: nsRange),
              match.numberOfRanges > group,
              let range = Range(match.range(at: group), in: html) else {
            return nil
        }
        return String(html[range])
    }

    private func cleanHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
