# AgentHighlight

에이전트가 사람의 화면 위에 "여기를 보세요" 를 그리는 macOS 도구다. 메뉴바 앱이 모든 모니터 위에
투명 오버레이를 띄우고, 에이전트는 `hl` 명령 한 줄로 화면 좌표·창·창 안의 문구를 가리킨다. 바깥은
어둡게 덮이고 대상만 밝게 뚫려 빨간 테두리와 라벨이 붙는다. 오버레이는 클릭을 가로채지 않는다.

Chrome 에 열린 문서(Confluence, GitHub 마크다운)는 접근성 트리로 문구를 찾아 그 글자 위치만 가리키고,
화면 밖이면 스크롤해 보이게 한다. Figma 링크는 node-id 로 열어 Figma 가 노드를 선택·확대하게 하고
창 위에 라벨을 띄운다.

## 설치

```bash
make install
```

- release 빌드 -> `~/Applications/AgentHighlight.app`(Apple Development 인증서가 있으면 그걸로, 없으면
  ad-hoc 서명) -> `hl` 을 `/usr/local/bin` 또는 `~/.local/bin` 에 복사 -> `~/.claude/skills/` 가 있으면
  에이전트용 스킬 `agent-highlight` 를 링크 -> 앱 실행 -> `hl doctor`.
- 첫 실행 때 접근성 권한 창이 뜬다. 시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용에서
  AgentHighlight 를 켠다. 메뉴바 아이콘의 "접근성 권한 열기..." 로도 갈 수 있다. 권한이 없어도 좌표
  가리키기와 제목 필터 없는 창 가리키기는 되고, 문구 탐색(`hl text`)과 창 제목 필터는 막힌다.
- 앱을 다시 빌드해 설치하면 서명이 바뀌어 권한을 다시 켜야 할 수 있다.

## 사용

```bash
hl text "응답 필드 표" --app "Google Chrome" --title "ADR" --label "(1) 여기"
hl figma "https://www.figma.com/design/<file>?node-id=1-2" --label "(2) 가입 버튼"
hl window --app "Google Chrome" --title "JIRA" --label "Jira 창"
hl rect 200 200 400 120 --label "좌표로 가리키기"
hl json '{"targets":[{"kind":"element","app":"Google Chrome","text":"검색바"},{"kind":"rect","rect":{"x":10,"y":10,"width":100,"height":40}}],"duration":20}'
hl find "PROJ-123" --app "Google Chrome"
hl windows --app chrome
hl clear
hl doctor
```

출력은 JSON. 종료 코드는 0 성공, 1 대상 못 찾음, 2 앱 연결 실패, 3 인자 오류. 하이라이트는 기본 8초
뒤 사라지고, Esc 나 `hl clear` 로 바로 지운다. 하이라이트가 떠 있는 동안의 Esc 한 번은 지우는 데만
쓰이고 앞 앱에는 전달되지 않는다. 앱은 같은 포트에 다른 인스턴스가 이미 응답하면 바로 종료한다. 좌표계는 주 모니터 왼쪽 위 원점(접근성 API·CGWindowList
와 같다). 에이전트용 사용 안내는 `skills/agent-highlight/SKILL.md` 에 있다.

## HTTP 인터페이스

앱은 `127.0.0.1:47831`(환경 변수 `HL_PORT`)에서 받는다. `hl` 은 이 인터페이스를 감싼 것이라 `curl` 로도
같은 일을 할 수 있다.

| 메서드·경로 | 본문 | 응답 |
|---|---|---|
| `GET /health` | - | `{ok, version, trusted, port, pid}` |
| `POST /highlight` | `HighlightRequest` | `HighlightResponse` - 대상별 좌표(`resolved`)와 못 찾은 것(`errors`) |
| `POST /find` | `HighlightRequest` | 같은 응답, 그리지 않고 앱도 앞으로 올리지 않는다 |
| `GET /windows?app=&title=` | - | 창 목록과 좌표 |
| `POST /clear` | - | `{ok}` |

`HighlightRequest`: `targets[]`(`kind: rect|window|element`, `rect`, `app`, `title`, `text`, `role`,
`match: contains|exact|regex`, `index`, `label`, `scroll`), `label`, `duration`, `activate`,
`style: {color, dim}`. 타입 정의는 `Sources/HighlightKit/Protocol.swift`.

## 개발

```bash
make build      # debug 빌드
make run-dev    # 터미널에서 앱 실행 - 터미널 호스트의 접근성 권한을 상속한다
.build/debug/hl doctor
```

구조: `Sources/HighlightKit`(공유 타입·좌표 변환), `Sources/AgentHighlightApp`(HTTP 서버, 대상 해석,
오버레이), `Sources/hl`(CLI).

## 알려진 한계

- Figma 캔버스 안의 레이어 좌표는 잡지 못한다. node-id 링크로 Figma 의 선택·확대를 쓴다.
- Orca 내장 브라우저 안의 페이지는 DOM 수준으로 가리키지 못한다. 창·좌표 지정은 된다.
- Chrome 은 보조 기술이 붙어야 웹 본문을 접근성 트리로 노출한다. 첫 호출에서 못 찾으면 0.3초 뒤 한 번
  더 찾는다.
