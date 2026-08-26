#!/usr/bin/env python3
"""PocketBeagle 2 자료를 개인 스페이스에 발행한다.

  python3 publish_pocketbeagle.py plan   대상과 원격 버전만 출력
  python3 publish_pocketbeagle.py sync   본문 발행

인덱스 페이지는 개인 스페이스 「개인 공부」 폴더(1400897555) 아래에 있다.
docs/ 의 PDF와 logs/ 의 부트 로그는 발행 대상이 아니다.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2]
                       / "tools" / "confluence"))
from publisher import Publisher  # noqa: E402

DOCS = [
    ("README.md",             "PocketBeagle 2",        None),
    ("boot-architecture.md",  "부트 구조와 코어 구성", None),
    ("roadmap.md",            "브링업 로드맵",         None),
    ("applications.md",       "오디오 응용 계획",      None),
]

Publisher(doc_dir=pathlib.Path(__file__).resolve().parent,
          index_id="1444151439", docs=DOCS).main()
