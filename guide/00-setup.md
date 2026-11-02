# 00. 준비하기

> 보드를 연결하고 호스트에 빌드 환경을 만든다. 여기까지 되면 다음 장부터 실제로 빌드하고 부팅시킬 수 있다.

## 0-1. 보드 연결

케이블이 둘 필요하다.

- **USB-C 케이블**: 보드에 전원을 공급한다. 호스트 PC에 연결하면 DFU 통신도 이 선으로
  한다.
- **디버그 프로브 U 포트**: 시리얼 콘솔이다. 부팅 로그를 보려면 이게 있어야 한다.

프로브의 U 포트는 TX·RX·GND 3선뿐이라 전원을 공급하지 않는다. 프로브만 꽂으면 보드가
안 켜지고, USB-C만 꽂으면 부팅 과정을 못 본다.

콘솔은 호스트에서 `/dev/ttyACM0`으로 보이고 115200 8N1이다.

```
screen /dev/ttyACM0 115200
```

디버그 프로브의 D 포트는 SWD용인데 AM62x는 SWD를 지원하지 않는다. JTAG을 쓰려면 보드의
Tag-Connect 10핀 패드에 별도 케이블이 필요하다.

## 0-2. 호스트 패키지

Ubuntu 24.04 기준이다. `build-r5.sh`가 시작할 때 전제를 확인하지만 전부는 아니다.
`gcc`, `python3-venv`, `python3-dev`, `dfu-util`, `gcc-aarch64-linux-gnu`는 검사하지
않는다.

```
sudo apt install gcc-arm-linux-gnueabihf gcc-aarch64-linux-gnu \
                 python3-venv python3-dev \
                 libgnutls28-dev libssl-dev \
                 gcc make bison flex swig device-tree-compiler pkgconf dfu-util
```

크로스 컴파일러가 둘이다. R5는 32비트 ARM이라 `arm-linux-gnueabihf-`, A53은 64비트라
`aarch64-linux-gnu-`를 쓴다.

R5용으로 `arm-linux-gnueabihf-`를 쓰는 것은 U-Boot의 K3 문서가 전제하는 값이기
때문이다(`doc/board/ti/k3.rst`). 베어메탈 툴체인(`arm-none-eabi-`)으로도 빌드된다. 이
빌드는 `CONFIG_USE_PRIVATE_LIBGCC=y`라 툴체인 libgcc를 링크하지 않고 U-Boot 자체
구현(`arch/arm/lib/lib.a`)을 쓰므로 어느 쪽이든 상관없다.

나머지 패키지는 없을 때 나는 오류가 원인과 멀다.

- `python3-dev`: pylibfdt가 swig로 만든 C 확장을 컴파일할 때 `Python.h`가 필요하다.
- `libgnutls28-dev`: 호스트 도구 `mkeficapsule`이 쓴다.
- `libssl-dev`: mkimage 계열이 쓴다.

U-Boot의 `tools/Makefile`은 `pkg-config` 실패를 빈 문자열로 넘긴다. 그래서 이 헤더들이
없으면 설정 단계에서 걸리지 않고 한참 컴파일한 뒤에야 터진다.

## 0-3. venv

U-Boot 빌드는 파이썬 도구를 쓴다. 이미지를 조립하는 binman이 대표적이다.

binman은 `tools/binman/requirements.txt`에 적힌 버전을 요구한다. apt로 설치되는
pyelftools는 버전이 낮아 빌드가 깨지므로 venv를 따로 만든다.

```
/usr/bin/python3 -m venv venv
venv/bin/python3 -m pip install -r u-boot/tools/binman/requirements.txt setuptools cryptography
```

`setuptools`는 `requirements.txt`에 없지만 pylibfdt의 `setup.py`가 쓴다. Python
3.12부터 venv 부트스트랩에서 빠졌으므로 따로 넣어야 한다. `cryptography`는 OP-TEE의
서명 스크립트가 쓴다.

배포판 python을 절대 경로(`/usr/bin/python3`)로 지정하는 것은 그냥 `python3`로 하면
conda 같은 다른 설치를 가리킬 수 있기 때문이다. venv는 만들 때의 인터프리터에 묶이므로
기계마다 다른 환경이 만들어진다.

### venv는 만든 자리에 묶인다

`bin/activate`가 절대 경로를 export하고 `bin/pip`의
shebang도 절대 경로다. 저장소를 다른 경로로 옮기면 둘 다 없는 경로를 가리킨다.

이때 `activate`는 오류를 내지 않고 조용히 실패하고 시스템 python이
잡힌다. 그 상태로 빌드하면 엉뚱한 패키지 버전이 쓰인다.

저장소를 옮겼으면 venv를 다시 만든다.

```
rm -rf venv && /usr/bin/python3 -m venv venv
venv/bin/python3 -m pip install -r u-boot/tools/binman/requirements.txt setuptools cryptography
```

## 0-4. 소스와 blob 받기

`u-boot/`, `trusted-firmware-a/`, `optee_os/`는 git에서 제외된다. 아래 명령으로 받는다.

```
git clone --depth 1 --branch v2026.01-am62-pocketbeagle2 https://github.com/beagleboard/u-boot.git
git clone --depth 1 --branch lts-v2.14.1 https://github.com/ARM-software/arm-trusted-firmware trusted-firmware-a
git clone --depth 1 --branch 4.9.0 https://github.com/OP-TEE/optee_os optee_os
```

태그는 보드가 출하 시 싣고 있던 것과 같은 값이다. 이유는
[04. 소스 받기와 빌드](04-building.md)에 있다.

u-boot 트리에 가한 수정은 `patches/`에 패치 파일로 보관한다. 새로 클론했으면 적용한다.

```
git -C u-boot apply patches/*.patch
```

소스에서 나오지 않는 조각도 있다. TI가 바이너리로만 배포하는 펌웨어다.

```
curl -L --create-dirs -o ti-linux-firmware/ti-sysfw/ti-fs-firmware-am62x-hs-fs-enc.bin https://raw.githubusercontent.com/TexasInstruments/ti-linux-firmware/11.02.11/ti-sysfw/ti-fs-firmware-am62x-hs-fs-enc.bin
curl -L --create-dirs -o ti-linux-firmware/ti-sysfw/ti-fs-firmware-am62x-hs-fs-cert.bin https://raw.githubusercontent.com/TexasInstruments/ti-linux-firmware/11.02.11/ti-sysfw/ti-fs-firmware-am62x-hs-fs-cert.bin
curl -L --create-dirs -o ti-linux-firmware/ti-dm/am62xx/ipc_echo_testb_mcu1_0_release_strip.xer5f https://raw.githubusercontent.com/TexasInstruments/ti-linux-firmware/11.02.11/ti-dm/am62xx/ipc_echo_testb_mcu1_0_release_strip.xer5f
```

앞의 둘은 R5 패스가, 마지막 하나는 A53 패스가 쓴다. ti-linux-firmware 저장소를 통째로
받을 필요는 없다.

## 0-5. udev 규칙

DFU로 부트로더를 보내려면 일반 사용자가 USB 장치를 열 수 있어야 한다. `dfu-util`
패키지가 설치하는 규칙에는 TI의 VID가 없어서 추가해야 한다.

```
# /etc/udev/rules.d/70-pocketbeagle2.rules
SUBSYSTEM=="usb", ATTR{idVendor}=="0451", ATTR{idProduct}=="6165", TAG+="uaccess"

ACTION=="add|change", SUBSYSTEM=="usb", ATTRS{idVendor}=="2e8a", ATTRS{idProduct}=="000c", ENV{ID_MM_DEVICE_IGNORE}="1"
ACTION=="add|change", SUBSYSTEM=="tty", ATTRS{idVendor}=="2e8a", ATTRS{idProduct}=="000c", ENV{ID_MM_DEVICE_IGNORE}="1"
```

자세한 설명은 [05. DFU로 부팅시키기](05-dfu.md)에 있다.

## 0-6. 빌드 확인

여기까지 됐으면 빌드가 돌아야 한다.

```
./build-r5.sh
./build-a53.sh
```

산출물은 `out/`에 나오고 git에서 제외된다. 스크립트는 자기가 놓인 자리를 작업 루트로
잡으므로 저장소를 어디에 두든 상관없다. 시작할 때 전제를 확인하고, 빠진 것이 있으면
모아서 보여준 뒤 멈춘다.

### 산출물 크기로 비교할 때 주의

크기는 같은 기계에서 조건 하나만 바꿔 비교할 때만 지표가 된다. 컴파일러 버전이 다르면
코드 생성 결과가 달라져 기계 간에는 크기가 일치하지 않는다.

기계를 건너 확인할 때는 실기기 부팅과 콘솔 배너의 빌드 타임스탬프를 본다.

## 정리

- 케이블 둘이 필요하다. USB-C는 전원과 DFU, 프로브 U 포트는 콘솔이다.
- 크로스 컴파일러가 둘이다. R5용 32비트, A53용 64비트.
- venv는 만든 자리에 묶인다. 저장소를 옮겼으면 다시 만든다.
- 소스 셋과 TI 바이너리 셋을 받아야 빌드가 된다.
