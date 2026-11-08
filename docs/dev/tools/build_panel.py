#!/usr/bin/env python3
"""把一张验收卡（Markdown）做成一个双击即可打开的点选式验收网页。

用法：
    python build_panel.py docs/dev/reviews/M1_r1.md [-o 输出.html]

网页里：跟着体验路线走 → 打 1-5 分 → 点几个问题 → 点「复制给 AI」→ 粘贴回对话。
网页是派生文件（默认放在验收卡旁边，已在 .gitignore 里），验收卡 .md 才是记录。
"""
import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import dk_common as dk  # noqa: E402


def find_panel_template():
    here = Path(__file__).resolve().parent
    for c in (here / "review_panel.html", here.parent / "assets" / "review_panel.html"):
        if c.exists():
            return c
    sys.exit("review_panel.html not found / 找不到 review_panel.html")


def build_data(path):
    text = dk.read(path)
    m = re.fullmatch(r"(M\d+)_r(\d+)", Path(path).stem)
    ms, rnd = (m.group(1), int(m.group(2))) if m else (Path(path).stem, 1)
    lang = "en" if re.search(r"(?m)^##\s*Human part", text) else dk.get_lang()
    dk.set_lang(lang)
    ai = dk.section(text, "AI 部分")

    run = dk.strip_comments(dk.section(ai, "怎么跑起来")).strip()
    run = "" if dk.PLACEHOLDER in run else run

    recheck = []
    for item in dk.bullets(dk.section(ai, "本轮复验")):
        if item.startswith("无") or item.lower().startswith("none"):
            continue
        m2 = re.match(r"(FB-\d+)\s*(.*)", item)
        recheck.append({"id": m2.group(1), "text": m2.group(2)} if m2 else {"id": item[:12], "text": item})

    dims = []
    score_sec = dk.strip_comments(dk.section(dk.section(text, "人的部分"), "打分"))
    for ln in score_sec.splitlines():
        if "|" in ln and not ln.strip().startswith("|--") and not re.match(r"^\s*\|\s*-", ln):
            first = ln.strip().strip("|").split("|")[0].strip()
            if first and first.lower() not in ("维度", "dimension"):
                dims.append(first)

    return {
        "id": f"{ms}_r{rnd}",
        "milestone": ms,
        "round": rnd,
        "run": run,
        # 步骤编号由面板按顺序自动加，去掉文本里自带的"1."之类前缀，避免重复
        "steps": [re.sub(r"^\d+[.、)]\s*", "", s) for s in
                  (dk.bullets(dk.section(ai, "3 分钟体验路线")) or dk.bullets(dk.section(ai, "体验路线")))],
        "verified": dk.bullets(dk.section(ai, "AI 已验证")),
        "questions": dk.bullets(dk.section(ai, "请你重点判断")),
        "known": dk.bullets(dk.section(ai, "已知不足")),
        "recheck": recheck,
        "dims": dims or dk.DIMS[lang],
        "lang": lang,
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("review", help="验收卡 .md")
    ap.add_argument("-o", "--out", help="输出 html 路径，默认与验收卡同名同目录")
    a = ap.parse_args()

    src = Path(a.review)
    if not src.exists():
        sys.exit(f"找不到 {src} / not found: {src}")
    data = build_data(src)
    if not data["steps"]:
        print(dk.L("提示：验收卡的「3 分钟体验路线」还是空的，面板里不会有可勾选的步骤。",
                   "Note: the \"3-minute test route\" in the review card is empty; the panel will have no checkable steps."), file=sys.stderr)

    payload = json.dumps(data, ensure_ascii=False).replace("</", "<\\/")
    html = find_panel_template().read_text(encoding="utf-8")
    if "/*__DATA__*/null" not in html:
        sys.exit("面板模板里缺少数据占位符 /*__DATA__*/null")
    html = html.replace("/*__DATA__*/null", payload)

    out = Path(a.out) if a.out else src.with_suffix(".html")
    out.write_text(html, encoding="utf-8")
    print(dk.L(f"已生成验收面板：{out}", f"Review panel created: {out}"))
    print(dk.L("双击打开（手机也可以：把这个 html 发到手机浏览器打开）。点完「复制给 AI」，粘贴回对话即可。",
               "Double-click to open (works on a phone too: send the html to your phone's browser). When done, tap \"Copy to AI\" and paste it back into the chat."))


if __name__ == "__main__":
    main()
