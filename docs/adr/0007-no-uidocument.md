# ADR-0007 — `UIDocument` 를 쓰지 않고 `NSFileCoordinator` 를 직접 쓴다

**상태** 확정 (2026-09-13)

## 맥락

`UIDocument` 는 iCloud 문서 앱을 위해 애플이 준비한 상위 계층이다. 자동 저장 ·
충돌 판본 · `NSFileCoordinator` 조율 · 열림/닫힘 상태 전이를 대신 해 준다. 안 쓰기로
했다면 **왜 안 쓰는지**가 남아 있어야 한다 — 안 그러면 다음 세션이 "이거 UIDocument
쓰면 되는 거 아닌가" 를 다시 묻는다.

## 결정

**`NSFileCoordinator` 를 직접 쓴다.** `UIDocument` 를 쓰지 않는다.

## 이유

1. **이 앱은 "문서 하나를 연다" 가 아니라 "폴더를 훑는다" 가 주된 동작이다.**
   목록 · 검색 색인 · 첨부 해석은 파일 300개를 열지 않고 `mtime` 과 본문 일부만
   읽는다. `UIDocument` 는 문서마다 인스턴스를 만들고 열고 닫는 모델이라 여기에 안 맞는다.
2. **자동 저장 시점을 우리가 정해야 한다.** ADR-0005 의 라이브 편집기는
   `textStorage.string` 이 곧 파일이다. 저장은 1초 디바운스 + `.background` 진입 시
   즉시로 정의되어 있는데, `UIDocument` 의 자동 저장 주기는 우리가 통제하지 못한다.
3. **충돌 처리를 화면에서 직접 보여 준다.** `mtime` 이 바뀌었으면 덮어쓰지 않고
   `이름 (충돌 …).md` 로 나란히 저장하고 알린다 (S4). `UIDocument` 의 기본 충돌 동작은
   이것과 다르다.
4. **(b) 임의 폴더(보안 범위 북마크)** 에서 `UIDocument` 의 이득이 줄어든다.
   보안 범위 접근은 어차피 우리가 열고 닫아야 한다.

## 대가 — 우리가 직접 해야 하는 것

- 모든 읽기 · 쓰기를 `NSFileCoordinator` 로 감싼다. **한 곳도 빠뜨리면 안 된다.**
  → `App/Storage/` 안의 한 타입(`actor FolderStore`)만 파일을 만지게 해서 강제한다.
- 쓰기는 **임시 파일 → `replaceItemAt`** (원자적).
- 충돌 판본은 `NSFileVersion.unresolvedConflictVersionsOfItem` 으로 직접 읽는다.
- 앱 활성화 시 전체 `mtime` 대조가 감시 누락의 그물이다.

## 되돌리는 신호

`App/Storage/` 밖에서 `FileManager` 로 사용자 폴더를 직접 읽거나 쓰는 코드가 보이면,
이 결정이 지켜지지 않고 있다는 뜻이다. 그때는 `UIDocument` 로 가는 편이 낫다.
