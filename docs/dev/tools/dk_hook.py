#!/usr/bin/env python3
"""Claude Code hook 入口：把"AI 不能自己宣布完成"从自觉变成强制。

由 .claude/settings.json 调用（init.py --hooks 会写入）：
    dk_hook.py start   SessionStart：把 ≤15 行的状态摘要注入新会话（plain stdout 会成为上下文）
    dk_hook.py stop    Stop：docs 检查有 ERROR 时拦住"收工"，让 Claude 先处理

Stop 拦截方式：输出 {"decision":"block","reason":...}（官方文档的顶层 decision 机制）。

防死循环：有些 ERROR 需要人来处理（例如验收签字），Claude 无法自己解决。
同一组错误（按内容指纹）在同一会话里最多拦 2 次，之后放行，并在 stderr 留一行提示。
如果官方输入里带有 stop_hook_active=true，也只会在指纹计数允许时才再次拦截，不会无限循环。

出错一律放行：hook 自己出问题不能卡住用户。
"""
import hashlib
import json
import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import dk_common as dk  # noqa: E402

MAX_BLOCKS = 2


def read_stdin_json():
    try:
        raw = sys.stdin.read()
        return json.loads(raw) if raw.strip() else {}
    except Exception:
        return {}


def find_root(data):
    for cand in (os.environ.get("CLAUDE_PROJECT_DIR"), data.get("cwd"), os.getcwd()):
        if cand and (Path(cand) / "docs" / "dev").is_dir():
            return Path(cand)
    return None


def state_path(session_id):
    safe = "".join(c for c in (session_id or "nosession") if c.isalnum() or c in "-_")[:64]
    return Path(tempfile.gettempdir()) / f"dk_hook_{safe}.json"


def load_state(p):
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return {}


def cmd_start(root):
    import check_docs as cd
    print(cd.brief(root))


def cmd_stop(root, data):
    import check_docs as cd
    dk.detect_lang(root)
    R, _ms, _rv = cd.run_checks(root)
    errors = R.messages("ERROR")
    sp = state_path(data.get("session_id"))
    if not errors:
        try:
            sp.unlink()
        except OSError:
            pass
        return

    fp = hashlib.sha1((str(root) + "\n" + "\n".join(sorted(errors))).encode("utf-8")).hexdigest()
    st = load_state(sp)
    count = st.get("count", 0) if st.get("fp") == fp else 0
    if count >= MAX_BLOCKS:
        sys.stderr.write(dk.L(f"vibecodingflow：仍有 {len(errors)} 个 ERROR，已提醒 {count} 次，不再拦截。请人来处理。\n",
                              f"vibecodingflow: {len(errors)} ERROR(s) remain after {count} reminders; no longer blocking. A human needs to handle this.\n"))
        return
    try:
        sp.write_text(json.dumps({"fp": fp, "count": count + 1}), encoding="utf-8")
    except OSError:
        pass

    shown = errors[:5]
    more = dk.L(f"\n（另有 {len(errors) - 5} 条）", f"\n({len(errors) - 5} more)") if len(errors) > 5 else ""
    if dk.get_lang() == "en":
        reason = (
            "vibecodingflow docs check found ERRORs; handle them before finishing:\n- " + "\n- ".join(shown) + more +
            "\n\nIf one needs a human decision (e.g. review sign-off), do not bypass it or sign on their behalf: "
            "set the milestone status back to \"In review\" or \"In progress\" and tell the human what they need to do. "
            "Full check: python docs/dev/tools/check_docs.py"
        )
    else:
        reason = (
            "vibecodingflow 文档检查有 ERROR，先处理再收工：\n- " + "\n- ".join(shown) + more +
            "\n\n如果某条需要人来决定（比如验收签字），不要自行绕过或代签："
            "把里程碑状态退回「待验收」或「进行中」，并向人说明需要他做什么。"
            "完整检查：python docs/dev/tools/check_docs.py"
        )
    print(json.dumps({"decision": "block", "reason": reason}, ensure_ascii=False))


def main():
    event = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        data = read_stdin_json()
        root = find_root(data)
        if root is None:
            return  # 不是 vibecodingflow 项目，静默放行
        if event == "start":
            cmd_start(root)
        elif event == "stop":
            cmd_stop(root, data)
    except Exception as e:  # hook 自己出错不能卡住用户
        sys.stderr.write(f"vibecodingflow hook error (let through) / hook 出错（已放行）: {e}\n")


if __name__ == "__main__":
    for _stream in (sys.stdout, sys.stderr):
        try:
            _stream.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass
    main()
