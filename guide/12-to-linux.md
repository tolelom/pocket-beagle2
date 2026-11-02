# 12. U-Boot에서 리눅스까지

> U-Boot 본체가 커널을 찾아 올리고 넘기는 과정, 그리고 어느 구간에 시간이 얼마나 드는지 본다.

## 12-1. SPL과 본체는 급이 다르다

같은 U-Boot인데 SPL과 본체는 규모가 다르다. 부팅 로그의 첫 줄들이 그것을 보여준다.

```
U-Boot 2026.01-gef03e3548837 (Feb 10 2026 - 19:33:29 +0000)

SoC:   AM62X SR1.0 HS-FS
Reset reason: POR
Model: BeagleBoard.org PocketBeagle2
DRAM:  512 MiB
Core:  89 devices, 32 uclasses, devicetree: separate
```

`89 devices, 32 uclasses`를 보면 규모 차이가 드러난다. SPL은
[10. 디바이스 트리와 SPL](10-devicetree.md)에서 본 대로 노드 64개짜리 DT로 도는데,
본체는 훨씬 많은 장치를 잡는다. DRAM 위에서 돌아 SRAM 크기 제약을 받지 않는다.

`Reset reason: POR`은 전원을 새로 넣은 부팅(Power On Reset)이라는 뜻이다. 소프트웨어
재부팅이면 `RST`로 찍힌다. 판별은 `arch/arm/mach-k3/am62x/boot.c`의 `get_reset_reason()`이
`CTRLMMR_MCU_RST_SRC`를 읽어서 한다.

## 12-2. 부팅 대상을 찾는다

U-Boot 본체는 어디서 커널을 가져올지 스스로 찾는다. `bootflow`라고 부르는 구조다.

```
Scanning for bootflows in all bootdevs
Seq  Method       State   Uclass    Part  Name                      Filename
---  -----------  ------  --------  ----  ------------------------  ----------------
Scanning bootdev 'mmc@fa00000.bootdev':
  0  extlinux     ready   mmc          1  mmc@fa00000.bootdev.part_ /extlinux/extlinux.conf
```

부팅 장치 후보를 순서대로 훑으면서 각각에 대해 알려진 부팅 방식을 시도한다. 여기서는
MMC의 첫 파티션에서 `/extlinux/extlinux.conf`를 찾아 성공했다.

SD 카드를 뽑은 채 U-Boot 셸에 들어가면 이 스캔이 실패하는 모습을 볼 수 있다.

```
Scanning bootdev 'mmc@fa10000.bootdev':
Card did not respond to voltage select! : -110
...
No more bootdevs
---  -----------  ------  --------  ----  ------------------------  ----------------
(0 bootflows, 0 valid)
```

카드가 없으니 후보가 하나도 안 나온 것이다.

## 12-3. extlinux.conf

`extlinux`는 부팅 항목을 텍스트로 적어두는 방식이다. Syslinux 계열 부트로더의 설정
형식이고 U-Boot가 같은 형식을 읽는다.

이 보드의 이미지에는 이런 항목이 들어 있다.

```
PocketBeagle 2 microSD (extlinux.conf) (swap enabled)
1:	microSD (failsafe)
2:	copy microSD to eMMC
3:	microSD (debug)
4:	microSD (default)
5:	techlab
6:	techlab workshop
Enter choice: 4:	microSD (default)
```

기본값이 4번이고 입력이 없으면 그대로 간다. 커널을 못 올리는 상황을 대비한 failsafe
항목이 따로 있다.

## 12-4. 커널에 무엇을 넘기나

선택된 항목이 지시하는 대로 파일 둘을 읽고 인자를 만든다.

```
Retrieving file: /Image.gz
append: console=ttyS2,115200n8 earlycon=ns16550a,mmio32,0x02860000
        root=/dev/mmcblk1p3 ro rootfstype=ext4 fsck.repair=yes
        resume=/dev/mmcblk1p2 rootwait net.ifnames=0
Retrieving file: /ti/k3-am62-pocketbeagle2.dtb
   Uncompressing Kernel Image to 0
## Flattened Device Tree blob at 88000000
   Booting using the fdt blob at 0x88000000
Working FDT set to 88000000
   Loading Device Tree to 0000000098ecd000, end 0000000098ee107d ... OK
```

넘기는 것이 셋이다.

**커널 이미지.** `Image.gz`는 압축된 것이고 U-Boot가 풀어서 올린다.

**커맨드 라인.** `console=`이 콘솔 장치를, `root=`가 루트 파일시스템 파티션을 지정한다.
`earlycon=`은 커널이 정식 콘솔 드라이버를 올리기 전에 쓸 임시 출력이고, 주소
0x02860000이 [04. 소스 받기와 빌드](04-building.md)에서 본 `main_uart6`다.

**디바이스 트리.** 리눅스용 전체 DT다. 0x88000000에 읽어 들였다가 DRAM 위쪽
(0x98ecd000)으로 옮긴다. 커널이 자기 아래쪽 메모리를 자유롭게 쓰게 비켜주는 것이다.

`Working FDT set to 98ecd000`이 그 결과다.

## 12-5. 부팅 시간은 어디에 드나

로그의 대괄호 숫자가 커널이 시작한 뒤로 흐른 초다. 이 보드의 정상 부팅을 재보면 이렇다.

```
[    0.000000]   커널 시작
[    3.044654]   Run /sbin/init          커널 구간 끝
[    3.465344]   systemd 배너
[   18.519803]   로그인 프롬프트 직전    유저스페이스 구간 끝
```

커널이 3초, 유저스페이스가 15초다.

무엇이 시간을 쓰는지는 로그에 그대로 나온다. IoT 최소판이라는 이미지인데
nginx, ssh, containerd, docker가 순서대로 올라온다.

### 부트로더 구간은 이 방법으로 못 잰다

앞 단계에는 타임스탬프가 없다. 커널이 `[0.000000]`부터 세기 시작하므로 그 이전에 얼마나
걸렸는지는 이 로그에 남지 않는다.

부트로더 구간을 재려면 다른 수단이 필요하다. 로그 캡처에 호스트 시각을 함께 찍거나,
SPL에 타이머 값을 출력하는 코드를 넣는 식이다.

## 12-6. 정상 부팅에도 나오는 오류들

이 보드에서는 아래 오류가 정상 부팅에도 나온다.

| 메시지 | 뜻 |
| --- | --- |
| `remoteproc remoteproc0: Direct firmware load for am62-mcu-m4f0_0-fw failed with error -2` | [11. 코어 사이의 대화](11-tisci.md)에서 다룬 그 오류 |

systemd 유닛이 전부 올라오고 FAILED가 0이면 정상이다.

## 12-7. 첫 부팅은 다르다

이미지를 처음 구워 부팅하면 한 번 더 재부팅한다.

```
[   15.550698] bbbio-set-sysconf[590]: Rebooting after setting up sysconf.txt options
```

`sysconf.txt`에 적어둔 설정(사용자 이름, ssh 키 같은 것)을 적용하고 파일시스템을 카드
크기에 맞춰 늘린 뒤 재부팅한다. 첫 부팅 로그를 보면 이 재부팅이 두 번 있다. 첫
사이클에서 호스트명·키맵·시간대를 잡고, 두 번째에서 파일시스템을 늘린다. 비밀번호
항목은 지워진 채 파일이 다시 만들어진다.

그래서 첫 부팅 로그와 이후 로그는 내용이 다르다. 위의 부팅 시간도 두 번째 부팅에서
잰 값이다.

## 정리

- U-Boot 본체는 SPL과 달리 장치를 89개 잡는다. SRAM 크기 제약을 받지 않는다.
- 부팅 대상은 `bootflow` 스캔으로 찾고, 이 보드는 MMC의 `extlinux.conf`로 간다.
- 커널에 넘기는 것은 이미지, 커맨드 라인, 디바이스 트리 셋이다.
- 커널 3초, 유저스페이스 15초다.
- 부트로더 구간은 커널 타임스탬프로 잴 수 없다.
