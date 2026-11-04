# 04. 소스 받기와 빌드

> 부트로더를 직접 빌드한다. 소스가 어디서 오는지, 왜 두 번 빌드하는지, 그리고 이 보드에서 반드시 맞춰야 하는 주소 네 개를 다룬다.

## 4-1. 어느 소스를 쓰나

U-Boot는 메인라인이 있고 벤더 포크가 있다. 이 보드는 벤더 포크를 쓴다.

```
저장소:    beagleboard/u-boot
브랜치:    v2026.01-am62-pocketbeagle2
커밋:      ef03e35488377a32cdd4f76d1a03ef7f60c798ef
defconfig: am62_pocketbeagle2_r5_defconfig
           am62_pocketbeagle2_a53_defconfig
```

이 커밋이 맞는지는 확인할 수 있다. 보드에 설치된 `bb-u-boot-pocketbeagle2` 패키지의
U-Boot 버전 문자열이 `2026.01-gef03e3548837`인데 위 커밋과 일치한다.

메인라인 U-Boot에도 이 보드의 디바이스 트리는 들어가 있다
(`dts/upstream/src/arm64/ti/k3-am62-pocketbeagle2.dts`). 하지만 defconfig가 없어서
메인라인만으로는 빌드할 수 없다.

함께 쓰는 다른 프로젝트의 버전은 이렇다. 보드가 출하 시 싣고 있던 것과 같은 값이다.

```
ti-linux-firmware  11.02.11
OP-TEE             4.9.0
TF-A               lts-v2.14.1
```

버전을 맞춰 두면 뭔가 안 될 때 원인이 "빌드 설정"인지 "버전 조합"인지 가를 수 있다.

## 4-2. 왜 두 번 빌드하나

K3는 2패스 빌드다. 같은 U-Boot 소스를 설정만 바꿔 두 번 빌드한다.

- **R5 패스**가 `tiboot3.bin`을 만든다. Cortex-R5용이라 32비트 ARM으로 컴파일된다.
- **A53 패스**가 `tispl.bin`과 `u-boot.img`를 만든다. Cortex-A53용이라 64비트다.

부팅 로그에 SPL 배너가 2회 찍히는 것이 이것 때문이다. 같은 바이너리가 두 번 도는 게
아니라 아예 다른 두 바이너리다.

R5 패스가 요구하는 외부 blob은 ti-linux-firmware의
`ti-sysfw/ti-fs-firmware-am62x-hs-fs-enc.bin`(TIFS 펌웨어)과
`ti-fs-firmware-am62x-hs-fs-cert.bin`(inner cert) 2개다. TF-A와 OP-TEE는 A53 패스의
재료라 `tiboot3.bin`만 빌드할 때는 필요 없다.

## 4-3. R5 패스

`build-r5.sh`가 이 과정을 돌린다. 핵심은 아래 두 줄이고 나머지는 전제 확인과 로그
정리다. 이 장의 명령은 저장소 루트에서 `W=$PWD`를 잡아둔 상태를 전제한다. 스크립트는 이 두 줄을 두 번 돌려 순정 빌드(`out/r5`)와 DFU 빌드(`out/r5-dfu`)를
만든다. 왜 두 벌인지는 [05. DFU로 부팅시키기](05-dfu.md)에서 다룬다.

```
make -C u-boot O=$W/out/r5 ARCH=arm am62_pocketbeagle2_r5_defconfig
make -C u-boot O=$W/out/r5 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- \
     BINMAN_INDIRS=$W/ti-linux-firmware -j$(nproc)
```

`O=`와 `BINMAN_INDIRS`가 절대 경로인 것은 `make -C`가 작업 디렉터리를 u-boot 트리로
옮기기 때문이다. 상대 경로로 적으면 u-boot 트리 안에 출력이 생긴다.

`BINMAN_INDIRS`는 binman이 blob을 찾을 디렉터리다. binman은 U-Boot 빌드가 이미지를
조립할 때 쓰는 도구이고, 소스에서 나오지 않는 조각(TI 펌웨어 같은 것)을 여기서 찾는다.

산출물은 `out/r5/tiboot3-am62x-hs-fs-evm.bin`이고 `tiboot3.bin` 심링크가 같이
생긴다. 함께 만들어지는 hs-evm(HS-SE용) 이미지의 blob 누락 경고는 이 보드(HS-FS)와
무관하니 무시해도 된다.

`BINMAN_INDIRS` 없이 빌드해도 빌드는 성공한다. 대신 blob 자리를 비운 이미지가 나오고
경고에 누락 파일이 열거된다. 조용히 망가진 이미지가 나오는 경우라 경고를 읽어야 한다.

### 빌드가 멈추는 곳 두 가지

`mkeficapsule`이 gnutls 헤더를 요구한다. EFI 캡슐 서명용 호스트 툴이라 `tiboot3.bin`과
무관하므로 꺼도 된다.

```
./scripts/config --file $W/out/r5/.config --disable TOOLS_MKEFICAPSULE
```

defconfig를 다시 풀면 `.config`가 재생성되므로 그때마다 다시 적용해야 한다. 헤더
(`libgnutls28-dev`)를 설치하면 이 처리가 필요 없다.

binman의 K3 board-config 처리가 python 모듈 `yamllint`·`jsonschema`를 요구한다. binman을
실행하는 python3에 설치돼 있어야 한다. PATH 선두의 python3가 쓰이므로, venv를 쓴다면
그 venv가 활성화된 상태여야 한다.

## 4-4. A53 패스: 소스가 셋으로 늘어난다

R5 패스는 U-Boot 소스 하나로 끝났지만, A53 패스는 세
프로젝트에서 나온 조각을 모아야 한다.

```
tispl.bin (FIT)
  ├─ atf    TF-A            trusted-firmware-a 에서 빌드
  ├─ tee    OP-TEE          optee_os 에서 빌드
  ├─ dm     DM 펌웨어        ti-linux-firmware 에서 받은 blob
  ├─ spl    A53 SPL         u-boot a53 defconfig 로 빌드
  └─ fdt-0  디바이스 트리     같은 빌드
```

조각별 로드 주소는 이렇다.

| 조각 | 출처 | 로드 주소 |
| --- | --- | --- |
| atf | trusted-firmware-a | 0x80000000 |
| tee | optee_os | 0x80080000 |
| dm | ti-linux-firmware blob | 0x89000000 |
| spl | u-boot a53 defconfig | 0x82000000 |
| fdt-0 | 같은 빌드 | 조각마다 다름 |

이 주소들은 binman 이 디바이스 트리에서 읽어 FIT 에 넣는다. `atf`는
`CONFIG_K3_ATF_LOAD_ADDR`, `tee`는 `CONFIG_K3_OPTEE_LOAD_ADDR` 값이다.

`dumpimage -l`로 보면 `tee`만 로드 주소가 안 나오는데, 도구가 그 타입의 값을 출력하지
않는 것이고 FIT 에는 들어 있다. 확인하는 방법은
[06. 직접 확인해보기](06-hands-on.md)에 있다.

DM 펌웨어만 소스 빌드가 아니라 `ti-linux-firmware/ti-dm/am62xx/`의 blob이다. 이것도
없으면 빌드는 통과하고 자리만 빈 이미지가 나온다.

## 4-5. 반드시 맞춰야 하는 주소 네 개

여기서 틀리면 콘솔에 아무것도 안 나온 채 멈춘다. 증상에 단서가 없어 원인을 찾기가
어렵다.

### 문제의 구조

U-Boot, TF-A, OP-TEE는 서로 다른 저장소에서 따로 빌드된다. 그런데 서로의 로드 주소를
알아야 한다. U-Boot의 SPL이 OP-TEE를 어느 주소에 올릴지 정하면, OP-TEE 자신도 그 주소를
전제로 링크되어야 하고, TF-A도 그 주소로 점프해야 한다.

이들은 서로의 설정 파일을 읽지 않는다. 세 곳에 같은 값이 따로 적혀 있고, 각자 자기
기본값을 갖고 있다. 그 기본값은 이 보드와 다르다.

| 대상 | TF-A·OP-TEE 기본값 | 이 보드 | 출처 |
| --- | --- | --- | --- |
| BL32 (OP-TEE) | 0x9e800000 | 0x80080000 | `CONFIG_K3_OPTEE_LOAD_ADDR` |
| BL33 (A53 SPL) | 0x80080000 | 0x82000000 | `CONFIG_SPL_TEXT_BASE` |
| 콘솔 UART | 0번 | 6번 | DT의 `stdout-path = &main_uart6` |

두 주소가 서로 엇갈려 있다. 기본값으로 빌드하면 BL31이 A53 SPL을 OP-TEE
자리에서 시작하려 한다.

콘솔도 마찬가지다. 이 보드의 콘솔은 `main_uart6`(0x02860000)인데 TF-A의 `K3_USART`와
OP-TEE의 `CFG_CONSOLE_UART`는 둘 다 0번이 기본값이다. 계수가 0x10000이라 6번이 그
주소가 된다.

### 왜 빌드 인자로 넘겨야 하나

TF-A에는 앞 단계가 진입점 정보를 인자로 넘겨주는 방식도 있다. 하지만 TI 플랫폼 코드는
그 방식을 쓰지 않는다. `plat/ti/common/ti_bl31_setup.c`의
`bl31_early_platform_setup2`가 인자를 읽지 않고 컴파일 상수를 그대로 진입점에 넣는다.

```c
bl32_image_ep_info.pc = BL32_BASE;
bl33_image_ep_info.pc = PRELOADED_BL33_BASE;
```

값이 바이너리에 박히므로 빌드할 때 정해줘야 한다.

### 빌드 명령

```
make -C trusted-firmware-a CROSS_COMPILE=aarch64-linux-gnu- ARCH=aarch64 \
     PLAT=k3 SPD=opteed TARGET_BOARD=lite \
     K3_USART=6 BL32_BASE=0x80080000 PRELOADED_BL33_BASE=0x82000000

make -C optee_os CROSS_COMPILE=arm-linux-gnueabihf- CROSS_COMPILE64=aarch64-linux-gnu- \
     PLATFORM=k3-am62x CFG_ARM64_core=y CFG_WITH_SOFTWARE_PRNG=y \
     CFG_CONSOLE_UART=6 CFG_TZDRAM_START=0x80080000

make -C u-boot O=$W/out/a53 CROSS_COMPILE=aarch64-linux-gnu- \
     am62_pocketbeagle2_a53_defconfig
make -C u-boot O=$W/out/a53 CROSS_COMPILE=aarch64-linux-gnu- BINMAN_INDIRS=$W/ti-linux-firmware \
     BL31=$W/trusted-firmware-a/build/k3/lite/release/bl31.bin \
     TEE=$W/optee_os/out/arm-plat-k3/core/tee-raw.bin
```

`build-a53.sh`가 이 세 단계를 순서대로 돌린다.

TI 문서에는 `K3_USART`, `BL32_BASE`, `PRELOADED_BL33_BASE`가 나오지 않는다. 레퍼런스
보드는 기본값으로 맞기 때문이다. 보드가 다르면 문서가 아니라 그 보드의 디바이스 트리와
defconfig를 봐야 한다.

## 4-6. 부팅시키기 전에 확인하기

주소가 어긋나도 빌드는 통과한다. 그래서 `build-a53.sh`는 빌드 끝에 세 프로젝트의
산출물에서 값을 뽑아 대조하고, 어긋나면 거기서 멈춘다.

```
=== 주소 정합성 ===
  OK    u-boot OPTEE 로드          0x80080000
  OK    u-boot A53 SPL             0x82000000
  OK    TF-A BL32_BASE             0x80080000
  OK    TF-A PRELOADED_BL33_BASE   0x82000000
  OK    OP-TEE entry               0x80080000
```

뽑는 곳은 각각 U-Boot의 `.config`, TF-A 바이너리의 역어셈블 결과, OP-TEE ELF의 진입점
필드다. 직접 해보는 방법은 [06. 직접 확인해보기](06-hands-on.md)에 있다.

## 정리

- U-Boot는 벤더 포크를 쓰고, 같은 소스를 R5용과 A53용으로 두 번 빌드한다.
- A53 패스는 TF-A, OP-TEE까지 세 프로젝트의 산출물을 모아 FIT으로 묶는다.
- 세 프로젝트가 서로의 주소를 각자 하드코딩하므로 빌드 인자로 맞춰야 한다.
- 어긋나도 빌드는 통과하고 실행 시 조용히 멈춘다. 부팅 전에 값을 대조한다.
