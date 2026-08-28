import Foundation

/// 번들에 포함된 `aibi-providers.json`, `aibi-browser-runtime.js`를 읽어 오는 로더.
/// 두 리소스는 `/Users/armsone/.codex/skills/aibi/assets`의 canonical 산출물을 그대로 옮긴 것이며
/// DenimDex 제품 지식을 담지 않는다.
enum AIBIProviderRegistry {
    private struct Root: Codable {
        var providers: [String: AIBIProviderConfig]
    }

    static let shared = load()

    private static func load() -> [String: AIBIProviderConfig] {
        guard let url = Bundle.main.url(forResource: "aibi-providers", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONDecoder().decode(Root.self, from: data) else {
            return [:]
        }
        return root.providers
    }

    static var chatGPT: AIBIProviderConfig? { shared["chatgpt"] }

    static let runtimeJavaScript: String = {
        guard let url = Bundle.main.url(forResource: "aibi-browser-runtime", withExtension: "js"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return text
    }()
}
