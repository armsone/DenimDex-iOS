# DenimDex iOS

사진으로 빈티지 데님의 특징과 한국·일본 시장 가치를 확인하고, 결과를 개인 아카이브로 쌓는 iPhone·iPad 앱입니다.

## 구성

- SwiftUI + SwiftData
- AIBI를 통한 사용자의 ChatGPT 웹 세션 활용
- 한양(`HanAI`) 기반 유사 사진 선별
- 최대 30장 수집, 유사 사진 정리 후 최대 20장 분석
- 한국·일본 예상 가격, 순수익과 시장 간 차익 표시

## 개발 환경

현재 Xcode 프로젝트는 같은 상위 폴더의 `HanAI` 저장소를 로컬 Swift Package로 참조합니다.

```text
git/
├── DenimDex-iOS/
└── HanAI/
```

Xcode에서 `DenimDex.xcodeproj`를 열어 실행합니다.
