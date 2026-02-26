import Foundation

// MARK: - URLSession Fetch (try GET first, then POST)

extension USCISService {
    static func fetchStatus(receiptNumber: String) async throws -> CaseStatus {
        let receipt = receiptNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard isValidReceiptNumber(receipt) else {
            throw USCISError.invalidReceiptNumber
        }
        // Try GET first (some apps use appReceiptNum query param - may bypass Cloudflare)
        if let status = try? await fetchStatusViaGET(receipt: receipt) {
            return status
        }
        // Fall back to POST
        return try await fetchStatusViaPOST(receipt: receipt)
    }

    private static func fetchStatusViaGET(receipt: String) async throws -> CaseStatus {
        guard var components = URLComponents(string: "https://egov.uscis.gov/casestatus/mycasestatus.do") else {
            throw USCISError.parsingError
        }
        components.queryItems = [URLQueryItem(name: "appReceiptNum", value: receipt)]
        guard let url = components.url else { throw USCISError.parsingError }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("https://egov.uscis.gov/casestatus/landing.do", forHTTPHeaderField: "Referer")
        request.setValue(safariUserAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        return try parseResponse(data: data, response: response)
    }

    private static func fetchStatusViaPOST(receipt: String) async throws -> CaseStatus {
        guard let url = buildStatusURL() else { throw USCISError.parsingError }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("https://egov.uscis.gov/casestatus/landing.do", forHTTPHeaderField: "Referer")
        request.setValue(safariUserAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = buildPOSTBody(for: receipt).data(using: .utf8)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        return try parseResponse(data: data, response: response)
    }

    private static func parseResponse(data: Data, response: URLResponse) throws -> CaseStatus {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw USCISError.parsingError
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw USCISError.parsingError
        }
        if html.contains("Verify you are human") || html.contains("Just a moment") ||
           html.contains("cf-browser-verification") || html.contains("challenge-running") {
            throw USCISError.cloudflareBlocked
        }
        let status = parseStatus(from: html)
        guard !status.title.isEmpty || !status.details.isEmpty else {
            throw USCISError.parsingError
        }
        return status
    }

    private static var safariUserAgent: String {
        #if os(iOS)
        return "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        #else
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        #endif
    }

    private static func parseStatus(from html: String) -> CaseStatus {
        var title = ""
        var details = ""

        // Extract h1 content
        if let h1Start = html.range(of: "<h1"),
           let h1End = html.range(of: "</h1>", range: h1Start.upperBound..<html.endIndex) {
            let between = html[h1Start.upperBound..<h1End.lowerBound]
            if let closeAngle = between.firstIndex(of: ">") {
                title = String(between[between.index(after: closeAngle)...])
                    .replacingOccurrences(of: "&nbsp;", with: " ")
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .trimmingCharacters(in: .whitespaces)
            }
        }

        // Extract first substantial <p> after rows/text-center
        if let rowsRange = html.range(of: "rows") {
            let fromRows = String(html[rowsRange.lowerBound...])
            if let pStart = fromRows.range(of: "<p"),
               let pEnd = fromRows.range(of: "</p>", range: pStart.upperBound..<fromRows.endIndex) {
                var text = String(fromRows[pStart.upperBound..<pEnd.lowerBound])
                if let closeAngle = text.firstIndex(of: ">") {
                    text = String(text[text.index(after: closeAngle)...])
                }
                text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                text = text.replacingOccurrences(of: "&nbsp;", with: " ")
                text = text.replacingOccurrences(of: "&amp;", with: "&")
                text = text.replacingOccurrences(of: "&lt;", with: "<")
                text = text.replacingOccurrences(of: "&gt;", with: ">")
                details = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if details.count > 800 { details = String(details.prefix(800)) }
            }
        }

        // Fallback: look for "Case Was" or "Case Is" in HTML
        if title.isEmpty {
            for pattern in ["Case Was ", "Case Is "] {
                if let range = html.range(of: pattern) {
                    let remainder = html[range.lowerBound...]
                    let endIndex = remainder.prefix(150).firstIndex(where: { $0 == "<" || $0 == "\n" })
                        ?? remainder.index(remainder.startIndex, offsetBy: min(150, remainder.count), limitedBy: remainder.endIndex)
                        ?? remainder.endIndex
                    title = String(remainder[..<endIndex]).trimmingCharacters(in: .whitespaces)
                    break
                }
            }
        }

        return CaseStatus(title: title, details: details)
    }
}

enum USCISError: LocalizedError, Equatable {
    case invalidReceiptNumber
    case parsingError
    case cloudflareBlocked
    case timeout
    case apiCredentialsMissing
    case apiAuthFailed
    case caseNotFound
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidReceiptNumber:
            return "Invalid receipt number. It should be 3 letters followed by 10 digits (e.g., EAC2190000001)."
        case .parsingError:
            return "Could not read case status. Please try again."
        case .cloudflareBlocked:
            return "USCIS is temporarily blocking automated requests. Please try again later."
        case .timeout:
            return "Request timed out. Please try again or use Open in Browser."
        case .apiCredentialsMissing:
            return "API credentials not set. Add Client ID and Secret in Settings."
        case .apiAuthFailed:
            return "API authentication failed. Check your credentials in Settings."
        case .caseNotFound:
            return "Case not found. The receipt number may be invalid or not in the system."
        case .apiError(let msg):
            return msg
        }
    }
}

extension USCISService {
    /// Parse pasted text from USCIS status page. Used when user copies from Safari.
    static func parsePastedStatus(_ text: String) -> CaseStatus? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var title = ""
        var details = ""
        let lines = trimmed.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for (i, line) in lines.enumerated() {
            if line.contains("Case Was ") || line.contains("Case Is ") || line.contains("Case Received") ||
               line.contains("Approved") || line.contains("Denied") || line.contains("Rejected") ||
               line.contains("Produced") || line.contains("Mailed") || line.contains("Delivered") ||
               line.contains("Transferred") || line.contains("Actively Reviewed") {
                title = line
                if i + 1 < lines.count {
                    details = lines[(i + 1)...].joined(separator: "\n")
                    if details.count > 800 { details = String(details.prefix(800)) }
                }
                break
            }
        }
        if title.isEmpty, let first = lines.first, first.count < 200 {
            title = first
                if lines.count > 1 {
                    let d = lines[1...].joined(separator: "\n")
                    details = String(d.prefix(800))
                }
        }
        if title.isEmpty, trimmed.contains("Case Was") || trimmed.contains("Case Is") {
            if let start = trimmed.range(of: "Case (Was|Is) ", options: .regularExpression)?.lowerBound
                ?? trimmed.range(of: "Case Was")?.lowerBound ?? trimmed.range(of: "Case Is")?.lowerBound {
                let lineEnd = trimmed[start...].range(of: "\n")?.lowerBound ?? trimmed.endIndex
                let titleEnd = trimmed.index(start, offsetBy: 150, limitedBy: lineEnd) ?? lineEnd
                title = String(trimmed[start..<titleEnd]).trimmingCharacters(in: .whitespaces)
                if titleEnd < trimmed.endIndex {
                    let restStart = trimmed[titleEnd...].firstIndex(where: { $0 != "\n" && $0 != " " }) ?? trimmed.endIndex
                    if restStart < trimmed.endIndex {
                        details = String(trimmed[restStart...].prefix(800))
                    }
                }
            }
        }
        if title.isEmpty, !trimmed.isEmpty {
            title = String(trimmed.prefix(150))
            if trimmed.count > 150 { details = String(trimmed.dropFirst(150).prefix(800)) }
        }
        guard !title.isEmpty else { return nil }
        return CaseStatus(title: title, details: details)
    }
}

struct USCISService {
    static func isValidReceiptNumber(_ number: String) -> Bool {
        let cleaned = number.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let pattern = "^[A-Z]{3}\\d{10}$"
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    static func buildStatusURL() -> URL? {
        URL(string: "https://egov.uscis.gov/casestatus/mycasestatus.do")
    }

    static func buildPOSTBody(for receiptNumber: String) -> String {
        let cleaned = receiptNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return "changeLocale=&completedActionsCurrentPage=0&upcomingActionsCurrentPage=0&appReceiptNum=\(cleaned)&caseStatusSearchBtn=CHECK+STATUS"
    }

    static let extractionJS = """
    (function() {
        var title = '';
        var details = '';
        var h1 = document.querySelector('.current-status-sec h1') || document.querySelector('.rows.text-center h1') || document.querySelector('.rows h1') || document.querySelector('div[class*="status"] h1') || document.querySelector('h1');
        if (h1) title = h1.innerText.trim();
        var p = document.querySelector('.rows.text-center p') || document.querySelector('.current-status-sec p') || document.querySelector('.rows p') || document.querySelector('div[class*="status"] p') || document.querySelector('.form-group p');
        if (p) details = p.innerText.trim();
        if (!title && !details) {
            var content = document.querySelector('.appointment-sec') || document.querySelector('.main-content') || document.querySelector('.current-status-sec') || document.querySelector('.rows') || document.querySelector('.col-lg-12') || document.querySelector('[class*="content"]');
            if (content) details = content.innerText.trim().substring(0, 800);
        }
        if (!title && details) {
            var firstLine = details.split('\\n')[0];
            if (firstLine && firstLine.length < 150) title = firstLine;
        }
        if (!title && !details && document.body) {
            var bodyText = document.body.innerText || '';
            if (bodyText.indexOf('Case Was') >= 0 || bodyText.indexOf('Case Is') >= 0 || bodyText.indexOf('Received') >= 0 || bodyText.indexOf('Approved') >= 0 || bodyText.indexOf('Denied') >= 0) {
                var lines = bodyText.trim().split(/\\n+/).filter(function(l) { return l.trim().length > 0; });
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i].trim();
                    if (line.indexOf('Case Was') >= 0 || line.indexOf('Case Is') >= 0 || line.length > 15) {
                        title = line.substring(0, 200);
                        details = lines.slice(i).join('\\n').substring(0, 800);
                        break;
                    }
                }
            }
        }
        return JSON.stringify({ title: title || '', details: details || '' });
    })();
    """

    static let cloudflareCheckJS = """
    (function() {
        var body = document.body ? document.body.innerText : '';
        var html = document.documentElement ? document.documentElement.innerHTML : '';
        var isChallenge = body.indexOf('Verify you are human') >= 0 || body.indexOf('Just a moment') >= 0 ||
            body.indexOf('Checking your browser') >= 0 || body.indexOf('cf-browser-verification') >= 0 ||
            html.indexOf('cf-browser-verification') >= 0 || body.indexOf('challenge-running') >= 0 ||
            document.querySelector('#challenge-running') !== null || document.querySelector('.cf-turnstile') !== null ||
            document.querySelector('#challenge-form') !== null || document.querySelector('#cf-wrapper') !== null;
        if (isChallenge) return 'challenge';
        return 'ready';
    })();
    """
}
