# 09. 이미지는 어떻게 조립되나

> `make` 한 번에 `tiboot3.bin`과 `tispl.bin`이 나오는데, 그 안에서 조각을 모으고 서명하는 일을 binman이 한다. 보드를 새로 포팅할 때 손대야 하는 부분이라 구조를 알아둘 만하다.

## 9-1. binman이 무엇인가

U-Boot 빌드의 마지막 단계에서 도는 파이썬 도구다. 컴파일 결과와 외부 바이너리를 모아
최종 이미지 파일을 만든다.

`tispl.bin` 하나를 만들려면 이런 일이 필요하다.

- U-Boot 빌드가 만든 A53 SPL 바이너리를 가져온다
- 다른 프로젝트가 빌드한 TF-A와 OP-TEE 바이너리를 가져온다
- TI가 배포한 DM 펌웨어 blob을 가져온다
- 각각에 X.509 인증서를 만들어 붙인다
- 로드 주소 같은 메타데이터와 함께 FIT으로 묶는다

컴파일러도 링커도 할 수 없는 일이다.

binman의 접근은 "무엇을 어떻게 조립할지를 디바이스 트리로 적는다"이다. 이미 디바이스
트리를 쓰고 있으니 형식을 재활용한 것이다.

## 9-2. 조립 지시는 DT에 있다

보드의 `-u-boot.dtsi`에 `&binman` 노드가 있고 거기에 이미지 구성이 적혀 있다.

`arch/arm/dts/k3-am62-pocketbeagle2-u-boot.dtsi`를 열면 `&binman` 블록이 넷이다.
각각 `tiboot3-am62x-hs-evm.bin`, `tiboot3-am62x-hs-fs-evm.bin`, `ti-spl`, `u-boot`을
만든다.

앞의 둘이 나뉜 것은 장치 보안 상태 때문이다. 이 보드는 HS-FS라
`tiboot3-am62x-hs-fs-evm.bin` 쪽을 쓰고, 여기에만 `symlink = "tiboot3.bin"`이 붙어
있다. 다른 하나(HS-SE용)도 같이 만들어지는데 이 보드와 무관하다.
[04. 소스 받기와 빌드](04-building.md)에서 무시해도 된다고 한 경고가 그쪽에서 나온다.

## 9-3. tiboot3.bin: 통째로 하나의 서명

R5용 이미지는 FIT이 아니다. `ti-secure-rom`이라는 항목 하나가 조각 다섯을 묶고 전체에
서명한다.

```
tiboot3-am62x-hs-fs-evm.bin
  ti-secure-rom
    content = <&u_boot_spl_fs>, <&ti_fs_enc_fs>, <&combined_tifs_cfg_fs>,
              <&combined_dm_cfg_fs>, <&sysfw_inner_cert_fs>
    keyfile = "custMpk.pem"
    load          = 0x43c00000    SPL 을 올릴 주소
    load-sysfw    = 0x40000       TIFS 펌웨어
    load-sysfw-data = 0x67000     TIFS 설정
    load-dm-data  = 0x43c3a800    DM 설정
```

ROM이 이 파일을 통째로 받아 TIFS에 넘기고, TIFS가 인증서를 검사한 뒤 각 조각을 적힌
주소에 배치한다. [02. 부팅은 어떻게 일어나는가](02-boot-flow.md)에서 본 "ROM이 M4로
전달"이 이 단계다.

`combined_tifs_cfg`와 `combined_dm_cfg`가 보드 디렉터리의 yaml 넷에서 온다.

```
board/beagle/pocketbeagle2/board-cfg.yaml
board/beagle/pocketbeagle2/pm-cfg.yaml
board/beagle/pocketbeagle2/rm-cfg.yaml
board/beagle/pocketbeagle2/sec-cfg.yaml
```

TIFS에게 "이 보드는 자원을 이렇게 나눠 쓰고 방화벽을 이렇게 걸어라"를 알려주는
설정이다. 어느 것을 손봐야 하는지는 9-7에 정리했다.

## 9-4. tispl.bin: FIT과 템플릿

A53용은 FIT이다. 그런데 보드 dtsi에 적힌 것은 일부뿐이다.

```
ti-spl {
    insert-template = <&ti_spl_template>;
    fit {
        images {
            dm { ... }        보드가 채우는 부분
            fdt-0 { ... }     보드가 채우는 부분
        };
        configurations {
            conf-0 {
                firmware = "atf";
                loadables = "tee", "dm", "spl";
                fdt = "fdt-0";
            };
        };
    };
};
```

`insert-template`은 `arch/arm/dts/k3-binman.dtsi`의 `ti_spl_template`를
가져다 깔고 그 위에 보드 고유 부분을 얹는다. K3 계열이 공유하는 뼈대는 한 곳에 두고
보드마다 다른 것만 따로 적는 구조다.

템플릿에 들어 있는 `atf` 노드를 보면 FIT 항목이 어떻게 생겼는지 알 수 있다.

```
atf {
    description = "ARM Trusted Firmware";
    type = "firmware";
    arch = "arm64";
    compression = "none";
    os = "arm-trusted-firmware";
    load  = <CONFIG_K3_ATF_LOAD_ADDR>;
    entry = <CONFIG_K3_ATF_LOAD_ADDR>;
    ti-secure {
        content = <&atf>;
        keyfile = "custMpk.pem";
    };
    atf: atf-bl31 { };
};
```

**로드 주소가 Kconfig 값이다.** `CONFIG_K3_ATF_LOAD_ADDR`가 그대로 들어간다. 즉
defconfig를 고치면 FIT의 로드 주소가 바뀐다. [04. 소스 받기와 빌드](04-building.md)에서
맞춰야 했던 주소들이 이 경로로 이미지에 박힌다.

**`os` 필드가 있다.** SPL이 다음 단계를 고를 때 읽는 값이다. 자세한 것은
[08. SPL의 C 구간](08-spl-c-code.md)에 있다.

**서명이 항목마다 걸린다.** `ti-secure`가 `content`로 지정된 데이터를 감싸 인증서를
붙인다. 조각마다 따로 붙는 이유가 이 구조다.

`atf: atf-bl31 { }`는 내용이 비어 있는데, 파일 경로를 빌드 시점에 인자로 받기
때문이다. 다음 절에서 본다.

## 9-5. 외부 파일은 인자로 들어간다

`make`가 binman을 부르는 명령이 U-Boot Makefile에 있다. 관련 부분만 추리면 이렇다.

```
binman build -u -d $(binman_dtb) -O . -m \
  --allow-missing --fake-ext-blobs \
  -I . -I $(srctree) -I $(srctree)/board/$(BOARDDIR) \
  $(foreach f,$(BINMAN_INDIRS),-I $(f)) \
  -a atf-bl31-path=${BL31} \
  -a tee-os-path=${TEE} \
  -a ti-dm-path=${TI_DM} \
  ...
```

`-a`가 인자 전달이다. `make`에 넘긴 `BL31=`과 `TEE=`가 여기로 흘러들어가
`atf-bl31`, `tee-os` 항목의 파일 경로가 된다.

`-I`가 파일 검색 경로다. `BINMAN_INDIRS`가 여기 붙는다. DM 펌웨어처럼 dtsi에 파일
이름만 적힌 항목은 이 경로들에서 찾는다.

### 파일이 없어도 빌드가 되는 이유

`--allow-missing --fake-ext-blobs`가 붙어 있다. 파일을 못 찾아도 실패하지 않고 가짜
데이터로 채운다는 뜻이다. 여러 아키텍처를 한 트리에서 빌드하는 프로젝트라 외부 blob이
없는 환경에서도 빌드가 돌아야 하기 때문이다.

그 결과가 [04. 소스 받기와 빌드](04-building.md)에서 본 조용히 망가진 이미지다.

## 9-6. 서명은 openssl이 한다

`ti-secure`와 `ti-secure-rom`은 binman의 엔트리 타입이고 구현이 각각
`tools/binman/etype/ti_secure.py`와 `ti_secure_rom.py`에 있다. 둘 다 `x509_cert`
타입을 상속받아 openssl로 인증서를 만든다.

dtsi의 `keyfile` 값이 여기까지 흘러와 openssl 인자가 된다. 그 키가 어떤 것이고 왜
따로 구할 필요가 없는지는 [03. 부트 이미지와 서명](03-images.md)에 있다.

방화벽 설정도 인증서에 실린다. `ti_secure.py`에 `Firewall` 클래스가 있고, dtsi에
방화벽 항목을 적으면 인증서 확장 필드로 들어간다. TIFS가 그 값을 읽어 메모리 접근
제한을 건다.

## 9-7. 보드를 포팅할 때 어디를 보나

이 장의 내용이 [브링업 로드맵](../roadmap.md) 2단계에 직결된다. 새 보드용 이미지를
만들려면 binman 쪽에서 필요한 것이 이렇다.

| 대상 | 하는 일 |
| --- | --- |
| `-u-boot.dtsi`의 `&binman` 블록 | 이미지 구성. 레퍼런스 보드 것을 베끼고 dm·fdt 경로를 바꾼다 |
| `board-cfg.yaml`, `pm-cfg.yaml` | 보드 자원·전원 설정 |
| `rm-cfg.yaml`, `sec-cfg.yaml` | SoC 공통. 대개 그대로 |
| defconfig의 로드 주소 | FIT에 그대로 박히므로 메모리 배치를 정할 때 함께 정한다 |

이미지가 제대로 만들어졌는지 확인하는 방법은
[06. 직접 확인해보기](06-hands-on.md)에 있다.

## 정리

- binman은 조립 지시를 디바이스 트리로 받는다. `&binman` 노드가 그것이다.
- `tiboot3.bin`은 FIT이 아니라 조각 다섯을 묶어 통째로 서명한 형식이다.
- `tispl.bin`은 FIT이고, K3 공통 템플릿에 보드 고유 부분을 얹어 만든다.
- FIT 항목의 로드 주소는 Kconfig 값이 그대로 들어간다.
- 외부 바이너리 경로는 `make` 인자가 binman 인자로 전달된다.
- 파일을 못 찾아도 빌드는 성공한다. 경고를 읽어야 잡힌다.
