# Claude Code 프롬프트 — SpectArk 브랜드 자산 (Mac · iPhone · iPad)

> 이 내용을 그대로 복사해서 Claude Code에 던지세요.

---

## 작업
SpectArk(Time Machine류 백업 앱)의 브랜드 자산을 macOS/iOS/iPadOS에 적용. 모든 자산은 `design_handoff_spectark/`에 베이킹되어 있다.

## 절대 금지
1. ❌ 워드마크("SpectArk")를 Text/UILabel/SwiftUI로 다시 그리지 마라 — 이미지에 베이킹됨
2. ❌ "A"를 별도 색으로, 시계·화살표·글래스를 코드로 재현하지 마라
3. ❌ Bricolage Grotesque 폰트 번들 금지 (불필요)
4. ❌ LaunchScreen.storyboard를 SwiftUI로 바꾸지 마라

## 해야 할 일
### ① 앱 아이콘
```bash
cp -R design_handoff_spectark/AppIcon-iOS.appiconset <App>/Resources/Assets.xcassets/AppIcon.appiconset
cp -R design_handoff_spectark/AppIcon-macOS.appiconset <MacApp>/Assets.xcassets/AppIcon.appiconset
```
> iOS는 풀블리드, macOS는 여백+라운드 — 섞지 마라.

### ② iOS/iPadOS 런치
```bash
rm -rf <App>/Resources/Assets.xcassets/{LaunchScreen,LaunchBackground,LaunchMark}.imageset
cp -R design_handoff_spectark/LaunchScreen.imageset <App>/Resources/Assets.xcassets/
cp design_handoff_spectark/LaunchScreen.storyboard <App>/Resources/LaunchScreen.storyboard
```
Info.plist: `UILaunchStoryboardName=LaunchScreen`. storyboard는 UIImageView 1개(`scaleAspectFill`).

### ③ macOS 스플래시
`launch/Mac-Window.png`를 첫 윈도우/about 배경으로:
```swift
Image("Mac-Window").resizable().aspectRatio(contentMode: .fill)
```

### ④ 인앱 워드마크 (다크 톤 → white 기본)
```bash
cp design_handoff_spectark/wordmark/wordmark-white*.png <App>/Resources/Assets.xcassets/
```

### ⑤ 빌드 + 시뮬레이터 캐시 클리어 (iOS/iPad 필수!)
```bash
xcrun simctl erase "iPad Pro (12.9-inch) (6th generation)"
xcrun simctl erase "iPhone 15 Pro"
```

## 검증
- [ ] iOS 아이콘: 풀블리드 글래스 + 큰 시계 링 + 앰버 바늘 (preview/app-icon-1024.png)
- [ ] macOS 아이콘: Dock 라운드+여백 (preview/mac-icon-512.png)
- [ ] 런치: 다크 + 아이콘 + "SpectArk" 흰색 + 앰버 "A" (preview/launch-ipad-portrait.png)
- [ ] storyboard에 UIImageView 1개만
- [ ] 시뮬레이터 캐시 클리어 후 검증

## 한 줄 요약
> **베이킹된 이미지를 자리에 넣는 게 전부. iOS는 풀블리드, macOS는 여백 포함 — 섞지 마라.**
