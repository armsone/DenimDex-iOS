import SwiftUI

/// "동기화되는 정보 보기" — 10장 목록과, 카드별 제외, 최소 전송 필드/보관되는 필드를 명확히 보여준다.
struct SyncDisclosureView: View {
    let items: [CollectionItem]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("함께 나누는 정보", systemImage: "arrow.up.circle")
                        .font(.subheadline.weight(.bold))
                    Text("브랜드, 모델, 추정 연대, 확인된 특징, 컨디션, 가격 범위, 통화, 국가, 기록일과 익명 식별 정보")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Label("공유하지 않는 정보", systemImage: "lock.shield")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(DenimTheme.signalRed)
                    Text("원본 사진, 이름, 이메일, 위치, ChatGPT 로그인 정보와 대화 원문")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("공유할 기록 (\(items.count)개)") {
                    ForEach(items) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayTitle.isEmpty ? "이름 없는 데님" : item.displayTitle)
                                    .font(.subheadline)
                                Text(item.formattedValueRange).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                toggle(item.id)
                            } label: {
                                Image(systemName: item.syncState == .excluded ? "circle" : "checkmark.circle.fill")
                                    .foregroundStyle(item.syncState == .excluded ? .secondary : DenimTheme.successGreen)
                            }
                            .accessibilityLabel(item.syncState == .excluded ? "제외됨, 탭하면 포함" : "포함됨, 탭하면 제외")
                        }
                    }
                }

                Section {
                    Text("이번 선택은 앞으로 추가할 기록에 자동 적용되지 않습니다. 새로운 기록 10개가 모이면 다시 확인합니다.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(DenimTheme.canvasGradient.ignoresSafeArea())
            .tint(DenimTheme.indigo)
            .navigationTitle("공유 정보")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        item.syncState = item.syncState == .excluded ? .pending : .excluded
        item.updatedAt = .now
        try? modelContext.save()
    }
}
