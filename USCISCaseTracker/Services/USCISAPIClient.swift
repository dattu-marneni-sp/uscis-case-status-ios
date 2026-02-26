import Foundation

/// Client for USCIS Torch Case Status API (OAuth 2.0 + REST).
/// Sandbox: api-int.uscis.gov | Production: api.uscis.gov
struct USCISAPIClient {
    private static let sandboxBase = "https://api-int.uscis.gov"
    private static let productionBase = "https://api.uscis.gov"

    private static var baseURL: String {
        KeychainService.useProduction ? productionBase : sandboxBase
    }

    private static var oauthURL: URL {
        URL(string: "\(baseURL)/oauth/accesstoken")!
    }
    private static var cachedToken: (token: String, expiresAt: Date)?

    /// Fetch case status via official USCIS API. Requires Client ID and Secret in Keychain.
    static func fetchStatus(receiptNumber: String) async throws -> CaseStatus {
        let receipt = receiptNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard USCISService.isValidReceiptNumber(receipt) else {
            throw USCISError.invalidReceiptNumber
        }
        let clientId = KeychainService.clientId?.trimmingCharacters(in: .whitespaces)
            ?? "destrw1MGVEnAm06PeijcWOAhc9bbAPW"
        let clientSecret = KeychainService.clientSecret?.trimmingCharacters(in: .whitespaces)
            ?? "NhFGmjUBcM4aJSTp"
        guard !clientId.isEmpty, !clientSecret.isEmpty else {
            throw USCISError.apiCredentialsMissing
        }

        let token = try await getAccessToken(clientId: clientId, clientSecret: clientSecret)
        return try await fetchCaseStatus(receiptNumber: receipt, token: token)
    }

    private static func getAccessToken(clientId: String, clientSecret: String) async throws -> String {
        if let cached = cachedToken, cached.expiresAt > Date().addingTimeInterval(60) {
            return cached.token
        }

        var request = URLRequest(url: oauthURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "grant_type=client_credentials&client_id=\(clientId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clientId)&client_secret=\(clientSecret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clientSecret)".data(using: .utf8)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw USCISError.parsingError
        }
        guard http.statusCode == 200 else {
            throw USCISError.apiAuthFailed
        }

        struct OAuthResponse: Decodable {
            let access_token: String
            let expires_in: String?
        }
        let oauth = try JSONDecoder().decode(OAuthResponse.self, from: data)
        let expiresIn = Double(oauth.expires_in ?? "1799") ?? 1799
        cachedToken = (oauth.access_token, Date().addingTimeInterval(expiresIn))
        return oauth.access_token
    }

    private static func fetchCaseStatus(receiptNumber: String, token: String) async throws -> CaseStatus {
        guard let url = URL(string: "\(baseURL)/case-status/\(receiptNumber)") else {
            throw USCISError.parsingError
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw USCISError.parsingError
        }
        if http.statusCode == 401 {
            cachedToken = nil
            throw USCISError.apiAuthFailed
        }
        if http.statusCode == 404 {
            throw USCISError.caseNotFound
        }
        guard http.statusCode == 200 else {
            throw parseAPIError(data: data, statusCode: http.statusCode)
        }

        // Check for error object (e.g. sandbox unavailable)
        if let apiError = parseErrorObject(data: data) {
            throw apiError
        }

        struct CaseStatusResponse: Decodable {
            let case_status: CaseStatusPayload?
            let caseStatus: CaseStatusPayload?
            let errors: [APIErrorItem]?
        }
        struct CaseStatusPayload: Decodable {
            let current_case_status_text_en: String?
            let current_case_status_desc_en: String?
            let currentCaseStatusTextEn: String?
            let currentCaseStatusDescEn: String?
        }
        struct APIErrorItem: Decodable {
            let message: String?
        }
        let decoded = try JSONDecoder().decode(CaseStatusResponse.self, from: data)
        let cs = decoded.case_status ?? decoded.caseStatus
        if let errs = decoded.errors, let msg = errs.first?.message, !msg.isEmpty {
            throw USCISError.apiError(msg)
        }
        guard let cs = cs else {
            if let apiError = parseErrorObject(data: data) {
                throw apiError
            }
            throw USCISError.parsingError
        }
        let title = cs.current_case_status_text_en ?? cs.currentCaseStatusTextEn ?? ""
        let details = cs.current_case_status_desc_en ?? cs.currentCaseStatusDescEn ?? ""
        return CaseStatus(title: title, details: details)
    }

    private static func parseAPIError(data: Data, statusCode: Int) -> USCISError {
        if let err = parseErrorObject(data: data) { return err }
        struct ErrorResponse: Decodable {
            let errors: [APIErrorItem]?
        }
        struct APIErrorItem: Decodable {
            let message: String?
        }
        if let decoded = try? JSONDecoder().decode(ErrorResponse.self, from: data),
           let msg = decoded.errors?.first?.message, !msg.isEmpty {
            return .apiError(msg)
        }
        return .parsingError
    }

    /// Parse "error": { "code": "...", "message": "..." } format
    private static func parseErrorObject(data: Data) -> USCISError? {
        struct ErrorObj: Decodable {
            let error: ErrorPayload?
        }
        struct ErrorPayload: Decodable {
            let message: String?
        }
        guard let decoded = try? JSONDecoder().decode(ErrorObj.self, from: data),
              let msg = decoded.error?.message, !msg.isEmpty else {
            return nil
        }
        return .apiError(msg)
    }
}
