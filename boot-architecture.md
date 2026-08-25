# 부트 구조와 코어 구성

> PocketBeagle 2 Rev A1(AM6254)의 코어 배치, 전원 인가부터 리눅스까지의 부트 체인, 부트 이미지 구성, 그리고 어느 지점부터 직접 만든 코드로 대체할 수 있는지를 다룬다.

## 코어 구성

SoC 안에 명령어를 실행하는 코어가 10개, 셰이더 가속기까지 11개다. 보드에는 SoC 밖에
MCU가 하나 더 있다.

<!-- colwidth: 70 190 50 110 340 -->
| 위치 | 코어 | 수 | ISA | 용도 |
|---|---|---|---|---|
| MAIN | Cortex-A53 (A53SS) | 4 | Armv8-A | 리눅스. L1 32KB+32KB 코어별, L2 512KB 공유 |
| MAIN | PRU0, PRU1 (PRUSS/ICSSM0) | 2 | TI PRU | 사이클 정확 I/O |
| MAIN | 3D GPU (AXE1-16C) | 1 | 셰이더 | OpenGL ES 3.1, Vulkan 1.2 |
| MCU | Cortex-M4F (MCU_M4FSS0) | 1 | Armv7-M | 안전 MCU 또는 범용 MCU. I-Code 192KB, D-Code 64KB |
| Boot/DM | Cortex-R5F (WKUP_R5FSS0) | 1 | Armv7-R | Public ROM → SPL → Device Manager 펌웨어 |
| SMS | M4F (TIFS) | 1 | Armv7-M | 부트 컨트롤러. TIFS 펌웨어 |
| SMS | M4F (HSM) | 1 | Armv7-M | Hardware Security Module |
| 보드 | MSPM0L1105 | 1 | Armv6-M | I2C0. ADC·EEPROM |

SMS(Security Management Subsystem)의 M4F 둘은 TI 전용이다. 이 블록에는 SECMGR SEC ROM,
AES·SHA·PKA·DRBG·TRNG, SA3_UL, 426KB SRAM이 함께 들어 있다. TIFS 코드가 276KB를 넘으면
HSM의 I/D RAM을 빌려 쓰도록 주소 앨리어싱이 걸려 있다.

`MCU_M4FSS0`은 부트에 관여하지 않는다. 부팅 중 다른 코어가 설정하고 리셋을 풀어주면
그때부터 사용자 코드를 실행한다. 리눅스에서는 펌웨어 파일이 없어 `offline`으로 보인다.

DSP는 없다. AM62A의 C7x는 이 칩에 들어 있지 않다.

### AM62x에 ADC가 없다

TRM과 데이터시트의 ADC 언급은 전부 외부 ADC를 가리킨다. PRU가 외부 ADC를 구동하거나
EPWM이 외부 ADC 변환을 트리거하는 문맥이고, SoC 모듈 목록에 ADC 모듈 자체가 없다.

그래서 보드가 `MSPM0L1105`를 I2C0에 달아 아날로그 입력을 제공한다. 이 칩은 Cortex-M0+에
flash 32KB, SRAM 4KB, 12비트 1.68Msps ADC 1개를 갖는다.

- 8채널 12비트 ADC: 실리콘 ADC를 펌웨어가 I2C 슬레이브로 포장해 내보낸다.
- 4KB EEPROM: 칩에 EEPROM 페리페럴이 없다. 펌웨어가 flash 위에 구현한다.

SPL이 이 EEPROM을 읽어 보드 모델과 RAM 용량을 판별한다.

## 부트 체인

```
전원 램프업
  |
  +- SMS M4F(TIFS): RTI 워치독 180초 설정
  |                 PLLCTRL 설정, MCU PLL 락
  |                 부트 모드별 기본 방화벽 설정
  |                 Secure Proxy / Ring Accelerator 설정
  |                 R5에게 부트 모드 정보 전달
  |                 R5 CPU0 리셋 해제
  |
  +- R5 Public ROM: BOOTMODE 스트랩 확인 후 부팅 장치 초기화
  |                 이미지 수신, 형식 1차 검사, M4로 전달
  |
  +- SMS M4F(TIFS): X.509 파싱, SA2UL SHA512로 무결성 검증
  |                 통과 시 R5 리셋 → 부트벡터를 새 이미지로 → 리셋 해제
  |                 (Public ROM은 완전히 분리된다)
  |
  +- R5: tiboot3.bin의 SPL 실행                 [SPL 배너 1회차]
  |      DDR 초기화, tispl.bin 로드              [Authentication passed x5]
  |
  +- A53: TF-A BL31 v2.14.1 (EL3)
  |       OP-TEE 4.9.0 (S-EL1), 초기화 후 콘솔 닫음
  |       A53 SPL                               [SPL 배너 2회차]
  |       u-boot.img 로드                        [Authentication passed x2]
  |
  +- U-Boot 2026.01: extlinux.conf 해석
  |
  +- 리눅스 → 데비안
```

A53은 이 흐름의 중반까지 꺼져 있다. R5 SPL이 DDR을 세우고 tispl.bin을 올린 뒤에야
전원이 들어온다. R5는 두 번 시작한다. 한 번은 Public ROM으로, 그다음 리셋되고
tiboot3.bin의 SPL로 다시 시작한다.

`Authentication passed`가 부팅당 7회 찍히는 것은 tispl.bin의 조각 5개와 u-boot.img의
조각 2개를 각각 검증하기 때문이다.

SPL 배너가 2회 찍히는 것은 R5용과 A53용을 별도 defconfig로 두 번 빌드하기 때문이다.
스택 사용량도 13416바이트와 2048바이트로 다르게 찍힌다.

### 첫 단계는 온칩 SRAM에 들어가야 한다

ROM이 이미지를 적재하는 시점에 DDR이 아직 초기화되지 않았다. U-Boot가 SPL과 본체로
나뉘어 있고 SPL의 첫 임무 중 하나가 DDR 초기화인 이유가 이것이다.

### ROM이 이미지를 받는 세 경로

| 경로 | 해당 부트 모드 | 방식 |
|---|---|---|
| Image | OSPI, QSPI, SPI, xSPI | R5와 M4가 플래시에서 직접 읽는다. OSPI·QSPI·SPI는 온칩 RAM에 복사한 뒤 실행한다 |
| Block | I2C, USB DFU, UART, eMMC, Ethernet, SD raw | 블록 단위 수신 후 X.509 헤더가 차면 M4로 전달 |
| Filesystem | USB MSC, SD·eMMC 파일시스템 | Block과 동일하되 위치를 파일시스템이 정한다 |

## 부트 이미지 3종

BOOT 파티션의 파일 세 개가 부트 체인의 물리적 실체다.

| 파일 | 크기 | 내용 |
|---|---|---|
| `tiboot3.bin` | 282,506 | R5 SPL + R5 DT(`k3-am62-r5-pocketbeagle2`) + `tifsstub-fs/gp/hs` + `dm-tifs` |
| `tispl.bin` | 946,403 | `atf`(→0x80000000), `tee`, `dm`(→0x89000000), `spl`(→0x82000000), `fdt-0` |
| `u-boot.img` | 895,831 | `uboot`(→0x82f80000), `fdt-0` |

`tispl.bin`과 `u-boot.img`는 FIT 컨테이너이고 `mkimage -l`로 구성을 볼 수 있다.
FIT 수준 해시는 crc32지만, 각 조각의 데이터 앞에는 X.509 인증서가 개별로 붙는다.

## 서명

```
키:   arch/arm/mach-k3/keys/custMpk.pem   (U-Boot 트리, 개인키 평문 포함)
지문: 00acfeb4d70d02eeabb36d01690d2b450f471ad40f7fde5f8247673567ddc0b0
```

보드의 `tiboot3.bin` 인증서 공개키와 이 키의 공개키 지문이 일치한다. 4096비트 RSA,
공개 지수 65537, sha512WithRSAEncryption, 발급자와 주체가 모두
`Texas Instruments Incorporated / TI Support / support@ti.com`인 자체 서명 인증서다.

U-Boot를 기본 설정으로 빌드하면 binman이 이 키로 서명한다. 별도의 키 확보나 서명 절차가
필요 없다.

장치 타입은 HS-FS다. TI 개발 키로 서명한 이미지가 통과하는 것은 관측된 사실이다.
그 조건이 eFuse의 고객 키 해시 상태라는 것과 HS-SE 전환의 되돌릴 수 없음은 공개 TRM
5장에 해당 서술이 없다.

보드의 인증서는 `notAfter`가 2026-03-12인데 그 이후에도 정상 부팅한다. ROM이 유효기간을
검사하지 않는다는 결론은 이 관측에서 나온 추론이다. TRM 5.7.2는 ROM이 X.509 구조에서
인증서 총 크기와 부트 이미지 총 크기를 뽑아 쓴다고만 서술한다.

## 부트 모드 결정

판정은 ROM이 하고, 무엇을 시도할지는 보드의 스트랩 저항이 정한다.

```
BOOTMODE[15:0] 핀 (풀업·풀다운 저항, USER 버튼)
      | MCU_PORz 해제 시 하드웨어가 래치
      v
CTRLMMR_MAIN_DEVSTAT   0x43000030  (WKUP_CTRL_MMR0_BASE 0x43000000 + 0x30)
      [2:0]   시스템 클럭 주파수 (PLL 설정용)
      [6:3]   primary 부트 모드
      [9:7]   primary 부가 설정
      [12:10] backup 부트 모드
      [13]    backup 부가 설정
      [15:14] 예약
      |
      v
ROM: primary 시도 → 실패 시 backup 시도
     선택 결과를 OCRAM 0x7000F290에 기록
      |
      v
SPL의 get_boot_device(): DEVSTAT와 OCRAM 값을 읽어 해석만 한다
```

`0x7000F290`은 U-Boot 헤더의 `K3_BOOT_PARAM_TABLE_INDEX_OCRAM` 값이고 SPL이 실제로 읽는
주소다. TRM Table 5-65는 같은 항목(Parameter tables index for R5 bootloader)을
`0x43c3f290`으로 적어 두 출처가 갈린다. 어느 쪽을 ROM이 쓰는지는 확정되지 않았다.

예약 핀을 포함해 모든 BOOTMODE 신호는 VDDSHV3로 풀업하거나 접지로 풀다운해야 하며
플로팅으로 두면 안 된다.

### 인코딩

primary(4비트)와 backup(3비트)이 서로 다른 번호 체계를 쓴다. backup 필드는 3비트라
0에서 7까지만 표현된다.

```
primary                        backup
0x01 OSPI                      0x01 DFU
0x02 QSPI                      0x03 UART
0x03 SPI                       0x04 Ethernet
0x04 Ethernet RGMII            0x05 MMC
0x05 Ethernet RMII             0x06 SPI
0x06 I2C                       0x07 I2C
0x07 UART
0x08 MMCSD (SD 카드 또는 eMMC UDA)
0x09 eMMC (boot 파티션)
0x0A USB (설정 비트로 DFU 장치 모드와 USB 호스트 MSC 모드를 구분)
0x0B GPMC NAND
0x0C GPMC NOR
0x0E xSPI
0x0F NOBOOT
```

부가 설정 필드가 세부를 정한다. MMCSD는 포트(MMC1·MMC2)와 파일시스템·RAW 여부를,
USB는 DFU 장치 모드인지 호스트 MSC 모드인지를 고른다.

### 이 보드에서 쓸 수 있는 것

| 방법 | 조건 | 프로토콜 |
|---|---|---|
| microSD | 카드 삽입 | primary |
| USB DFU | SD 없음 | backup |
| UART | SD 없음 + USER 버튼을 누른 채 전원 인가 | XMODEM |

SoC는 OSPI·QSPI·SPI·xSPI·Ethernet·I2C·eMMC·GPMC도 지원하지만 보드에 해당 부품이 없다.
SRM 3.6.1은 eMMC를 풋프린트만 있고 미실장으로 적는다. 이더넷 PHY와 부트용 플래시도
실리지 않았다. USB 호스트 MSC는 포트가 있어 부품 문제는 아니다.

스트랩이 primary를 MMC로, backup을 DFU로 지정하고 USB 호스트 MSC를 고르지 않는다는 것은
SRM 서술과 관측된 동작에서 얻은 추론이다. `0x43000030`을 직접 읽어 확정한 값은 아니다.

## 수정 가능 경계

```
     저항·USER 버튼        하드웨어 변경으로만
     마스크 ROM            대체 불가
------------------------------------------------ 실리콘에 고정
     SMS의 TIFS·HSM 펌웨어  TI 바이너리
     tifsstub-*, dm-tifs   ti-linux-firmware의 TI 바이너리
------------------------------------------------ TI 영역
     tiboot3.bin           R5 SPL, R5 DT
     tispl.bin             TF-A, OP-TEE, DM, A53 SPL
     u-boot.img
     커널·유저스페이스
------------------------------------------------ 소스 빌드 가능
```

직접 만든 코드로 채울 수 있는 최상단은 `tiboot3.bin` 안의 R5 SPL이다.

## 소스 트리

```
저장소:    beagleboard/u-boot
브랜치:    v2026.01-am62-pocketbeagle2
커밋:      ef03e35488377a32cdd4f76d1a03ef7f60c798ef
defconfig: am62_pocketbeagle2_r5_defconfig
           am62_pocketbeagle2_a53_defconfig
```

보드에 설치된 `bb-u-boot-pocketbeagle2` 패키지의 U-Boot 버전 문자열
`2026.01-gef03e3548837`이 이 커밋과 일치한다.

메인라인 U-Boot에는 `k3-am62-pocketbeagle2.dts`가 `dts/upstream/src/arm64/ti/`에 있다.
defconfig는 없다.

패키지가 참조하는 상위 버전은 U-Boot v2026.01, ti-linux-firmware 11.02.11,
OP-TEE 4.9.0, TF-A lts-v2.14.1이다.

K3는 2패스 빌드다. R5 패스가 `tiboot3.bin`을, A53 패스가 `tispl.bin`과 `u-boot.img`를
만든다.

R5 패스가 요구하는 외부 blob은 ti-linux-firmware의
`ti-sysfw/ti-fs-firmware-am62x-hs-fs-enc.bin`(TIFS 펌웨어)과
`ti-fs-firmware-am62x-hs-fs-cert.bin`(inner cert) 2개다. TF-A·OP-TEE는 A53 패스의
재료라 `tiboot3.bin`만 빌드할 때는 필요 없다.

## R5 패스 빌드

소스는 `u-boot/`, blob 2개는 `ti-linux-firmware/ti-sysfw/`에 있다. ti-linux-firmware
저장소 전체는 필요 없다.

```
cd u-boot
make ARCH=arm O=build-r5 am62_pocketbeagle2_r5_defconfig
make ARCH=arm O=build-r5 CROSS_COMPILE=arm-none-eabi- \
     BINMAN_INDIRS=$HOME/Desktop/develop/pocketbeagle/ti-linux-firmware -j$(nproc)
```

SPL은 freestanding이라 bare-metal 툴체인(arm-none-eabi-gcc 13)으로 빌드된다.
산출물은 `build-r5/tiboot3-am62x-hs-fs-evm.bin`이고 `tiboot3.bin` 심링크가 같이
생긴다. 함께 만들어지는 hs-evm(HS-SE용) 이미지의 blob 누락 경고는 이 보드(HS-FS)와
무관하다. BINMAN_INDIRS 없이 빌드하면 blob 자리를 비운 이미지가 나오고 경고에
누락 파일이 열거된다.

빌드가 멈추는 곳 두 가지.

- `mkeficapsule`이 gnutls 헤더를 요구한다. EFI 캡슐 서명용 호스트 툴이라
  `tiboot3.bin`과 무관하므로 끈다:
  `./scripts/config --file build-r5/.config --disable TOOLS_MKEFICAPSULE`.
  defconfig를 다시 풀면 `.config`가 재생성되므로 그때마다 다시 적용한다.
  gnutls 헤더(libgnutls28-dev)를 설치하면 이 처리가 필요 없다.
- binman의 K3 board-config 처리가 python 모듈 `yamllint`·`jsonschema`를 요구한다.
  binman을 실행하는 python3(PATH 선두의 것)에 설치돼 있어야 한다.

## USB DFU 경로

SD 카드가 없으면 ROM이 DFU로 넘어간다. SD를 건드리지 않고 부트로더를 시험할 수 있다.

```
0451:6165   Texas Instruments, Inc. AM62x DFU
DFU 1.10, 전송 단위 512바이트, 인터페이스 1개에 alt 2개
  alt=0  bootloader    tiboot3.bin 전송 대상
  alt=1  SocId         200바이트 읽기 전용
```

alt 1이 돌려주는 200바이트에 `am62x`와 `HSFS` 문자열이 들어 있다.

호스트에서 `dfu-util`이 장치를 열려면 udev 규칙이 필요하다. `dfu-util` 패키지가 설치하는
`60-dfu-util.rules`에는 TI VID(0451)가 없다.

```
# /etc/udev/rules.d/70-pocketbeagle2.rules
SUBSYSTEM=="usb", ATTR{idVendor}=="0451", ATTR{idProduct}=="6165", TAG+="uaccess"

ACTION=="add|change", SUBSYSTEM=="usb", ATTRS{idVendor}=="2e8a", ATTRS{idProduct}=="000c", ENV{ID_MM_DEVICE_IGNORE}="1"
ACTION=="add|change", SUBSYSTEM=="tty", ATTRS{idVendor}=="2e8a", ATTRS{idProduct}=="000c", ENV{ID_MM_DEVICE_IGNORE}="1"
```

`uaccess` 태그는 systemd-logind가 활성 로컬 좌석 사용자에게 POSIX ACL을 붙이도록 한다.
ssh로만 접속한 상태에서는 아무 권한도 부여되지 않는다.

두 번째와 세 번째 줄은 Raspberry Pi Debug Probe 대상이다. cdc_acm으로 붙는 CDC-ACM
장치라 ModemManager가 모뎀 후보(`ID_MM_CANDIDATE=1`)로 잡고 AT 명령을 보내면서 콘솔을
점유한다.

장치 번호는 재열거하면 바뀌므로 경로 대신 VID:PID로 지정한다.

```
dfu-util -d 0451:6165 -l
dfu-util -d 0451:6165 -a 1 -U socid.bin
dfu-util -d 0451:6165 -a 0 -D tiboot3.bin
```

전송 완료 직후 `LIBUSB_ERROR_TIMEOUT`이 나는 것은 장치가 로드한 코드로 넘어가 DFU 상태
응답을 하지 않기 때문이다.

순정 `tiboot3.bin`을 이 경로로 전송하면 콘솔에 SPL 배너가 뜬 뒤
`SPL: Unsupported Boot Device!`에서 멈춘다. `get_boot_device()`가 `BOOT_DEVICE_DFU`를
반환하는데 이 빌드에 DFU 로더가 컴파일돼 있지 않기 때문이다. `am62x_r5_usbdfu.config`를
얹어 빌드하면 다음 단계도 DFU로 이어받는다.

DFU 경로로 부팅하면 SD 부팅에는 나오지 않는 EEPROM 읽기 실패가 찍힌다.

```
EEPROM not available at 0x50, trying to read at 0x51
Reading on-board EEPROM at 0x51 failed -121
```

`-121`은 I2C NACK다. 부팅은 계속 진행된다. 원인은 확인되지 않았다.

## 복구

부트로더 교체가 실패했을 때의 복구 경로는 셋이다.

1. SD 카드 재삽입. DFU로만 시험했다면 SD는 변경되지 않는다.
2. 보드의 `/opt/u-boot/bb-u-boot-pocketbeagle2/install-microsd.sh` 실행. 패키지가
   원본 `tiboot3.bin`·`tispl.bin`·`u-boot.img`를 이 경로에 보관한다.
3. `~/Downloads/pb2-images/`의 이미지로 SD 재굽기. `sysconf.txt` 재설정과 ssh 키
   재등록이 뒤따른다.

## 콘솔

부팅 과정을 보려면 USB-C 전원과 디버그 프로브 U 포트가 둘 다 연결돼 있어야 한다.
프로브의 U 포트는 TX·RX·GND 3선뿐이라 전원을 공급하지 않는다.

```
호스트   /dev/ttyACM0   115200 8N1
커널     console=ttyS2,115200n8  earlycon=ns16550a,mmio32,0x02860000
```

베어메탈 코드에서 이 UART를 직접 쓸 경우 NS16550 호환에 레지스터 간격 4바이트다.
