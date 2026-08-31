import SwiftUI
import PhotosUI
import SwiftData
import UniformTypeIdentifiers

struct ScanView: View {
    private enum ScrollTarget: Hashable {
        case analyzeButton
        case progress
    }

    @AppStorage(DenimDexSettingsKeys.didAcknowledgeAITransfer) private var didAcknowledgeAITransfer = false
    @Environment(\.modelContext) private var modelContext

    @StateObject private var hiddenHost = AIBIHiddenContainerHost()
    @StateObject private var runner = QuickValueRunner()
    @StateObject private var loginStore = AIBILoginStatusStore()

    // 촬영 모드 선택 (팬츠 정밀 / 재킷 정밀 / 자유 촬영)
    @State private var selectedMode: CaptureModeSelection = .pants

    // 가이드 모드 슬롯 상태
    @State private var pantsSlots: [GuidedShotSlot] = GuidedCapturePreset.pants.shots.map {
        GuidedShotSlot(definition: $0, photoData: nil, isSkipped: false)
    }
    @State private var jacketSlots: [GuidedShotSlot] = GuidedCapturePreset.jacket.shots.map {
        GuidedShotSlot(definition: $0, photoData: nil, isSkipped: false)
    }
    @State private var isGuidedCameraPresented = false
    @State private var guidedCameraStartIndex = 0

    // 개별 슬롯 사진 보관함 선택
    @State private var singleSlotPickerItem: PhotosPickerItem?
    @State private var targetSlotIndexForPicker: Int?

    // 자유 촬영 모드 상태
    @State private var freePhotos: [Data] = []
    @State private var libraryPickerItems: [PhotosPickerItem] = []
    @State private var libraryLoadTask: Task<Void, Never>?
    @State private var libraryLoadID = UUID()
    @State private var isLoadingPhotos = false
    @State private var isFreeCameraPresented = false
    @State private var draggedPhotoIndex: Int?

    // 공통 알림 및 시트
    @State private var showAITransferNotice = false
    @State private var showPhotoSaveIssue = false
    @State private var showLoginSheet = false
    @State private var shouldAnalyzeAfterLogin = false
    @State private var showClearAllConfirmation = false

    private var isGuidedMode: Bool { selectedMode == .pants || selectedMode == .jacket }

    private var activeGuidedSlots: [GuidedShotSlot] {
        selectedMode == .pants ? pantsSlots : jacketSlots
    }

    private var capturedGuidedCount: Int {
        activeGuidedSlots.filter(\.isCaptured).count
    }

    private var skippedGuidedCount: Int {
        activeGuidedSlots.filter { $0.isSkipped && !$0.isCaptured }.count
    }

    private var totalPhotosCount: Int {
        isGuidedMode ? capturedGuidedCount : freePhotos.count
    }

    private var readyToAnalyze: Bool {
        if isGuidedMode {
            return capturedGuidedCount >= 1
        } else {
            return !freePhotos.isEmpty && !isLoadingPhotos
        }
    }

    private var canAddMoreFreePhotos: Bool { freePhotos.count < QuickValueImagePolicy.captureMaximumCount }
    private var remainingLibrarySlots: Int { max(0, QuickValueImagePolicy.captureMaximumCount - freePhotos.count) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(spacing: 20) {
                        header

                        modeSelector

                        if isGuidedMode {
                            guidedCollector
                        } else {
                            freePhotoCollector
                        }

                        Button {
                            requestValueAnalysis()
                        } label: {
                            Label("가치 확인하기", systemImage: "sparkles")
                        }
                        .buttonStyle(.denimPrimary)
                        .disabled(!readyToAnalyze || runner.state == .running)
                        .accessibilityHint("사진을 ChatGPT로 보내 한국·일본 가격 범위와 교차 검증 소견을 확인합니다")
                        .id(ScrollTarget.analyzeButton)

                        if !readyToAnalyze {
                            Text(isGuidedMode
                                 ? "핵심 부위를 1장 이상 촬영하면 교차 검증을 시작할 수 있어요. 많이 찍을수록 더 정확해집니다."
                                 : "사진 한 장부터 시작할 수 있어요. 원본은 30장까지 담고, 가장 선명한 사진을 골라 분석합니다.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        if runner.state == .running, !runner.session.isVisibleBrowserPresented {
                            runningPanel
                                .id(ScrollTarget.progress)
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
                .onChange(of: totalPhotosCount) { previousCount, currentCount in
                    guard currentCount > previousCount else { return }
                    scrollTo(.analyzeButton, anchor: .bottom, using: scrollProxy)
                }
                .onChange(of: runner.state) { _, state in
                    guard state == .running else { return }
                    scrollTo(.progress, anchor: .bottom, using: scrollProxy)
                }
            }
            .safeAreaPadding(.vertical, 16)
            .denimDynamicIslandFade()
            .background(DenimTheme.canvasGradient.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .background(
                AIBIHiddenContainerRepresentable(host: hiddenHost)
                    .frame(width: 375, height: 667)
                    .offset(x: -10_000, y: -10_000)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            )
            .background(AIBILoginStatusProbeView(store: loginStore))
            .sheet(isPresented: Binding(
                get: { runner.session.isVisibleBrowserPresented },
                set: { presented in
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
            // 가이드 연속 촬영 카메라
            .fullScreenCover(isPresented: $isGuidedCameraPresented) {
                if let preset = selectedMode == .pants ? GuidedCapturePreset.pants : (selectedMode == .jacket ? GuidedCapturePreset.jacket : nil) {
                    GuidedCameraCaptureView(
                        preset: preset,
                        initialSlotIndex: guidedCameraStartIndex,
                        initialSlots: activeGuidedSlots,
                        onFinish: { updatedSlots in
                            if selectedMode == .pants {
                                pantsSlots = updatedSlots
                            } else {
                                jacketSlots = updatedSlots
                            }
                        },
                        onPhotoLibrarySaveIssue: { showPhotoSaveIssue = true }
                    )
                    .ignoresSafeArea()
                }
            }
            // 자유 촬영 카메라
            .fullScreenCover(isPresented: $isFreeCameraPresented) {
                CameraCaptureView(
                    maxCount: QuickValueImagePolicy.captureMaximumCount,
                    currentCount: freePhotos.count,
                    onFinish: { captured in
                        appendFreePhotos(captured)
                    },
                    onPhotoLibrarySaveIssue: { showPhotoSaveIssue = true }
                )
                .ignoresSafeArea()
            }
            // 자유 촬영 사진 보관함
            .onChange(of: libraryPickerItems) { _, items in
                guard !items.isEmpty else { return }
                libraryLoadTask?.cancel()
                let loadID = UUID()
                libraryLoadID = loadID
                libraryLoadTask = Task { await loadFreePhotos(from: items, loadID: loadID) }
            }
            // 개별 가이드 슬롯 사진 보관함 선택
            .onChange(of: singleSlotPickerItem) { _, item in
                guard let item, let slotIndex = targetSlotIndexForPicker else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty {
                        await MainActor.run {
                            if selectedMode == .pants, pantsSlots.indices.contains(slotIndex) {
                                pantsSlots[slotIndex].photoData = data
                                pantsSlots[slotIndex].isSkipped = false
                            } else if selectedMode == .jacket, jacketSlots.indices.contains(slotIndex) {
                                jacketSlots[slotIndex].photoData = data
                                jacketSlots[slotIndex].isSkipped = false
                            }
                            singleSlotPickerItem = nil
                            targetSlotIndexForPicker = nil
                        }
                    }
                }
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
                Button("모두 비우기", role: .destructive) { clearCurrentModePhotos() }
                Button("취소", role: .cancel) {}
            } message: {
                Text("현재 감정을 위해 담은 사진만 비워집니다. 사진 앱과 아카이브의 원본은 그대로 유지됩니다.")
            }
            .onAppear { loginStore.refresh() }
        }
    }

    private func scrollTo(
        _ target: ScrollTarget,
        anchor: UnitPoint,
        using proxy: ScrollViewProxy
    ) {
        Task { @MainActor in
            await Task.yield()
            withAnimation(.easeInOut(duration: 0.35)) {
                proxy.scrollTo(target, anchor: anchor)
            }
        }
    }

    // MARK: - Header & Mode selector

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                DenimEyebrow(text: "DenimDex · Precision Appraisal")
                    .foregroundStyle(DenimTheme.washedDenim)
                Spacer()
                Text("EST. 2026")
                    .font(.caption2.weight(.medium))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.5))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("당신의 데님,\n정밀하게 교차 감정")
                    .font(.system(size: 32, weight: .semibold, design: .default))
                    .foregroundStyle(.white)
                    .tracking(-1.0)
                    .fixedSize(horizontal: false, vertical: true)
                Text("핵심 부위 사진을 대조해 진품·복각 가능성과 가치를 확인하세요.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
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

    private var modeSelector: some View {
        HStack(spacing: 8) {
            ForEach(CaptureModeSelection.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedMode = mode
                    }
                } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: 5) {
                            Image(systemName: mode.iconName)
                                .font(.subheadline.weight(.semibold))
                            Text(mode.title)
                                .font(.subheadline.weight(.bold))
                        }
                        Text(mode.badgeText)
                            .font(.caption2)
                            .foregroundStyle(selectedMode == mode ? .white.opacity(0.85) : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(selectedMode == mode ? DenimTheme.indigo : DenimTheme.cardSurface)
                    .foregroundStyle(selectedMode == mode ? .white : DenimTheme.charcoal)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(selectedMode == mode ? DenimTheme.indigo : DenimTheme.hairline, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Guided photo collector

    private var guidedCollector: some View {
        let presetTitle = selectedMode == .pants ? "리바이스 팬츠 9단계" : "리바이스 재킷 9단계"
        let slots = activeGuidedSlots

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(presetTitle)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(DenimTheme.charcoal)
                    Text("버튼·라벨·패치를 대조해 연대와 진품·복각 가능성을 살펴봅니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(capturedGuidedCount) / 9")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(DenimTheme.indigo)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(DenimTheme.fadedDenim)
                    .clipShape(Capsule())
                if capturedGuidedCount > 0 || skippedGuidedCount > 0 {
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
                    .accessibilityLabel("촬영한 가이드 사진 모두 비우기")
                }
            }

            // 가이드 진행 상황 미니 바
            HStack(spacing: 4) {
                ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                    Rectangle()
                        .fill(slot.isCaptured ? DenimTheme.indigo : (slot.isSkipped ? DenimTheme.warningAmber.opacity(0.5) : DenimTheme.hairline))
                        .frame(height: 5)
                        .clipShape(Capsule())
                }
            }

            // 9개 샷 슬롯 카드 리스트
            VStack(spacing: 10) {
                ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                    guidedSlotRow(index: index, slot: slot)
                }
            }

            // 전체 가이드 촬영 시작 버튼
            Button {
                let firstIncomplete = slots.firstIndex(where: { !$0.isCaptured }) ?? 0
                guidedCameraStartIndex = firstIncomplete
                isGuidedCameraPresented = true
            } label: {
                Label(capturedGuidedCount == 0 ? "순서대로 가이드 촬영 시작" : "이어서 가이드 촬영하기", systemImage: "camera.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.denimSecondary)
            .tint(DenimTheme.indigo)
        }
        .padding(0)
        .denimCard()
    }

    private func guidedSlotRow(index: Int, slot: GuidedShotSlot) -> some View {
        HStack(spacing: 12) {
            // 썸네일 or 아이콘 영역
            if let data = slot.photoData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(slot.isSkipped ? DenimTheme.warningAmber.opacity(0.12) : DenimTheme.offWhite)
                        .frame(width: 58, height: 58)
                    Image(systemName: slot.isSkipped ? "forward.fill" : slot.definition.iconName)
                        .font(.headline)
                        .foregroundStyle(slot.isSkipped ? DenimTheme.warningAmber : DenimTheme.inkSoft)
                }
            }

            // 설명 영역
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("\(index + 1). \(slot.definition.title)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(DenimTheme.charcoal)
                    Text(slot.statusText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(slot.isCaptured ? DenimTheme.successGreen : (slot.isSkipped ? DenimTheme.warningAmber : .secondary))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((slot.isCaptured ? DenimTheme.successGreen : (slot.isSkipped ? DenimTheme.warningAmber : Color.gray)).opacity(0.12))
                        .clipShape(Capsule())
                }
                Text(slot.definition.shortInstruction)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            // 우측 작업 메뉴
            Menu {
                Button {
                    guidedCameraStartIndex = index
                    isGuidedCameraPresented = true
                } label: {
                    Label(slot.isCaptured ? "다시 촬영" : "카메라로 촬영", systemImage: "camera")
                }

                Button {
                    targetSlotIndexForPicker = index
                } label: {
                    Label("보관함에서 선택", systemImage: "photo")
                }

                if !slot.isCaptured && !slot.isSkipped {
                    Button {
                        toggleSkipSlot(at: index)
                    } label: {
                        Label("건너뛰기", systemImage: "forward")
                    }
                }

                if slot.isSkipped {
                    Button {
                        cancelSkipSlot(at: index)
                    } label: {
                        Label("건너뛰기 취소", systemImage: "arrow.uturn.backward")
                    }
                }

                if slot.isCaptured {
                    Button(role: .destructive) {
                        deleteSlotPhoto(at: index)
                    } label: {
                        Label("사진 삭제", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.title3)
                    .foregroundStyle(DenimTheme.indigo.opacity(0.8))
                    .padding(6)
            }
        }
        .padding(10)
        .background(DenimTheme.fadedDenim.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .photosPicker(
            isPresented: Binding(
                get: { targetSlotIndexForPicker == index },
                set: { if !$0 { targetSlotIndexForPicker = nil } }
            ),
            selection: $singleSlotPickerItem,
            matching: .images
        )
    }

    private func toggleSkipSlot(at index: Int) {
        if selectedMode == .pants, pantsSlots.indices.contains(index) {
            pantsSlots[index].isSkipped = true
            pantsSlots[index].photoData = nil
        } else if selectedMode == .jacket, jacketSlots.indices.contains(index) {
            jacketSlots[index].isSkipped = true
            jacketSlots[index].photoData = nil
        }
    }

    private func cancelSkipSlot(at index: Int) {
        if selectedMode == .pants, pantsSlots.indices.contains(index) {
            pantsSlots[index].isSkipped = false
        } else if selectedMode == .jacket, jacketSlots.indices.contains(index) {
            jacketSlots[index].isSkipped = false
        }
    }

    private func deleteSlotPhoto(at index: Int) {
        if selectedMode == .pants, pantsSlots.indices.contains(index) {
            pantsSlots[index].photoData = nil
            pantsSlots[index].isSkipped = false
        } else if selectedMode == .jacket, jacketSlots.indices.contains(index) {
            jacketSlots[index].photoData = nil
            jacketSlots[index].isSkipped = false
        }
    }

    // MARK: - Free photo collector

    private var freePhotoCollector: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("자유 촬영")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(DenimTheme.charcoal)
                    Text("정해진 순서 없이 원하는 부위를 자유롭게 담아보세요")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(freePhotos.count) / \(QuickValueImagePolicy.captureMaximumCount)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(DenimTheme.indigo)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(DenimTheme.fadedDenim)
                    .clipShape(Capsule())
                if !freePhotos.isEmpty {
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
                ForEach(Array(freePhotos.enumerated()), id: \.offset) { index, data in
                    photoThumbnail(data: data, index: index)
                        .onDrag {
                            draggedPhotoIndex = index
                            return NSItemProvider(object: NSString(string: "\(index)"))
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: PhotoReorderDropDelegate(
                                targetIndex: index,
                                photos: $freePhotos,
                                draggedIndex: $draggedPhotoIndex
                            )
                        )
                }
                if canAddMoreFreePhotos {
                    addTile
                }
            }

            HStack(spacing: 10) {
                Button {
                    isFreeCameraPresented = true
                } label: {
                    Label("직접 촬영", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!canAddMoreFreePhotos)
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
                .disabled(!canAddMoreFreePhotos || isLoadingPhotos)
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
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                freePhotos.remove(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, DenimTheme.charcoal.opacity(0.7))
            }
            .padding(5)
            .accessibilityLabel("\(index + 1)번 사진 지우기")
        }
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
            isFreeCameraPresented = true
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DenimTheme.offWhite)
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
        }
        .accessibilityLabel("사진 추가")
    }

    // MARK: - Status & Error panels

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

    // MARK: - Analysis flow

    private func startQuickValue() {
        if isGuidedMode {
            let captured = activeGuidedSlots.filter(\.isCaptured)
            let photos = captured.compactMap(\.photoData)
            let roles = captured.map { $0.definition.role }
            let missingRoles = activeGuidedSlots.filter { !$0.isCaptured }.map { $0.definition.role }
            guard !photos.isEmpty else { return }
            runner.start(
                photos: photos,
                roles: roles,
                missingRoles: missingRoles,
                hiddenContainer: hiddenHost.containerView
            )
        } else {
            guard !freePhotos.isEmpty else { return }
            runner.start(photos: freePhotos, roles: nil, hiddenContainer: hiddenHost.containerView)
        }
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
    private func loadFreePhotos(from items: [PhotosPickerItem], loadID: UUID) async {
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
        appendFreePhotos(loaded)
    }

    private func appendFreePhotos<S: Sequence>(_ newPhotos: S) where S.Element == Data {
        let available = max(0, QuickValueImagePolicy.captureMaximumCount - freePhotos.count)
        freePhotos.append(contentsOf: newPhotos.prefix(available))
    }

    private func clearCurrentModePhotos() {
        if isGuidedMode {
            if selectedMode == .pants {
                pantsSlots = GuidedCapturePreset.pants.shots.map { GuidedShotSlot(definition: $0, photoData: nil, isSkipped: false) }
            } else {
                jacketSlots = GuidedCapturePreset.jacket.shots.map { GuidedShotSlot(definition: $0, photoData: nil, isSkipped: false) }
            }
        } else {
            libraryLoadTask?.cancel()
            libraryLoadTask = nil
            libraryPickerItems = []
            draggedPhotoIndex = nil
            freePhotos.removeAll()
        }
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
        let photosData: [Data]
        let roles: [String]
        let presetRaw: String

        if isGuidedMode {
            let captured = activeGuidedSlots.filter(\.isCaptured)
            photosData = captured.compactMap(\.photoData)
            roles = captured.map { $0.definition.role }
            presetRaw = selectedMode.rawValue
        } else {
            photosData = freePhotos
            roles = freePhotos.indices.map { "photo_\($0 + 1)" }
            presetRaw = "quick"
        }

        let item = CollectionItem(
            userTitle: "",
            photosData: photosData,
            photoRoleRawValues: roles,
            result: result,
            quickValueJSON: rawJSON,
            capturePreset: presetRaw
        )
        item.markEligibleForSyncIfNeeded()
        modelContext.insert(item)
        try? modelContext.save()
        runner.reset()
        if isGuidedMode {
            clearCurrentModePhotos()
        } else {
            freePhotos = []
        }
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
