# MATARI 보안 정책

MATARI는 프롬프트, 응답, tool payload와 로컬 경로를 포함할 수 있는 Codex session JSONL을
읽습니다. 취약점과 민감정보 노출은 공개 issue보다 비공개 경로로 먼저 알려 주세요.

## 취약점 제보

[GitHub 비공개 보안 권고](https://github.com/dreamyoungs/matari/security/advisories/new)를
사용해 주세요. 해당 기능을 사용할 수 없다면 공개 issue에는 민감정보를 제거한 최소 설명만
남기고, 원본 JSONL이나 진단 파일을 첨부하지 마세요.

제보에는 가능한 범위에서 다음 정보를 포함해 주세요.

- 영향을 받는 commit 또는 앱 version
- macOS와 Xcode/Swift version
- Codex Desktop, CLI 또는 관련 session source
- 합성 데이터로 재현 가능한 단계
- 예상 영향과 이미 확인한 완화 방법

프롬프트, 응답, tool 입력·출력, credential, account/session ID, 사용자명, 절대 경로와 실제
session file은 보내지 마세요. 꼭 필요한 경우에도 먼저 private advisory에서 안전한 전달
방법을 협의합니다.

## 지원 범위

첫 정식 Release 전에는 `main` branch의 최신 commit만 보안 수정 대상입니다. 첫 Release
게시 후 이 문서에 지원 version 범위를 명시합니다.

## 현재 구현된 경계

- 기본 `CODEX_HOME`의 `sessions`와 `archived_sessions`를 읽기 전용으로 확인합니다.
- `session_meta`와 `token_count`의 필요한 식별·숫자 field만 선택적으로 파싱합니다.
- 원본 JSONL, 프롬프트, 응답, tool payload와 인증 정보는 MATARI SQLite에 저장하지 않습니다.
- 파일 cursor, session file identity, 파생 token contribution, quota snapshot과 epoch만 로컬에
  저장합니다.
- 인증 파일을 요구하거나 읽지 않고, Codex의 인증·설정·quota 또는 session file을 수정하지
  않습니다.
- 앱 자체는 서버 telemetry나 background network request를 전송하지 않습니다. 설정의
  오픈소스 링크는 사용자가 선택할 때만 기본 browser를 엽니다.
- 파일 변경은 FSEvents로 감지하고, 완성되지 않은 마지막 JSONL 행은 저장하지 않고 다음
  쓰기까지 보류합니다.
- 손상된 개별 행은 건너뛰며 원문을 오류 메시지나 진단에 포함하지 않습니다.

## 현재 한계

- Codex JSONL 내부 schema는 공개 안정 API가 아니며 변경될 수 있습니다.
- MATARI는 sandboxed app이 아니며 선택한 Codex 폴더를 현재 macOS 사용자 권한으로 읽습니다.
- 파생 SQLite는 암호화되지 않은 현재 사용자 Application Support 영역에 저장됩니다. 원문은
  저장하지 않지만 session identity, 로컬 파일 경로와 사용량 숫자는 포함됩니다.
- 같은 macOS 사용자 권한으로 실행되는 악성 process로부터 session file이나 파생 DB를
  보호하지는 못합니다.
- quota는 다른 Mac, Codex Cloud 또는 ChatGPT Work 사용을 포함할 수 있지만 토큰은 현재
  Mac에서 관측한 값이므로 `토큰/1%`는 근사치입니다.
- 공개 배포용 Developer ID 서명과 notarization은 아직 구성되지 않았습니다. 로컬 build의
  ad-hoc 서명은 배포 신뢰를 제공하지 않습니다.

## 공개 저장소 원칙

- 실제 session JSONL, prompt, response, tool payload, cwd, account/session ID와 인증 정보를
  source, fixture, issue, screenshot 또는 test output에 포함하지 않습니다.
- fixture는 완전히 합성한 값만 사용하고 실제 기록을 익명화한 사본으로 대체하지 않습니다.
- 오류와 진단에는 원본 행 대신 익명화된 위치와 count만 사용합니다.
- 새 telemetry, network request, 업로드 또는 외부 service 연동은 기본 비활성·명시적 동의와
  별도 개인정보 검토 없이 추가하지 않습니다.

세부 데이터 경계는 [텔레메트리 타당성 문서](docs/codex-telemetry-feasibility.ko.md)와
[기술 설계](docs/technical-design-v0.1.ko.md)를 참고해 주세요.
