import XCTest
import UIKit
@testable import DenimDex

final class HanYangPhotoRefinementTests: XCTestCase {
    private func solidImage(_ color: UIColor, size: CGSize = CGSize(width: 64, height: 48)) -> Data {
        UIGraphicsImageRenderer(size: size).pngData { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            context.fill(CGRect(x: 8, y: 8, width: 20, height: 12))
        }
    }

    private func assertSameAsLegacy(_ images: [Data], file: StaticString = #filePath, line: UInt = #line) async throws {
        let legacy = HanAIPhotoDeduplicator.selectRepresentatives(from: images)
        let cached = try await HanAIPhotoDeduplicator.selectRepresentativesRefined(from: images)
        XCTAssertEqual(cached.keptIndices, legacy.keptIndices, file: file, line: line)
        XCTAssertEqual(cached.removedCount, legacy.removedCount, file: file, line: line)
        XCTAssertEqual(cached.images, legacy.images, file: file, line: line)
    }

    func testCachedSelectionThrowsWhenCancelledBeforeStart() async {
        let images = [Data([0]), Data([1])]
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await HanAIPhotoDeduplicator.selectRepresentativesRefined(from: images)
        }
        do {
            _ = try await task.value
            XCTFail("취소되어야 합니다.")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testSingleAndEmptyInputsUnchanged() async throws {
        try await assertSameAsLegacy([])
        try await assertSameAsLegacy([solidImage(.red)])
    }

    func testMalformedBytesMatchLegacy() async throws {
        let bad = Data([0, 1, 2])
        try await assertSameAsLegacy([bad, bad, Data(), Data([9]), bad])
    }

    func testRepeatedInputsKeepLegacyOutputAndInputIndices() async throws {
        let a = solidImage(.red)
        let b = solidImage(.blue, size: CGSize(width: 48, height: 96))
        let images = [a, b, a, a, b, Data([7]), a]
        let legacy = HanAIPhotoDeduplicator.selectRepresentatives(from: images)
        let cached = try await HanAIPhotoDeduplicator.selectRepresentativesRefined(from: images)
        XCTAssertEqual(cached.keptIndices, legacy.keptIndices)
        XCTAssertEqual(cached.removedCount, legacy.removedCount)
        XCTAssertTrue(cached.keptIndices.allSatisfy { images.indices.contains($0) })
        XCTAssertEqual(cached.keptIndices, cached.keptIndices.sorted())
    }

    func testRolesFollowOriginalInputIndexWithRepeats() async throws {
        let a = solidImage(.red)
        let images = [a, a, a, solidImage(.green, size: CGSize(width: 48, height: 96)), a]
        let legacy = HanAIPhotoDeduplicator.selectRepresentatives(from: images)
        let cached = try await HanAIPhotoDeduplicator.selectRepresentativesRefined(from: images)
        XCTAssertEqual(
            HanYangEvalRunner.roles(cached.keptIndices, count: images.count),
            HanYangEvalRunner.roles(legacy.keptIndices, count: images.count)
        )
    }

    func testLocalProductionFixtureEvaluation() async throws {
        let taskRoot = try HanYangEvalPaths.taskRoot()
        guard HanYangEvalPaths.entryType(taskRoot) == .typeDirectory,
              HanYangEvalPaths.entryType(taskRoot.appendingPathComponent("manifest.json")) != nil
        else { throw XCTSkip("DenimDex 한양 평가 fixture가 앱 캐시에 없습니다.") }

        let worker = Task.detached(priority: .userInitiated) {
            try await HanYangEvalRunner.run(taskRoot: taskRoot)
        }
        let outcome = try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }

        let attachment = XCTAttachment(data: outcome.json, uniformTypeIdentifier: "public.json")
        attachment.name = "result.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("HanYangEval photos=\(outcome.photoCount) guides=\(outcome.guideCount) batches=\(outcome.batchCount)")

        XCTAssertTrue(outcome.allOutputsEqual, "legacy/cached 출력 불일치")
        XCTAssertTrue(outcome.allRolesEqual, "role 매핑 불일치")
        XCTAssertTrue(outcome.benchmarkOutputsEqual, "반복 입력 출력 불일치")
    }

    func testCleanupOnlyEvaluationFixtures() throws {
        let cachesRoot = try HanYangEvalPaths.cachesRoot()
        let taskRoot = cachesRoot.appendingPathComponent(HanYangEvalPaths.taskName, isDirectory: true)
        defer { XCTAssertNil(HanYangEvalPaths.entryType(taskRoot)) }
        guard let type = HanYangEvalPaths.entryType(taskRoot) else { return }
        guard type == .typeDirectory,
              !((try? taskRoot.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? true),
              taskRoot.resolvingSymlinksInPath().path == taskRoot.standardizedFileURL.path,
              taskRoot.deletingLastPathComponent().path == cachesRoot.path
        else { return XCTFail("평가 캐시 경로 검증 실패") }
        try FileManager.default.removeItem(at: taskRoot)
    }
}

// MARK: - 로컬 평가 보조 (테스트 전용)

private enum HanYangEvalError: Error { case invalidManifest, unsafePath, invalidFile, invalidPair }

private enum HanYangEvalPaths {
    static let taskName = "DenimDexHanYangEvaluation-202610171106"

    static func cachesRoot() throws -> URL {
        guard let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw HanYangEvalError.unsafePath
        }
        return url.resolvingSymlinksInPath()
    }

    static func taskRoot() throws -> URL {
        try cachesRoot().appendingPathComponent(taskName, isDirectory: true)
    }

    /// symlink를 따라가지 않는 lstat 기반 종류. 없으면 nil.
    static func entryType(_ url: URL) -> FileAttributeType? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType
    }

    static func isSimpleLeaf(_ s: String) -> Bool {
        !s.isEmpty && s.utf8.count <= 64 && !s.hasPrefix(".") && !s.contains("..")
            && !s.contains("/") && !s.contains("\\") && !s.contains(":")
            && !s.unicodeScalars.contains { $0.value < 32 }
    }
}

private struct HanYangManifest: Decodable {
    struct Item: Decodable { let id: Int; let file: String }
    struct Pair: Decodable { let firstIndex: Int; let secondIndex: Int }
    let schemaVersion: Int
    let photos: [Item]
    let guides: [Item]?
    let pairs: [Pair]
}

private struct HanYangOutcome: Sendable {
    var json = Data()
    var photoCount = 0, guideCount = 0, batchCount = 0
    var allOutputsEqual = false
    var allRolesEqual = false
    var benchmarkOutputsEqual = false
}

private enum HanYangEvalRunner {
    static let batchLimit = 30
    static let itemLimit = 64

    static func ms(_ start: ContinuousClock.Instant) -> Int {
        let c = (ContinuousClock.now - start).components
        return Int(c.seconds * 1000 + c.attoseconds / 1_000_000_000_000_000)
    }

    static func loadManifest(root: URL) throws -> HanYangManifest {
        let url = root.appendingPathComponent("manifest.json")
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard HanYangEvalPaths.entryType(root) == .typeDirectory,
              attrs[.type] as? FileAttributeType == .typeRegular,
              ((attrs[.size] as? NSNumber)?.intValue ?? Int.max) <= 256 * 1024
        else { throw HanYangEvalError.unsafePath }
        let manifest = try JSONDecoder().decode(HanYangManifest.self, from: Data(contentsOf: url))
        let guides = manifest.guides ?? []
        for items in [manifest.photos, guides] {
            guard items.count <= itemLimit,
                  Set(items.map(\.id)).count == items.count,
                  Set(items.map(\.file)).count == items.count,
                  items.allSatisfy({ HanYangEvalPaths.isSimpleLeaf($0.file) })
            else { throw HanYangEvalError.invalidManifest }
        }
        guard manifest.schemaVersion == 1, !manifest.photos.isEmpty, manifest.pairs.count <= 256 else {
            throw HanYangEvalError.invalidManifest
        }
        return manifest
    }

    static func load(_ items: ArraySlice<HanYangManifest.Item>, root: URL) throws -> [Data] {
        try items.map { item in
            let url = root.appendingPathComponent(item.file)
            guard HanYangEvalPaths.entryType(url) == .typeRegular else { throw HanYangEvalError.invalidFile }
            try Task.checkCancellation()
            return try Data(contentsOf: url)
        }
    }

    /// Runner와 같은 공식: 선택 결과(keptIndices)를 같은 원본 입력 index의 role로 매핑.
    static func roles(_ kept: [Int], count: Int) -> [String] {
        let source = QuickValuePhotoRoles.identifiers(count: count)
        return Array(kept.map { source.indices.contains($0) ? source[$0] : "photo_\($0 + 1)" }
            .prefix(QuickValuePhotoRoles.maxCount))
    }

    static func median(_ values: [Int]) -> Int { values.sorted()[values.count / 2] }

    /// 같은 입력에 대해 baseline(old)과 cached(new)를 번갈아 실행하고 출력 동일 여부와 시간을 기록한다.
    static func benchmark(_ images: [Data]) async throws -> (json: [String: Any], equal: Bool) {
        _ = HanAIPhotoDeduplicator.selectRepresentatives(from: Array(images.prefix(2)))
        var oldRuns: [Int] = [], newRuns: [Int] = []
        var equal = true
        for run in 0..<3 {
            try Task.checkCancellation()
            var old: PhotoDeduplicationResult?, new: PhotoDeduplicationResult?
            for step in 0..<2 {
                let runsOld = (step == 0) == (run % 2 == 0)
                let start = ContinuousClock.now
                if runsOld {
                    old = HanAIPhotoDeduplicator.selectRepresentatives(from: images)
                    oldRuns.append(ms(start))
                } else {
                    new = try await HanAIPhotoDeduplicator.selectRepresentativesRefined(from: images)
                    newRuns.append(ms(start))
                }
            }
            equal = equal && old?.keptIndices == new?.keptIndices && old?.removedCount == new?.removedCount
        }
        return ([
            "inputCount": images.count,
            "oldRunsMilliseconds": oldRuns, "newRunsMilliseconds": newRuns,
            "oldMedianMilliseconds": median(oldRuns), "newMedianMilliseconds": median(newRuns),
            "keptCount": images.count - (HanAIPhotoDeduplicator.selectRepresentatives(from: images).removedCount),
            "outputsEqual": equal,
        ], equal)
    }

    static func run(taskRoot root: URL) async throws -> HanYangOutcome {
        let total = ContinuousClock.now
        let manifest = try loadManifest(root: root)
        let guides = manifest.guides ?? []
        var out = HanYangOutcome()
        out.photoCount = manifest.photos.count
        out.guideCount = guides.count

        let photoData = try load(manifest.photos[...], root: root)

        // photos/guides 각각 30개 이하 순서 batch: sync baseline과 async cached 전체 비교
        var batches: [[String: Any]] = []
        var outputsEqual = true, rolesEqual = true
        for (group, items) in [("photos", manifest.photos), ("guides", guides)] {
            for (batchIndex, start) in stride(from: 0, to: items.count, by: batchLimit).enumerated() {
                try Task.checkCancellation()
                let slice = items[start..<min(start + batchLimit, items.count)]
                let datas = group == "photos" ? Array(photoData[start..<(start + slice.count)]) : try load(slice, root: root)
                let legacy = HanAIPhotoDeduplicator.selectRepresentatives(from: datas)
                let cached = try await HanAIPhotoDeduplicator.selectRepresentativesRefined(from: datas)
                let same = legacy.keptIndices == cached.keptIndices && legacy.removedCount == cached.removedCount
                let rolesSame = roles(legacy.keptIndices, count: datas.count) == roles(cached.keptIndices, count: datas.count)
                outputsEqual = outputsEqual && same
                rolesEqual = rolesEqual && rolesSame
                batches.append([
                    "group": group == "photos" ? 0 : 1, "batchIndex": batchIndex, "inputCount": datas.count,
                    "keptCount": cached.keptIndices.count, "removedCount": cached.removedCount,
                    "outputsEqual": same, "rolesEqual": rolesSame,
                ])
            }
        }
        out.batchCount = batches.count
        out.allOutputsEqual = outputsEqual
        out.allRolesEqual = rolesEqual

        // 같은 로드된 Data를 반복한 입력의 old/new 시간 (이 기기·이 입력의 관측값일 뿐)
        guard photoData.count >= 3 else { throw HanYangEvalError.invalidManifest }
        let single = try await benchmark(Array(repeating: photoData[0], count: 30))
        let triple = try await benchmark(photoData.prefix(3).flatMap { Array(repeating: $0, count: 10) })
        out.benchmarkOutputsEqual = single.equal && triple.equal

        let result: [String: Any] = [
            "schemaVersion": 1,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            "appBuild": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "",
            "photoCount": out.photoCount,
            "guideCount": out.guideCount,
            "batches": batches,
            "repeatedFirstPhoto30": single.json,
            "repeatedFirstThreePhotosEach10": triple.json,
            "totalMilliseconds": ms(total),
        ]
        out.json = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        let resultURL = root.appendingPathComponent("result.json")
        if let type = HanYangEvalPaths.entryType(resultURL), type != .typeRegular {
            throw HanYangEvalError.unsafePath
        }
        try out.json.write(to: resultURL, options: .atomic)
        return out
    }
}
