# 진행 상황

| 단계 | 내용 | 상태 |
|---|---|---|
| 0 | 저장소·보안 기반 | 통과 |
| 1 | 체스 핵심 (Pass & Play·기보) | 진행 중 (사용자 검증 대기) |
| 2 | BLE 기술 검증 (관문) | 대기 |
| 3 | 닉네임·방 만들기/찾기·대기실 | 대기 |
| 4 | 암호화·확인 코드·랜덤 색 | 대기 |
| 5 | BLE 대국·시계·기권/무승부/재대국 | 대기 |
| 6 | 채팅 | 대기 |
| 7 | 연결 유지·재연결·복구 | 대기 |
| 8 | 릴리스 빌드·보안 점검 | 대기 |
| 9 | (선택) 엔진 분석 (9a 분석 보드 → 9b 엔진 → 9c 복기) | 대기 |

## 기록

아래에 덧붙이기만 합니다. 기존 항목은 고치지 않습니다.

### 2026-10-09 21:34 — 0단계: 저장소·보안 기반

- 한 일: 빈 저장소 확인(로컬·원격 커밋 0), `flutter create`(Android 전용, `io.github.movingmin.bit_chess`), `.gitignore` 보강, SPEC/PROGRESS/README/SECURITY, GPL-3.0 LICENSE, gitleaks pre-commit 훅(`scripts/hooks`), GitHub Actions CI(analyze·test·gitleaks, `contents: read`, 액션 SHA 고정).
- 매니페스트: main에 INTERNET 없음. debug/profile에만 있음(Flutter 기본).
- 새 패키지: 없음(Flutter 기본 템플릿 의존성만).
- 미확인: CI 초록색(push 전이라 실행 안 됨), GitHub 웹 보안 설정, 훅 차단 시험(사용자 시험 대기).

### 2026-10-09 21:53 — 0단계: 검증 결과 보완

- 훅 차단: 에이전트가 가짜 GitHub PAT로 커밋을 시도해 막히는 것을 확인했다(`github-pat` 규칙). 시험 파일은 커밋하지 않고 지웠다. 사용자 재시험 대기.
- 폰: 디버그 APK 빌드·설치 성공, Flutter 엔진 시작 로그 확인. 화면 표시는 미확인(사용자 검증).
- `flutter analyze`: No issues found. `flutter test`: All tests passed(1개).
- `secret-check.ps1`: 금지 파일 0, gitleaks staged·전체 히스토리 0, 커밋 이메일 noreply, 개인 경로 없음, main INTERNET 없음.
- 보완 커밋: CI Flutter 3.47.7 고정, `.gitignore`에 `Screenshot_*`와 `!test/**/*.pgn` 추가.
- 환경: 첫 빌드 때 Gradle이 Android SDK Build-Tools 36.0.0을 자동 설치했다.
- 미확인: CI 초록색(push 전), GitHub 웹 보안 설정.

### 2026-10-09 21:59 — 0단계: 통과

- 사용자 검증: 통과 — 폰 카운터 앱 동작 확인(사용자). 금지 파일 0, gitleaks 0, main INTERNET 없음, 훅이 가짜 토큰 차단(에이전트 실행).
- GitHub 보안 설정(gh API): Secret scanning·Push protection·Dependabot alerts·security updates·Private vulnerability reporting 켬. main ruleset: 삭제 금지·force push 금지.
- CI: 첫 push 후 `check` 통과(1m42s).
- 남은 것: 필수 상태 검사(required check)는 main 직접 push를 막으므로 걸지 않았다. PR 흐름으로 바꿀 때 추가.

### 2026-10-09 22:28 - 1단계: 체스 핵심 (Pass & Play·기보)

- 한 일: 규칙 dartchess, 보드 chessground(둘 다 lichess, GPL-3.0). 홈(혼자 두기·지난 대국·설정, BLE·분석 보드 자리), 대국 화면(시계 무제한/3/5/10/15+10, 뒤집기, 기권, 합의 무승부), 결과 8종, PGN 자동 저장(중단 포함), 다시보기, 공유 시트 내보내기, 강제 종료 복구.
- 단위 테스트 8개: 메이트·스테일메이트·3회 반복·기물 부족·핀·특수 수 PGN·시계·저장/복구. analyze 깨끗.
- 폰: 디버그 APK 설치·실행 확인(앱 맨 앞 화면). 화면 동작은 미확인(사용자 검증).
- 결정: 상태 관리는 Riverpod 대신 Flutter 기본(StatefulWidget). 화면 하나에 상태가 모여 있어 충분하다. BLE 상태가 여러 화면에 걸치면 그때 다시 본다.
- 한계: 효과음은 시스템 클릭음 하나(이동·잡기·체크·종료 구분 없음). 진동은 잡기·체크·종료에 강하게. 50수·3회 반복은 자동 무승부(Chess.com 방식).
- 첫 빌드 때 Gradle이 Android SDK Platform 35를 자동 설치했다.
