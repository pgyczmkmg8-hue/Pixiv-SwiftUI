import Foundation

/// 应用级别的错误类型
enum AppError: LocalizedError {
    case networkError(String)
    case databaseError(String)
    case decodingError(String)
    case authenticationError(String)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return "네트워크 오류: \(message)"
        case .databaseError(let message):
            return "데이터베이스 오류: \(message)"
        case .decodingError(let message):
            return "데이터 파싱 오류: \(message)"
        case .authenticationError(let message):
            return "인증 오류: \(message)"
        case .unknown(let error):
            return "알 수 없는 오류: \(error.localizedDescription)"
        }
    }
}
