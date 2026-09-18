# MATARI v0.1 기술 설계

- 상태: v0.1 구현 기준선
- 최종 갱신: 2026-09-18
- 제품 기준: [MATARI v0.1 제품 기획](product-plan-v0.1.ko.md)
- UX 기준: [MATARI v0.1 UX 상태 명세](ux-state-spec-v0.1.ko.md)
- 데이터 근거: [MATARI v0.1 텔레메트리 실험 기록](telemetry-experiments-v0.1.ko.md)

## 1. 설계 목표

- Codex의 로컬 JSONL을 읽기 전용으로 수집
- 여러 세션과 subagent의 토큰을 중복 없이 집계
- quota snapshot의 동시성 노이즈를 보정
- 앱 재시작 후 전체 파일을 반복 파싱하지 않음
- 대화 본문과 인증 정보를 저장하지 않음
- 메뉴바 UI가 수집 및 파싱 작업에 의해 멈추지 않음
- 공개되지 않은 스키마 변화에 부분적으로 실패하고 복구 가능

## 2. 플랫폼 구성

```text
MATARI.app
├─ SwiftUI App
│  └─ MenuBarExtra (.window)
├─ Presentation
│  ├─ MenuBarLabelView
│  ├─ UsagePanelView
│  └─ SettingsView
├─ UsageDomain
│  ├─ Models
│  ├─ TokenAggregator
│  ├─ QuotaAggregator
│  └─ UsageSnapshotBuilder
├─ CodexTelemetry
│  ├─ CodexPathResolver
│  ├─ SessionFileScanner
│  ├─ JSONLStreamReader
│  ├─ TelemetryParser
│  └─ DirectoryWatcher
└─ Persistence
   ├─ SQLiteStore
   └─ SchemaMigrations
```

Dock과 앱 전환기에서는 숨기며 `LSUIElement = true`를 사용한다.

## 3. 모듈 경계

### 3.1 CodexTelemetry

책임:

- `CODEX_HOME` 및 기본 경로 탐색
- `sessions`, `archived_sessions` 파일 열거
- byte offset 기반 증분 읽기
- 완성된 JSONL 행만 parser로 전달
- directory change event debounce
- 원본 파일 수정 금지

이 모듈은 UI 타입과 SQLite query를 알지 않는다.

### 3.2 UsageDomain

책임:

- token contribution 계산
- quota epoch 및 high-water 계산
- 오늘/이번 주 집계
- 표시할 canonical limit group 선택
- UX 상태 생성

Foundation 외의 UI 프레임워크에 의존하지 않는다. 대부분을 `swift test`로 검증할 수 있어야 한다.

### 3.3 Persistence

책임:

- file cursor
- 파생 token contribution
- quota snapshot 및 epoch high-water
- 사용자 설정
- schema migration

원본 JSONL 행과 대화 본문을 저장하지 않는다.

### 3.4 Presentation

책임:

- `UsageViewState` 렌더링
- 시간과 숫자 현지화
- 설정 전환
- 접근성 label

Presentation은 JSONL을 직접 읽지 않는다.

## 4. 동시성 모델

```text
FSEvents
   ↓
TelemetryCoordinator actor
   ├─ file enumeration
   ├─ cursor coordination
   └─ parse scheduling
       ↓
UsageRepository actor
   ├─ SQLite transaction
   ├─ token delta
   ├─ quota high-water
   └─ snapshot publication
       ↓ MainActor
UsageViewModel
```

- 파일 읽기, JSON decode, SQLite write는 MainActor 밖에서 실행
- repository 변경 후 불변 `UsageSnapshot`만 UI로 전달
- 한 파일은 동시에 두 번 파싱하지 않음
- 여러 파일의 결과는 SQLite transaction으로 idempotent하게 반영

## 5. 원본 모델

### 5.1 SessionDescriptor

```swift
struct SessionDescriptor: Sendable, Equatable {
    let fileID: String
    let sessionID: String?
    let threadSource: ThreadSource
    let cliVersion: String?
    let startedAt: Date?
}
```

`fileID` 우선순위:

1. 첫 `session_meta.id`
2. rollout basename
3. 파일의 첫 timestamp와 크기를 이용한 fallback fingerprint

경로는 archive 이동으로 바뀔 수 있으므로 identity로 사용하지 않는다.

### 5.2 TokenSnapshot

```swift
struct TokenSnapshot: Sendable, Equatable {
    let eventID: EventID
    let fileID: String
    let observedAt: Date
    let ordinal: Int?
    let total: TokenUsage
    let last: TokenUsage
}
```

### 5.3 TokenUsage

```swift
struct TokenUsage: Sendable, Equatable {
    let inputTokens: Int64
    let cachedInputTokens: Int64
    let cacheWriteInputTokens: Int64
    let outputTokens: Int64
    let reasoningOutputTokens: Int64
    let totalTokens: Int64
}
```

모든 숫자는 64-bit signed integer로 저장한다. 음수와 overflow는 invalid record로 처리한다.

`cachedInputTokens`와 `reasoningOutputTokens`는 `totalTokens`에 다시 더하지 않는다.

### 5.4 QuotaSnapshot

```swift
struct QuotaSnapshot: Sendable, Equatable {
    let eventID: EventID
    let observedAt: Date
    let limitID: String
    let planType: String?
    let windowMinutes: Int
    let usedPercent: Double
    let resetsAt: Date
}
```

primary와 secondary를 같은 `QuotaSnapshot` 배열로 정규화한다. 위치가 아닌 `windowMinutes`로 UI 이름을 결정한다.

### 5.5 EventID

```text
fileID + ordinal
```

ordinal이 없으면:

```text
fileID + byteOffset + eventType
```

SQLite unique key로 사용해 재스캔을 idempotent하게 만든다.

## 6. 파생 모델

### 6.1 TokenContribution

```swift
struct TokenContribution: Sendable, Equatable {
    let eventID: EventID
    let occurredAt: Date
    let usage: TokenUsage
    let source: ThreadSource
}
```

원본 누적값이 아니라 해당 이벤트의 신규 기여량만 저장한다.

### 6.2 QuotaEpochKey

```swift
struct QuotaEpochKey: Hashable, Sendable {
    let limitID: String
    let windowMinutes: Int
    let resetsAt: Date
}
```

### 6.3 QuotaEpoch

```swift
struct QuotaEpoch: Sendable, Equatable {
    let key: QuotaEpochKey
    let planType: String?
    let firstObservedAt: Date
    let lastObservedAt: Date
    let highWaterUsedPercent: Double
}
```

### 6.4 UsageSnapshot

```swift
struct UsageSnapshot: Sendable, Equatable {
    let buckets: [UsageBucket]
    let todayTokens: Int64?
    let weekTokens: Int64?
    let todayTokensPerPercent: Double?
    let weekTokensPerPercent: Double?
    let lastQuotaObservation: Date?
    let state: UsageDataState
}
```

## 7. token delta 알고리즘

파일별 `lastTotalTokens`를 cursor와 함께 저장한다.

```swift
if cursor.lastTotalTokens == nil {
    contribution = snapshot.last
} else if snapshot.total.totalTokens > previousTotal {
    contribution = snapshot.total - previousTotal
} else if snapshot.total.totalTokens == previousTotal {
    contribution = .zero
} else if snapshot.last.totalTokens == 0 {
    contribution = .zero
} else {
    contribution = snapshot.last
}

cursor.lastTotalTokens = snapshot.total.totalTokens
```

TokenUsage의 각 차원은 같은 규칙으로 delta를 계산하되, 음수 차원은 0으로 clamp하고 진단 counter를 증가시킨다. 대표 합계는 `totalTokens` 필드를 따른다.

## 8. quota high-water 알고리즘

```swift
let key = QuotaEpochKey(limitID, windowMinutes, resetsAt)
epoch.highWater = max(epoch.highWater, snapshot.usedPercent)
epoch.lastObservedAt = max(epoch.lastObservedAt, snapshot.observedAt)
```

같은 epoch에서 낮아진 used percent는 이전 상태를 되돌리지 않는다.

### 기간 소비량

기간 `[start, end]`에 대해:

1. long-term bucket을 선택
2. 기간과 겹치는 epoch 열거
3. 기간 시작 직전의 high-water를 baseline으로 선택
4. 기간 중 high-water 증가분 계산
5. 기간 안에서 시작된 epoch는 baseline 0
6. 시작 전 baseline을 관측하지 못했다면 해당 epoch는 계산 불가

하나라도 필요한 baseline이 없으면 억지로 합산하지 않고 `tokensPerPercent = nil`로 둔다.

## 9. canonical quota 선택

우선순위:

1. `limitID == "codex"`인 유효 group
2. `planType != nil`이고 가장 최근에 관측된 유효 group
3. 없음

group 안에서:

- `resetsAt > now`
- window별 가장 최근에 관측된 epoch
- window가 짧은 순서로 UI 정렬

long-term bucket은 유효 bucket 중 `windowMinutes`가 가장 큰 값이다.

v0.1에서는 서로 다른 limit group을 동시에 한 메뉴바에 혼합하지 않는다.

## 10. 시간 집계

- 캘린더: Gregorian
- 로케일: `ko_KR`
- 시간대: `Asia/Seoul`
- 오늘: 현지 시각 00:00부터 다음 자정 전
- 이번 주: 월요일 00:00부터 다음 월요일 전

TokenContribution은 `occurredAt`을 기준으로 합산한다. UTC 원본 timestamp를 Date로 저장하고 query 경계를 UTC instant로 변환한다.

## 11. 파일 cursor

```swift
struct FileCursor: Sendable, Equatable {
    let fileID: String
    var currentPath: String
    var byteOffset: Int64
    var pendingBytes: Data
    var lastTotalTokens: TokenUsage?
    var fileSize: Int64
    var modifiedAt: Date
}
```

규칙:

- `pendingBytes`는 완성되지 않은 마지막 줄만 메모리에 유지
- 앱 종료 시 pending raw bytes는 저장하지 않음
- 다음 실행에서 마지막 완성 행의 byte offset부터 다시 읽음
- file size가 offset보다 작아지면 truncate로 보고 처음부터 identity 검사
- archive에서 같은 `fileID`를 발견하면 path만 갱신

## 12. JSONL 파서

전체 payload용 거대 Codable 모델을 만들지 않는다.

1. top-level envelope decode
2. 관심 type 판정
3. 필요한 payload만 선택 decode
4. 알 수 없는 field 무시
5. 타입이 잘못된 관심 레코드는 해당 행만 skip

관심 레코드:

- `session_meta`
- `event_msg` + `payload.type == token_count`
- `token_usage_record`는 진단 전용

파서 오류에는 원본 행을 포함하지 않는다.

## 13. 파일 감시

- 초기 실행: 전체 파일 열거 후 cursor 기반 증분 scan
- 실행 중: FSEvents로 `sessions`, `archived_sessions` 감시
- event burst: 약 250ms debounce
- panel open: 최신 directory metadata 재검사
- watcher event 유실 대비: 낮은 빈도의 directory reconciliation 수행 가능

정상 UI에 사용자가 누르는 새로고침 버튼은 두지 않는다.

## 14. SQLite schema

### `source_files`

```text
file_id TEXT PRIMARY KEY
current_path TEXT NOT NULL
byte_offset INTEGER NOT NULL
last_total_* INTEGER
file_size INTEGER
modified_at REAL
cli_version TEXT
thread_source TEXT
```

### `token_contributions`

```text
event_id TEXT PRIMARY KEY
file_id TEXT NOT NULL
occurred_at REAL NOT NULL
input_tokens INTEGER NOT NULL
cached_input_tokens INTEGER NOT NULL
cache_write_input_tokens INTEGER NOT NULL
output_tokens INTEGER NOT NULL
reasoning_output_tokens INTEGER NOT NULL
total_tokens INTEGER NOT NULL
thread_source TEXT NOT NULL
```

### `quota_snapshots`

```text
event_id TEXT NOT NULL
bucket_index INTEGER NOT NULL
observed_at REAL NOT NULL
limit_id TEXT NOT NULL
plan_type TEXT
window_minutes INTEGER NOT NULL
used_percent REAL NOT NULL
resets_at REAL NOT NULL
PRIMARY KEY(event_id, bucket_index)
```

### `quota_epochs`

```text
limit_id TEXT NOT NULL
window_minutes INTEGER NOT NULL
resets_at REAL NOT NULL
plan_type TEXT
first_observed_at REAL NOT NULL
last_observed_at REAL NOT NULL
high_water_used_percent REAL NOT NULL
PRIMARY KEY(limit_id, window_minutes, resets_at)
```

### `app_metadata`

```text
key TEXT PRIMARY KEY
value BLOB NOT NULL
```

SQLite는 WAL mode와 transaction을 사용한다. 원본 transcript는 저장하지 않는다.

## 15. UI state

```swift
enum UsageDataState: Sendable, Equatable {
    case loading(hasCachedData: Bool)
    case ready
    case noSessionDirectory
    case noSessions
    case noQuota
    case waitingForPostResetSnapshot
    case inaccessiblePath
    case readError(recoverable: Bool)
}
```

서로 동시에 가능한 세부 상태는 bucket 상태와 진단 상태로 분리한다. 예를 들어 quota 없음과 token 데이터 존재를 표현할 수 있어야 한다.

## 16. 설정 저장

### UserDefaults

- 로그인 시 자동 실행
- 사용자가 선택한 Codex 경로
- 첫 개인정보 안내 표시 여부

### SQLite

- parser/schema version
- file cursor
- derived usage history

인증 정보는 어떤 저장소에서도 읽거나 저장하지 않는다.

## 17. 테스트 구조

### Unit

- JSON envelope와 관심 payload decode
- token delta 모든 분기
- quota high-water와 지연 snapshot
- canonical limit group 선택
- 일/주 경계와 DST 비영향 확인
- 숫자 및 상대시간 formatter
- UsageDataState 생성

### Integration

- 임시 CODEX_HOME initial scan
- append 및 partial line
- 두 파일 동시 변경
- archive 이동
- truncate 및 재생성
- 앱 재시작 후 cursor resume
- SQLite migration

### UI

- 정상 두 bucket
- 단일 bucket
- quota 없음
- loading
- 비활성
- post-reset 대기
- path 오류
- 계산 중
- light/dark
- VoiceOver label

## 18. 진단

로컬 진단에는 다음 count와 상태만 기록한다.

- scanned files
- parsed relevant records
- skipped invalid records
- schema fingerprints
- counter rebases
- stale quota snapshots ignored
- last successful scan time

원본 JSON, 프롬프트, 응답, tool payload, cwd, 인증 정보는 기록하지 않는다.

## 19. 구현 순서

1. Swift package 형태로 Domain 및 Parser 구성
2. 합성 fixture와 unit test
3. SQLiteStore 및 integration test
4. directory scanner와 watcher
5. UsageViewModel
6. Xcode macOS app target
7. MenuBarExtra와 panel UI
8. 설정 및 login item
9. 실제 로컬 CODEX_HOME read-only smoke test
10. release build 및 UX 완료 조건 검증

## 20. 프로젝트 생성 기준

다음 값은 사용자 확인을 거쳐 v0.1 기준으로 확정했다.

1. 최소 지원 macOS 버전
   - 확정: macOS 13
   - 이유: `MenuBarExtra`와 현대적인 login item API를 지원하면서 범위가 넓음
2. bundle identifier
   - 확정: `com.dreamhyoungs.matari`
3. 개발 환경
   - `/Applications/Xcode.app`의 전체 Xcode를 사용
   - core Swift package, parser/domain 및 unit test는 `swift test`로 검증
   - macOS app target, asset catalog와 Release `.app`은 `xcodebuild`로 검증

## 21. v0.1 구현 검증 기록

2026-09-18 기준:

- Swift Package core test 24개 통과
- Debug 및 Release macOS app target 빌드 성공
- bundle identifier `com.dreamhyoungs.matari` 확인
- 최소 macOS 13 및 `LSUIElement = true` 확인
- app icon asset catalog 컴파일 확인
- ad-hoc 서명 및 `codesign --verify --deep --strict` 통과
- 실제 로컬 CODEX_HOME 1,426개 파일 read-only smoke test 성공
- 최초 smoke에서 111,757개 관심 레코드 파싱, 파일 읽기 실패 0개
- 증분 smoke 2.44초, 새 관심 레코드 49개 반영, 중복 집계 없음
- 정상, 단일 버킷, quota 없음, 비활성, reset 대기, 경로·읽기 오류 presentation 상태 테스트 통과
- 실제 데이터에서 오늘/이번 주 로컬 토큰 및 두 `≈ 토큰/1%` 값 생성 확인
- 실제 SwiftUI 패널과 설정 화면의 레이아웃 및 접근성 트리 확인
