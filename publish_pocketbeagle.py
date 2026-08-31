#!/usr/bin/env python3
"""PocketBeagle 2 자료를 개인 스페이스에 발행한다.

  python3 publish_pocketbeagle.py plan   대상과 원격 버전만 출력
  python3 publish_pocketbeagle.py sync   본문 발행

인덱스 페이지는 개인 스페이스 「개인 공부」 폴더(1400897555) 아래에 있다.
datasheets/ 의 PDF와 logs/ 의 부트 로그는 발행 대상이 아니다.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2]
                       / "tools" / "confluence"))
from publisher import Publisher  # noqa: E402

DOCS = [
    ("README.md",              "PocketBeagle 2 부트로더 직접 만들기", None),
    ("guide/00-setup.md",      "00. 준비하기", None),
    ("guide/01-hardware.md",   "01. 보드와 칩", None),
    ("guide/02-boot-flow.md",  "02. 부팅은 어떻게 일어나는가", None),
    ("guide/03-images.md",     "03. 부트 이미지와 서명", None),
    ("guide/04-building.md",   "04. 소스 받기와 빌드", None),
    ("guide/05-dfu.md",        "05. DFU로 부팅시키기", None),
    ("guide/06-hands-on.md",   "06. 직접 확인해보기", None),
    ("guide/07-spl-code.md",   "07. SPL 코드 읽기", None),
    ("guide/08-spl-c-code.md", "08. SPL의 C 구간", None),
    ("guide/09-binman.md",     "09. 이미지는 어떻게 조립되나", None),
    ("guide/10-devicetree.md", "10. 디바이스 트리와 SPL", None),
    ("guide/11-tisci.md",      "11. 코어 사이의 대화", None),
    ("guide/12-to-linux.md",   "12. U-Boot에서 리눅스까지", None),
    ("roadmap.md",             "브링업 로드맵", None),
    ("applications.md",        "오디오 응용 계획", None),
]

Publisher(doc_dir=pathlib.Path(__file__).resolve().parent,
          index_id="1444151439", docs=DOCS).main()
