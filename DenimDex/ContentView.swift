import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            ScanView()
                .tabItem { Label("감정", systemImage: "camera.viewfinder") }

            MyDenimListView()
                .tabItem { Label("아카이브", systemImage: "square.stack.3d.up.fill") }

            LearnView()
                .tabItem { Label("가이드", systemImage: "book.closed.fill") }

            SettingsView()
                .tabItem { Label("설정", systemImage: "gearshape.fill") }
        }
        .tint(DenimTheme.indigo)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        // 현재 DenimDex 디자인 시스템은 밝은 상품·도감 화면을 기준으로 한다.
        // 다크 모드의 동적 흰 글자가 흰 카드 위에 놓이는 일을 막는다.
        .preferredColorScheme(.light)
    }
}

#Preview {
    ContentView()
}
