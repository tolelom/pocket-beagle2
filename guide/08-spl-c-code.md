# 08. SPL의 C 구간

> 어셈블리가 판을 깔고 나면 C 코드가 시작된다. DDR을 켜고 다음 단계를 불러오는 실제 작업이 여기서 일어난다. 콘솔에 찍히는 줄과 코드가 어떻게 대응하는지 나란히 놓고 본다.

앞 장([07. SPL 코드 읽기](07-spl-code.md))이 `board_init_f`에 닿기까지였다면 이 장은
그다음이다.

## 8-1. 콘솔 로그와 코드를 나란히 놓기

부팅 로그를 처음 보면 무슨 순서로 뭐가 일어나는지 감이 안 온다. `board_init_f`
본문과 나란히 놓으면 한 줄씩 대응된다.

```
board_init_f()                          콘솔
  setup_k3_mpu_regions()                (조용함, 콘솔이 아직 없다)
  store_boot_info_from_rom()
  ctrl_mmr_unlock()
  spl_early_init()
  serial 0·3 핀먹스
  preloader_console_init()              여기부터 printf 가 보인다
  배너 출력                              U-Boot SPL 2026.01-...
  do_board_detect()                     EEPROM ... failed -121   (3회)
  k3_sysfw_loader()
  clk 초기화
  k3_sysfw_print_ver()                  SYSFW ABI: 4.0 (...)
  remove_fwl_region()
  ESM 초기화
  uclass_get_device(UCLASS_RAM, 0)      DDR 초기화가 여기서 일어난다
  spl_enable_cache()                    EEPROM ... failed -121   (2회)
  fixup_a53_cpu_freq_by_speed_grade()   Changed A53 CPU frequency to ...
crt0.S
  spl_relocate_stack_gd()               SPL initial stack usage: ...
board_init_r()                          Trying to boot from DFU
jump_to_image()                         Starting ATF on ARM64 core...
```

이 보드 소스에는 배너와 `>>> tolelom log 2: DDR is up` 두 줄이 직접 추가되어 있다.
위 표에서는 뺐다. `DDR is up`은 `uclass_get_device(UCLASS_RAM, 0)` 바로 뒤에
찍힌다.

이 대응을 알면 부팅이 멈췄을 때 어디까지 갔는지 바로 짚을 수 있다. 예를 들어 배너가
안 뜨면 `preloader_console_init()` 전에 죽은 것이고, `SYSFW ABI`가 안 나오면 TIFS
로딩에서 막힌 것이다.

## 8-2. 콘솔이 늦게 켜지는 이유

`board_init_f`의 앞부분은 조용하다. 콘솔을 쓰려면 UART가 초기화되어 있어야 하고, UART를
초기화하려면 디바이스 트리를 읽어 어느 UART인지 알아야 하고, 디바이스 트리를 읽으려면
드라이버 모델이 서 있어야 하기 때문이다.

그 준비를 하는 것이 `spl_early_init()`이고, 그다음 UART 핀먹스를 잡고,
`preloader_console_init()`이 콘솔을 연다.

이 구간에서 문제가 생기면 아무 메시지 없이 멈춘다. 진단 수단이 없는 구간이라
[06. 직접 확인해보기](06-hands-on.md)의 정적 검증이 중요하다.

## 8-3. EEPROM 읽기가 두 번 나오는 이유

로그를 보면 EEPROM 실패 메시지가 앞에 3회, DDR 초기화 뒤에 2회 나온다. 서로 다른
함수가 부르기 때문이다.

앞의 셋은 `do_board_detect()`다. 이름은 보드 판별인데 본문이 하는 일은 다르다.

```c
dram_init();
dram_init_banksize();
...
fdt_fixup_memory_banks(fdt, start, size, CONFIG_NR_DRAM_BANKS);
return update_ddrss_timings();
```

RAM 크기를 확정하고, 디바이스 트리의 메모리 노드를 그 값으로 고치고, DDR 타이밍을
갱신한다. 이 안에서 EEPROM을 읽는 함수가 여러 번 불려 메시지가 셋 나온다.

뒤의 둘은 `spl_enable_cache()` 안에서 나온다. 캐시를 켜는 함수 안에서 `dram_init()`을 부르기 때문에 EEPROM을 읽게
된다.

```c
void spl_enable_cache(void)
{
    gd->ram_top = CFG_SYS_SDRAM_BASE;
    dram_init();
    dram_init_banksize();
    ...
    enable_caches();
}
```

캐시를 켜려면 페이지 테이블을 만들어야 하고, 페이지 테이블을 만들려면 RAM이 어디부터
어디까지인지 알아야 한다. 그래서 RAM 크기를 먼저 확정한다.

## 8-4. RAM 크기는 EEPROM으로 정한다

`dram_init()`은 보드 코드에 있고(`board/beagle/pocketbeagle2/pocketbeagle2.c`), 하는
일이 이렇다.

```c
ram_size = pocketbeagle2_get_am62_ddr_size_default();
switch (ram_size) {
case EEPROM_RAM_SIZE_1GB:
    gd->ram_size = 0x40000000;
    break;
default:
    gd->ram_size = 0x20000000;
}
```

`pocketbeagle2_get_am62_ddr_size_default()`는 EEPROM에서 보드 이름 문자열을 읽어
모델을 가린다. 소스 주석에 적힌 모델이 셋이다.

```
POCKETBEAGL2A00   am6232  512MB
POCKETBEAGL2A10   am625   512MB
POCKETBEAGL2A1I   am625   1GB
```

이름 12번째 자리부터 `2A1I`면 1GB, 아니면 512MB다.

**EEPROM 실패와 이어지는 지점이다.** 읽기가 실패하면 함수가 기본값을 돌려주고 RAM은
512MB로 잡힌다. 이 보드에서 실제로 그렇게 되고 있다.

이 보드에서는 맞는 값이다. DDR 타이밍 파일 헤더가 `Density: 4Gb`, `Number of Ranks: 1`로
적혀 있어 512MB가 맞고, `bdinfo` 보고와도 일치한다.

## 8-5. DDR은 드라이버 모델이 켠다

`board_init_f` 안에서 DDR 초기화는 한 줄이다.

```c
if (IS_ENABLED(CONFIG_K3_AM64_DDRSS)) {
    ret = uclass_get_device(UCLASS_RAM, 0, &dev);
    if (ret)
        panic("DRAM init failed: %d\n", ret);
}
```

`uclass_get_device`는 "이 종류의 장치를 가져와라"는 뜻이고, 아직 프로브되지 않았으면
그 자리에서 프로브한다. 즉 이 한 줄이 DDR 드라이버의 `probe` 함수를 부른다.

드라이버는 `drivers/ram/k3-ddrss/k3-ddrss.c`이고 디바이스 트리의 `compatible` 값으로
연결된다. AM62x는 `ti,am64-ddrss`를 쓴다.

실패하면 `panic()`이라 그 자리에서 멈춘다.

### 타이밍 값은 도구가 만든다

DDR 컨트롤러를 초기화하려면 수백 개의 레지스터 값이 필요하다. 메모리 칩의 타이밍
특성과 보드 배선에 따라 달라지는 값이라 손으로 쓸 수 없다.

TI가 제공하는 도구가 만들어준다. 이 보드의 파일 헤더에 그 흔적이 남아 있다.

```
This file was generated with the
AM623/AM625 SysConfig DDR Configuration Tool ... v0.10.32
DDR Type: DDR4
Frequency = 800MHz (1600MTs)
```

`arch/arm/dts/k3-am62-pocketbeagle2-ddr4-1600MTs.dtsi`는 대부분이 레지스터 값
목록이다. 보드를 새로 포팅할 때 이 파일을 직접 쓰는 것이 아니라 도구에
메모리 사양을 넣어 뽑는다.

## 8-6. board_init_r: 다음 단계로 넘기기

`board_init_f`가 돌아오면 `crt0.S`가 스택과 global data를 DDR로 옮기고
`board_init_r`로 넘긴다. 여기부터가 "다음 단계를 불러오는" 구간이다.

`common/spl/spl.c`에 있고 흐름이 이렇다.

```
spl_board_init()
board_boot_order(spl_boot_list)          부팅 장치 순서를 정한다
boot_from_devices()                      순서대로 시도, 전부 실패하면 hang()
spl_perform_arch_fixups()
jump_to_image()                          다음 단계로 넘어간다
```

이 보드 로그의 `Trying to boot from DFU`는 `boot_from_devices()`가 찍는 것이다.

`spl.c`에는 로드한 이미지의 os 종류를 보고 `spl_invoke_atf` 같은 다른 진입 함수를
고르는 분기도 있다. 하지만 이 보드는 그 경로를 타지 않는다. 분기가 `CONFIG_SPL_ATF`
조건부인데 이 빌드에는 그 심볼이 없어서 `spl_atf.c`가 아예 컴파일되지 않는다.
`out/r5-dfu`와 `out/a53` 어디에도 `spl_atf.o`가 없는 것으로 확인된다.

### K3 R5는 jump_to_image를 자기 구현으로 덮는다

`jump_to_image`는 플랫폼이 재정의할 수 있는 자리다. K3 R5용 구현이
`arch/arm/mach-k3/r5/common.c`에 있고 여기가 이 보드의 실제 경로다.

```
독점 장치 해제
rproc_init()
DM 펌웨어를 ELF 로 로드
printf("Starting ATF on ARM64 core...")
rproc_start(1)                           A53 을 깨운다
image_entry()                            R5 는 DM 펌웨어로 넘어간다
```

**R5가 A53에게 넘기고 사라지는 것이 아니다.** `rproc_start(1)`로 A53을 깨운 다음, R5
자신은 방금 로드한 DM 펌웨어를 실행한다. 부팅이 끝난 뒤에도 R5는 Device Manager로
계속 돌면서 다른 코어의 전원과 클럭 요청을 처리한다.

[01. 보드와 칩](01-hardware.md)의 표에 R5F 용도가 "Public ROM → SPL → Device Manager
펌웨어"로 적혀 있는데, 그 마지막 전환이 여기서 일어난다.

A53이 어느 주소부터 실행할지는 SPL이 인자로 넘겨서 정하는 것이 아니다. TF-A가 자기
컴파일 상수를 쓰기 때문이고, 그래서 빌드 인자로 맞춰야 한다. 자세한 것은
[04. 소스 받기와 빌드](04-building.md)에 있다.

## 정리

- 콘솔 로그의 각 줄이 `board_init_f` 본문의 어느 호출에서 나오는지 대응된다. 멈춘
  위치를 짚는 데 쓴다.
- 콘솔은 드라이버 모델과 디바이스 트리가 선 뒤에야 열린다. 그전 구간은 조용히 죽는다.
- EEPROM은 RAM 크기 결정에 쓰인다. 읽기가 실패하면 512MB 기본값으로 간다.
- DDR 초기화는 `uclass_get_device(UCLASS_RAM, 0)` 한 줄이 드라이버를 프로브하는 것이고,
  타이밍 값은 TI 도구가 만든 dtsi에 들어 있다.
- 이 보드는 K3 R5용 `jump_to_image`를 탄다. A53을 깨우고 R5 자신은 DM 펌웨어가 된다.
