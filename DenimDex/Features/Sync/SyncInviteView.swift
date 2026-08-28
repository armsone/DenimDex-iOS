import SwiftUI
import SwiftData

/// 기술서 11.4절에 정의된 정확한 문구와 버튼 순서.
struct SyncInviteView: View {
    let pendingCount: Int
    var onDismissed: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CollectionItem.createdAt, order: .reverse) private var items: [CollectionItem]
    @State private var showDisclosure = false
    @State private var syncOutcome: SyncOutcome?

    private var pendingItems: [CollectionItem] {
        items.filter { $0.syncState == .pending }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(DenimTheme.indigoGradient)
                        .frame(width: 104, height: 104)
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(.white)
                }
                .padding(.top, 12)

                DenimEyebrow(text: "Shared Archive")

                Text("아카이브를 확장할까요?")
                    .font(.title.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text("다른 컬렉터의 기록으로 내 아카이브를 넓히고,\n내 기록도 익명으로 함께 나눕니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let syncOutcome {
                    Text(syncOutcome.message)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(syncOutcome.isError ? DenimTheme.signalRed : DenimTheme.successGreen)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }

                VStack(spacing: 10) {
                    Button("지금 확장하기") { runSync() }
                        .buttonStyle(.denimPrimary)

                    Button("나중에") {
                        onDismissed()
                        dismiss()
                    }
                    .buttonStyle(.denimSecondary)

                    Button("공유되는 정보 확인") { showDisclosure = true }
                        .font(.footnote)
                        .foregroundStyle(DenimTheme.indigo)
                }
                .padding(.top, 8)

                Spacer()
            }
            .padding(.horizontal, 24)
            .safeAreaPadding(.vertical, 20)
            .background(DenimTheme.canvasGradient.ignoresSafeArea())
            .sheet(isPresented: $showDisclosure) {
                SyncDisclosureView(items: pendingItems)
            }
        }
    }

    private func runSync() {
        Task {
            let client: DenimDexSyncClient = DisabledDenimDexSyncClient()
            do {
                let bundles = pendingItems.map { $0.contributionBundle() }
                _ = try await client.uploadContributions(bundles)
                syncOutcome = SyncOutcome(message: "아카이브가 새롭게 확장되었어요.", isError: false)
            } catch {
                // 실제로 성공하지 않았다면 절대 성공한 척하지 않는다.
                syncOutcome = SyncOutcome(message: error.localizedDescription, isError: true)
            }
        }
    }
}

private struct SyncOutcome {
    let message: String
    let isError: Bool
}

private extension CollectionItem {
    func contributionBundle() -> ContributionBundle {
        ContributionBundle(
            anonymousContributorKey: id.uuidString,
            normalizedBrand: brandGuess,
            normalizedModel: modelGuess,
            normalizedEra: eraGuess,
            observedFeatures: [],
            condition: conditionRaw,
            currency: currency,
            valueLow: valueLow,
            valueHigh: valueHigh,
            country: "KR",
            observedAt: createdAt,
            aiProvider: "chatgpt",
            promptVersion: "quick_value.v1",
            contentFingerprint: id.uuidString
        )
    }
}
