# MATARI v0.1 텔레메트리 실험 기록

- 상태: 구현 기준선
- 조사일: 2026-09-18
- 조사 환경: macOS, `codex-cli 0.155.0-alpha.2.6`
- 상위 문서: [Codex 로컬 텔레메트리 타당성 조사](codex-telemetry-feasibility.ko.md)

## 1. 목적

MATARI의 실제 집계 로직을 결정하기 위해 다음을 검증한다.

1. `token_count`와 `token_usage_record`의 관계
2. 세션별 누적 토큰의 중복과 counter reset
3. subagent 및 guardian 세션의 상속된 누적값
4. quota snapshot의 동시성 노이즈와 reset 구분
5. 로컬 마지막 quota와 Codex가 현재 보고하는 값의 일치 여부
6. 활성·보관 세션의 중복 가능성

## 2. 개인정보 보호 방식

실험은 다음 정보만 추출했다.

- 레코드 타입과 키
- timestamp와 ordinal
- 토큰 숫자
- quota 숫자와 reset timestamp
- thread source 범주
- 식별자의 존재 및 동일성 여부

다음 내용은 출력하거나 연구 문서에 저장하지 않았다.

- 프롬프트와 답변
- 도구 입력과 출력
- 파일 내용
- 작업 디렉터리
- 인증 정보
- 계정 식별자

## 3. 공식적으로 보장되는 범위

공식 OpenAI 문서는 다음 경로를 안내한다.

- 활성 세션 기록: `$CODEX_HOME/sessions`
- 보관 세션 기록: `$CODEX_HOME/archived_sessions`

문서는 로그에 민감한 정보가 있을 수 있으므로 공유 전에 검토하라고 안내한다. 내부 JSONL 필드와 집계 의미는 공개 계약으로 문서화돼 있지 않다.

출처: [OpenAI Docs — Codex 문제 해결](https://developers.openai.com/ko-KR/docs/reference/troubleshooting)

따라서 아래 결과는 현재 로컬 구현에 대한 관측이며, 호환성 파서와 fixture 테스트가 필요하다.

## 4. 실험 A — 사용량 레코드의 가용 범위

### 결과

- `token_count`는 조사한 거의 모든 사용 세션에서 관측됨
- 숫자 레코드가 있는 파일: 1,414개
- 조사한 `token_count` 레코드: 110,222개
- `token_usage_record`가 있는 파일: 87개
- 최초 관측일: 2026-08-11
- `token_usage_record`는 비교적 최근에 추가된 형식

### 결정

`token_usage_record`를 필수 원천으로 사용할 수 없다. v0.1의 기준 원천은 하위 호환 범위가 더 넓고 quota snapshot도 함께 가진 `token_count`로 한다.

`token_usage_record`는 존재할 때 진단 및 교차 검증에만 사용한다.

## 5. 실험 B — 두 토큰 레코드의 대응

`token_usage_record`가 있는 87개 파일에서 관련 레코드를 timestamp 순으로 비교했다.

| 항목 | 결과 |
|---|---:|
| `token_usage_record` | 5,391개 |
| 뒤따르는 `token_count`와 인접한 쌍 | 5,390개 |
| `usage.total_tokens` ↔ `last_token_usage.total_tokens` 불일치 | 12개 |
| `thread_token_usage.total_tokens` ↔ `total_token_usage.total_tokens` 불일치 | 1,357개 |

### 해석

- 최신 일반 흐름에서는 `usage`와 `last_token_usage`가 거의 동일함
- 완전히 일치하지 않는 예외가 존재함
- thread 누적값과 `token_count` 누적값은 상당수 세션에서 의미가 다름

### 결정

- 실제 집계: `token_count.info`
- 진단 비교: `token_usage_record`
- 두 형식이 충돌해도 사용자 화면을 오류로 만들지 않음
- 스키마 진단 로그에는 숫자의 불일치 여부만 기록하고 원문은 기록하지 않음

## 6. 실험 C — 누적 token counter의 특성

### 결과

| 항목 | 결과 |
|---|---:|
| 숫자 레코드가 있는 파일 | 1,414개 |
| 누적 token 레코드 | 110,222개 |
| 동일 누적값 반복 | 3,044회 |
| counter 감소가 있는 파일 | 6개 |
| counter 감소 이벤트 | 7회 |

동일 누적값이 반복되므로 모든 `last_token_usage`를 합하면 중복된다.

counter 감소는 두 형태로 나뉘었다.

### 형태 1 — 사용 없는 rebase

- 누적값 감소
- `last_token_usage.total_tokens == 0`
- 일부 과거 파일에서 새 누적값이 context window 크기와 같은 값으로 바뀜

이 이벤트는 새 토큰 사용으로 계산하지 않는다.

### 형태 2 — 새 epoch의 첫 응답

- 장시간 뒤 누적값 감소
- `last_token_usage.total_tokens > 0`
- 새 누적값이 `last_token_usage`와 같거나 그 값에서 다시 증가

이 이벤트는 `last_token_usage`를 새 토큰 기여량으로 계산한다.

## 7. 실험 D — subagent의 상속 누적값

일부 subagent와 guardian 세션은 첫 `total_token_usage`가 현재 파일에서 새로 발생한 사용량보다 훨씬 크다. 부모 또는 이전 문맥의 누적값을 상속한 것으로 관측된다.

전체 로컬 기록의 단순 마지막 누적값 합과 보정 합을 비교했다.

| thread source | 파일 | 마지막 누적값 단순 합 | 보정 합 |
|---|---:|---:|---:|
| user | 214 | 6.81B | 6.92B |
| subagent | 992 | 20.64B | 5.57B |
| agent-created | 32 | 261.51M | 261.51M |
| guardian review | 17 | 35.88M | 15.30M |
| unknown/구버전 | 159 | 514.83M | 514.68M |

subagent의 마지막 누적값을 단순 합하면 약 20.64B로 보이지만 보정 후 약 5.57B다. 첫 누적값을 그대로 더하면 심각한 중복이 발생한다.

### 결정 — 세션 토큰 delta

각 파일을 timestamp/ordinal 순서로 처리한다.

```text
첫 유효 token_count:
  contribution = max(last_token_usage.total_tokens, 0)

이후 total > previousTotal:
  contribution = total - previousTotal

이후 total == previousTotal:
  contribution = 0

이후 total < previousTotal and last == 0:
  contribution = 0
  새 baseline = total

이후 total < previousTotal and last > 0:
  contribution = last
  새 baseline = total
```

이 방식은 다음을 동시에 처리한다.

- 첫 파일에 상속된 부모 누적값 제외
- 반복 방출된 `last_token_usage` 제외
- 정상 누적 증가 반영
- compaction 또는 resume 이후 counter rebase 처리

## 8. 실험 E — 멀티에이전트 파일을 포함할지

subagent 파일의 첫 누적 baseline은 제외해야 하지만, 이후 모델 요청은 실제 로컬 토큰 사용이다. 따라서 subagent 파일 자체를 제외하면 실제 사용량을 누락한다.

### 결정

- `user`, `subagent`, `agent_created_thread`, `guardian_review`를 모두 수집
- thread source는 분석 차원으로 저장 가능하지만 v0.1 UI에는 노출하지 않음
- 각 파일 안에서 위의 delta 규칙을 적용
- 부모와 자식이라는 이유만으로 자식 토큰을 제거하지 않음

## 9. 실험 F — quota snapshot의 동시성

모든 snapshot을 시간순으로 합치면 동일한 `resets_at` 안에서도 `used_percent`가 감소하는 경우가 있다.

전체 기록에서 관측한 canonical `codex` bucket:

| 창 | 같은 epoch 내 증가 | 같은 epoch 내 감소 | reset처럼 보이는 전환 |
|---|---:|---:|---:|
| 300분 | 4,991 | 1,676 | 284 |
| 10,080분 | 2,299 | 990 | 105 |

현재 월의 주간 bucket에서도 같은 epoch 내 감소가 37회 관측됐다.

### 해석

여러 세션이 동시에 요청하면 먼저 생성된 오래된 quota snapshot이 늦게 기록될 수 있다. 따라서 시간순으로 모든 양의 변화량을 합하면 값의 왕복을 반복 소비로 잘못 계산한다.

### 결정 — quota high-water mark

snapshot을 다음 epoch key로 그룹화한다.

```text
limit_id + window_minutes + resets_at
```

같은 epoch에서는:

- `used_percent` 최고 관측값만 전진시킴
- 최고값보다 낮은 snapshot은 stale snapshot으로 무시
- 같은 값은 중복으로 무시

기간 소비량은 epoch별 high-water 증가분을 합산한다.

```text
epoch가 기간 시작 전에 존재:
  baseline = 기간 시작 직전까지의 high-water

epoch가 기간 안에 시작:
  baseline = 0

과거 baseline을 관측하지 못함:
  첫 관측값을 baseline으로 두고 이후 증가만 계산
```

과거 baseline이 없으면 값을 추정하지 않고 `계산 중` 상태를 유지한다.

## 10. 실험 G — 여러 reset timestamp의 교차 기록

동시 세션 때문에 새 epoch가 시작된 뒤 과거 `resets_at`을 가진 snapshot이 다시 기록될 수 있다. 시간순으로 `현재 epoch` 하나만 교체하면 새 epoch와 과거 epoch가 반복 전환되는 문제가 생긴다.

### 결정

- epoch를 `resets_at`별로 독립 저장
- UI의 현재 bucket은 아직 reset되지 않은 epoch 중 가장 최근에 관측된 적절한 epoch를 선택
- `resets_at <= now`인 epoch는 현재 퍼센트 후보에서 제외
- 과거 epoch가 늦게 도착해도 현재 epoch를 되돌리지 않음

## 11. 실험 H — limit ID 선택

대부분의 파일은 `limit_id = codex`를 기록한다. 소수 파일에서 `codex_bengalfox` 또는 `null`도 관측됐다.

`codex_bengalfox`는 소수의 user/subagent 파일에서 나타났으며 snapshot 특성이 canonical `codex`와 달랐다.

### 결정

- 모든 limit ID를 파싱하고 파생 저장소에 보존
- v0.1 UI는 canonical `codex`를 우선 표시
- `codex`가 없을 때만 최신의 유효하고 plan 정보가 있는 다른 limit group을 fallback으로 검토
- 서로 다른 limit ID의 bucket을 한 줄에 섞지 않음
- 새로운 ID를 자동으로 canonical로 승격하지 않음

## 12. 실험 I — 현재값 교차 확인

조사 시점의 가장 최근 로컬 canonical snapshot:

- used: 97%
- window: 10,080분
- secondary: 없음
- plan: `prolite`

Codex 앱이 같은 시점에 보고한 core usage와 used percent, window, reset timestamp, plan type이 모두 일치했다.

### 결정

로컬 JSONL의 최신 canonical snapshot은 현재 quota quick view의 데이터 원천으로 사용할 수 있다. 단, Codex가 새 snapshot을 기록하지 않으면 값도 갱신되지 않는다는 한계는 유지한다.

## 13. 실험 J — 활성 및 보관 세션

- 활성 파일과 보관 파일의 basename 중복: 0
- 같은 파일 안에 `session_meta`가 반복될 수 있음
- 파일별 첫 `session_meta.id` 기준으로 서로 다른 파일의 중복은 관측되지 않음

### 결정

- `sessions`와 `archived_sessions`를 모두 검색
- 파일 안에서 반복되는 session metadata는 한 번만 채택
- archive 이동은 basename 또는 session ID와 파일 fingerprint로 기존 cursor를 승계
- 경로만 바뀌었다고 전체 파일을 다시 집계하지 않음

## 14. 확정된 v0.1 집계 원천

### 토큰

```text
token_count.info.total_token_usage
token_count.info.last_token_usage
```

### quota

```text
token_count.rate_limits.limit_id
token_count.rate_limits.primary / secondary
used_percent
window_minutes
resets_at
plan_type
```

### 보조 metadata

```text
session_meta.id
session_meta.thread_source
session_meta.parent_thread_id
session_meta.cli_version
```

대화 본문과 도구 payload는 집계 모델에 포함하지 않는다.

## 15. 구현에 필요한 fixture

원본 대화 내용을 제거한 합성 fixture로 다음 사례를 만들어야 한다.

1. 정상 단일 세션 누적 증가
2. 동일 `token_count` 반복
3. 첫 total에 부모 누적값이 포함된 subagent
4. `last == 0` counter rebase
5. `last > 0` 새 counter epoch
6. 동일 quota epoch의 stale 감소 snapshot
7. reset 이후 과거 epoch snapshot의 지연 도착
8. primary만 있는 주간 제한
9. primary와 secondary가 모두 있는 제한
10. `rate_limits == null`
11. 미완성 마지막 JSONL 행
12. sessions에서 archived_sessions로 이동

## 16. 텔레메트리 단계 완료 판정

다음 결론은 구현에 충분한 근거가 확보됐다.

- 로컬 JSONL로 v0.1 구현 가능
- 토큰 단순 합산은 불가능하며 delta 보정 필요
- subagent를 제외하면 안 되지만 상속 baseline은 제외해야 함
- quota는 epoch별 high-water mark 필요
- canonical limit group 선택 필요
- 최신 로컬 quota는 현재 Codex core 값과 일치
- 공개 스키마가 아니므로 합성 fixture와 호환성 진단 필요

이제 데이터 모델과 집계 규칙을 코드 수준으로 설계할 수 있다.

