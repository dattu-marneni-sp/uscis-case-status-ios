import Foundation

final class PersistenceService {
    static let shared = PersistenceService()
    private let casesKey = "savedCases"
    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    func saveCases(_ cases: [CaseItem]) {
        guard let data = try? encoder.encode(cases) else { return }
        defaults.set(data, forKey: casesKey)
    }

    func loadCases() -> [CaseItem] {
        guard let data = defaults.data(forKey: casesKey),
              let cases = try? decoder.decode([CaseItem].self, from: data) else {
            return []
        }
        return cases
    }
}
