import SwiftUI

/// 기술서 13.3절 결과 화면 원칙을 반영한 가치 카드(V2).
/// 한국·일본 두 시장 카드를 가장 먼저, 각각 예상 판매가와 예상 순수익을 함께 보여준다.
/// 가격 산술은 전부 `MarketValueCalculator`(호스트 결정론적 계산)의 결과이며 AI가 계산하지 않는다.
struct QuickValueResultCard: View {
    let result: QuickValueResult
    var onSave: () -> Void
    var onAddRequestedPhoto: () -> Void
    var onStartOver: () -> Void

    @State private var didSave = false

    private var confidence: QuickValueConfidence { QuickValueConfidence(rawValue: result.confidence) ?? .unknown }
    private var condition: QuickValueCondition { QuickValueCondition(rawValue: result.condition) ?? .unknown }

    private var koreaNet: QuickValueResult.ValueRange {
        MarketValueCalculator.koreaNetProceeds(saleRange: result.koreaSaleRange)
    }
    private var japanNet: QuickValueResult.ValueRange {
        MarketValueCalculator.japanNetProceeds(saleRange: result.japanSaleRange)
    }
    private var crossMarket: CrossMarketComparison {
        MarketValueCalculator.crossMarketComparison(
            korea: result.koreaSaleRange,
            japan: result.japanSaleRange,
            jpyToKrwRate: result.jpyToKrwRate
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                DenimEyebrow(text: "Valuation Report")
                Spacer()
                Label(confidence.displayName, systemImage: confidence.iconName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(confidenceColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(confidenceColor.opacity(0.10))
                    .clipShape(Capsule())
                    .accessibilityLabel("판단 신뢰도 \(confidence.displayName)")
            }

            VStack(alignment: .leading, spacing: 5) {
                Text([result.productGuess.brand, result.productGuess.model].filter { !$0.isEmpty }.joined(separator: " "))
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(DenimTheme.charcoal)
                if !result.productGuess.era.isEmpty {
                    Text(result.productGuess.era)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DenimTheme.indigoBright)
                }
                Text(result.summary)
                    .font(.subheadline)
                    .foregroundStyle(DenimTheme.inkSoft)
                    .padding(.top, 3)
            }

            marketCardsRow

            HStack {
                Text("컨디션")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(condition.displayName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DenimTheme.charcoal)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(DenimTheme.fadedDenim)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if !result.valueReasons.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("가치를 만든 디테일")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(result.valueReasons, id: \.self) { reason in
                        Label(reason, systemImage: "checkmark").font(.caption)
                    }
                }
            }

            crossMarketSection

            disclaimerSection

            if !result.caveats.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(result.caveats, id: \.self) { caveat in
                        Text("· \(caveat)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            VStack(spacing: 10) {
                Button {
                    onSave()
                    didSave = true
                } label: {
                    Label(didSave ? "보관 완료" : "내 아카이브에 보관", systemImage: didSave ? "checkmark" : "square.and.arrow.down")
                }
                .buttonStyle(.denimPrimary)
                .disabled(didSave)

                if let instruction = result.nextPhotoInstruction, !instruction.isEmpty {
                    Button {
                        onAddRequestedPhoto()
                    } label: {
                        Label(instruction, systemImage: "camera.badge.ellipsis")
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.denimSecondary)
                }

                Button("새로 감정하기") { onStartOver() }
                    .buttonStyle(.denimSecondary)

                Text("거래 근거를 더하는 정밀 조사는 준비 중입니다.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .denimCard(padding: 20)
    }

    // MARK: - Market cards

    private var marketCardsRow: some View {
        HStack(spacing: 10) {
            marketCard(
                title: "한국",
                tint: DenimTheme.indigo,
                saleRange: result.koreaSaleRange,
                netRange: koreaNet,
                currencyCode: "KRW"
            )
            marketCard(
                title: "일본",
                tint: DenimTheme.coolBlue,
                saleRange: result.japanSaleRange,
                netRange: japanNet,
                currencyCode: "JPY"
            )
        }
    }

    private func marketCard(title: String, tint: Color, saleRange: QuickValueResult.ValueRange, netRange: QuickValueResult.ValueRange, currencyCode: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                Spacer()
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
            }

            Text(formattedRange(saleRange, currencyCode: currencyCode))
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(DenimTheme.charcoal)
                .minimumScaleFactor(0.7)
                .lineLimit(2)
            Text("판매가 추정")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Rectangle()
                .fill(tint.opacity(0.15))
                .frame(height: 1)

            Text(formattedRange(netRange, currencyCode: currencyCode))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DenimTheme.successGreen)
                .minimumScaleFactor(0.7)
                .lineLimit(2)
            Text("순수익 추정")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.075))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.14), lineWidth: 1)
        }
    }

    // MARK: - Cross-market section

    private var crossMarketSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DenimSectionTitle(title: "시장별 판매 기회")
                .foregroundStyle(DenimTheme.charcoal)

            marginRow(title: "일본 구매 → 한국 판매", range: crossMarket.japanToKorea)
            marginRow(title: "한국 구매 → 일본 판매", range: crossMarket.koreaToJapan)

            Text(recommendationText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(recommendationColor)

            Text("국제 배송비 30,000원과 판매 수수료 10%를 반영한 추정입니다. 관세·세금·환전 수수료·반품·환율 변동은 포함되지 않습니다.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(DenimTheme.fadedDenim.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func marginRow(title: String, range: QuickValueResult.ValueRange) -> some View {
        HStack {
            Text(title).font(.caption.weight(.medium))
            Spacer()
            Text(formattedRange(range, currencyCode: "KRW"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(range.low >= 0 ? DenimTheme.successGreen : DenimTheme.signalRed)
        }
    }

    private var recommendationText: String {
        switch crossMarket.recommendation {
        case .japanToKorea: "일본에서 매입해 한국에서 판매하는 편이 유리합니다."
        case .koreaToJapan: "한국에서 매입해 일본에서 판매하는 편이 유리합니다."
        case .noClearAdvantage: "현재 추정으로는 뚜렷하게 유리한 시장이 없습니다."
        }
    }

    private var recommendationColor: Color {
        crossMarket.recommendation == .noClearAdvantage ? .secondary : DenimTheme.successGreen
    }

    // MARK: - Disclaimer

    private var disclaimerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("현재 가격은 실시간 거래 자료가 아닌 AI 기반 추정치입니다.", systemImage: "exclamationmark.triangle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DenimTheme.signalRed)
            Text("한국: 판매 수수료 10%와 국내 배송비 5,000원 반영")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("일본: 판매 수수료 10%와 국내 배송비 1,000엔 반영")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("적용 환율: 1엔 ≈ \(formattedRate)원")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(DenimTheme.signalRed.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Formatting

    private func formattedRange(_ range: QuickValueResult.ValueRange, currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let low = formatter.string(from: NSNumber(value: range.low)) ?? "\(range.low)"
        let high = formatter.string(from: NSNumber(value: range.high)) ?? "\(range.high)"
        return "\(currencyCode) \(low) ~ \(high)"
    }

    private var formattedRate: String {
        String(format: "%.2f", result.jpyToKrwRate)
    }

    private var confidenceColor: Color {
        switch confidence {
        case .high: DenimTheme.successGreen
        case .medium: DenimTheme.brass
        case .low, .unknown: DenimTheme.signalRed
        }
    }
}
