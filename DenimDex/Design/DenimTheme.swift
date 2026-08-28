import SwiftUI

/// DenimDex visual language: archival denim, clean editorial space, and precise market data.
/// The palette borrows from the material—not from another product's screen or trademark.
enum DenimTheme {
    static let signalRed = Color(red: 228 / 255, green: 30 / 255, blue: 37 / 255)

    static let indigo = Color(red: 0.045, green: 0.16, blue: 0.25)
    static let indigoBright = Color(red: 0.10, green: 0.34, blue: 0.50)
    static let indigoDeep = Color(red: 0.018, green: 0.052, blue: 0.078)
    static let washedDenim = Color(red: 0.70, green: 0.79, blue: 0.82)
    static let fadedDenim = Color(red: 0.91, green: 0.925, blue: 0.925)

    static let charcoal = Color(red: 0.08, green: 0.085, blue: 0.09)
    static let inkSoft = Color(red: 0.29, green: 0.30, blue: 0.31)
    static let offWhite = Color(red: 0.95, green: 0.945, blue: 0.925)
    static let canvas = Color(red: 0.98, green: 0.978, blue: 0.965)
    static let coolBlue = indigoBright

    static let brass = Color(red: 0.60, green: 0.45, blue: 0.25)
    static let leather = Color(red: 0.36, green: 0.24, blue: 0.16)
    static let successGreen = Color(red: 0.16, green: 0.44, blue: 0.29)
    static let warningAmber = Color(red: 0.7, green: 0.47, blue: 0.13)

    static let cardSurface = Color.white
    static let hairline = Color(red: 0.08, green: 0.10, blue: 0.11).opacity(0.10)
    static let softShadow = Color(red: 0.03, green: 0.06, blue: 0.08).opacity(0.055)

    static let canvasGradient = LinearGradient(
        colors: [canvas, Color(red: 0.955, green: 0.955, blue: 0.945)],
        startPoint: .top,
        endPoint: .bottom
    )

    static let indigoGradient = LinearGradient(
        colors: [indigoDeep, indigo, Color(red: 0.06, green: 0.24, blue: 0.34)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct DenimCardModifier: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(DenimTheme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DenimTheme.hairline, lineWidth: 0.75)
            }
            .shadow(color: DenimTheme.softShadow, radius: 12, y: 5)
    }
}

extension View {
    func denimCard(padding: CGFloat = 18) -> some View {
        modifier(DenimCardModifier(padding: padding))
    }

    func denimScreenBackground() -> some View {
        background(DenimTheme.canvasGradient.ignoresSafeArea())
    }

    /// 전체 화면 스크롤 콘텐츠가 상태 표시줄·다이내믹 아일랜드 아래로 들어갈 때
    /// 갑자기 잘리지 않고 위쪽으로 갈수록 자연스럽게 사라지게 한다.
    func denimDynamicIslandFade() -> some View {
        overlay(alignment: .top) {
            // ScrollView의 시작점은 안전영역 아래다. 페이드 층을 그 위로 올려
            // 정지한 첫 콘텐츠에는 닿지 않고, 스크롤되어 상태 영역에 들어간 부분만 가린다.
            LinearGradient(
                stops: [
                    .init(color: DenimTheme.canvas, location: 0),
                    .init(color: DenimTheme.canvas.opacity(0.96), location: 0.34),
                    .init(color: DenimTheme.canvas.opacity(0.55), location: 0.68),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 58)
            .offset(y: -58)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

struct DenimPrimaryButtonStyle: ButtonStyle {
    var isDisabled = false
    @Environment(\.isEnabled) private var isEnabled

    private var active: Bool { isEnabled && !isDisabled }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background {
                if !active {
                    Color.gray.opacity(0.38)
                } else {
                    DenimTheme.indigoGradient
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: active ? DenimTheme.indigo.opacity(0.18) : .clear, radius: 10, y: 5)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct DenimSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DenimTheme.indigoDeep)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DenimTheme.hairline, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.68 : 1)
    }
}

struct DenimEyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(2.1)
            .foregroundStyle(DenimTheme.brass)
    }
}

struct DenimSectionTitle: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(DenimTheme.charcoal)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension ButtonStyle where Self == DenimPrimaryButtonStyle {
    static var denimPrimary: DenimPrimaryButtonStyle { DenimPrimaryButtonStyle() }
}

extension ButtonStyle where Self == DenimSecondaryButtonStyle {
    static var denimSecondary: DenimSecondaryButtonStyle { DenimSecondaryButtonStyle() }
}
