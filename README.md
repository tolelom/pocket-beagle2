# PocketBeagle 2

> 개인 학습용 보드(Rev A1, AM6254) 자료 보관처다.

## 문서

<!-- colwidth: 200 560 -->
| 문서 | 내용 |
|---|---|
| [부트 구조와 코어 구성](boot-architecture.md) | 코어 배치, 부트 체인, 부트 이미지 구성, 서명, 부트 모드 결정 구조, 직접 만든 코드로 대체할 수 있는 경계, USB DFU 경로와 복구 수단 |
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

A53 패스는 DM 펌웨어 blob을 하나 더 요구한다. 요구하는 쪽은
`k3-am62-pocketbeagle2-u-boot.dtsi`의 `ti-dm` 노드다.

```
curl -L --create-dirs -o ti-linux-firmware/ti-dm/am62xx/ipc_echo_testb_mcu1_0_release_strip.xer5f https://raw.githubusercontent.com/TexasInstruments/ti-linux-firmware/11.02.11/ti-dm/am62xx/ipc_echo_testb_mcu1_0_release_strip.xer5f
```

`tispl.bin`의 나머지 조각은 소스에서 빌드한다. 태그는 보드가 출하 시 싣고 있던
것과 같은 값이다.

```
git clone --depth 1 --branch lts-v2.14.1 https://github.com/ARM-software/arm-trusted-firmware trusted-firmware-a
git clone --depth 1 --branch 4.9.0 https://github.com/OP-TEE/optee_os optee_os
```

## 빌드

`build-r5.sh`가 1b(R5 패스) 두 빌드를, `build-a53.sh`가 1e(A53 패스)를 돌린다. 산출물은 `out/`에 나오고 git에서
제외된다. 스크립트는 자기가 놓인 자리를 작업 루트로 잡으므로 저장소를 어디에
두든 상관없다. 시작할 때 전제를 확인하고, 빠진 것이 있으면 모아서 보여준 뒤
멈춘다.

### 호스트 패키지

Ubuntu 24.04 기준이다. `build-r5.sh`는 시작할 때 이 목록을 확인하되 `gcc`와
`python3-venv`·`python3-dev`는 검사하지 않는다.

```
sudo apt install gcc-arm-linux-gnueabihf python3-venv python3-dev \
                 libgnutls28-dev libssl-dev \
                 gcc make bison flex swig device-tree-compiler pkgconf
```

크로스 컴파일러는 `arm-linux-gnueabihf-`다. U-Boot의 K3 문서가 전제하는 값이고
(`doc/board/ti/k3.rst`), `build-r5.sh`도 이 값을 쓴다. 이 빌드는
`CONFIG_USE_PRIVATE_LIBGCC=y`라 툴체인 libgcc를 링크하지 않고 U-Boot 자체
구현(`arch/arm/lib/lib.a`)을 쓴다. `arm-none-eabi-`로도 빌드된다.

`python3-dev`는 pylibfdt가 swig로 만든 C 확장을 컴파일할 때 `Python.h`가
필요해서 든다. `libgnutls28-dev`는 호스트 도구 `mkeficapsule`이,
`libssl-dev`는 mkimage 계열이 쓴다. U-Boot의 `tools/Makefile`은 `pkg-config`
실패를 빈 문자열로 넘기므로, 이 헤더들이 없으면 한참 컴파일한 뒤에야 터진다.

### venv

binman은 `tools/binman/requirements.txt`의 버전 고정을 요구한다. apt의
pyelftools는 버전이 낮아 빌드가 깨지므로 venv를 따로 만든다. `venv/`도 git에서
제외된다.

```
/usr/bin/python3 -m venv venv
venv/bin/python3 -m pip install -r u-boot/tools/binman/requirements.txt setuptools cryptography
./build-r5.sh
```

`setuptools`는 `requirements.txt`에 없지만 pylibfdt의 `setup.py`가 쓴다.
Python 3.12부터 venv 부트스트랩에서 빠졌으므로 따로 넣어야 한다. `cryptography`는
OP-TEE의 서명 스크립트가 쓴다.

venv는 만든 자리에 묶인다. `bin/activate`가 절대 경로를 export하고 `bin/pip`의
shebang도 절대 경로이므로, 저장소를 옮기면 둘 다 없는 경로를 가리킨다. 이때
`activate`는 조용히 실패해 시스템 python이 잡히므로 저장소를 옮겼으면 venv를
다시 만든다.

배포판 python을 절대 경로로 지정하는 이유는 `python3`가 conda 같은 다른 설치를
가리킬 수 있어서다. venv는 만들 때의 인터프리터에 묶이므로, 그 인터프리터가
기계마다 다르면 같은 명령이 다른 환경을 만든다.

### 산출물 크기 대조

크기는 같은 기계에서 조건 하나만 바꿔 비교할 때만 지표가 된다. 컴파일러 버전이
다르면 코드 생성 결과가 달라져 기계 간에는 크기가 일치하지 않는다. 기계를 건너
확인할 때는 실기기 부팅과 콘솔 배너의 빌드 타임스탬프를 본다.
