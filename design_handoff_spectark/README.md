# SpectArk — 브랜드 자산 (Mac · iPhone · iPad)

> Specta 시리즈 · Time Machine류 백업 앱.
> 가족 DNA(라이트 글래스 스퀘어클 · 블루 · 앰버 · Bricolage Grotesque 폰트) 유지.
> 아이콘: 큰 블루 시계 링 + 앰버 되감기 화살표 + **앰버 시계바늘**. 워드마크 앰버 액센트는 **"A"**.

## 포함 자산

```
design_handoff_spectark/
├── README.md · CLAUDE_CODE_PROMPT.md
├── AppIcon-iOS.appiconset/         iOS/iPadOS 앱 아이콘 (풀블리드, 17 사이즈)
├── AppIcon-macOS.appiconset/       macOS 앱 아이콘 (여백+라운드, 16~1024)
├── LaunchScreen.storyboard         iOS/iPadOS 런치 (UIImageView 1개)
├── LaunchScreen.imageset/          권장: iPhone/iPad 다크 분기
├── launch/                          방향별 imageset + Mac-Window 스플래시
├── wordmark/                        wordmark-{white,navy}(.2x) · lockup-{white,navy}(.2x)
└── preview/                         app-icon-1024 · mac-icon-512 · launch-ipad-portrait
```

## 플랫폼 적용

| 플랫폼 | 아이콘 | 런치/스플래시 |
|---|---|---|
| iOS/iPadOS | `AppIcon-iOS.appiconset` (풀블리드) | `LaunchScreen.imageset` + `LaunchScreen.storyboard` |
| macOS | `AppIcon-macOS.appiconset` (여백+라운드) | `launch/Mac-Window.png`를 첫 윈도우 배경으로 |

빌드 후 iOS/iPad는 **시뮬레이터 캐시 클리어**(`Erase All Content and Settings`) 필수.

## 디자인 토큰

| Token | Value |
|---|---|
| 아이콘 글래스 바디 | `#EAF1FB → #D2E0F2 → #BCD0EA` |
| 시계 링 | `#4AA3FF → #1A6FE0` |
| 되감기 화살표 · 시계바늘 | `#FFE066 → #F5B400` (앰버) |
| 런치 배경 | radial `#1b2434 → #0c111b → #070a11` |
| 워드마크 | 흰색(다크 기본)/네이비(라이트), **"A"만 앰버** |
| 폰트 | Bricolage Grotesque ExtraBold (베이킹, 번들 불필요) |

## Specta 시리즈 일관성
- Spectalo(재생=비디오) · SpectaLing(웨이브폼=전사) · **SpectArk(시계 되감기=백업)**
- 같은 글래스·블루·앰버·폰트 DNA로 형제 시리즈임이 한눈에
