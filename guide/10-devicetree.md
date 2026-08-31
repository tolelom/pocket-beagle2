# 10. 디바이스 트리와 SPL

> SPL은 본체와 다른 디바이스 트리를 쓴다. 왜 나뉘어 있고 무엇이 빠지는지 알아야, 본체에서는 되는데 SPL에서만 안 되는 문제를 짚을 수 있다.

## 10-1. 디바이스 트리가 하는 일

임베디드 SoC에는 주변장치가 수백 개 붙어 있다. UART가 일곱 개, I2C가 다섯 개, 그런
식이다. 그런데 보드마다 쓰는 것이 다르다. 어떤 보드는 UART0을 콘솔로 쓰고 어떤 보드는
UART6을 쓴다.

이걸 코드에 박아 넣으면 보드마다 커널을 새로 컴파일해야 한다. 그래서 하드웨어 구성을
자료 구조로 빼냈다. 그것이 디바이스 트리다.

트리 구조로 노드를 적고, 각 노드에 `compatible`(어느 드라이버가 다룰지), `reg`(레지스터
주소), 그밖의 속성을 단다. 드라이버는 `compatible`로 자기 노드를 찾아 붙는다.

U-Boot도 같은 방식을 쓴다. [08. SPL의 C 구간](08-spl-c-code.md)에서 본
`uclass_get_device(UCLASS_RAM, 0)` 한 줄이 DDR 드라이버를 프로브할 수 있는 것도, DT에
그 노드가 있고 `compatible`이 드라이버와 맞기 때문이다.

## 10-2. SPL은 왜 DT가 따로인가

이유는 크기다. [02. 부팅은 어떻게 일어나는가](02-boot-flow.md)에서 본 SRAM 제약이
여기에도 걸린다.

이 보드의 두 DT를 재보면 차이가 분명하다.

```
out/r5-dfu/dts/dt.dtb                          57,608 바이트   노드 300개
out/r5-dfu/spl/dts/k3-am62-r5-pocketbeagle2.dtb 22,610 바이트   노드  64개
```

노드가 4분의 1 남짓으로 줄었다. SPL이 쓰지 않는 장치는 다 뺀 것이다. SPL 단계에서 필요한 건
UART, I2C, MMC, DDR 정도이고 디스플레이나 오디오는 나중 문제다.

## 10-3. 무엇을 남길지는 태그로 정한다

빌드가 자동으로 판단하는 것이 아니라 DT에 표시해둔다. `bootph-`로 시작하는 태그다.

`doc/develop/spl.rst`에 규칙이 적혀 있다. 빌드 과정에서 `fdtgrep`이라는 도구가 본체
DT를 걸러 SPL용을 만드는데, 남기는 것이 이렇다.

- 필수 노드(`/alias`, `/chosen`, `/config`)
- `bootph-all` 또는 `bootph-pre-ram` 속성이 있는 노드

그리고 SPL DT를 만든 뒤에는 `bootph-*` 태그 자체를 지운다. 역할이 끝났기 때문이다.

태그 종류가 몇 가지 있는데 어느 단계에서 쓰이는지를 나타낸다.

| 태그 | 뜻 |
| --- | --- |
| `bootph-all` | 모든 단계에서 쓴다 |
| `bootph-pre-ram` | SPL 단계에서 쓴다 |
| `bootph-pre-sram` | TPL 단계에서 쓴다 |
| `bootph-verify` | VPL 단계에서 쓴다 |

이 보드의 `-u-boot.dtsi`를 보면 SPL에서 쓸 노드마다 `bootph-all`을 달아둔 것이 보인다.

```
&usb0 {
	dr_mode = "peripheral";
	bootph-all;
};
```

상위 DT에는 없던 속성을 U-Boot 전용 dtsi에서 덧붙이는 방식이다. 상위 DT는 리눅스와
공유하므로 U-Boot 사정을 거기 적지 않는다.

## 10-4. 태그를 빠뜨리면 생기는 일

이 규칙이 만드는 함정이 있다. 노드를 지우는 것은 참조까지 정리해주지 않는다.

[05. DFU로 부팅시키기](05-dfu.md)에서 본 경고가 정확히 그 경우다.

```
dwc3-am62 dwc3-usb@f900000: unable to get ti,syscon-phy-pll-refclk regmap
```

기전을 하나씩 따라가면 이렇다.

**본체 DT에서는** USB 컨트롤러 노드가 syscon 노드를 phandle로 가리킨다. phandle은
다른 노드를 참조하는 번호다.

```
dwc3-usb@f900000 {
    ti,syscon-phy-pll-refclk = <0x23 0x00>;
}
syscon@4008 {
    compatible = "ti,am62-usb-phy-ctrl", "syscon";
    phandle = <0x23>;
}
```

`0x23`이 두 노드를 잇는다.

**SPL DT에서는** USB 컨트롤러 노드는 남았는데(`bootph-all`이 있다) syscon 노드는
사라졌다(태그가 없다). 그런데 참조하는 속성은 그대로 남아 있다.

```
dwc3-usb@f900000 {
    ti,syscon-phy-pll-refclk = <0x23 0x00>;   <- 남아 있음
}
syscon@4008 { }                               <- 없음
```

드라이버가 `0x23`을 따라가면 아무것도 없다. 그래서 경고가 난다.

이 보드에서 USB 열거와 DFU 전송은 정상 동작한다. 드라이버가 그 regmap 없이도 진행하기
때문이다.

DTB를 직접 열어 확인하는 방법은 [06. 직접 확인해보기](06-hands-on.md)에 있다.

## 10-5. SPL DT를 직접 들여다보기

DTB는 이진 파일이지만 형식이 공개되어 있어 그대로 열어볼 수 있다. 두 DT를 나란히 놓고
어느 노드가 빠졌는지 보면 SPL이 무엇을 쓰고 무엇을 안 쓰는지가 드러난다.

명령은 [06. 직접 확인해보기](06-hands-on.md)에 있다. 실행 중인 보드에서는 U-Boot 셸의
`dm tree`로도 볼 수 있다.

## 10-6. DT 파일이 여럿인 이유

이 보드 하나에 DT 관련 파일이 넷이다. 각자 역할이 다르다.

| 파일 | 역할 |
| --- | --- |
| `dts/upstream/src/arm64/ti/k3-am62-pocketbeagle2.dts` | 상위 DT. 리눅스와 공유하는 하드웨어 서술 |
| `arch/arm/dts/k3-am62-pocketbeagle2-u-boot.dtsi` | U-Boot 전용 덧붙임. `bootph` 태그와 `&binman` 노드 |
| `arch/arm/dts/k3-am62-pocketbeagle2-ddr4-1600MTs.dtsi` | DDR 타이밍. TI 도구 생성물 |
| `arch/arm/dts/k3-am62-r5-pocketbeagle2.dts` | R5용 최상위. 위 셋을 include 한다 |

마지막 파일이 실제로 컴파일되는 진입점이고 내용은 짧다. 나머지를 조합하고 R5
단계에서만 필요한 것을 얹는다.

`&binman` 노드가 U-Boot 전용 dtsi에 들어 있는 것도 이 구조 때문이다. 이미지 조립 지시는
리눅스와 무관하므로 공유 DT에 둘 수 없다. 자세한 것은
[09. 이미지는 어떻게 조립되나](09-binman.md)에 있다.

## 10-7. 보드를 포팅할 때

DT 쪽에서 새로 만들거나 고쳐야 하는 것이 이렇다.

- **상위 DT**: 보드에 실제로 붙은 장치를 적는다. 핀먹스, 전원, I2C에 매달린 칩 같은 것.
  레퍼런스 보드 파일을 베끼고 다른 부분만 고치는 것이 보통이다.
- **U-Boot dtsi**: SPL에서 쓸 노드에 `bootph` 태그를 단다. 여기서 빠뜨리면 10-4에서
  본 문제가 생긴다.
- **DDR dtsi**: TI 도구에 메모리 사양을 넣어 뽑는다.
- **R5용 최상위**: 위 셋을 include 하고 콘솔 alias를 정한다.

태그를 달 때 주의할 점 하나. **참조되는 쪽도 같이 태그를 달아야 한다.** 노드 하나만
보고 태그를 달면 그 노드가 phandle로 가리키는 대상이 빠질 수 있다.

## 정리

- SPL DT는 본체 DT를 `fdtgrep`으로 걸러 만든다. 이 보드는 노드 300개가 64개로 줄어든다.
- 무엇을 남길지는 `bootph-*` 태그가 정한다. U-Boot 전용 dtsi에서 단다.
- 노드를 지워도 그 노드를 가리키는 phandle은 남는다. dwc3 경고가 그 경우다.
- 태그를 달 때는 참조되는 노드까지 함께 봐야 한다.
- DT 파일이 넷으로 나뉜 것은 리눅스와 공유하는 부분과 U-Boot 전용을 가르기 위해서다.
