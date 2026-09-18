# MATARI 개인정보 안내

MATARI는 사용자의 Mac 안에서 동작하는 읽기 전용 Codex 사용량 도구입니다.

## 읽는 데이터

MATARI는 사용자가 선택한 `CODEX_HOME` 또는 기본 `~/.codex` 아래의 `sessions`와
`archived_sessions` JSONL을 읽습니다. 이 파일에는 민감한 대화 내용이 포함될 수 있지만,
MATARI가 사용하는 것은 다음과 같은 최소 field입니다.

- session file identity와 source 종류
- token count의 누적값과 최근 증가값
- quota window, 사용률, reset 시각과 관측 시각
- 증분 읽기를 위한 파일 경로, 크기, 수정 시각과 byte offset

## 저장하는 데이터

파생 데이터는 현재 사용자의 다음 로컬 영역에 SQLite로 저장됩니다.

```text
~/Library/Application Support/MATARI/matari.sqlite
```

저장 항목은 file cursor, session identity, 파생 token contribution, quota snapshot/epoch와
schema metadata입니다. 원본 JSONL 행, 프롬프트, 응답, tool payload와 인증 정보는 저장하지
않습니다.

앱과 파생 데이터를 제거하려면 MATARI를 종료하고 앱과 위 `MATARI` Application Support
폴더를 사용자가 직접 삭제할 수 있습니다.

## 전송과 수집

- MATARI는 자체 analytics, crash upload 또는 원격 telemetry를 전송하지 않습니다.
- Codex 서버에 quota를 요청하거나 인증 정보를 전송하지 않습니다.
- 설정의 오픈소스 링크는 사용자가 선택했을 때 기본 browser로 GitHub를 엽니다.
- 로그인 시 실행을 켜면 macOS의 `SMAppService`를 사용해 로컬 로그인 항목을 등록합니다.

## 수치의 범위

quota는 계정 전체 사용량을 반영할 수 있지만 token 합계는 현재 Mac의 로컬 관측값입니다.
다른 Mac, Codex Cloud 또는 ChatGPT Work 사용이 있으면 두 값의 범위가 다릅니다. MATARI는
이를 합치지 않으며 `토큰/1%`를 정확한 환산값이 아닌 `≈` 근사치로 표시합니다.

## 문의와 보안 제보

일반적인 개인정보 문의는 GitHub issue를 사용할 수 있습니다. 실제 session data 노출이나
취약점은 [SECURITY.md](SECURITY.md)의 비공개 보안 권고 경로로 제보해 주세요.
