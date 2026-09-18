# Codex 로컬 텔레메트리 타당성 조사

- 상태: 1차 조사 완료, 구현 전 검증 계속 필요
- 조사일: 2026-09-18
- 조사 환경: macOS, `codex-cli 0.155.0-alpha.2.6`
- 목적: MATARI v0.1에 필요한 사용량 데이터를 로컬에서 읽기 전용으로 얻을 수 있는지 판단
- 상세 실험: [MATARI v0.1 텔레메트리 실험 기록](telemetry-experiments-v0.1.ko.md)

## 1. 결론

**MATARI v0.1은 현재 로컬 데이터만으로 구현 가능하다.** 실제 세션 JSONL에서 토큰 사용량, quota 사용률, 제한 창 길이, 초기화 시각을 함께 관측할 수 있다.

다만 이것은 공개되고 버전이 고정된 telemetry API가 아니다. 공식 OpenAI 문서는 세션 기록의 위치와 `/status`에서 사용 가능량을 볼 수 있다는 사실은 설명하지만, JSONL 내부의 `token_count` 및 `rate_limits` 스키마를 안정적인 외부 계약으로 보장하지 않는다. 따라서 제품의 정확한 성격은 다음과 같다.

> Codex의 로컬 내부 기록을 이용하는 best-effort 관측기이며, 스키마 변경에 견디는 방어적 파서가 필요한 앱

## 2. 근거 수준

| 판단 | 근거 | 신뢰 수준 |
|---|---|---:|
| Codex 상태 데이터의 기본 루트는 `~/.codex` | 공식 문서 | 높음 |
| 세션 transcript는 `$CODEX_HOME/sessions`에 존재 | 공식 문서 | 높음 |
| `/status`는 현재 사용 가능량을 보여줌 | 공식 문서 | 높음 |
| 세션 JSONL에 토큰 및 rate-limit 스냅샷이 기록됨 | 현재 Mac의 로컬 관측 | 중간 |
| 현재 필드명이 향후에도 유지됨 | 보장 없음 | 낮음 |
| quota 퍼센트가 정확한 실수 정밀도를 제공함 | 현재 관측상 정수 | 낮음 |

## 3. 공식 문서에서 확인된 범위

OpenAI 공식 문서는 다음을 확인해 준다.

- `CODEX_HOME`의 기본값은 `~/.codex`이며 구성, 로그, 세션 등 Codex 상태 데이터의 루트다.
- 문제 해결 문서에서 세션 transcript 경로를 `$CODEX_HOME/sessions`로 안내한다.
- 현재 사용 한도와 초기화 정보는 사용량 대시보드 또는 Codex CLI의 `/status`에서 확인할 수 있다.
- 로컬 메시지와 cloud chat은 사용량 quota를 공유할 수 있고, 모델·컨텍스트·추론·도구·검색·캐시 등이 소비량에 영향을 준다.

공식 자료:

- [Codex 환경 변수](https://developers.openai.com/ko-KR/docs/config-file/environment-variables)
- [Codex 고급 구성](https://developers.openai.com/ko-KR/docs/config-file/config-advanced)
- [Codex 문제 해결](https://developers.openai.com/ko-KR/docs/reference/troubleshooting)
- [Codex 가격 및 사용량](https://developers.openai.com/ko-KR/docs/pricing)

공식 문서에서 찾지 못한 보장:

- `rollout-*.jsonl` 파일명 규칙의 안정성
- `payload.type == "token_count"` 스키마
- `rate_limits.primary`와 `secondary`의 의미 및 순서
- `used_percent`, `window_minutes`, `resets_at` 필드의 장기 호환성
- 기록 시점과 갱신 빈도

## 4. 로컬 조사 방법

민감한 대화 본문은 출력하거나 복사하지 않았다. 다음 메타데이터만 조사했다.

- 파일 수와 날짜 범위
- JSON 레코드 타입
- 객체의 키와 값 타입
- 제한 창 종류와 결측 여부
- 토큰 누적값의 단조 증가 여부
- 퍼센트 값의 정밀도와 범위

`auth.json`, 프롬프트, 응답, 도구 입출력은 조사 대상에서 제외했다.

## 5. 로컬 관측 결과

### 5.1 파일 구성

조사한 환경에서는 다음이 확인됐다.

- 기본 루트: `~/.codex`
- 활성 세션: `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`
- 보관 세션: `~/.codex/archived_sessions/*.jsonl`
- 활성 JSONL: 1,423개
- 보관 JSONL: 3개
- 관측 날짜 범위: 2026-04-24 ~ 2026-09-18

세션 파일에는 사용량 정보뿐 아니라 대화와 도구 실행 내용도 함께 들어 있다. 전체 파일을 별도 위치에 복사하는 설계는 피해야 한다.

### 5.2 관련 레코드

현재 세션에는 두 종류의 사용량 관련 레코드가 관측된다.

1. `event_msg` 안의 `payload.type == "token_count"`
2. 최상위 `type == "token_usage_record"`

`token_count`의 관측된 개념 구조는 다음과 같다. 아래 예시는 실제 값이 아닌 스키마 요약이다.

```json
{
  "timestamp": "ISO-8601 문자열",
  "type": "event_msg",
  "payload": {
    "type": "token_count",
    "info": {
      "total_token_usage": {
        "input_tokens": "number",
        "cached_input_tokens": "number",
        "output_tokens": "number",
        "reasoning_output_tokens": "number",
        "total_tokens": "number"
      },
      "last_token_usage": {
        "...": "동일한 토큰 필드"
      },
      "model_context_window": "number"
    },
    "rate_limits": {
      "limit_id": "string",
      "plan_type": "string 또는 null",
      "primary": {
        "used_percent": "number",
        "window_minutes": "number",
        "resets_at": "Unix timestamp number"
      },
      "secondary": "동일 구조 또는 null"
    }
  }
}
```

`token_usage_record`에는 세션, 스레드, 턴 식별자와 함께 다음 누적 구조가 관측된다.

- `usage`
- `turn_token_usage`
- `thread_token_usage`

각 구조는 입력, 캐시 입력, 출력, 추론 출력, 전체 토큰 필드를 가진다. 어떤 레코드를 집계의 최종 기준으로 삼을지는 fixture 비교 실험 후 확정해야 한다.

### 5.3 제한 버킷 변형

전체 기록에서는 다음 형태가 모두 관측됐다.

- `primary = 300분`, `secondary = 10,080분`
- `primary = 10,080분`, `secondary = null`
- `limit_id = codex`
- `limit_id = codex_bengalfox`
- `plan_type = plus | pro | prolite | null`

현재 월 표본의 `token_count` 5,700여 건은 모두 `primary = 10,080분`, `secondary = null`이었다. 과거 기록이 있는 1,117개 파일에서는 300분 제한도 확인됐다.

따라서 다음 가정을 해서는 안 된다.

- `primary`가 항상 5시간 제한이다.
- `secondary`가 항상 주간 제한이다.
- 제한 버킷은 항상 두 개다.
- `limit_id`는 항상 하나의 고정 문자열이다.

버킷은 배열처럼 일반화해 `window_minutes` 기준으로 해석하는 편이 안전하다.

### 5.4 퍼센트와 초기화 시각

현재 로컬 기록의 약 17만 개 `used_percent` 값은 다음 특성을 보였다.

- 모두 숫자 타입
- 모두 0~100 범위
- 모두 정수값

현재 월의 quota 레코드는 `resets_at`이 숫자형 Unix timestamp였고 결측이 관측되지 않았다.

정수 퍼센트이므로 `토큰/1%`는 본질적으로 양자화 오차가 큰 근삿값이다. UI의 `≈` 표시는 필수다.

### 5.5 토큰 누적 특성

최근 20개 파일의 `total_token_usage.total_tokens`는 파일 안에서 감소하지 않았다. 동일한 누적값이 인접 레코드에 반복된 경우도 있었다.

따라서 모든 `last_token_usage` 또는 모든 `total_token_usage`를 단순 합산하면 중복 집계할 수 있다. 세션별 누적 카운터의 증가분을 계산하는 방식이 필요하다.

현재 월 대부분의 레코드에서 `total_tokens == input_tokens + output_tokens` 관계가 관측됐지만 예외도 있었다. `cached_input_tokens`와 `reasoning_output_tokens`는 별도 분석 차원으로 취급하고 대표 토큰 합계에 다시 더하지 않아야 한다.

## 6. 제품 기능별 실현 가능성

| 제품 값 | 로컬 원천 | 판정 | 주의점 |
|---|---|---:|---|
| 현재 잔여율 | `used_percent` | 가능 | 마지막 요청 시점의 스냅샷 |
| 제한 창 이름 | `window_minutes` | 가능 | 알려지지 않은 창에 대한 fallback 필요 |
| 초기화 절대시각 | `resets_at` | 가능 | Unix timestamp 변환 필요 |
| 초기화까지 남은 시간 | `resets_at - 현재 시각` | 가능 | snapshot이 오래돼도 시계 계산은 가능 |
| 오늘 로컬 토큰 | 세션별 누적 토큰 delta | 가능 | 날짜 경계, 병렬 세션, 중복 처리 필요 |
| 이번 주 로컬 토큰 | 동일 | 가능 | 한국 시간대 월요일 경계 필요 |
| 오늘/주간 `토큰/1%` | 로컬 토큰 delta + quota snapshot delta | 조건부 가능 | 계정 전체 quota와 로컬 토큰의 관측 범위가 다름 |
| Codex 비활성 상태 | 마지막 유효 이벤트 시각 | 가능 | 비활성 임계값은 제품 결정 필요 |
| 서버 기준 실시간 퍼센트 | 로컬 파일만 사용 | 불가 | 새 Codex 이벤트가 있어야 snapshot 갱신 |

## 7. 핵심 한계

### 7.1 공개 API가 아니다

세션 JSONL 내부 스키마는 변경될 수 있다. 필드 추가는 무시하고, 필드 누락·타입 변경·새 레코드 버전을 오류 없이 처리해야 한다.

### 7.2 quota와 토큰의 관측 범위가 다르다

quota는 계정의 다른 기기나 cloud 사용량까지 반영할 수 있다. 반면 MATARI가 읽는 토큰은 현재 Mac의 로컬 세션에 한정된다. 따라서 `1%당 토큰`은 회계값이 아니라 상관관계 지표다.

### 7.3 수동으로 서버를 조회하지 않는다

MATARI는 인증 정보를 읽거나 비공개 API를 호출하지 않는다. Codex가 새 이벤트를 기록하지 않으면 quota 퍼센트도 새로워지지 않는다. `마지막 갱신`이 제품 신뢰성의 핵심이다.

### 7.4 세션 파일에는 민감한 내용이 있다

파서는 필요한 레코드 타입만 스트리밍으로 처리해야 한다. 원본 행, 대화 텍스트 또는 인증 정보를 로그와 데이터베이스에 남기지 않는다.

### 7.5 앱 샌드박스와 배포

샌드박스 없는 직접 배포 앱은 사용자 권한으로 `~/.codex`를 읽을 수 있다. 향후 App Sandbox를 활성화하면 사용자가 폴더를 선택하고 security-scoped bookmark를 부여하는 흐름이 필요할 수 있다. v0.1 배포 전략과 함께 다시 결정한다.

## 8. 권장 수집 설계

### 8.1 경로 탐색

1. 사용자가 지정한 Codex 데이터 경로
2. 앱이 확인할 수 있는 `CODEX_HOME`
3. 기본값 `~/.codex`

Finder에서 실행한 앱은 셸 환경 변수를 그대로 상속하지 않을 수 있으므로 사용자 지정 경로 fallback이 필요하다.

### 8.2 원본 읽기

- `sessions`와 `archived_sessions`를 모두 대상으로 한다.
- JSONL을 한 줄씩 스트리밍 파싱한다.
- 마지막 미완성 행은 실패로 확정하지 않고 다음 변경 시 재시도한다.
- 파일별 안정 식별자, 읽은 byte offset, 마지막 레코드 정보를 기록한다.
- 파일 이동과 archive를 중복 신규 세션으로 취급하지 않는다.

### 8.3 데이터 추출

허용 목록 방식으로 다음 숫자와 식별 정보만 추출한다.

- 이벤트 시각
- 세션 또는 스레드 식별자
- 토큰 누적 카운터
- limit ID
- window minutes
- used percent
- reset timestamp

그 밖의 payload는 디코딩 후 즉시 버린다.

### 8.4 집계

- 토큰 첫 레코드: 상속된 누적값 대신 `last_token_usage`만 반영
- 이후 토큰: 세션별 누적 카운터의 양의 증가분만 반영
- 동일 누적값: 증가량 0
- 카운터 감소 + `last == 0`: 사용 없는 rebase로 처리
- 카운터 감소 + `last > 0`: 새 epoch의 첫 사용량으로 `last` 반영
- quota: `limit_id + window_minutes + resets_at`별 epoch 저장
- 같은 quota epoch: `used_percent` high-water mark만 전진
- 같은 epoch의 감소 snapshot: 동시성으로 늦게 도착한 stale 값으로 무시
- reset: 새 `resets_at` epoch를 독립 생성하며 과거 epoch의 지연 도착을 허용
- 날짜 집계: Asia/Seoul 기준으로 일/주 경계를 계산

원본 JSONL 전체를 별도 보관하지 않고 파생 레코드만 저장한다.

### 8.5 스키마 호환성

- 알 수 없는 필드와 레코드 타입은 무시
- 핵심 필드가 없으면 해당 레코드만 건너뜀
- 파서 버전과 관측한 스키마 fingerprint를 진단 정보로 저장
- 원본 대화 내용을 포함하지 않는 익명화된 진단 리포트 제공 가능성 검토

## 9. 구현 전 추가 실험

다음 항목은 코드를 본격 구현하기 전에 작은 조사 도구 또는 테스트 fixture로 확인해야 한다.

1. `token_count`와 `token_usage_record`의 토큰 값이 같은 작업에서 어떻게 대응하는지
2. 세션 중 compaction 또는 모델 변경 시 누적 카운터가 어떻게 변하는지
3. subagent/병렬 세션의 토큰이 부모 세션에 중복 반영되는지
4. 세션 archive 시 파일 식별과 offset을 어떻게 유지할지
5. quota reset 전후 `used_percent`와 `resets_at` 변화 패턴
6. 다른 기기 또는 cloud 사용 후 로컬 snapshot이 어떻게 변하는지
7. Codex CLI와 데스크톱 앱이 같은 `CODEX_HOME`에서 같은 형식으로 기록하는지
8. 앱 업데이트 전후의 실제 스키마 변화 사례
9. 실행 중 파일 truncate, partial write, 삭제에 대한 처리
10. `CODEX_HOME` 사용자 지정 환경에서 Finder 실행 앱의 경로 탐색

## 10. 현재 의사결정

- v0.1 데이터 원천은 로컬 세션 JSONL로 한다.
- 인증 파일과 비공개 네트워크 API는 사용하지 않는다.
- rate-limit 버킷은 `primary/secondary` 위치가 아니라 `window_minutes`로 해석한다.
- quota 퍼센트는 관측 시점 스냅샷으로 표현한다.
- 토큰 통계에는 `로컬 관측`의 의미를 제품 문구와 도움말에 명시한다.
- `1%당 토큰`은 근사 지표이며, 표본이 부족하면 표시하지 않는다.
- 실제 파서 구현 전에 익명화 fixture와 집계 불변조건을 먼저 만든다.
