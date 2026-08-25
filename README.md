# PocketBeagle 2

> 개인 학습용 보드(Rev A1, AM6254) 자료 보관처다.

## 문서

<!-- colwidth: 200 560 -->
| 문서 | 내용 |
|---|---|
| [부트 구조와 코어 구성](boot-architecture.md) | 코어 배치, 부트 체인, 부트 이미지 3종의 구성, 서명, 부트 모드 결정 구조, 직접 만든 코드로 대체할 수 있는 경계, USB DFU 경로와 복구 수단 |
| [브링업 로드맵](roadmap.md) | 브링업 연습 단계별 계획. 단계마다 완료 기준과 이해할 것을 둔다 |
| [오디오 응용 계획](applications.md) | 오디오 응용 두 가지. 휴대형 플레이어와 악기용 이펙터이며 헤더 신호와 전원 구성을 공유한다 |

## 참고 자료

`pocketbeagle-2-srm.pdf`는 시스템 레퍼런스 매뉴얼 2026-06-04판이다. 아래 명령으로
받는다.

```
curl -L -o docs/pocketbeagle-2-srm.pdf https://docs.beagleboard.org/pocketbeagle-2.pdf
```

HTML 원본은 [docs.beagleboard.org](https://docs.beagleboard.org/boards/pocketbeagle-2/)에 있다.

SoC 문서는 TI에서 받는다. 부팅은 TRM 5장이다.

```
curl -L -o docs/am62x-trm-spruiv7c.pdf       https://www.ti.com/lit/pdf/spruiv7
curl -L -o docs/am62x-datasheet-sprsp58c.pdf https://www.ti.com/lit/pdf/sprsp58
curl -L -o docs/mspm0l1105.pdf               https://www.ti.com/lit/gpn/mspm0l1105
```

문헌번호 없이 받으면 최신 리비전으로 리다이렉트된다. 위 파일명은 받은 시점의
리비전(TRM Rev C, 데이터시트 Rev C)이다.

## 빌드 재료

`u-boot/`는 beagleboard/u-boot의 shallow 클론이고 git에서 제외된다. 저장소·브랜치·
커밋은 [boot-architecture.md](boot-architecture.md) 소스 트리 절에 있다.

```
git clone --depth 1 --branch v2026.01-am62-pocketbeagle2 https://github.com/beagleboard/u-boot.git
```

u-boot 트리에 가한 수정은 `patches/`에 패치 파일로 보관한다. 새 클론에는
`git -C u-boot apply patches/*.patch`로 적용한다.

`ti-linux-firmware/ti-sysfw/`의 TIFS blob 2개는 TexasInstruments/ti-linux-firmware
저장소 11.02.11 태그에서 받는다.

```
curl -L -o ti-linux-firmware/ti-sysfw/ti-fs-firmware-am62x-hs-fs-enc.bin  https://raw.githubusercontent.com/TexasInstruments/ti-linux-firmware/11.02.11/ti-sysfw/ti-fs-firmware-am62x-hs-fs-enc.bin
curl -L -o ti-linux-firmware/ti-sysfw/ti-fs-firmware-am62x-hs-fs-cert.bin https://raw.githubusercontent.com/TexasInstruments/ti-linux-firmware/11.02.11/ti-sysfw/ti-fs-firmware-am62x-hs-fs-cert.bin
```

`BINMAN_INDIRS`는 위 blob 2개가 있는 `ti-linux-firmware/`만 있으면 되고,
ti-linux-firmware 저장소를 통째로 받을 필요는 없다.

## 빌드

`build-r5.sh`가 1b(R5 패스) 두 빌드를 돌린다. 산출물은 `out/`에 나오고 git에서
제외된다. 스크립트는 자기가 놓인 자리를 작업 루트로 잡으므로 저장소를 어디에
두든 상관없다.

binman은 `tools/binman/requirements.txt`의 버전 고정을 요구한다. apt의
pyelftools는 버전이 낮아 빌드가 깨지므로 venv를 따로 만든다. `venv/`도 git에서
제외된다.

```
python3 -m venv venv
venv/bin/pip install -r u-boot/tools/binman/requirements.txt
./build-r5.sh
```

크로스 컴파일러는 `arm-linux-gnueabihf-`다.
