import Foundation

/// 가치 확인의 호스트 소유 90초 타임아웃 표시용 결정적 포맷터.
/// AIBI 엔진의 내부 타이밍과 별개로, `1:30 → 0:00` 카운트다운과
/// 진행 바 값을 계산한다.
enum CountdownFormatter {
    static let quickValueTimeoutSeconds = 90

    static func remainingSeconds(elapsed: TimeInterval, totalSeconds: Int = quickValueTimeoutSeconds) -> Int {
        max(0, totalSeconds - Int(elapsed.rounded(.down)))
    }

    static func formatMinutesSeconds(_ totalSeconds: Int) -> String {
        let clamped = max(0, totalSeconds)
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }

    /// 1.0(가득 참) → 0.0(소진) 진행 바 값.
    static func progressFraction(elapsed: TimeInterval, totalSeconds: Int = quickValueTimeoutSeconds) -> Double {
        guard totalSeconds > 0 else { return 0 }
        let remaining = Double(remainingSeconds(elapsed: elapsed, totalSeconds: totalSeconds))
        return min(1, max(0, remaining / Double(totalSeconds)))
    }

    static func isExpired(elapsed: TimeInterval, totalSeconds: Int = quickValueTimeoutSeconds) -> Bool {
        elapsed >= TimeInterval(totalSeconds)
    }
}
