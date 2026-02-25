import Foundation

enum USCISError: LocalizedError {
    case invalidReceiptNumber
    case parsingError

    var errorDescription: String? {
        switch self {
        case .invalidReceiptNumber:
            return "Invalid receipt number. It should be 3 letters followed by 10 digits (e.g., EAC2190000001)."
        case .parsingError:
            return "Could not read case status from the page. Try refreshing."
        }
    }
}

struct USCISService {
    static func isValidReceiptNumber(_ number: String) -> Bool {
        let cleaned = number.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let pattern = "^[A-Z]{3}\\d{10}$"
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    static func buildStatusURL(for receiptNumber: String) -> URL? {
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

        var h1 = document.querySelector('.current-status-sec h1') || document.querySelector('h1');
        if (h1) title = h1.innerText.trim();

        var p = document.querySelector('.rows.text-center p');
        if (p) details = p.innerText.trim();

        if (!title && !details) {
            var content = document.querySelector('.appointment-sec') || document.querySelector('.main-content');
            if (content) details = content.innerText.trim().substring(0, 500);
        }

        return JSON.stringify({
            title: title || '',
            details: details || ''
        });
    })();
    """

    static let cloudflareCheckJS = """
    (function() {
        var body = document.body ? document.body.innerText : '';
        var isChallenge = body.indexOf('Verify you are human') >= 0
            || body.indexOf('Just a moment') >= 0
            || body.indexOf('cf-browser-verification') >= 0
            || document.querySelector('#challenge-running') !== null
            || document.querySelector('.cf-turnstile') !== null;
        return isChallenge ? 'challenge' : 'ready';
    })();
    """
}
