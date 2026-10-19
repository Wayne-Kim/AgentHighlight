#!/usr/bin/env python3
"""Render a GitHub PR as a local page with one <div> per diff line, open it, and build `hl steps` targets."""

import argparse
import html
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unicodedata

BROWSER = "Google Chrome"
SEARCH_LIMIT = 20
SKIPPED_HEADERS = ("index ", "--- ", "+++ ", "new file mode", "deleted file mode")
HUNK = re.compile(r"^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@")

STYLE = """
:root{--bg:#fff;--fg:#1d1d1f;--mute:#6e6e73;--add:#e6ffec;--del:#ffebe9;--hunk:#ddf4ff;--file:#f6f8fa;--line:#d0d7de}
body{background:var(--bg);color:var(--fg);font:15px/1.6 -apple-system,"Apple SD Gothic Neo",sans-serif;max-width:1100px;margin:0 auto;padding:24px 16px}
h1{font-size:24px}
h2{font-size:20px;margin-top:48px;border-top:1px solid var(--line);padding-top:24px}
.meta{color:var(--mute);font-family:ui-monospace,monospace;font-size:12px;margin:0}
.diff{font:12.5px/1.5 ui-monospace,Menlo,monospace;border:1px solid var(--line);border-radius:6px;overflow-x:auto}
.l{white-space:pre;padding:0 10px}
.add{background:var(--add)}
.del{background:var(--del)}
.hunk{background:var(--hunk);color:var(--mute)}
.file{background:var(--file);font-weight:600;padding:6px 10px;border-top:1px solid var(--line)}
figure{margin:12px 0}
figure img{max-width:100%;border:1px solid var(--line);border-radius:6px}
"""


def run(args, cwd, stdin=None):
    return subprocess.run(args, cwd=cwd, input=stdin, capture_output=True, text=True, check=True).stdout


def normalize(text):
    return " ".join(unicodedata.normalize("NFC", text).lower().split())


def find_hl():
    found = shutil.which("hl")
    if found:
        return found
    for candidate in (pathlib.Path.home() / ".local/bin/hl", pathlib.Path("/usr/local/bin/hl")):
        if candidate.exists():
            return str(candidate)
    sys.exit("hl not found on PATH, ~/.local/bin or /usr/local/bin")


def pairs(values, name):
    result = {}
    for value in values:
        key, sep, rest = value.partition("=")
        if not sep:
            sys.exit(f"--{name} expects <commit>=<value>, got {value!r}")
        result.setdefault(key, []).append(rest)
    return result


def ensure_commits(repo, number, commits):
    missing = [c["oid"] for c in commits if subprocess.run(["git", "cat-file", "-e", c["oid"]], cwd=repo, capture_output=True).returncode != 0]
    if missing:
        run(["git", "fetch", "--quiet", "origin", f"pull/{number}/head"], repo)


def parse_diff(diff):
    lines = []
    file_name = ""
    old = new = 0
    for raw in diff.splitlines():
        if raw.startswith(SKIPPED_HEADERS):
            continue
        if raw.startswith("diff --"):
            file_name = raw.split(" b/", 1)[1] if " b/" in raw else raw.split(" ", 2)[-1]
            lines.append({"kind": "file", "file": file_name, "text": file_name})
            continue
        if raw.startswith("@@"):
            hunk = HUNK.match(raw)
            if hunk:
                old, new = int(hunk.group(1)), int(hunk.group(2))
            lines.append({"kind": "hunk", "file": file_name, "text": raw})
            continue
        if raw.startswith("+"):
            kind, number, new = "add", new, new + 1
        elif raw.startswith("-"):
            kind, number, old = "del", old, old + 1
        else:
            kind, number, old, new = "ctx", new, old + 1, new + 1
        lines.append({"kind": kind, "file": file_name, "line": number, "code": raw, "text": f"{number:>5} {raw}"})
    return lines


class Page:
    def __init__(self, title):
        self.title = title
        self.title_regex = re.escape(title)
        self.parts = []
        self.seen = {}

    def text_block(self, tag, text, css=None):
        key = normalize(text)
        index = self.seen.get(key, 0)
        if key:
            self.seen[key] = index + 1
        attribute = f' class="{css}"' if css else ""
        self.parts.append(f"<{tag}{attribute}>{html.escape(text) or '&nbsp;'}</{tag}>")
        return {"kind": "element", "app": BROWSER, "title": self.title_regex, "text": text, "match": "exact", "index": index}

    def raw(self, markup):
        self.parts.append(markup)

    def render(self):
        return (
            '<!doctype html><html lang="ko"><head><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width,initial-scale=1">'
            f"<title>{html.escape(self.title)}</title><style>{STYLE}</style></head><body>"
            + "\n".join(self.parts)
            + "</body></html>"
        )


def build(pr, number, repo, out, notes, images, intro):
    page = Page(f"PR {number} guide {time.strftime('%H:%M:%S')}")
    page.text_block("h1", f"PR #{number} {pr['title']}")
    page.text_block("p", f"base: {pr['baseRefName']} / head: {pr['headRefName']}", "meta")
    for paragraph in intro:
        page.text_block("p", paragraph)

    sections = []
    for position, commit in enumerate(pr["commits"], 1):
        sha = commit["oid"]
        keys = [k for k in set(notes) | set(images) if sha.startswith(k) or k == str(position)]
        page.raw(f'<section id="c{position}">')
        heading = page.text_block("h2", f"{position}. {commit['messageHeadline']}")
        page.text_block("p", sha[:11], "meta")
        for key in keys:
            for note in notes.get(key, []):
                page.text_block("p", note)
            for image in images.get(key, []):
                source = pathlib.Path(image).expanduser().resolve()
                target = out / "img" / f"c{position}-{source.name}"
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, target)
                page.raw(f'<figure><img src="img/{html.escape(target.name)}" alt=""></figure>')
        page.raw('<div class="diff">')
        lines = parse_diff(run(["git", "show", "--format=", "--no-color", sha], repo))
        for line in lines:
            css = "file" if line["kind"] == "file" else f"l {line['kind']}"
            line["target"] = page.text_block("div", line["text"], css)
        page.raw("</div></section>")
        sections.append({"number": position, "sha": sha, "subject": commit["messageHeadline"], "heading": heading, "lines": lines})
    return page, sections


def section_for(point, sections):
    commit = str(point.get("commit", ""))
    if not commit:
        return sections
    return [s for s in sections if s["sha"].startswith(commit) or str(s["number"]) == commit]


def resolve_point(point, sections):
    if "target" in point:
        return dict(point["target"])
    if "figma" in point:
        return {"kind": "figma", "url": point["figma"]}
    if "section" in point:
        found = [s for s in sections if s["number"] == point["section"]]
        return dict(found[0]["heading"]) if found else None
    needle = point.get("text", "")
    for section in section_for(point, sections):
        for line in section["lines"]:
            if "code" not in line or needle not in line["code"]:
                continue
            if point.get("file") and point["file"] not in line["file"]:
                continue
            return dict(line["target"])
    return None


def steps_request(points, sections):
    targets, errors = [], []
    for position, point in enumerate(points):
        target = resolve_point(point, sections)
        if target is None:
            errors.append({"index": position, "message": f"no diff line matches {point}"})
            continue
        if target.get("index", 0) >= SEARCH_LIMIT:
            errors.append({"index": position, "message": f"line repeats {target['index'] + 1} times; hl only reaches the first {SEARCH_LIMIT}"})
        for key in ("label", "note"):
            if key in point:
                target[key] = point[key]
        targets.append(target)
    return {"targets": targets}, errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pr", type=int)
    parser.add_argument("--repo", default=".", help="git checkout of the PR's repository")
    parser.add_argument("--out", help="output directory (default: $TMPDIR/hl-pr-guide/<repo>-<pr>)")
    parser.add_argument("--note", action="append", default=[], help="<commit sha prefix or number>=<paragraph>")
    parser.add_argument("--image", action="append", default=[], help="<commit sha prefix or number>=<image path>")
    parser.add_argument("--intro", action="append", default=[], help="paragraph under the PR title")
    parser.add_argument("--points", help="JSON file (or - for stdin) with tour points")
    parser.add_argument("--no-open", action="store_true")
    args = parser.parse_args()

    repo = pathlib.Path(args.repo).expanduser().resolve()
    out = pathlib.Path(args.out).expanduser() if args.out else pathlib.Path(tempfile.gettempdir()) / "hl-pr-guide" / f"{repo.name}-{args.pr}"
    out.mkdir(parents=True, exist_ok=True)

    pr = json.loads(run(["gh", "pr", "view", str(args.pr), "--json", "title,commits,headRefName,baseRefName"], repo))
    ensure_commits(repo, args.pr, pr["commits"])
    page, sections = build(pr, args.pr, repo, out, pairs(args.note, "note"), pairs(args.image, "image"), args.intro)
    index_html = out / "index.html"
    index_html.write_text(page.render(), encoding="utf-8")
    (out / "lines.json").write_text(json.dumps(sections, ensure_ascii=False, indent=1), encoding="utf-8")

    summary = {
        "ok": True,
        "html": str(index_html),
        "lines": str(out / "lines.json"),
        "windowTitle": page.title_regex,
        "sections": [{"number": s["number"], "commit": s["sha"][:11]} for s in sections],
    }
    hl = find_hl()
    if not args.no_open:
        opened = subprocess.run(
            [hl, "open", index_html.as_uri(), "--new-window", "--wait-title", page.title_regex, "--wait", "15"],
            capture_output=True, text=True,
        )
        summary["window"] = json.loads(opened.stdout or "{}")
        summary["ok"] = opened.returncode == 0

    if args.points:
        points = json.load(sys.stdin if args.points == "-" else open(args.points, encoding="utf-8"))
        request, errors = steps_request(points, sections)
        steps_file = out / "steps.json"
        steps_file.write_text(json.dumps(request, ensure_ascii=False, indent=1), encoding="utf-8")
        summary["steps"] = str(steps_file)
        summary["pointErrors"] = errors
        if not args.no_open:
            checked = subprocess.run([hl, "steps", "--check", "-"], input=json.dumps(request), capture_output=True, text=True)
            result = json.loads(checked.stdout or "{}")
            summary["check"] = {
                "ok": result.get("ok", False),
                "errors": result.get("errors", []),
                "matched": [r.get("matchedText") for r in result.get("resolved", [])],
            }
        summary["ok"] = summary["ok"] and not errors and summary.get("check", {}).get("ok", True)

    print(json.dumps(summary, indent=1))
    return 0 if summary["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
