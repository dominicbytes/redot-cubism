"""Add one callback event to an isolated copy of Mao's TapBody/3 motion.

Run before the isolated project is imported. This never writes to the retained
source fixture; the supplied path must name the runner's private project copy.
"""

import argparse
import json
from pathlib import Path


EVENT = "csharp-wrapper-event-😀"
MOTION = Path("addons/gd_cubism/example/res/live2d/mao_pro_jp/runtime/motions/special_01.motion3.json")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("project", type=Path)
    args = parser.parse_args()
    project = args.project.resolve(strict=True)
    path = (project / MOTION).resolve(strict=True)
    if not path.is_relative_to(project):
        raise RuntimeError("motion path leaves private project")
    data = json.loads(path.read_text(encoding="utf-8"))
    if data["Meta"]["UserDataCount"] != 0 or data.get("UserData"):
        raise RuntimeError("expected an unmodified Mao motion with no user data")
    data["Meta"]["UserDataCount"] = 1
    data["Meta"]["TotalUserDataSize"] = len(EVENT.encode("utf-8"))
    data["UserData"] = [{"Time": 0.1, "Value": EVENT}]
    path.write_text(json.dumps(data, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8")
    print(f"MOTION_EVENT_FIXTURE: {path} event={EVENT}")


if __name__ == "__main__":
    main()
