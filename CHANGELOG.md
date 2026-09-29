# Changelog

MATARI의 주목할 만한 변경 사항을 기록합니다. 형식은
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/)를 참고하며 version은
[Semantic Versioning](https://semver.org/)을 따릅니다.

## [Unreleased]

## [0.2.0] - 2026-09-29

개발용 Pre-release. Developer ID 서명 및 Apple 공증을 받지 않은 ad-hoc 빌드입니다.
다른 Mac에서 Gatekeeper 보안 경고 또는 실행 차단이 발생할 수 있습니다.

### Changed

- 설정 버전을 앱 bundle 정보와 통일: 0.2.0, build 2
- 라이트·다크 테마별 반투명 바탕과 보조 글씨·그래프 축 대비 개선

### Fixed

- quota 초기화 시각 흔들림과 관측 구간·요금제에 따른 비율 계산 보완
- 독립창의 헤더 드래그 영역 확대와 비활성 창 첫 클릭 처리

### Added

- 30분 주기 계정 quota 조회, 수동 갱신 및 잠자기 복귀 조회
- 최근 48시간 잔여율 그래프와 5시간·주간 제한 선택
- 앵커 독립창, 헤더 드래그 이동 및 메뉴바 복귀

- macOS 메뉴바 전용 SwiftUI 앱
- 동적 quota 버킷과 reset 대기 상태
- 오늘·이번 주 로컬 token 합계와 근사 token/1%
- Codex JSONL 증분 scanner, FSEvents watcher와 SQLite 파생 저장소
- 한국어 사용량·설정 UI와 접근성 label
- 합성 fixture 기반 core test 및 로컬 read-only smoke 도구

[Unreleased]: https://github.com/dreamyoungs/matari/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/dreamyoungs/matari/releases/tag/v0.2.0
