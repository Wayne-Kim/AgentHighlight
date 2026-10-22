---
name: agent-highlight
description: 사람이 보고 있는 화면(Chrome 에 열린 문서, Figma, 아무 앱 창) 위에 오버레이로 "여기를 보세요" 를 그린다. 답변이 화면의 특정 문장·요소·창을 가리키는 순간, "여기 보세요", "이 부분 하이라이트해줘", "화면에서 가리켜줘", 문서나 Figma 를 같이 보며 설명할 때 트리거. 셸에서 `hl` 명령으로 호출한다.
---

# agent-highlight

사람은 에이전트 답변을 텍스트로만 받는다. "오른쪽 표의 세 번째 행" 같은 말은 사람이 화면에서 다시
찾아야 한다. `hl` 은 그 자리를 화면 위에 직접 그린다 - 대상에 빨간 테두리와 라벨을 붙인다. 클릭은
가로채지 않으므로 사람은 하이라이트가 떠 있는 채로 계속 작업한다.

## 언제 호출하나

- 답변이 화면의 어떤 요소를 가리키는 문장을 쓸 때마다. 텍스트 설명을 빼지 않고, 설명과 함께 호출한다.
- Confluence 요구사항·API 명세, GitHub 마크다운처럼 Chrome 에 열린 문서에서 특정 문장을 짚을 때.
- Figma 노드를 열어 보여줄 때.
- 답변의 (1)(2)(3) 번호 항목을 화면의 여러 곳과 대응시킬 때.
- 흐름·순서가 있는 설명(요청이 어디서 시작해 어디로 가는지, 화면을 위에서 아래로 훑기)은 `hl steps`
  로 한 곳씩 넘기며 보여준다. 사람이 각 지점에서 무엇을 봐야 하는지 `note` 에 적는다.

## 전제

- `hl doctor` 가 `appRunning: true` 여야 한다. 앱이 꺼져 있으면 `hl` 이 알아서 띄운다. `hl` 이 PATH 에
  없으면 `~/.local/bin/hl` 또는 `/usr/local/bin/hl` 을 그대로 부른다.
- `trusted: false` 면 문구 탐색(`hl text`)과 창 제목 필터(`--title`)가 안 된다. 사람에게 시스템 설정 >
  개인정보 보호 및 보안 > 손쉬운 사용에서 AgentHighlight 를 켜 달라고 한 번 요청한다. 좌표 가리키기
  (`hl rect`)와 제목 필터 없는 창 가리키기는 권한 없이도 된다.
- 출력은 항상 JSON 한 덩어리. 종료 코드는 0 성공, 1 대상 못 찾음, 2 앱 연결 실패, 3 인자 오류.

## 명령

| 명령 | 하는 일 |
|---|---|
| `hl text <문구> --app <앱> [--title <창 제목 정규식>] [--label <라벨>]` | 창의 접근성 트리에서 문구를 찾아 그 글자 위치를 가리킨다. 화면 밖이면 스크롤해 보이게 한다 |
| `hl figma <링크> [--label <라벨>]` | 링크를 열고 Figma 창이 뜨면 창을 가리킨다. Figma 가 node-id 의 노드를 선택·확대한다 |
| `hl window --app <앱> [--title <정규식>] [--label <라벨>]` | 창 전체를 가리킨다 |
| `hl rect <x> <y> <w> <h> [--label <라벨>]` | 화면 좌표를 그대로 가리킨다. 주 모니터 왼쪽 위가 원점, 왼쪽 모니터는 x 가 음수 |
| `hl json '<HighlightRequest JSON>'` | 대상 여러 개를 한 번에. 번호 배지가 targets 순서대로 1부터 붙는다 |
| `hl steps '<HighlightRequest JSON>'` | 대상을 한 단계씩. 첫 단계만 그리고 사람이 → 로 넘긴다. 대상마다 `label`(제목)과 `note`(볼 것) |
| `hl steps --check '<JSON>'` / `hl json --check '<JSON>'` | 그리지도, 스크롤하지도, 링크를 열지도 않고 대상마다 찾기 결과(`resolved`·`errors`)만 돌려준다. JSON 자리에 `-` 를 쓰면 표준 입력에서 읽는다 |
| `hl open <링크> [--new-window] [--wait-title <정규식>] [--wait <초>] [--app <브라우저>]` | 링크를 연다. `--new-window` 는 기존 창의 탭이 아니라 새 창으로 연다. `--wait-title` 을 주면 제목이 맞는 창이 뜰 때까지(기본 10초) 기다렸다가 그 창 목록을 돌려준다 |
| `hl next` / `hl prev` | 단계를 넘기거나 되돌린다. 마지막 단계에서 `next` 는 단계를 마친다 |
| `hl status` | 지금 단계 번호(`current`)·전체(`total`)·제목. 단계가 끝났으면 `active: false` |
| `hl find <문구> --app <앱>` | 그리지 않고 좌표만 돌려준다 |
| `hl windows [--app <앱>]` | 창 목록과 좌표 |
| `hl clear` | 지운다 |
| `hl doctor` | 앱 실행 여부, 접근성 권한, 포트 |

공통 옵션: `--duration <초>`(기본 8, 0 은 지울 때까지), `--color <#RRGGBB>`, `--no-activate`(대상 앱을
앞으로 올리지 않음), `--no-dim`(바깥을 어둡게 덮지 않음. 기본값은 메뉴바의 "바깥 어둡게" 가 정하고
처음엔 꺼져 있다). `hl text` 에는 `--match contains|exact|regex`, `--index <n>`(n 번째 후보),
`--role <접근성 역할>` 이 더 있다.

## HighlightRequest JSON

`hl json`·`hl steps` 가 받는 형식이다. 맨 위 키는 `targets`(필수), `label`, `duration`, `activate`,
`style`(`{"color":"#RRGGBB","dim":false}`).

`targets` 의 대상 하나가 받는 키:

| 키 | 뜻 |
|---|---|
| `kind` | `element`(창 안의 문구) · `window`(창 전체) · `rect`(화면 좌표) · `figma`(Figma 링크를 열고 그 창). 필수 |
| `app` | 앱 이름. 없으면 맨 앞 앱. `figma` 는 기본 `Google Chrome` |
| `title` | 창 제목 정규식(대소문자 무시). 여러 창 중 하나로 좁힌다. `figma` 는 기본 `Figma(\s*-\|$)` |
| `text` | 찾을 문구. `element` 에 필수 |
| `match` | `contains`(기본) · `exact` · `regex` |
| `index` | 후보 중 몇 번째인지, 0부터. 후보는 최대 20개라 0~19 만 된다 |
| `role` | 접근성 역할로 좁힌다. 예: `AXHeading`, `AXStaticText` |
| `rect` | `rect` 에 필수. `{"x":0,"y":0,"width":100,"height":50}` |
| `url` | `figma` 에 필수. node-id 가 든 Figma 링크 |
| `scroll` | `false` 면 화면 밖 대상을 스크롤하지 않는다 |
| `label` | 라벨. 단계에서는 카드 제목 |
| `note` | 단계 카드에 적는 "볼 것" |

문구 비교는 공백·줄바꿈을 하나로 합치고 대소문자를 무시한다. 들여쓰기만 다른 같은 줄은 구분되지 않으므로
`match: exact` 로 줄 전체를 주고 `index` 로 고른다. 후보 순서는 웹 페이지 안 > 완전 일치 > 앞부분 일치 >
포함 순이고, 같은 등급이면 짧은 글이 먼저, 그다음 문서 순서다.

## 패턴

### 문서의 문장 가리키기

```bash
hl text "응답 필드" --app "Google Chrome" --title "API 명세" --label "(1) 이 표의 status 행"
```

`ok: true` 와 `matchedText` 를 확인한 뒤 답변에서 "(1)" 로 부른다. 문구는 요소 하나의 텍스트 일부로
짧게 잡는다. 표 제목이나 헤딩처럼 한 요소에 들어 있는 글이 가장 잘 잡힌다.

### Figma 노드 열어 보여주기

```bash
hl figma "https://www.figma.com/design/<파일>?node-id=1-2" --label "(2) 가입 버튼"
```

캔버스 안의 좌표는 잡을 수 없다. 더 좁은 영역을 가리키려면 그 영역에 해당하는 하위 노드의 node-id
링크를 쓴다. 로딩이 끝날 때까지 최대 10초 기다린 뒤 가리키고, 기본 15초 동안 보여준다.

### 여러 곳에 번호 배지

```bash
hl json '{"targets":[
  {"kind":"element","app":"Google Chrome","text":"검색바","label":"검색 입력"},
  {"kind":"element","app":"Google Chrome","text":"추천 목록","label":"추천 리스트"}
],"duration":20}'
```

답변의 번호와 배지 번호를 맞춘다. 일부만 찾으면 찾은 것은 그려지고 `errors` 에 나머지가 온다.

### 단계별로 따라가게 하기

```bash
hl steps '{"targets":[
  {"kind":"element","app":"Google Chrome","text":"요청 필드","label":"요청","note":"page 가 비면 서버가 1 을 쓴다"},
  {"kind":"element","app":"Google Chrome","text":"응답 필드","label":"응답","note":"status 가 DONE 이면 처리가 끝난 것이다"},
  {"kind":"element","app":"Google Chrome","text":"에러 코드","label":"실패","note":"404 는 빈 목록으로 처리한다"}
]}'
```

- 화면에는 지금 단계 하나만 뜬다. 카드에 `n / 전체`, 제목, `note`, 다음 단계 제목, 키 안내가 나온다.
- 사람은 → 로 다음, ← 로 이전, Esc 로 끝낸다. 마지막 단계에서 → 를 누르면 끝난다. 화살표는 지금
  단계의 앱이 맨 앞에 있을 때만 가로채므로, 사람이 터미널로 돌아와 입력할 때는 평소대로 동작한다.
- 단계마다 들어갈 때 대상을 다시 찾아 스크롤하고 앱을 앞으로 올린다. 앞 단계의 스크롤이 뒤 단계를
  어긋나게 하지 않는다.
- 시작할 때 모든 단계를 스크롤 없이 미리 찾는다. 못 찾은 단계는 `errors` 에 오고 투어에서 빠진다(나머지는
  그대로 진행, 종료 코드 1). 카드 번호는 targets 순서 그대로라 답변 번호와 맞는다.
- `duration` 은 쓰지 않는다. 단계는 사람이 넘기거나 Esc 를 누를 때까지 떠 있다.
- 답변 텍스트에는 단계별 설명을 같은 번호로 적고, "→ 로 넘기며 보세요" 라고 한 줄 알린다. 사람이
  어디까지 봤는지 알아야 하면 `hl status` 를 부른다.
- 들어간 순간 대상을 못 찾으면(사람이 탭을 바꾼 경우 등) 화면 가운데에 그 사실을 적은 카드가 뜨고,
  사람은 그대로 → 로 넘어갈 수 있다.
- 띄우기 전에 `hl steps --check` 로 모든 단계가 찾아지는지 본다. 화면 밖 대상은 높이 1 같은 좌표로
  찾히는데, 그 단계에 들어갈 때 다시 찾아 스크롤하므로 정상이다.

### 단계에 Figma 섞기

```bash
hl steps '{"targets":[
  {"kind":"element","app":"Google Chrome","title":"PR 123 guide","text":"공용 매퍼","label":"매퍼"},
  {"kind":"figma","url":"https://www.figma.com/design/<파일>?node-id=3-4","label":"시안","note":"이 뱃지가 status 값이다"}
]}'
```

- `figma` 단계에 들어가면 링크를 열고 Figma 창을 가리킨다. 이미 Figma 창이 있으면 그 창을 앞으로 올려 탭으로
  열고, 없으면 새 창으로 연다. 다른 단계가 쓰는 창의 탭은 바뀌지 않는다.
- `--check` 와 시작할 때의 미리 찾기는 링크를 열지 않는다. 이때 `figma` 단계는 좌표 0 으로 온다.
- Figma 창 하나는 노드 하나만 보여준다. 노드마다 `figma` 단계를 따로 두거나, Figma MCP
  `get_screenshot` 으로 받은 이미지를 안내 페이지에 넣는다(아래 `--image`).

### PR 을 커밋 순서로 안내하기

GitHub PR 의 커밋·파일 diff 화면은 보이는 줄만 그려서 아래쪽 줄은 접근성 트리에 없다. `hl find` 가 0건을
돌려준다. diff 를 로컬 페이지로 만들어 연다.

```bash
python3 ~/.agents/skills/agent-highlight/scripts/pr-guide.py 123 --repo ~/Projects/my-app \
  --note 1="응답 타입만 넓혔다" --image 4=/path/list-item.png --points - <<'JSON'
[
  {"section": 1, "label": "1. 응답 타입", "note": "세 곳에 같은 두 필드를 더한다"},
  {"commit": 2, "file": "mapUserDto.ts", "text": "export const", "label": "공용 매퍼", "note": "다섯 곳의 매핑을 모았다"},
  {"figma": "https://www.figma.com/design/<파일>?node-id=3-4", "label": "시안"}
]
JSON
hl steps - < <출력의 steps 경로>
```

- 스크립트는 `gh pr view` 로 커밋 목록을 받고, 커밋마다 `git show` diff 를 섹션 하나로 그린다. 줄마다
  `<div>` 하나이고 앞에 줄 번호가 붙는다. 커밋이 로컬에 없으면 `pull/<번호>/head` 를 받아 온다.
- 페이지를 새 Chrome 창으로 열고 창이 뜰 때까지 기다린다. 창 제목은 `PR <번호> guide <시각>` 이다.
- `--points` 의 항목 하나가 단계 하나가 된다. `section`(커밋 번호) 은 섹션 제목, `commit`(번호나 커밋 해시
  앞부분)·`file`·`text` 는 그 커밋에서 `text` 가 든 첫 diff 줄, `figma` 는 Figma 단계, `target` 은 대상
  JSON 그대로다. `label`·`note` 는 그대로 옮긴다.
- 같은 줄이 여러 번 나와도 스크립트가 `match: exact` 와 맞는 `index` 를 채운다. 만든 요청은 출력의
  `steps` 파일에 있고, 스크립트가 `hl steps --check` 까지 돌려 `check.errors` 와 `pointErrors` 에 못 찾은
  단계를 적는다. 둘 다 비었으면 바로 `hl steps` 로 띄운다.
- `--note <커밋>=<문단>` 과 `--image <커밋>=<경로>` 는 섹션 머리에 설명과 이미지를 붙인다. `--intro` 는
  PR 제목 아래 문단. 출력 폴더는 `--out` 으로 정하고, 없으면 임시 폴더 아래 `hl-pr-guide/` 에 둔다.
  `lines.json` 에 모든 줄의 대상 JSON 이 있다.
- 순서: PR·diff 읽기 -> (필요하면) Figma 캡처 -> 스크립트 -> `hl steps`.

## 실패했을 때

- `no element matching ...`: 문구를 더 짧게 바꾸거나, `--title` 로 창을 좁히거나, `--index 1` 로 다음
  후보를 본다. 같은 문구가 여러 번 나오면 후보는 완전 일치 > 앞부분 일치 > 포함 순으로 정렬되어 있다.
- GitHub 의 코드 뷰(`/blob/...`)와 PR diff 는 본문을 접근성 트리에 다 내놓지 않아 문구를 못 찾는다.
  PR 은 `scripts/pr-guide.py` 로, 파일 하나는 `hl open file:///절대경로 --new-window --wait-title <제목>`
  으로 열어 가리킨다.
- 로컬 페이지를 `open -a "Google Chrome"` 으로 열면 기존 창의 뒤쪽 탭으로 들어가 창 제목에 잡히지 않는다.
  `hl open --new-window` 를 쓴다. 이 명령은 `open -na "Google Chrome" --args --new-window` 로 연다.
- 사람이 탭이나 창을 바꾸면 그려 둔 하이라이트는 그 자리에 그대로 남는다. 바뀐 화면 위에 남아 있으면
  `hl clear` 로 지우고 다시 가리킨다.
- 종료 코드 2: `hl doctor` 를 보고, 앱 번들이 없으면 저장소에서 `make install` 을 돌린다.
- 가리킨 자리가 어긋나 보이면 `hl find` 로 좌표를 받아 `hl windows` 의 창 좌표와 대조한다.

## 지키는 것

- 하이라이트는 보조 수단이다. 답변 텍스트에도 무엇을 가리키는지 적는다.
- `duration` 은 사람이 읽을 시간만큼만. 긴 설명이면 15~20초. 0 으로 띄웠으면 `hl clear` 로 꼭 지운다.
- 기본으로 대상 앱이 앞으로 온다. 사람이 다른 창에서 작업 중이라 방해가 되면 `--no-activate` 를 쓴다.
- 하이라이트가 떠 있는 동안 Esc 한 번은 하이라이트를 지우는 데 쓰이고 앞 앱에는 전달되지 않는다.
  그다음 Esc 부터 평소대로 앱에 간다. 단계 진행 중에는 Esc 한 번이 단계 전체를 끝낸다.
- 새 `hl text`·`hl json` 등을 부르면 진행 중인 단계는 끝난다.
- `hl figma` 가 종료 코드 1 이면 링크가 다른 브라우저나 Figma 앱에서 열린 것이다. 그때는 창을 가리키지
  않았으니 `--app <그 앱>` 으로 다시 부른다.
