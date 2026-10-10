# 보안 정책

## 취약점 제보

공개 이슈에 올리지 말고 GitHub의 **Private vulnerability reporting**으로 알려 주세요.
저장소 → Security 탭 → **Report a vulnerability**.

적어 주시면 좋은 것: 영향받는 버전·기기, 재현 절차, 예상 영향.
비밀번호·키 같은 민감한 값은 제보 본문에 붙여 넣지 마세요.

## 지원 버전

정식 릴리스 전입니다. 최신 `main`만 지원합니다.

## 저장소 보안 설정 (관리자용)

저장소 → Settings에서 켭니다.

- Settings → **Code security** → Secret scanning: Enable, Push protection: Enable
- Settings → **Code security** → Dependabot alerts: Enable, Dependabot security updates: Enable
- Settings → **Code security** → Private vulnerability reporting: Enable
- Settings → **Branches** → Add branch ruleset(또는 classic protection rule), 대상 `main`:
  - Restrict deletions, Block force pushes
  - Require status checks to pass → CI 워크플로의 `check` 작업 선택
