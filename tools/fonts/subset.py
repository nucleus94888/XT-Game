"""字型子集化：掃出 hanzo/ 內所有腳本與場景實際用到的字，加上 fonts/extra_chars.txt 的常用字池，
從 tools/fonts/NotoSansTC-Regular.otf（OFL 授權，5.7 MB，不進遊戲包）切出只含這些字的 hanzo/fonts/ui.otf（約 200 KB）。

用法：python tools/fonts/subset.py
需要：pip install fonttools
UI 新增了面板上沒出現過的字時，把字加進 extra_chars.txt 再跑一次即可。
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2] / "hanzo"
SRC = pathlib.Path(__file__).resolve().parent / "NotoSansTC-Regular.otf"
DST = ROOT / "fonts" / "ui.otf"


def collect_chars() -> str:
    chars: set[str] = set()
    files = list(ROOT.rglob("*.gd")) + list(ROOT.rglob("*.tscn")) + [ROOT / "project.godot"]
    files += list((ROOT / "fonts").glob("*.txt"))
    for p in files:
        if p.is_file():
            chars.update(p.read_text(encoding="utf-8", errors="ignore"))
    return "".join(sorted(c for c in chars if ord(c) >= 0x20 and not c.isspace()))


SRC_URL = "https://github.com/notofonts/noto-cjk/raw/main/Sans/SubsetOTF/TC/NotoSansTC-Regular.otf"


def main() -> int:
    if not SRC.exists():
        import urllib.request
        print(f"下載來源字型 {SRC_URL} …")
        urllib.request.urlretrieve(SRC_URL, SRC)
    text = collect_chars()
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8") as f:
        f.write(text)
        text_file = f.name
    cmd = [
        sys.executable, "-m", "fontTools.subset", str(SRC),
        f"--text-file={text_file}",
        "--unicodes=U+0020-007E,U+00A0-00FF,U+2000-206F,U+3000-303F,U+FF00-FFEF",
        f"--output-file={DST}",
        "--layout-features=*", "--no-hinting", "--desubroutinize",
    ]
    subprocess.check_call(cmd)
    print(f"ui.otf: {DST.stat().st_size / 1024:.0f} KB，包含 {len(text)} 個非空白字元")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
