import SwiftUI
import SwiftData

struct CollectionItemDetailView: View {
    @Bindable var item: CollectionItem
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !item.photosData.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(item.photosData.enumerated()), id: \.offset) { _, data in
                                if let uiImage = UIImage(data: data) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 244, height: 270)
                                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    DenimEyebrow(text: "Archive Piece")
                    TextField("이름을 지어주세요", text: $item.userTitle, prompt: Text(item.displayTitle.isEmpty ? "이름 없는 데님" : item.displayTitle))
                        .font(.title2.weight(.semibold))
                        .onSubmit { save() }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.formattedValueRange)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(DenimTheme.charcoal)
                    Label(item.valueBasis.badgeText, systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .denimCard()

                VStack(spacing: 12) {
                    LabeledContent("브랜드", value: item.brandGuess.isEmpty ? "확인되지 않음" : item.brandGuess)
                    LabeledContent("모델", value: item.modelGuess.isEmpty ? "확인되지 않음" : item.modelGuess)
                    LabeledContent("추정 연대", value: item.eraGuess.isEmpty ? "확인되지 않음" : item.eraGuess)
                    LabeledContent("추정 생산연도", value: item.estimatedProductionYear.flatMap { $0.isEmpty ? nil : $0 } ?? "확인되지 않음")
                    LabeledContent("추정 제조공장", value: item.estimatedFactory.flatMap { $0.isEmpty ? nil : $0 } ?? "확인되지 않음")
                    if let variant = item.productVariant, !variant.isEmpty {
                        LabeledContent("세부 변형", value: variant)
                    }
                    LabeledContent("컨디션", value: item.condition.displayName)
                    LabeledContent("판단 신뢰도", value: item.confidence.displayName)
                    LabeledContent("기록일", value: item.createdAt.formatted(date: .abbreviated, time: .omitted))
                }
                .font(.subheadline)
                .denimCard()

                VStack(alignment: .leading, spacing: 8) {
                    Text("감정 요약")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(item.summary)
                        .font(.subheadline)
                        .foregroundStyle(DenimTheme.inkSoft)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .denimCard()

                if item.rarityLevel != .unknown || !(item.raritySummary ?? "").isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("희귀도")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Label(item.rarityLevel.displayName, systemImage: item.rarityLevel.iconName)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(DenimTheme.indigoBright)
                        }
                        if let raritySummary = item.raritySummary, !raritySummary.isEmpty {
                            Text(raritySummary)
                                .font(.subheadline)
                                .foregroundStyle(DenimTheme.inkSoft)
                        }
                        if let reasons = item.rarityReasons, !reasons.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(reasons, id: \.self) { reason in
                                    Label(reason, systemImage: "checkmark").font(.caption)
                                }
                            }
                        }
                        Text("희귀도는 AI 추정이며 객관적으로 검증된 희소성이 아닙니다.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .denimCard()
                }

                if let koreaFair = item.koreaFairPurchaseRange, let japanFair = item.japanFairPurchaseRange {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("적정 매입가")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        LabeledContent("한국", value: formattedRange(koreaFair, currencyCode: "KRW"))
                        LabeledContent("일본", value: formattedRange(japanFair, currencyCode: "JPY"))
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .denimCard()
                }

                Picker("확인 상태", selection: $item.verificationStateRaw) {
                    Text(VerificationState.aiEstimate.displayName).tag(VerificationState.aiEstimate.rawValue)
                    Text(VerificationState.userConfirmed.displayName).tag(VerificationState.userConfirmed.rawValue)
                }
                .pickerStyle(.segmented)
                .onChange(of: item.verificationStateRaw) { _, _ in
                    item.markEligibleForSyncIfNeeded()
                    save()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("나만의 메모").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextEditor(text: $item.userNotes)
                        .frame(minHeight: 90)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DenimTheme.hairline))
                        .onChange(of: item.userNotes) { _, _ in save() }
                }

                if !item.caveats.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(item.caveats, id: \.self) { caveat in
                            Text("· \(caveat)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("아카이브에서 삭제", systemImage: "trash")
                }
                .buttonStyle(.denimSecondary)
                .foregroundStyle(DenimTheme.signalRed)
            }
            .padding(.horizontal, 18)
            .safeAreaPadding(.vertical, 16)
        }
        .denimDynamicIslandFade()
        .background(DenimTheme.canvasGradient.ignoresSafeArea())
        .navigationTitle(item.displayTitle.isEmpty ? "데님 기록" : item.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("아카이브에서 삭제할까요?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("아카이브에서 삭제", role: .destructive) {
                modelContext.delete(item)
                try? modelContext.save()
                dismiss()
            }
            Button("취소", role: .cancel) {}
        }
    }

    private func save() {
        item.updatedAt = .now
        try? modelContext.save()
    }

    private func formattedRange(_ range: QuickValueResult.ValueRange, currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let low = formatter.string(from: NSNumber(value: range.low)) ?? "\(range.low)"
        let high = formatter.string(from: NSNumber(value: range.high)) ?? "\(range.high)"
        return "\(currencyCode) \(low) ~ \(high)"
    }
}
