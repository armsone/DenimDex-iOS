import SwiftUI

/// 촬영법·상태 기준·신뢰도 설명. 기술서 7·9·10장에서 실제로 정의한 내용만 담고,
/// 검증되지 않은 제품 사실은 넣지 않는다.
struct LearnView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        DenimEyebrow(text: "Field Guide")
                            .foregroundStyle(DenimTheme.washedDenim)
                        Text("디테일을 기록하는\n가장 좋은 방법")
                            .font(.system(size: 30, weight: .semibold, design: .default))
                            .foregroundStyle(.white)
                            .tracking(-0.8)
                        Text("더 정교한 감정을 위한 데님 촬영 가이드")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DenimTheme.indigoGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                    section(title: "사진은 몇 장이 좋을까요?", icon: "camera.fill") {
                        Text("한 장으로도 시작할 수 있지만, 전체 모습과 주요 디테일을 함께 담으면 판단이 더 정교해집니다. 최대 30장을 담으면 한양이 비슷한 사진을 정리해 선명한 사진만 분석합니다. 원본은 그대로 보관됩니다.")
                    }

                    section(title: "가치를 잘 보여주는 촬영법", icon: "checkmark.circle.fill") {
                        VStack(alignment: .leading, spacing: 10) {
                            tip("전체 실루엣", "밝은 곳에서 제품 전체가 프레임 안에 들어오도록 정면에서 담아주세요.")
                            tip("레드탭과 패치", "글자와 색이 선명하게 보이도록 초점을 맞춰 가까이 담아주세요.")
                            tip("버튼과 리벳", "각인에 그림자가 생기지 않도록 각도를 조금 바꿔보세요.")
                            tip("케어 라벨", "라벨을 부드럽게 펴고 글자가 또렷하게 보이도록 촬영해주세요.")
                        }
                    }

                    section(title: "확인하면 좋은 디테일", icon: "tag.fill") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(EvidencePhotoRole.allCases) { role in
                                Text("· \(role.displayName)")
                                    .font(.footnote)
                            }
                        }
                    }

                    section(title: "컨디션 기준", icon: "gauge.with.dots.needle.50percent") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(QuickValueCondition.allCases, id: \.self) { condition in
                                if condition != .unknown {
                                    Text("· \(condition.displayName)")
                                        .font(.footnote)
                                }
                            }
                        }
                    }

                    section(title: "판단 신뢰도", icon: "gauge.medium") {
                        Text("사진에서 확인된 특징이 많고 서로 일치할수록 신뢰도가 높아집니다. 정보가 부족하거나 특징이 모호할 때는 제품을 단정하지 않고, 판단에 도움이 될 다음 사진을 안내합니다.")
                    }

                    section(title: "두 가지 가치 기준", icon: "wonsign.circle.fill") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("빠른 AI 추정 · 사진 속 특징과 일반 시장 지식을 바탕으로 빠르게 살펴보는 가격 범위입니다.")
                                .font(.footnote)
                            Text("근거 조사 · 날짜와 출처가 확인되는 거래 사례를 중심으로 살펴보는 방식입니다. 현재 준비 중입니다.")
                                .font(.footnote)
                        }
                    }

                    section(title: "이용 전 확인해주세요", icon: "info.circle.fill") {
                        Text("DenimDex의 결과는 정품 인증서나 공식 감정서가 아닙니다. 사진에서 확인한 특징과 시장 가치의 추정 범위를 제공하는 참고 자료입니다.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 18)
                .safeAreaPadding(.vertical, 16)
            }
            .denimDynamicIslandFade()
            .background(DenimTheme.canvasGradient.ignoresSafeArea())
            .navigationTitle("감정 가이드")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    @ViewBuilder
    private func section(title: String, icon: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(DenimTheme.indigo)
                    .frame(width: 34, height: 34)
                    .background(DenimTheme.fadedDenim)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(title)
                    .font(.headline)
                    .foregroundStyle(DenimTheme.charcoal)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .denimCard()
    }

    private func tip(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.footnote.weight(.semibold))
            Text(body).font(.caption).foregroundStyle(.secondary)
        }
    }
}
