# 05. DFU로 부팅시키기

> SD 카드를 건드리지 않고 부트로더를 시험하는 방법이다. 부트로더를 만들다 보면 실패한 이미지를 수없이 보내게 되는데, 이 방법이면 SD를 매번 다시 굽지 않아도 된다.

## 5-1. 왜 DFU인가

부트로더를 직접 만들 때 가장 큰 위험은 벽돌(brick)이다. 잘못된 이미지를 저장 장치에
쓰면 보드가 부팅 자체를 못 하고, 되살리려면 별도 수단이 필요하다.

이 보드는 그 걱정이 거의 없다. SD 카드에서 부팅에 실패하면 ROM이 USB로 넘어와 DFU
장치가 되기 때문이다. SD 카드를 뽑아두면 DFU로 온다.

DFU(Device Firmware Upgrade)는 USB 표준에 정의된 펌웨어 전송 규격이다. 보낸 이미지는
RAM에만 올라가므로 전원을 뺐다 꽂으면 흔적 없이 사라진다. 실패해도 잃을 게 없다.

## 5-2. ROM이 띄우는 DFU 장치

SD 없이 USB-C만 연결하면 호스트에 이렇게 보인다.

```
0451:6165   Texas Instruments, Inc. AM62x DFU
DFU 1.10, 전송 단위 512바이트, 인터페이스 1개에 alt 2개
  alt=0  bootloader    tiboot3.bin 전송 대상
  alt=1  SocId         200바이트 읽기 전용
```

alt setting은 하나의 USB 장치가 여러 전송 대상을 노출하는 방식이다. `-a` 옵션으로
어디에 보낼지 고른다. 여기서는 `bootloader`에 부트로더를 쓰고, `SocId`에서는 칩 정보를
읽을 수 있다. alt 1이 돌려주는 200바이트에 `am62x`와 `HSFS` 문자열이 들어 있다.

### udev 규칙이 필요하다

리눅스에서 일반 사용자가 USB 장치를 열려면 권한이 있어야 한다. `dfu-util` 패키지가
설치하는 `60-dfu-util.rules`에는 TI의 VID(0451)가 없어서 규칙을 추가해야 한다. 규칙
본문은 [00. 준비하기](00-setup.md)에 있고, 각 줄의 의미는 이렇다.

TI VID를 대상으로 하는 `uaccess` 규칙은 systemd-logind가 활성 로컬 좌석 사용자에게
POSIX ACL을 붙이게 한다. 주의할 점은 ssh로만 접속한 상태에서는 아무 권한도 부여되지
않는다는 것이다. 원격에서 작업한다면 다른 방법이 필요하다.

Debug Probe VID를 대상으로 하는 규칙 둘은 ModemManager 회피용이다. 이 프로브는
CDC-ACM 장치로 붙는데, ModemManager가 모뎀 후보로 오해하고 AT 명령을 보내면서 콘솔을
점유해버린다.

### 장치 지정은 VID:PID로

전송할 때마다 USB가 다시 열거되어 장치 번호가 바뀐다. 그래서 경로 대신 VID:PID로
지정한다.

```
dfu-util -d 0451:6165 -l
dfu-util -d 0451:6165 -a 1 -U socid.bin
dfu-util -d 0451:6165 -a 0 -D tiboot3.bin
```

전송 완료 직후 `LIBUSB_ERROR_TIMEOUT`이나 `LIBUSB_ERROR_IO`가 나는 것은 정상이다.
장치가 받은 코드로 넘어가느라 DFU 상태 질의에 답하지 않아서 그렇다.

## 5-3. 첫 관문: 다음 단계를 이어받지 못한다

순정 `tiboot3.bin`을 DFU로 보내면 SPL 배너까지는 뜨는데 거기서 멈춘다.

```
SPL: Unsupported Boot Device!
```

`get_boot_device()`는 `BOOT_DEVICE_DFU`를 제대로 반환한다. 즉
"DFU로 부팅해야 한다"는 것까지는 안다. 그런데 그 장치에서 이미지를 읽어올 로더가 이
빌드에 컴파일되어 있지 않다.

배포되는 `tiboot3.bin`은 SD 부팅용이라 DFU 로더가 빠져 있는 것이다. 앞 장에서 본
SRAM 예산 문제와 이어진다. 넣을 자리가 없다.

## 5-4. DFU 로더를 넣은 빌드

U-Boot에 `am62x_r5_usbdfu.config`라는 설정 조각(fragment)이 있다. defconfig 위에 얹어
빌드하면 DFU 로더가 들어간다.

이 fragment가 켜는 것과 끄는 것을 보면 예산 문제가 그대로 드러난다. USB 가젯 스택을
켜는 대신 `SPL_MMC`·`SPL_FS_FAT`·`SPL_SPI`·`SPL_MTD`·`TI_K3_NAVSS_UDMA`를 끈다.

**그래서 이 이미지는 SD 카드로 부팅하지 못한다.** 순정 defconfig 빌드를 따로 남겨
두어야 하는 이유가 이것이고, `build-r5.sh`가 두 벌을 만드는 이유이기도 하다.

fragment를 얹은 빌드를 전송하면 SPL이 자체 DFU 가젯을 올린다. 콘솔에 찍히는 문구가
바뀌고, 호스트에서 보이는 장치 이름과 alt도 바뀐다.

```
Unsupported Boot Device!  ->  Trying to boot from DFU
AM62x DFU                 ->  USB download gadget
alt=0 bootloader          ->  alt=0 tispl.bin
alt=1 SocId               ->  alt=1 u-boot.img
```

여기까지 오면 직접 만든 코드가 USB를 잡았다는 뜻이다. 장치 이름으로 단계를 가르는 방법은
[06. 직접 확인해보기](06-hands-on.md)에 있다.

### 코드 경로

```
get_boot_device()                      arch/arm/mach-k3/am62x/boot.c
  BACKUP_BOOT_DEVICE_DFU -> BOOT_DEVICE_DFU
    SPL_LOAD_IMAGE_METHOD("DFU", ...)  common/spl/spl_ram.c:118
      spl_ram_load_image()
        spl_dfu_cmd(0, "dfu_alt_info_ram", "ram", "0")
        -> DFU 가젯 기동, 호스트 전송 대기
        -> 받은 것을 RAM 에서 FIT 으로 파싱
```

## 5-5. 전송 주소가 맞아야 한다

앞 장의 주소 문제와 성격이 같은 문제가 한 번 더 있다.

DFU가 데이터를 쓰는 주소는 환경변수 `dfu_alt_info_ram`이 정한다. 그런데 SPL이 FIT을
읽는 주소는 `CONFIG_SPL_LOAD_FIT_ADDRESS`다. 두 값이 다른 곳에 적혀 있고, 어긋나면
전송은 성공하고 그다음 파싱에서 실패한다.

```
####DOWNLOAD ... OK
Error: -22
SPL: Unsupported Boot Device!
```

`-22`는 `-EINVAL`이다. SPL이 지정된 주소에서 FDT 매직을 못 찾아 legacy 이미지 경로로
빠지고 거기서 나오는 값이다. `DOWNLOAD ... OK`가 찍혔는데 그다음이 실패한다면 이걸
의심하면 된다.

K3 공통 설정(`k3_dfu.env`)은 `tispl.bin`을 0x80080000, `u-boot.img`를 0x81000000에
둔다. 그런데 이 보드의 R5 defconfig는 FIT을 0x82000000에서 읽는다. 맞지 않는다.

그래서 보드 환경변수에서 덮어쓴다.

```
# board/beagle/pocketbeagle2/pocketbeagle2.env
dfu_alt_info_ram=
	tispl.bin ram 0x82000000 0x200000;
	u-boot.img ram 0x82f80000 0x400000
```

`u-boot.img`의 0x82f80000은 A53 defconfig의 `CONFIG_TEXT_BASE`다.

벤더 이미지에는 이 덮어쓰기가 없다. 배포되는 `tiboot3.bin`에 DFU 로더 자체가 없어서
이 경로를 타지 않기 때문이다.

## 5-6. 전송 절차

세 이미지를 순서대로 보낸다. 성공 경로에서는 전원을 다시 넣지 않고 이어서 보낸다.

```
dfu-util -d 0451:6165 -a bootloader -D out/r5-dfu/tiboot3.bin
dfu-util -R -d 0451:6165 -a tispl.bin  -D out/a53/tispl.bin
dfu-util -R -d 0451:6165 -a u-boot.img -D out/a53/u-boot.img
```

`-R`은 전송 후 USB 리셋을 보내라는 뜻이고 2단계부터 필요하다.

각 단계에서 USB가 다시 열거되므로 다음 전송 전에 `dfu-util -l`로 alt가 바뀐 것을
확인한다. alt 이름이 아직 안 바뀌었으면 앞 단계가 실패한 것이다.

- ROM: `bootloader`, `SocId`
- R5 SPL과 A53 SPL: `tispl.bin`, `u-boot.img`

콘솔에 `### ERROR ### Please RESET the board ###`가 나오면 SPL이 포기한 것이다. 이
상태에서는 전원을 다시 넣어야 ROM으로 돌아온다.

## 5-7. 알려진 경고

가젯이 올라올 때 dwc3 경고가 하나 찍힌다. USB 열거와 전송은 정상 동작한다.

```
dwc3-am62 dwc3-usb@f900000: unable to get ti,syscon-phy-pll-refclk regmap
```

원인은 SPL용 디바이스 트리에서 참조가 끊긴 것이다. 기전은
[10. 디바이스 트리와 SPL](10-devicetree.md)에 있다.

## 5-8. 복구 경로

부트로더 교체가 실패했을 때 되살리는 방법이 셋이다.

1. **SD 카드 재삽입.** DFU로만 시험했다면 SD는 변경되지 않았으므로 카드를 꽂으면
   원래대로 부팅한다. 이게 DFU로 실험하는 가장 큰 이유다.
2. **보드에서 재설치.** `/opt/u-boot/bb-u-boot-pocketbeagle2/install-microsd.sh`를
   실행한다. 패키지가 원본 `tiboot3.bin`·`tispl.bin`·`u-boot.img`를 이 경로에 보관한다.
3. **SD 재굽기.** `~/Downloads/pb2-images/`의 이미지로 다시 굽는다. `sysconf.txt`
   재설정과 ssh 키 재등록이 뒤따른다.

## 5-9. 콘솔 인자

케이블 연결은 [00. 준비하기](00-setup.md)에 있다. 커널까지 올라간 뒤 쓰이는 인자는
이렇다.

```
console=ttyS2,115200n8  earlycon=ns16550a,mmio32,0x02860000
```

베어메탈 코드에서 이 UART를 직접 쓸 경우 NS16550 호환에 레지스터 간격 4바이트다.

## 정리

- SD를 뽑으면 ROM이 DFU로 넘어온다. 보낸 이미지는 RAM에만 올라가므로 실패해도 안전하다.
- 배포되는 `tiboot3.bin`에는 DFU 로더가 없어서 다음 단계를 이어받지 못한다.
  `am62x_r5_usbdfu.config`를 얹어 빌드해야 한다.
- 그 fragment는 스토리지 지원을 끄므로 SD 부팅용 빌드를 따로 남겨야 한다.
- DFU가 쓰는 주소와 SPL이 읽는 주소가 맞아야 한다. 어긋나면 `Error: -22`가 난다.
