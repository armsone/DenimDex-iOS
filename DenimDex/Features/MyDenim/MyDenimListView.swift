import SwiftUI
import SwiftData

struct MyDenimListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CollectionItem.createdAt, order: .reverse) private var items: [CollectionItem]

    @State private var searchText = ""
    @State private var showSyncInvite = false
    @AppStorage(DenimDexSettingsKeys.lastSyncPromptCount) private var lastSyncPromptCount = 0

    private var filteredItems: [CollectionItem] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return items }
        let query = searchText.lowercased()
        return items.filter {
            $0.displayTitle.lowercased().contains(query)
                || $0.brandGuess.lowercased().contains(query)
                || $0.modelGuess.lowercased().contains(query)
                || $0.userNotes.lowercased().contains(query)
        }
    }

    private var pendingSyncCount: Int {
        items.filter { $0.syncState == .pending }.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(filteredItems) { item in
                            NavigationLink(value: item) {
                                CollectionItemRow(item: item)
                            }
                            .listRowBackground(Color.white)
                            .listRowSeparatorTint(DenimTheme.hairline)
                            .listRowInsets(EdgeInsets(top: 7, leading: 18, bottom: 7, trailing: 18))
                        }
                        .onDelete(perform: delete)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .searchable(text: $searchText, prompt: "브랜드, 모델 또는 메모")
                }
            }
            .background(DenimTheme.canvasGradient.ignoresSafeArea())
            .navigationTitle("내 아카이브")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: CollectionItem.self) { item in
                CollectionItemDetailView(item: item)
            }
            .onAppear(perform: checkSyncInvite)
            .sheet(isPresented: $showSyncInvite) {
                SyncInviteView(pendingCount: pendingSyncCount) {
                    lastSyncPromptCount = pendingSyncCount
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(DenimTheme.indigoGradient)
                    .frame(width: 112, height: 112)
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(.white)
            }
            VStack(spacing: 7) {
                DenimEyebrow(text: "Private Collection")
                Text("첫 데님을 보관해보세요")
                    .font(.title3.weight(.semibold))
                Text("사진으로 가치를 확인하고\n당신만의 아카이브를 완성해보세요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(filteredItems[index]) }
        try? modelContext.save()
    }

    /// 동기화 대기 카드가 10장 쌓일 때마다, My Denim으로 돌아온 시점에 한 번만 제안한다 (기술서 11.4절).
    private func checkSyncInvite() {
        guard pendingSyncCount >= 10, pendingSyncCount - lastSyncPromptCount >= 10 else { return }
        showSyncInvite = true
    }
}

private struct CollectionItemRow: View {
    let item: CollectionItem

    var body: some View {
        HStack(spacing: 14) {
            if let data = item.photosData.first, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Rectangle()
                    .fill(DenimTheme.offWhite)
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle.isEmpty ? "이름 없는 데님" : item.displayTitle)
                    .font(.headline.weight(.semibold))
                    .lineLimit(2)
                Text(item.formattedValueRange)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DenimTheme.indigo)
                Text(item.verificationState.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 5)
    }
}

extension DenimDexSettingsKeys {
    static let lastSyncPromptCount = "denimdex.lastSyncPromptCount"
}
