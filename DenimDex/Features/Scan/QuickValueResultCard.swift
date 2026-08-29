import SwiftUI

/// 기술서 13.3절 결과 화면 원칙을 반영한 가치 카드(V3).
/// "한눈에 보는 결론 → 제품 정보 → 희귀도 → 적정 금액" 순서로 정보를 배치해, 무엇인지·얼마나
/// 희귀한지·얼마에 사는 게 합리적인지를 위에서부터 순서대로 답한다.
/// 가격 산술은 전부 `MarketValueCalculator`(호스트 결정론적 계산)의 결과이며 AI가 계산하지 않는다.
struct QuickValueResultCard: View {
    let result: QuickValueResult
    var onSave: () -> Void
    var onAddRequestedPhoto: () -> Void
    var onStartOver: () -> Void

    @State private var didSave = false

    private var confidence: QuickValueConfidence { QuickValueConfidence(rawValue: result.confidence) ?? .unknown }
    private var condition: QuickValueCondition { QuickValueCondition(rawValue: result.condition) ?? .unknown }
    private var rarity: QuickValueRarity { QuickValueRarity(rawValue: result.rarityLevel) ?? .unknown }

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

    private var productTitle: String {
        [result.productGuess.brand, result.productGuess.model].filter { !$0.isEmpty }.joined(separator: " ")
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

            conclusionSection
            productInfoSection
            raritySection
            fairAmountSection

            if !result.caveats.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(result.caveats, id: \.self) { caveat in
                        Text("· \(caveat)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            actionSection
        }
        .denimCard(padding: 20)
    }

    // MARK: - 1. 한눈에 보는 결론

    private var conclusionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DenimSectionTitle(title: "한눈에 보는 결론")
                .foregroundStyle(DenimTheme.charcoal)

            Text(productTitle.isEmpty ? "제품을 특정하기 어려움" : productTitle)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(DenimTheme.charcoal)
            Text(result.summary)
                .font(.subheadline)
                .foregroundStyle(DenimTheme.inkSoft)

            HStack(spacing: 8) {
                Label(rarity.displayName, systemImage: rarity.iconName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(rarityColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(rarityColor.opacity(0.10))
                    .clipShape(Capsule())
                Spacer()
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("적정 매입가 스냅샷")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("한국 \(formattedRange(result.koreaFairPurchaseRange, currencyCode: "KRW")) · 일본 \(formattedRange(result.japanFairPurchaseRange, currencyCode: "JPY"))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DenimTheme.charcoal)
                    .minimumScaleFactor(0.7)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DenimTheme.fadedDenim)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - 2. 제품 정보

    private var productInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DenimSectionTitle(title: "제품 정보")
                .foregroundStyle(DenimTheme.charcoal)

            VStack(spacing: 0) {
                infoRow(label: "브랜드", value: result.productGuess.brand)
                infoDivider
                infoRow(label: "모델", value: result.productGuess.model)
                infoDivider
                infoRow(label: "추정 연대", value: result.productGuess.era)
                infoDivider
                infoRow(label: "추정 생산연도", value: result.productGuess.estimatedProductionYear)
                infoDivider
                infoRow(label: "추정 제조공장", value: result.productGuess.estimatedFactory)
                if !result.productGuess.variant.isEmpty {
                    infoDivider
                    infoRow(label: "세부 변형", value: result.productGuess.variant)
                }
                infoDivider
                infoRow(label: "컨디션", value: condition.displayName)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(DenimTheme.fadedDenim)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value.isEmpty ? "확인되지 않음" : value)
                .font(.caption.weight(.bold))
                .foregroundStyle(DenimTheme.charcoal)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 9)
    }

    private var infoDivider: some View {
        Rectangle().fill(DenimTheme.hairline).frame(height: 1)
    }

    // MARK: - 3. 희귀도

    private var raritySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            DenimSectionTitle(title: "희귀도")
                .foregroundStyle(DenimTheme.charcoal)

            if !result.raritySummary.isEmpty {
                Text(result.raritySummary)
                    .font(.subheadline)
                    .foregroundStyle(DenimTheme.inkSoft)
            }

            if !result.rarityReasons.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(result.rarityReasons, id: \.self) { reason in
                        Label(reason, systemImage: "checkmark").font(.caption)
                    }
                }
            }

            Text("희귀도는 AI 추정이며 객관적으로 검증된 희소성이 아닙니다.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 4. 적정 금액

    private var fairAmountSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            DenimSectionTitle(title: "적정 금액")
                .foregroundStyle(DenimTheme.charcoal)

            marketCardsRow

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
        }
    }

    private var marketCardsRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 10) {
                marketCard(title: "한국", tint: DenimTheme.indigo, currencyCode: "KRW", fairPurchaseRange: result.koreaFairPurchaseRange, saleRange: result.koreaSaleRange, netRange: koreaNet)
                marketCard(title: "일본", tint: DenimTheme.coolBlue, currencyCode: "JPY", fairPurchaseRange: result.japanFairPurchaseRange, saleRange: result.japanSaleRange, netRange: japanNet)
            }
            VStack(spacing: 10) {
                marketCard(title: "한국", tint: DenimTheme.indigo, currencyCode: "KRW", fairPurchaseRange: result.koreaFairPurchaseRange, saleRange: result.koreaSaleRange, netRange: koreaNet)
                marketCard(title: "일본", tint: DenimTheme.coolBlue, currencyCode: "JPY", fairPurchaseRange: result.japanFairPurchaseRange, saleRange: result.japanSaleRange, netRange: japanNet)
            }
        }
    }

    private func marketCard(
        title: String,
        tint: Color,
        currencyCode: String,
        fairPurchaseRange: QuickValueResult.ValueRange,
        saleRange: QuickValueResult.ValueRange,
        netRange: QuickValueResult.ValueRange
    ) -> some View {
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

            amountRow(label: "적정 매입가", range: fairPurchaseRange, currencyCode: currencyCode, valueColor: DenimTheme.charcoal)

            Rectangle().fill(tint.opacity(0.15)).frame(height: 1)

            amountRow(label: "예상 판매가", range: saleRange, currencyCode: currencyCode, valueColor: DenimTheme.charcoal)

            Rectangle().fill(tint.opacity(0.15)).frame(height: 1)

            amountRow(label: "순수익 추정", range: netRange, currencyCode: currencyCode, valueColor: DenimTheme.successGreen)
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

    private func amountRow(label: String, range: QuickValueResult.ValueRange, currencyCode: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(formattedRange(range, currencyCode: currencyCode))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(valueColor)
                .minimumScaleFactor(0.7)
                .lineLimit(2)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
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

    // MARK: - Actions

    private var actionSection: some View {
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

    private var rarityColor: Color {
        switch rarity {
        case .unknown: DenimTheme.inkSoft
        case .common: DenimTheme.inkSoft
        case .uncommon: DenimTheme.brass
        case .rare, .extremelyRare: DenimTheme.indigoBright
        }
    }
}
