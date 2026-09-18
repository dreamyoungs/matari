# MATARI

MATARI는 macOS 메뉴바에서 Codex 사용 한도와 이 Mac에서 관측한 로컬 토큰 사용량을 보여주는 읽기 전용 앱입니다.

> [!IMPORTANT]
> MATARI는 비공식 커뮤니티 프로젝트이며 OpenAI가 개발·보증하거나 지원하는 제품이
> 아닙니다. Codex의 로컬 JSONL 내부 형식은 안정된 공개 API가 아니므로 향후 변경될 수
> 있습니다.

## 요구 사항

- macOS 13 이상
- Xcode 16 이상
- Codex Desktop 또는 CLI의 로컬 세션 기록

## 실행

Xcode에서 `Matari.xcodeproj`를 열고 `MATARI` scheme을 실행합니다. 앱은 Dock에 나타나지 않으며 화면 상단 메뉴바에 MATARI 심볼과 현재 잔여율을 표시합니다.

터미널에서 검증용 Release 빌드를 만들려면:

```sh
./scripts/build-release.sh
```

생성 위치:

```text
.build/ReleaseDerivedData/Build/Products/Release/MATARI.app
```

스크립트는 로컬 실행 검증을 위해 앱에 ad-hoc 서명을 적용합니다. 외부 배포에는 Apple Developer 인증서와 notarization 설정이 별도로 필요합니다.

로컬 CODEX_HOME 호환성 smoke test:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run matari-smoke
```

smoke 도구는 파일 수와 파생 숫자만 출력하며 원본 대화, 프롬프트, 응답 또는 tool payload를 출력하지 않습니다.

## 개인정보와 데이터 범위

- `$CODEX_HOME/sessions`와 `$CODEX_HOME/archived_sessions`를 읽기 전용으로 확인합니다.
- `session_meta`와 `token_count`에서 필요한 식별·숫자 필드만 파싱합니다.
- 원본 JSONL, 대화 본문 및 인증 정보는 MATARI 데이터베이스에 저장하지 않습니다.
- quota는 계정 전체 사용량일 수 있지만 토큰 합계는 현재 Mac의 로컬 관측값입니다.

자세한 내용은 [개인정보 안내](PRIVACY.md)와 [보안 정책](SECURITY.md)을 참고하세요.

## 기여하기

작은 버그 수정, telemetry schema 호환성 검증, 접근성 개선과 보안 리뷰를 환영합니다.
[CONTRIBUTING.md](CONTRIBUTING.md)의 개발·검증 절차를 먼저 확인해 주세요.
[행동 강령](CODE_OF_CONDUCT.md)은 issue, pull request와 프로젝트 커뮤니티 공간에 모두
적용됩니다.

저장소 공개와 공식 바이너리 배포는 별개의 단계입니다. 유지관리 절차는
[공개·릴리스 체크리스트](docs/public-release-checklist.ko.md)에 정리되어 있습니다.

## 라이선스와 상표

MATARI의 source code와 문서는 별도 표기가 없는 한 [Apache License 2.0](LICENSE)으로
공개됩니다. `OpenAI`와 `Codex`는 각 권리자의 상표이며, 이 저장소의 라이선스는 해당
상표에 대한 권리를 부여하지 않습니다.

## 문서

- [제품 기획](docs/product-plan-v0.1.ko.md)
- [UX 상태 명세](docs/ux-state-spec-v0.1.ko.md)
- [텔레메트리 실험 기록](docs/telemetry-experiments-v0.1.ko.md)
- [기술 설계](docs/technical-design-v0.1.ko.md)
- [변경 기록](CHANGELOG.md)
