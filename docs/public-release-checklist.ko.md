# MATARI 공개·릴리스 체크리스트

이 문서는 저장소를 공개하고 macOS 바이너리를 배포할 때 유지관리자가 따르는 기준입니다.
소스 공개와 공식 바이너리 배포는 별개의 단계로 진행합니다.

## 현재 상태

- [x] Apache License 2.0 적용
- [x] README에 현재 기능, 데이터 범위와 build 방법 명시
- [x] 기여 안내, 행동 강령, 개인정보 안내와 보안 제보 경로 작성
- [x] Swift test와 macOS app bundle CI 작성
- [x] Swift·GitHub Actions Dependabot 설정
- [x] 합성 fixture만 사용하는 parser 및 집계 test
- [ ] GitHub 저장소 `PUBLIC` 전환
- [ ] private vulnerability reporting과 secret scanning 확인
- [ ] `main` branch protection과 필수 CI check 설정
- [ ] Developer ID Application 인증서와 notarytool profile 준비
- [ ] notarization된 첫 Release 게시

## 1. 공개 전에 확인할 것

1. 저장소 전체에서 credential, account/session ID, 사용자명, 절대 경로, 실제 prompt, response,
   tool payload와 session JSONL을 검색합니다.
2. fixture는 완전히 합성한 데이터인지 확인합니다. 실제 기록의 익명화 사본을 사용하지 않습니다.
3. screenshot과 문서 수치는 개인이나 계정을 식별할 수 없는지 확인합니다.
4. README의 기능과 한계가 실제 코드와 일치하는지 확인합니다.
5. `SECURITY.md`와 issue template의 private advisory URL이 동작하는지 확인합니다.
6. GitHub Actions가 fork pull request에서 secret 없이 `contents: read` 권한만 사용하는지
   확인합니다.

권장 검사:

```bash
rg -n -i 'PRIVATE KEY|AIza|ya29\.|authorization|password|api[_-]?key' . \
  -g '!.git/**' -g '!.build/**'
rg -n '/Users/|account[_ -]?id|session[_ -]?id' . \
  -g '!.git/**' -g '!.build/**'
git status --short
git diff --check
```

검색 결과는 무조건 삭제하지 말고 정책 설명과 실제 비밀정보를 구분해서 검토합니다.

## 2. 결정론적 검증

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
./scripts/build-release.sh
codesign --verify --deep --strict --verbose=2 \
  .build/ReleaseDerivedData/Build/Products/Release/MATARI.app
git diff --check
```

로컬 CODEX_HOME smoke test는 사용자의 기기에서만 실행합니다. session path, 원문 또는 식별자를
CI artifact나 공개 log에 옮기지 않습니다.

## 3. GitHub 저장소 공개

공개 직전에 다음 저장소 설정을 확인합니다.

- Issues와 private vulnerability reporting 활성화
- Actions workflow 권한을 read-only 기본값으로 제한
- `main`에 pull request와 `CI / Swift core and app bundle` 성공 요구
- force push와 branch 삭제 금지
- secret scanning, push protection와 Dependabot alerts 활성화
- 저장소 설명과 topics 설정

모든 검사가 끝나고 소유자가 최종 확인한 뒤에만 공개로 전환합니다.

```bash
gh repo edit dreamyoungs/matari \
  --visibility public \
  --accept-visibility-change-consequences
```

공개 전환은 fork와 외부 노출에 영향을 주므로 자동화하지 않고 저장소 소유자가 최종
확인합니다.

## 4. Developer ID와 notarization

Mac App Store 밖의 공식 앱 배포에는 Developer ID Application 서명, Hardened Runtime,
secure timestamp와 notarization을 사용합니다. 현재 `scripts/build-release.sh`의 ad-hoc 서명은
로컬 검증용이며 공개 배포 신뢰를 제공하지 않습니다.

1. Apple Developer 계정에서 Developer ID Application 인증서를 준비합니다.
2. `notarytool` credential은 유지관리자 Keychain에 저장합니다.
3. credential, app-specific password 또는 API key를 저장소·shell history·CI log에 남기지
   않습니다.
4. 서명된 archive를 notarization하고 ticket을 staple한 뒤 Gatekeeper를 검증합니다.

## 5. 태그와 GitHub Release

1. `CHANGELOG.md`, `CFBundleShortVersionString`과 `CFBundleVersion`을 갱신합니다.
2. release commit과 CI 성공을 확인합니다.
3. annotated tag를 만들고 push합니다.
4. notarization된 artifact와 SHA-256 checksum만 Release에 첨부합니다.

개발용 ad-hoc 앱이나 notarization 전 archive를 공식 Release asset으로 올리지 않습니다.

### v0.2.0 개발용 Pre-release 예외 (2026-09-29 소유자 승인)

Developer ID 인증서가 없는 현재 환경에 한해 v0.2.0은 ad-hoc 서명된 앱을
개발용 Pre-release로 배포한다. 정식 공증 릴리스로 표시하지 않는다.
저장소 공개 범위는 변경하지 않으며 다음 조건을 적용한다.

- 제목과 본문에 Apple 미공증 및 Gatekeeper 경고·실행 차단 가능성을 명시
- 지원 아키텍처·macOS 최소 버전·앱 버전·빌드 번호를 명시
- 실제 빌드 아키텍처에 맞는 앱 ZIP과 SHA-256 체크섬을 첨부
- CI 성공 및 병합 커밋에 대한 annotated tag 확인 후 게시
- 이 예외는 v0.2.0에만 적용하며 이후 정식 릴리스는 기존 공증 요건 유지

## 6. 게시 후 확인

- 깨끗한 macOS 사용자 계정에서 다운로드와 최초 실행
- Gatekeeper에 확인된 개발자 이름 표시
- `codesign`, `spctl`과 stapler validation 성공
- 메뉴바 아이콘, 정상·단일·reset 대기·오류 상태 확인
- 로그인 시 실행 설정과 앱 종료 확인
- README의 artifact 이름과 checksum 일치

공개 뒤 credential이나 실제 session data 노출을 발견하면 commit 삭제만으로 끝내지 않고
credential을 폐기·회전하고 Git history와 GitHub cache 정리를 함께 진행합니다.
