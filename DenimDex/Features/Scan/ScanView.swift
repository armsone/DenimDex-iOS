import SwiftUI
import PhotosUI
import SwiftData
import UniformTypeIdentifiers

struct ScanView: View {
    @AppStorage(DenimDexSettingsKeys.didAcknowledgeAITransfer) private var didAcknowledgeAITransfer = false
    @Environment(\.modelContext) private var modelContext

    @StateObject private var hiddenHost = AIBIHiddenContainerHost()
    @StateObject private var runner = QuickValueRunner()
    @StateObject private var loginStore = AIBILoginStatusStore()

    @State private var photos: [Data] = []
    @State private var libraryPickerItems: [PhotosPickerItem] = []
    @State private var libraryLoadTask: Task<Void, Never>?
    @State private var libraryLoadID = UUID()
    @State private var isLoadingPhotos = false
    @State private var isCameraPresented = false
    @State private var showAITransferNotice = false
    @State private var showPhotoSaveIssue = false
    @State private var showLoginSheet = false
    @State private var shouldAnalyzeAfterLogin = false
    @State private var showClearAllConfirmation = false
    @State private var draggedPhotoIndex: Int?

    private var readyToAnalyze: Bool { !photos.isEmpty && !isLoadingPhotos }
    private var canAddMorePhotos: Bool { photos.count < QuickValueImagePolicy.captureMaximumCount }
    private var remainingLibrarySlots: Int { max(0, QuickValueImagePolicy.captureMaximumCount - photos.count) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header

                    photoCollector

                    Button {
                        requestValueAnalysis()
                    } label: {
                        Label("가치 확인하기", systemImage: "sparkles")
                    }
                    .buttonStyle(.denimPrimary)
                    .disabled(!readyToAnalyze || runner.state == .running)
                    .accessibilityHint("사진을 ChatGPT로 보내 한국·일본 가격 범위를 확인합니다")

                    if !readyToAnalyze {
                        Text("사진 한 장부터 시작할 수 있어요. 원본은 30장까지 담고, 가장 선명한 사진을 골라 분석합니다.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if runner.state == .running, !runner.session.isVisibleBrowserPresented {
                        runningPanel
                    }

                    if case .succeeded(let result, let rawJSON) = runner.state {
                        QuickValueResultCard(
                            result: result,
                            onSave: { saveToCollection(result: result, rawJSON: rawJSON) },
                            onAddRequestedPhoto: { runner.reset() },
                            onStartOver: { runner.reset() }
                        )
                    }

                    if case .failed(let message) = runner.state {
                        errorPanel(message: message, retryLabel: "다시 시도")
                    }
                    if runner.state == .timedOut {
                        errorPanel(message: "분석이 예상보다 오래 걸리고 있어요. 잠시 후 다시 시도해주세요.", retryLabel: "다시 시도")
                    }
                }
                .padding(.horizontal, 18)
            }
            // 스크롤 영역 자체를 상·하 안전영역에서 같은 거리만큼 안쪽으로 둔다.
            // 따라서 스크롤 중에도 다이내믹 아일랜드나 하단 홈/탭 영역과 겹치지 않는다.
            .safeAreaPadding(.vertical, 16)
            .denimDynamicIslandFade()
            .background(DenimTheme.canvasGradient.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .background(
                AIBIHiddenContainerRepresentable(host: hiddenHost)
                    // AIBI hidden mode still requires a real, attached viewport.
                    // A zero-sized parent prevents WebKit attachment previews from rendering.
                    .frame(width: 375, height: 667)
                    .offset(x: -10_000, y: -10_000)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            )
            .background(AIBILoginStatusProbeView(store: loginStore))
            .sheet(isPresented: Binding(
                get: { runner.session.isVisibleBrowserPresented },
                set: { presented in
                    // 성공 후 세션이 시트를 닫을 때 결과 상태를 cancel로 덮어쓰지 않는다.
                    // 사용자가 실제로 열려 있는 시트를 직접 내린 경우에만 취소한다.
                    if !presented && runner.session.isVisibleBrowserPresented {
                        runner.cancel()
                    }
                }
            )) {
                AIBIVisibleBrowserSheet(
                    session: runner.session,
                    providerDisplayName: "ChatGPT",
                    onCancel: { runner.cancel() },
                    onManualImport: { text in runner.importManualResult(text) },
                    elapsedSinceSubmission: runner.elapsedSinceSubmission
                )
            }
            .sheet(isPresented: $showLoginSheet, onDismiss: continueAfterLoginIfReady) {
                AIBILoginSheet {
                    loginStore.markLoggedIn()
                }
            }
            .alert("사진 분석을 시작할까요?", isPresented: $showAITransferNotice) {
                Button("취소", role: .cancel) {}
                Button("동의하고 시작") {
                    didAcknowledgeAITransfer = true
                    startQuickValue()
                }
            } message: {
                Text("선택한 사진의 사본과 분석 요청이 로그인된 ChatGPT로 전송됩니다. DenimDex 서버에는 남지 않으며, 전송용 사본은 분석 후 폐기됩니다.")
            }
            .fullScreenCover(isPresented: $isCameraPresented) {
                CameraCaptureView(
                    maxCount: QuickValueImagePolicy.captureMaximumCount,
                    currentCount: photos.count,
                    onFinish: { captured in
                        appendPhotos(captured)
                    },
                    onPhotoLibrarySaveIssue: { showPhotoSaveIssue = true }
                )
                .ignoresSafeArea()
            }
            .onChange(of: libraryPickerItems) { _, items in
                guard !items.isEmpty else { return }
                libraryLoadTask?.cancel()
                let loadID = UUID()
                libraryLoadID = loadID
                libraryLoadTask = Task { await loadPhotos(from: items, loadID: loadID) }
            }
            .alert("사진 앱에 저장하지 못했어요", isPresented: $showPhotoSaveIssue) {
                Button("확인", role: .cancel) {}
            } message: {
                Text("촬영한 사진은 감정 목록에 담겼지만 사진 앱에는 저장되지 않았어요. 설정에서 사진 추가 권한을 확인해주세요.")
            }
            .confirmationDialog(
                "담은 사진을 모두 비울까요?",
                isPresented: $showClearAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("모두 비우기", role: .destructive) { clearAllPhotos() }
                Button("취소", role: .cancel) {}
            } message: {
                Text("현재 감정을 위해 담은 사진만 비워집니다. 사진 앱과 아카이브의 원본은 그대로 유지됩니다.")
            }
            .onAppear { loginStore.refresh() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                DenimEyebrow(text: "DenimDex · Private Archive")
                    .foregroundStyle(DenimTheme.washedDenim)
                Spacer()
                Text("EST. 2026")
                    .font(.caption2.weight(.medium))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.5))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("당신의 데님,\n가치를 발견하다")
                    .font(.system(size: 34, weight: .semibold, design: .default))
                    .foregroundStyle(.white)
                    .tracking(-1.1)
                    .fixedSize(horizontal: false, vertical: true)
                Text("제품의 정체와 한·일 시장 가치를 한 번에 살펴보세요.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DenimTheme.indigoGradient)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Rectangle()
                .fill(DenimTheme.brass.opacity(0.75))
                .frame(width: 54, height: 2)
                .padding(22)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Photo collector

    private var photoCollector: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("감정 사진")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(DenimTheme.charcoal)
                    Text("실루엣부터 라벨과 작은 각인까지")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(photos.count) / \(QuickValueImagePolicy.captureMaximumCount)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(DenimTheme.indigo)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(DenimTheme.fadedDenim)
                    .clipShape(Capsule())
                if !photos.isEmpty {
                    Button(role: .destructive) {
                        showClearAllConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(DenimTheme.inkSoft)
                            .frame(width: 30, height: 30)
                            .background(DenimTheme.offWhite)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("담은 사진 모두 비우기")
                }
            }

            Text("사진을 길게 눌러 중요도 순으로 정리할 수 있어요.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                spacing: 10
            ) {
                ForEach(Array(photos.enumerated()), id: \.offset) { index, data in
                    photoThumbnail(data: data, index: index)
                        .onDrag {
                            draggedPhotoIndex = index
                            return NSItemProvider(object: NSString(string: "\(index)"))
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: PhotoReorderDropDelegate(
                                targetIndex: index,
                                photos: $photos,
                                draggedIndex: $draggedPhotoIndex
                            )
                        )
                }
                if canAddMorePhotos {
                    addTile
                }
            }

            HStack(spacing: 10) {
                Button {
                    isCameraPresented = true
                } label: {
                    Label("직접 촬영", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!canAddMorePhotos)
                .accessibilityLabel("카메라로 촬영")

                PhotosPicker(
                    selection: $libraryPickerItems,
                    maxSelectionCount: max(1, remainingLibrarySlots),
                    selectionBehavior: .ordered,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("사진 선택", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!canAddMorePhotos || isLoadingPhotos)
                .accessibilityLabel("사진 보관함에서 순서대로 여러 장 선택")
            }
            .buttonStyle(.denimSecondary)
            .tint(DenimTheme.indigo)
        }
        .padding(0)
        .denimCard()
    }

    @ViewBuilder
    private func photoThumbnail(data: Data, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            if let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .aspectRatio(1, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Button {
                photos.remove(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, DenimTheme.charcoal.opacity(0.7))
            }
            .padding(5)
            .accessibilityLabel("\(index + 1)번 사진 지우기")
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            Image(systemName: "line.3.horizontal")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(6)
                .background(.black.opacity(0.38), in: Circle())
                .padding(5)
                .accessibilityHidden(true)
        }
    }

    private var addTile: some View {
        Button {
            isCameraPresented = true
        } label: {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DenimTheme.offWhite)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    VStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.title3.weight(.medium))
                        Text("사진 추가")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(DenimTheme.indigo)
                }
        }
        .accessibilityLabel("사진 추가")
    }

    private var runningPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            AIBIProgressRow(session: runner.session, onCancel: { runner.cancel() })
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if runner.elapsedSinceSubmission > 0 {
                let remaining = CountdownFormatter.remainingSeconds(elapsed: runner.elapsedSinceSubmission)
                HStack {
                    Text("남은 시간 \(CountdownFormatter.formatMinutesSeconds(remaining))")
                        .font(.caption.weight(.semibold))
                }
                ProgressView(value: CountdownFormatter.progressFraction(elapsed: runner.elapsedSinceSubmission))
                    .tint(DenimTheme.indigo)
            }
            if runner.sentPhotoCount > 0 {
                Text(analysisPhotoSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .denimCard()
    }

    private func errorPanel(message: String, retryLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DenimTheme.signalRed)
            Button(retryLabel) { runner.reset() }
                .buttonStyle(.denimSecondary)
        }
        .denimCard()
    }

    private func startQuickValue() {
        guard !photos.isEmpty else { return }
        runner.start(photos: photos, hiddenContainer: hiddenHost.containerView)
    }

    private func requestValueAnalysis() {
        guard readyToAnalyze else { return }
        guard loginStore.status == .loggedIn else {
            shouldAnalyzeAfterLogin = true
            showLoginSheet = true
            return
        }
        requestAITransferConsentOrStart()
    }

    private func continueAfterLoginIfReady() {
        guard shouldAnalyzeAfterLogin else { return }
        shouldAnalyzeAfterLogin = false
        guard loginStore.status == .loggedIn else { return }
        requestAITransferConsentOrStart()
    }

    private func requestAITransferConsentOrStart() {
        if didAcknowledgeAITransfer {
            startQuickValue()
        } else {
            showAITransferNotice = true
        }
    }

    @MainActor
    private func loadPhotos(from items: [PhotosPickerItem], loadID: UUID) async {
        isLoadingPhotos = true
        defer {
            if libraryLoadID == loadID {
                isLoadingPhotos = false
                libraryPickerItems = []
            }
        }

        var loaded: [Data] = []
        let capacity = remainingLibrarySlots
        for item in items.prefix(capacity) {
            if Task.isCancelled { return }
            if let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty {
                loaded.append(data)
            }
        }
        guard !Task.isCancelled, libraryLoadID == loadID else { return }
        appendPhotos(loaded)
    }

    private func appendPhotos<S: Sequence>(_ newPhotos: S) where S.Element == Data {
        let available = max(0, QuickValueImagePolicy.captureMaximumCount - photos.count)
        photos.append(contentsOf: newPhotos.prefix(available))
    }

    private func clearAllPhotos() {
        libraryLoadTask?.cancel()
        libraryLoadTask = nil
        libraryPickerItems = []
        draggedPhotoIndex = nil
        photos.removeAll()
        runner.reset()
    }

    private var analysisPhotoSummary: String {
        var details = ["\(runner.sentPhotoCount)장 분석"]
        if runner.removedSimilarPhotoCount > 0 {
            details.append("유사 사진 \(runner.removedSimilarPhotoCount)장 제외")
        }
        if runner.omittedForTransferLimitCount > 0 {
            details.append("전송 한도 \(runner.omittedForTransferLimitCount)장 제외")
        }
        return details.joined(separator: " · ")
    }

    private func saveToCollection(result: QuickValueResult, rawJSON: String) {
        let roles = photos.indices.map { "original_photo_\($0 + 1)" }
        let item = CollectionItem(
            userTitle: "",
            photosData: photos,
            photoRoleRawValues: roles,
            result: result,
            quickValueJSON: rawJSON
        )
        item.markEligibleForSyncIfNeeded()
        modelContext.insert(item)
        try? modelContext.save()
        runner.reset()
        photos = []
    }
}

private struct PhotoReorderDropDelegate: DropDelegate {
    let targetIndex: Int
    @Binding var photos: [Data]
    @Binding var draggedIndex: Int?

    func dropEntered(info: DropInfo) {
        guard let sourceIndex = draggedIndex,
              sourceIndex != targetIndex,
              photos.indices.contains(sourceIndex),
              photos.indices.contains(targetIndex) else { return }

        withAnimation(.easeInOut(duration: 0.18)) {
            photos.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
            )
        }
        draggedIndex = targetIndex
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedIndex = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

enum DenimDexSettingsKeys {
    static let alwaysShowBrowser = "denimdex.alwaysShowBrowser"
    static let didAcknowledgeAITransfer = "denimdex.didAcknowledgeAITransfer"
}
