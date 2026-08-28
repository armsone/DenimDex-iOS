import Foundation

/// 기술서 11.5절 NAS 최소 서비스 계약. 실제 NAS 엔드포인트가 아직 없으므로
/// 이 프로토콜은 앱 어디에서도 성공을 가장하지 않고, 활성화된 구현만 통신을 시도한다.
protocol DenimDexSyncClient {
    func uploadContributions(_ bundles: [ContributionBundle]) async throws -> SyncUploadReceipt
    func fetchLatestManifest() async throws -> ArchiveManifest
}

struct ContributionBundle: Codable {
    var schemaVersion: Int = 1
    var anonymousContributorKey: String
    var normalizedBrand: String
    var normalizedModel: String
    var normalizedEra: String
    var observedFeatures: [String]
    var condition: String
    var currency: String
    var valueLow: Int
    var valueHigh: Int
    var country: String
    var observedAt: Date
    var aiProvider: String
    var promptVersion: String
    var contentFingerprint: String
}

struct SyncUploadReceipt: Codable {
    var acceptedCount: Int
    var archiveVersion: String
}

struct ArchiveManifest: Codable {
    var version: String
    var sizeBytes: Int
    var sha256: String
}

enum SyncClientError: LocalizedError {
    case notConfigured

    var errorDescription: String? {
        "아직 NAS 주소가 설정되지 않아 동기화를 진행할 수 없습니다."
    }
}

/// NAS 주소가 없는 기본 상태. 절대 성공을 흉내 내지 않고 항상 명확한 오류를 던진다.
struct DisabledDenimDexSyncClient: DenimDexSyncClient {
    func uploadContributions(_ bundles: [ContributionBundle]) async throws -> SyncUploadReceipt {
        throw SyncClientError.notConfigured
    }

    func fetchLatestManifest() async throws -> ArchiveManifest {
        throw SyncClientError.notConfigured
    }
}
