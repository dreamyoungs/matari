# Contributing to MATARI

MATARI에 관심을 갖고 기여해 주셔서 감사합니다. 작은 버그 수정, Codex 로컬 텔레메트리
호환성 검증, 접근성 개선, 집중된 UX 제안, 문서와 보안 리뷰를 환영합니다.

[행동 강령](CODE_OF_CONDUCT.md)을 따라 주세요. 취약점이나 민감정보 노출은 공개 issue가
아니라 [SECURITY.md](SECURITY.md)의 비공개 경로로 제보해 주세요.

## 시작하기 전에

- 기존 issue와 pull request를 검색해 중복 작업을 피합니다.
- 데이터 모델, 집계 규칙, 개인정보 경계, 새로운 네트워크 기능 또는 UI 구조를 크게 바꾸는
  작업은 먼저 issue에서 논의합니다.
- pull request는 한 가지 목적에 집중하고, 관련 없는 리팩터링을 분리합니다.
- 실제 Codex JSONL, 프롬프트, 응답, tool payload, 계정·세션 식별자, 사용자명, 절대 경로,
  인증 정보 또는 이를 포함한 screenshot을 추가하지 않습니다.

## 개발 환경

- macOS 13 이상
- Xcode 16 이상과 Swift 6 호환 toolchain

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
./scripts/build-release.sh
git diff --check
```

Xcode에서는 `Matari.xcodeproj`의 `MATARI` scheme을 실행합니다. 검증용 Release 앱은 다음에
생성됩니다.

```text
.build/ReleaseDerivedData/Build/Products/Release/MATARI.app
```

## 설계와 개인정보 경계

- Codex의 `sessions`와 `archived_sessions`는 읽기 전용으로 취급합니다.
- Presentation, 집계 규칙, JSONL parsing, 파일 cursor와 SQLite persistence의 경계를
  유지합니다.
- 원본 JSONL 행, 대화 본문, 프롬프트, 응답과 tool payload를 저장하거나 log에 남기지
  않습니다.
- 인증 파일을 읽거나 Codex 인증·설정·quota를 변경하지 않습니다.
- 공개되지 않은 JSONL schema는 바뀔 수 있습니다. parser 변경에는 합성 fixture, 손상 행,
  unknown field와 partial line 검증을 포함합니다.
- quota는 계정 전체 관측값일 수 있고 토큰은 현재 Mac의 로컬 관측값이라는 구분을 UI와
  문서에서 유지합니다.
- 새 네트워크 요청, telemetry, 외부 process, 권한 또는 background 동작은 사전 논의와
  개인정보·보안 설명이 필요합니다.

## 검증

pull request를 열기 전에 다음을 실행합니다.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
./scripts/build-release.sh
codesign --verify --deep --strict --verbose=2 \
  .build/ReleaseDerivedData/Build/Products/Release/MATARI.app
git diff --check
```

로컬 실데이터 smoke test는 선택 사항입니다.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run matari-smoke
```

smoke 출력과 screenshot에는 원문 session data나 개인 식별정보가 없어야 합니다. UI 변경은
가능한 범위에서 다음을 확인합니다.

- 라이트·다크 모드
- 정상, 단일 버킷, quota 없음, reset 대기와 오류 상태
- 키보드와 VoiceOver label
- Reduce Motion 및 색상 외 상태 정보

## 커밋과 pull request

간결한 Conventional Commit 제목을 사용합니다. 한국어 또는 영어 모두 가능하지만 한
커밋에서는 한 언어를 일관되게 사용합니다.

```text
feat: 단일 quota 버킷 표시를 추가
fix: partial JSONL 행의 cursor 갱신을 보류
docs: 공개 릴리스 절차를 정리
```

pull request에는 다음 내용을 포함합니다.

- 사용자가 겪는 문제
- 선택한 접근과 중요한 tradeoff
- 수행한 검증
- 개인정보와 보안 영향
- 의도적으로 미룬 작업

기여물을 제출하면 [Apache License 2.0](LICENSE) 제5조에 따라 같은 라이선스로 프로젝트에
포함되는 것에 동의하게 됩니다.
