#!/usr/bin/env python3
"""接手已有项目：扫描代码，输出一份"事实清单"，供 AI 据此写出 CURRENT_STATE 和欠账草稿。

用法：
    python adopt.py [项目目录] [-o 输出.md] [--lang en|zh]

只报告能从文件里确定的事实（引擎、版本、结构、体检结果），不做推断。
推断（设计意图、历史决定）由 AI 完成，并必须标注"（推断，待确认）"，交给人在 M0 验收卡里确认。
"""
import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import dk_common as dk  # noqa: E402

for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

IGNORE_DIRS = {
    ".git", "node_modules", "dist", "build", "out", "Library", "Temp", "Logs", "obj", "bin",
    ".godot", ".import", ".venv", "venv", "env", "__pycache__", ".idea", ".vscode", "target",
    "coverage", ".next", ".cache", "Binaries", "Intermediate", "Saved", "DerivedDataCache",
}
CODE_EXT = {
    ".js", ".mjs", ".ts", ".tsx", ".jsx", ".py", ".gd", ".cs", ".cpp", ".cc", ".c", ".h", ".hpp",
    ".rs", ".lua", ".html", ".css", ".shader", ".gdshader", ".java", ".kt", ".swift", ".go", ".luau",
}
MAX_FILES = 6000
MAX_READ = 400_000


def walk(root):
    n = 0
    for dp, dns, fns in os.walk(root):
        dns[:] = [d for d in dns if d not in IGNORE_DIRS and not d.startswith(".")]
        for fn in fns:
            n += 1
            if n > MAX_FILES:
                return
            yield Path(dp) / fn


def read_text(p):
    try:
        if p.stat().st_size > MAX_READ:
            return ""
        return p.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return ""


def sh(root, *args):
    try:
        r = subprocess.run(args, cwd=root, capture_output=True, text=True, timeout=10)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


# ---------- 引擎检测 ----------

WEB_LIBS = ["phaser", "three", "pixi.js", "@pixi/", "@babylonjs/core", "babylonjs", "kaplay", "kaboom",
            "excalibur", "matter-js", "p5", "playcanvas", "melonjs", "planck"]


def detect_stack(root):
    found = []

    def add(name, ver, ev):
        found.append({"name": name, "version": ver or dk.L("未知", "unknown"), "evidence": ev})

    pg = root / "project.godot"
    if pg.exists():
        t = read_text(pg)
        m = re.search(r'config/features=PackedStringArray\("([\d.]+)"', t)
        scene = re.search(r'run/main_scene="([^"]+)"', t)
        add("Godot", m.group(1) if m else None, "project.godot" + (dk.L(f"，主场景 {scene.group(1)}", f", main scene {scene.group(1)}") if scene else ""))
    pv = root / "ProjectSettings" / "ProjectVersion.txt"
    if pv.exists():
        m = re.search(r"m_EditorVersion:\s*(\S+)", read_text(pv))
        add("Unity", m.group(1) if m else None, "ProjectSettings/ProjectVersion.txt")
    for up in root.glob("*.uproject"):
        m = re.search(r'"EngineAssociation"\s*:\s*"([^"]+)"', read_text(up))
        add("Unreal", m.group(1) if m else None, up.name)
    pkg = root / "package.json"
    if pkg.exists():
        try:
            d = json.loads(read_text(pkg) or "{}")
            deps = {**d.get("dependencies", {}), **d.get("devDependencies", {})}
            for lib in WEB_LIBS:
                for k, v in deps.items():
                    if k == lib or (lib.endswith("/") and k.startswith(lib)):
                        add(f"Web: {k}", v, "package.json")
            scripts = d.get("scripts", {})
            if scripts:
                found.append({"name": "npm scripts", "version": "", "evidence": ", ".join(scripts)})
        except Exception:
            pass
    for f in ("requirements.txt", "pyproject.toml", "Pipfile", "setup.py"):
        p = root / f
        if p.exists():
            t = read_text(p).lower()
            for lib in ("pygame", "arcade", "pyglet", "panda3d", "ursina", "kivy"):
                if lib in t:
                    add(f"Python: {lib}", None, f)
    ct = root / "Cargo.toml"
    if ct.exists() and "bevy" in read_text(ct):
        m = re.search(r'bevy\s*=\s*(?:\{[^}]*version\s*=\s*)?"([^"]+)"', read_text(ct))
        add("Bevy (Rust)", m.group(1) if m else None, "Cargo.toml")
    if (root / "main.lua").exists() and (root / "conf.lua").exists():
        m = re.search(r'version\s*=\s*"([\d.]+)"', read_text(root / "conf.lua"))
        add("LÖVE", m.group(1) if m else None, "main.lua + conf.lua")
    if (root / "default.project.json").exists() or any(root.glob("*.rbxl*")):
        add("Roblox", None, "default.project.json / .rbxl")
    idx = root / "index.html"
    if idx.exists() and "<canvas" in read_text(idx).lower() and not any(f["name"].startswith("Web:") for f in found):
        add(dk.L("纯 Web（Canvas）", "Plain web (Canvas)"), None, dk.L("index.html 含 <canvas>", "index.html contains <canvas>"))
    return found


# ---------- 结构统计 ----------

def structure(root):
    loc_by_ext, files = {}, []
    top = {}
    for p in walk(root):
        if p.suffix.lower() not in CODE_EXT:
            continue
        t = read_text(p)
        n = t.count("\n") + 1 if t else 0
        loc_by_ext[p.suffix.lower()] = loc_by_ext.get(p.suffix.lower(), 0) + n
        rel = p.relative_to(root)
        files.append((n, rel.as_posix()))
        k = rel.parts[0] if len(rel.parts) > 1 else dk.L("(根目录)", "(root)")
        top[k] = top.get(k, 0) + 1
    files.sort(reverse=True)
    return loc_by_ext, files[:10], top


def entry_points(root):
    cands = []
    for name in ("index.html", "main.js", "main.ts", "src/main.js", "src/main.ts", "src/index.js", "src/index.ts",
                 "main.py", "app.py", "game.py", "main.gd", "main.lua", "Program.cs", "src/main.rs", "main.cpp"):
        if (root / name).exists():
            cands.append(name)
    pg = root / "project.godot"
    if pg.exists():
        m = re.search(r'run/main_scene="([^"]+)"', read_text(pg))
        if m:
            cands.append(m.group(1))
    return cands


def existing_docs(root):
    out = []
    for name in ("README.md", "README.zh-CN.md", "CLAUDE.md", "AGENTS.md", "GDD.md", "DESIGN.md", "CHANGELOG.md", "TODO.md"):
        if (root / name).exists():
            out.append(name)
    d = root / "docs"
    if d.is_dir():
        out.append(dk.L("docs/（" + str(sum(1 for _ in d.rglob("*.md"))) + " 个 md）", "docs/ (" + str(sum(1 for _ in d.rglob("*.md"))) + " md files)"))
    for p in root.glob("*.md"):
        if p.name not in out and p.name.lower().startswith(("gdd", "design", "设计")):
            out.append(p.name)
    return out


# ---------- 体检 ----------

PATTERNS = {
    "unseeded_random": r"Math\.random|\brandom\.(?:random|randint|choice|uniform)\b|\brandf\(|\brandi\(|\brandf_range\(|Random\.Range|\bUnityEngine\.Random\b|\brand\(\)",
    "seed": r"\bseed\b|RandomNumberGenerator|mulberry32|seedrandom|SeededRandom|random\.seed|srand",
    "tuning_panel": r"dat\.gui|lil-gui|lil\.gui|tweakpane|ImGui|imgui|[?&]debug\b|F9|debugPanel|tuning",
    "debug_report": r"clipboard|F8|copyDebug|debugReport|debug_report",
    "save": r"localStorage|sessionStorage|indexedDB|user://|PlayerPrefs|\bsave_game\b|saveGame|SaveData|save_data|json\.dump",
    "save_version": r"save_?version|saveVersion|schemaVersion|schema_version|\"version\"\s*:",
    "config": r"config\.(?:js|ts|json|py|gd)|settings\.(?:js|json|py)|balance\.(?:json|js)|\.tres\b",
    "version_display": r"\bVERSION\b|version_label|versionLabel|app_version",
}


def health(root):
    counts = {k: 0 for k in PATTERNS}
    tests = False
    configs = []
    for p in walk(root):
        low = p.name.lower()
        if re.search(r"(^test_|_test\.|\.test\.|\.spec\.|^tests?$)", low) or "gdunit" in low:
            tests = True
        if re.match(r"(config|settings|balance|tuning)[._-]", low) or low in ("config.json", "settings.json"):
            configs.append(p.relative_to(root).as_posix())
        if p.suffix.lower() not in CODE_EXT:
            continue
        t = read_text(p)
        if not t:
            continue
        for k, pat in PATTERNS.items():
            if k == "config":
                continue
            counts[k] += len(re.findall(pat, t))
    return counts, tests, configs[:8]


def run_hint(root, stack):
    hints = []
    if (root / "index.html").exists():
        hints.append(dk.L("双击 index.html（或起一个本地静态服务器）", "double-click index.html (or start a local static server)"))
    if (root / "package.json").exists():
        try:
            s = json.loads(read_text(root / "package.json") or "{}").get("scripts", {})
            for k in ("dev", "start", "serve"):
                if k in s:
                    hints.append(f"npm run {k}")
                    break
        except Exception:
            pass
    if (root / "project.godot").exists():
        hints.append(dk.L("用 Godot 打开 project.godot，或 godot --path .", "open project.godot in Godot, or run godot --path ."))
    return hints


def debt_drafts(counts, tests, configs, stack):
    rows = []
    if counts["unseeded_random"] and not counts["seed"]:
        rows.append((dk.L("随机没有走带种子的随机数", "Randomness does not go through a seeded RNG"), dk.L("bug 无法复现，调参前后无法公平比较", "Bugs cannot be reproduced; before/after tuning cannot be compared fairly"),
                     dk.L("所有随机经过一个带种子的 RNG，同种子两次运行关键状态一致", "All randomness goes through one seeded RNG; the same seed gives the same key state on two runs"), "高"))
    elif counts["unseeded_random"] > counts["seed"] * 3:
        rows.append((dk.L("仍有大量未带种子的随机调用", "Many unseeded random calls remain"), dk.L("部分行为无法复现", "Some behaviour cannot be reproduced"),
                     dk.L("全项目随机调用都走同一个带种子的 RNG（grep 无遗漏）", "Every random call in the project uses the same seeded RNG (grep finds none left)"), "中"))
    if not counts["debug_report"]:
        rows.append((dk.L("没有一键复制调试信息", "No one-click debug copy"), dk.L("人报 bug 要手写复现条件，来回追问", "Humans must hand-write repro conditions; back-and-forth questions"),
                     dk.L("按 F8 能复制版本、种子、场景、关键状态、最近事件、控制台错误", "F8 copies version, seed, scene, key state, recent events and console errors"), "高"))
    if not counts["tuning_panel"]:
        rows.append((dk.L("没有调参面板", "No tuning panel"), dk.L("手感类反馈要靠描述来回改", "Feel feedback has to be iterated through descriptions"),
                     dk.L("按 F9 出现面板，手感参数可实时拖动并「复制当前参数」", "F9 opens a panel; feel parameters can be dragged live and \"copy current values\""), "中"))
    if not configs:
        rows.append((dk.L("没有集中的配置文件", "No central config file"), dk.L("调参数要翻代码，AI 改参数容易动到逻辑", "Tuning means digging through code; the AI may touch logic when changing parameters"),
                     dk.L("手感和平衡类参数全部进入配置文件，代码里无魔法数字", "All feel and balance parameters live in config; no magic numbers in code"), "中"))
    if counts["save"] and not counts["save_version"]:
        rows.append((dk.L("存档没有版本号", "Save files have no version"), dk.L("改结构后旧存档会悄悄损坏，测试进度丢失", "Old saves silently break after a structure change; test progress is lost"),
                     dk.L("存档带 version 字段，改结构有迁移或明确废弃", "Saves carry a version field; structure changes come with a migration or an explicit drop"), "中"))
    if not tests:
        rows.append((dk.L("没有自动化测试或冒烟脚本", "No automated tests or smoke script"), dk.L("AI 无法自己验证，验收只能靠人", "The AI cannot self-verify; acceptance depends on humans"),
                     dk.L("至少有一条能一键运行的冒烟脚本，并在验收卡里作为「AI 已验证」", "At least one one-click smoke script exists and is listed as \"Verified by AI\" on the review card"), "中"))
    if not counts["version_display"]:
        rows.append((dk.L("界面上看不到版本号", "No version number visible in the UI"), dk.L("反馈对不上是哪一版", "Feedback cannot be matched to a version"), dk.L("界面角落显示版本 / 里程碑号", "The UI corner shows the version / milestone number"), "低"))
    return rows


# ---------- 输出 ----------

def build_report(root):
    L = []
    w = L.append
    w(dk.L(f"# 接手扫描：{root.name}", f"# Adoption scan: {root.name}"))
    w("")
    w(dk.L("> 这是**事实清单**，只含能从文件确定的内容。设计意图、历史决定属于推断，写进文档时必须标「（推断，待确认）」。", "> This is a **fact list**: only what can be determined from the files. Design intent and past decisions are inferences and must be marked \"(inferred, to be confirmed)\" when written into docs."))
    w("")

    w(dk.L("## 1. 版本控制", "## 1. Version control"))
    branch = sh(root, "git", "rev-parse", "--abbrev-ref", "HEAD")
    if branch:
        w(dk.L(f"- 分支：{branch}", f"- Branch: {branch}"))
        w(dk.L(f"- 提交数：{sh(root, 'git', 'rev-list', '--count', 'HEAD') or '未知'}", f"- Commits: {sh(root, 'git', 'rev-list', '--count', 'HEAD') or 'unknown'}"))
        w(dk.L(f"- 最近提交：{sh(root, 'git', 'log', '-1', '--format=%cs %s') or '未知'}", f"- Latest commit: {sh(root, 'git', 'log', '-1', '--format=%cs %s') or 'unknown'}"))
        dirty = sh(root, "git", "status", "--porcelain")
        w((dk.L(f"- 未提交改动：{len(dirty.splitlines())} 个文件", f"- Uncommitted changes: {len(dirty.splitlines())} file(s)")) if dirty else dk.L("- 工作区干净", "- Working tree clean"))
    elif sh(root, "git", "rev-parse", "--git-dir"):
        w(dk.L("- 是 git 仓库，但还没有任何提交（欠账：先做一次基线提交，改坏了才能退回）", "- A git repo, but with no commits yet (debt: make a baseline commit so you can roll back)"))
    else:
        w(dk.L("- **不是 git 仓库**（这是第一笔欠账：改坏了无法退回）", "- **Not a git repo** (the first debt: you cannot roll back if something breaks)"))
    w("")

    stack = detect_stack(root)
    w(dk.L("## 2. 技术栈与引擎", "## 2. Stack and engine"))
    if stack:
        for s in stack:
            w(f"- {s['name']}" + (f" {s['version']}" if s["version"] and s["name"] != "npm scripts" else "") + f" ({s['evidence']})")
    else:
        w(dk.L("- 没有识别出已知引擎或框架，需要人说明", "- No known engine or framework recognized; ask the human"))
    hints = run_hint(root, stack)
    if hints:
        w(dk.L("- 运行方式（推测）：", "- How to run (guess): ") + dk.L("；", "; ").join(hints))
    w("")

    loc, big, top = structure(root)
    w(dk.L("## 3. 代码结构", "## 3. Code structure"))
    if loc:
        w(dk.L("- 代码行数：", "- Lines of code: ") + dk.L("，", ", ").join(f"{k} {v}" for k, v in sorted(loc.items(), key=lambda x: -x[1])[:6]))
        w(dk.L("- 各目录代码文件数：", "- Code files per directory: ") + dk.L("，", ", ").join(f"{k} {v}" for k, v in sorted(top.items(), key=lambda x: -x[1])[:8]))
        w(dk.L("- 最大的文件（超过约 500 行建议拆分）：", "- Largest files (consider splitting beyond ~500 lines):"))
        for n, f in big[:8]:
            w(dk.L(f"  - {f}（{n} 行）", f"  - {f} ({n} lines)"))
    eps = entry_points(root)
    if eps:
        w(dk.L("- 入口：", "- Entry points: ") + dk.L("、", ", ").join(eps))
    w("")

    w(dk.L("## 4. 已有文档", "## 4. Existing docs"))
    docs = existing_docs(root)
    w("- " + dk.L("、", ", ").join(docs) if docs else dk.L("- 没有找到 README 或设计文档", "- No README or design doc found"))
    w("")

    counts, tests, configs = health(root)
    w(dk.L("## 5. 可验收性体检（对照 contracts/feedback_friendly.md）", "## 5. Reviewability health check (against contracts/feedback_friendly.md)"))
    w("")
    w(dk.L("| 项 | 发现 |", "| Item | Finding |"))
    w("| --- | --- |")
    w(dk.L(f"| 随机调用 / 种子相关 | 未带种子的随机调用约 {counts['unseeded_random']} 处；种子相关约 {counts['seed']} 处 |", f"| Random calls / seeds | ~{counts['unseeded_random']} unseeded random call(s); ~{counts['seed']} seed-related |"))
    w(f"| {dk.L('调参面板', 'Tuning panel')} | {dk.L('发现相关代码', 'related code found') if counts['tuning_panel'] else dk.L('未发现', 'not found')} |")
    w(f"| {dk.L('一键复制调试信息', 'One-click debug copy')} | {dk.L('发现相关代码', 'related code found') if counts['debug_report'] else dk.L('未发现', 'not found')} |")
    w(f"| {dk.L('集中配置文件', 'Central config')} | {dk.L('、', ', ').join(configs) if configs else dk.L('未发现', 'not found')} |")
    w(dk.L(f"| 存档 | {'有存档相关代码' if counts['save'] else '未发现'}；版本号字段：{'有' if counts['save_version'] else '未发现'} |", f"| Saves | {'save-related code found' if counts['save'] else 'not found'}; version field: {'yes' if counts['save_version'] else 'not found'} |"))
    w(f"| {dk.L('自动化测试', 'Automated tests')} | {dk.L('发现测试文件', 'test files found') if tests else dk.L('未发现', 'not found')} |")
    w(f"| {dk.L('界面版本号', 'Version in UI')} | {dk.L('发现', 'found') if counts['version_display'] else dk.L('未发现', 'not found')} |")
    w("")
    w(dk.L("> 以上是关键词扫描，会有误报和漏报；AI 读入口和配置文件后要核实，不要照单全收。", "> The above is a keyword scan with false positives and negatives; the AI must verify after reading the entry and config files, not take it at face value."))
    w("")

    w(dk.L("## 6. 欠账草稿（可直接整理进 DEVELOP_DEBT.md）", "## 6. Debt drafts (ready to move into DEVELOP_DEBT.md)"))
    rows = debt_drafts(counts, tests, configs, stack)
    if not branch:
        rows.insert(0, (dk.L("没有 git 存档", "No git history"), dk.L("改坏了无法退回", "Cannot roll back if something breaks"), dk.L("仓库已建并提交一次", "Repo created and committed once"), "高"))
    if rows:
        w("")
        w(dk.L("| 欠什么 | 影响 | 怎样才算还清 | 优先级 |", "| What is owed | Impact | Payoff criteria | Priority |"))
        w("| --- | --- | --- | --- |")
        for r in rows:
            w("| " + " | ".join(list(r[:-1]) + [dk.tv(r[-1])]) + " |")
    else:
        w(dk.L("- 没有发现明显缺口", "- No obvious gaps found"))
    w("")

    w(dk.L("## 7. 给 AI 的下一步", "## 7. Next steps for the AI"))
    w(dk.L("1. 只读入口文件、配置文件和上面「最大的文件」里与核心玩法相关的几个，不要通读。", "1. Read only the entry files, config files and the few of the \"largest files\" above that relate to the core loop; don't read everything."))
    w(dk.L("2. 写 `docs/dev/CURRENT_STATE.md`（≤100 行）：能用到什么、没有什么、关键实现在哪个文件。", "2. Write `docs/dev/CURRENT_STATE.md` (≤100 lines): what works, what is missing, which file holds the key implementation."))
    w(dk.L("3. 写 `docs/design/DESIGN.md`：只写能从 README 和代码确定的，推断处标「（推断，待确认）」，不要编造设计意图；验收基准用类型预设（`init.py --genre`）。", "3. Write `docs/design/DESIGN.md`: only what the README and code establish; mark inferences \"(inferred, to be confirmed)\" and never invent design intent; use a genre preset for the acceptance baseline (`init.py --genre`)."))
    w(dk.L("4. 把第 6 节整理进 `DEVELOP_DEBT.md`；README 与代码对不上的地方记进 `known_mismatches.md`。", "4. Move section 6 into `DEVELOP_DEBT.md`; log places where the README and code disagree in `known_mismatches.md`."))
    w(dk.L("5. 在 `plans/README.md` 建 **M0「接手基线」**，状态「待验收」，生成验收卡。「请你重点判断」写：CURRENT_STATE 描述属实吗？设计意图的推断对吗？", "5. In `plans/README.md` create **M0 \"Adoption baseline\"** with status \"In review\" and generate its review card. Under \"Key questions for you\" ask: is the CURRENT_STATE description accurate? Are the design-intent inferences right?"))
    w(dk.L("6. 人在 M0 验收卡上签字，接手才算完成。", "6. Adoption is complete only when the human signs the M0 review card."))
    return "\n".join(L) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("root", nargs="?", default=".")
    ap.add_argument("-o", "--out")
    ap.add_argument("--lang", default=None, choices=("en", "zh"), help="输出语言；默认读 docs/dev/.lang，没有则 en")
    a = ap.parse_args()
    dk.set_lang("en")
    if a.lang:
        dk.set_lang(a.lang)
    else:
        _f = Path(a.root).resolve() / "docs" / "dev" / ".lang"
        if _f.exists():
            dk.set_lang(_f.read_text(encoding="utf-8").strip())
    root = Path(a.root).resolve()
    if not root.is_dir():
        sys.exit(dk.L(f"不是目录：{root}", f"Not a directory: {root}"))
    report = build_report(root)
    if a.out:
        Path(a.out).write_text(report, encoding="utf-8")
        print(dk.L(f"已写入 {a.out}", f"Written to {a.out}"))
    else:
        print(report)


if __name__ == "__main__":
    main()
