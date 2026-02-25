import Foundation

struct CaseItem: Identifiable, Codable {
    let id: UUID
    var receiptNumber: String
    var nickname: String
    var status: CaseStatus?
    var lastRefreshed: Date?
    var isLoading: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, receiptNumber, nickname, status, lastRefreshed
    }

    init(id: UUID = UUID(), receiptNumber: String, nickname: String = "", status: CaseStatus? = nil, lastRefreshed: Date? = nil) {
        self.id = id
        self.receiptNumber = receiptNumber
        self.nickname = nickname
        self.status = status
        self.lastRefreshed = lastRefreshed
    }
}

struct CaseStatus: Codable, Equatable {
    let title: String
    let details: String
}
