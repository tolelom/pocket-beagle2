# 11. 코어 사이의 대화

> 이 칩에서는 코어가 자기 전원과 클럭을 스스로 켜지 못한다. TIFS에게 요청해야 한다. 그 요청이 어떤 형식으로 오가고, A53을 깨우는 일이 어떻게 그 위에 얹히는지 본다.

## 11-1. 왜 직접 못 켜나

보통의 MCU라면 클럭 레지스터에 비트를 쓰면 페리페럴이 켜진다. 이 칩은 다르다. 전원·클럭·리셋
레지스터에 직접 접근하면 방화벽에 막힌다.

접근 권한을 TIFS가 쥐고 있기 때문이다. [01. 보드와 칩](01-hardware.md)에서 본 SMS 안의
M4F가 그 역할이고, 사용자 코드를 올릴 수 없다.

이유는 안전과 격리다. 코어가 여럿이고 리눅스와 실시간 코드가 함께 도는 칩에서, 한쪽이
다른 쪽이 쓰는 클럭을 꺼버리면 곤란하다. 자원 관리를 한 곳에 몰아 조정하게 만든 구조다.

그래서 뭔가를 켜려면 메시지를 보내 부탁해야 한다. 그 메시지 규격이 TISCI다.

## 11-2. TISCI, Secure Proxy, TIFS

이름마다 맡은 자리가 다르다.

| 이름 | 자리 | 하는 일 |
| --- | --- | --- |
| TISCI | 프로토콜 | 메시지 형식과 명령 번호를 정한다 |
| Secure Proxy | 전송 | 메시지를 실어 나르는 메일박스 하드웨어 |
| TIFS | 상대편 | 요청을 받아 실제로 레지스터를 만지는 펌웨어 |

디바이스 트리에도 이 구분이 그대로 보인다.

```
secure_proxy_main: mailbox@4d000000 {
    compatible = "ti,am654-secure-proxy";
    ...
};

dmsc: system-controller@44043000 {
    compatible = "ti,k2g-sci";
    ti,host-id = <12>;
    mbox-names = "rx", "tx";
    mboxes = <&secure_proxy_main 12>, <&secure_proxy_main 13>;
    ...
};
```

`dmsc`가 TISCI를 말하는 창구이고, 그 창구가 메일박스 채널을 쓴다. `ti,host-id`는 자기가
누구인지 밝히는 번호다. 여러 코어가 같은 TIFS에 요청하므로 누가 보낸 것인지 구분이
필요하다.

위는 상위 DT의 값이고 리눅스가 쓰는 설정이다. R5 SPL은 같은 노드를 덮어쓴다.

```
&dmsc {
    mboxes = <&secure_proxy_main 0>, <&secure_proxy_main 1>, <&secure_proxy_main 0>;
    mbox-names = "rx", "tx", "notify";
    ti,host-id = <35>;
    ti,secure-host;
};
```

번호와 채널이 다르고 `ti,secure-host`가 붙는다. 같은 TIFS를 상대하더라도 부팅 초기의
R5와 나중의 리눅스가 서로 다른 자격으로 말한다는 뜻이다.

## 11-3. 요청은 DT에 적혀 있다

디바이스 트리에 "이 장치는 이 전원 도메인과 이 클럭이 필요하다"고 적어두면 프레임워크가
메시지를 만들어 보낸다. 드라이버가 TISCI 메시지를 직접 조립하지 않는다.

`dmsc` 아래에 그 창구가 하위 노드로 붙어 있다.

```
k3_pds: power-controller {
    compatible = "ti,sci-pm-domain";
};
k3_clks: clock-controller {
    compatible = "ti,k2g-sci-clk";
};
```

그러면 장치 노드에서 이렇게 참조한다.

```
power-domains = <&k3_pds 61 TI_SCI_PD_EXCLUSIVE>;
clocks = <&k3_clks 61 0>, <&k3_clks 135 0>;
resets = <&k3_reset 135 0>;
```

숫자가 TIFS가 아는 장치 번호와 클럭 번호다. 드라이버가 프로브될 때 프레임워크가 이
값들로 TISCI 메시지를 만들어 보낸다. `61`이 무엇인지는 SoC마다 정해진 표에 있다.

`TI_SCI_PD_EXCLUSIVE`는 이 장치를 독점으로 쓰겠다는 표시다.

## 11-4. 부팅 로그에서 보이는 것

TISCI가 언제 서는지는 로그로 확인된다.

```
SYSFW ABI: 4.0 (firmware rev 0x000b '11.2.5--v11.02.05 (Fancy Rat)')
```

`arch/arm/mach-k3/common.c`의 `k3_sysfw_print_ver()`가 찍는 줄이다. TIFS와 통신이
되어야 버전을 물어볼 수 있으므로, 이 줄이 나왔다면 TISCI 경로가 살아 있다는 뜻이다.

[08. SPL의 C 구간](08-spl-c-code.md)의 대응표에서 이 줄이 `k3_sysfw_loader()` 뒤에
오는 것도 같은 이유다. 펌웨어를 올리고 나서야 말을 걸 수 있다.

## 11-5. A53을 깨우는 것도 같은 방식이다

[08. SPL의 C 구간](08-spl-c-code.md)에서 R5가 `rproc_start(1)`로 A53을 깨운다고 했다.
그 `1`이 무엇인지 디바이스 트리에 적혀 있다.

```
aliases {
    remoteproc0 = &sysctrler;
    remoteproc1 = &a53_0;
};
```

`remoteproc1`이 A53이다. 그 노드를 보면 코어 하나를 깨우는 데 무엇이 필요한지 드러난다.

```
a53_0: a53@0 {
    compatible = "ti,am654-rproc";
    reg = <0x00 0x00a90000 0x00 0x10>;
    power-domains = <&k3_pds 61 ...>, <&k3_pds 135 ...>, <&k3_pds 166 ...>;
    resets = <&k3_reset 135 0>;
    clocks = <&k3_clks 61 0>, <&k3_clks 135 0>;
    clock-names = "gtc", "core";
    ti,sci = <&dmsc>;
    ti,sci-proc-id = <32>;
    ti,sci-host-id = <10>;
    ...
};
```

전원 도메인 셋, 클럭 둘이다. 코어를 켠다는 것이 스위치 하나가 아니라 이 자원들을
순서대로 확보하는 일이라는 뜻이다.

`clock-names`의 첫 항목이 `gtc`이고, `reg`의 0x00a90000이 그 GTC(Global Timer Counter)
레지스터 자리다. A53 계열이 공유하는 시스템 카운터라 코어를 깨우기 전에 주파수를 적고
켜야 한다.

`ti,sci-proc-id`는 TIFS가 이 코어를 부르는 번호이고, `ti,sci-host-id`는 이 코어가
나중에 TISCI 요청을 보낼 때 쓸 번호다. A53도 깨어난 뒤에는 같은 방식으로 TIFS에
요청한다.

드라이버는 `drivers/remoteproc/ti_k3_arm64_rproc.c`이고 하는 일이 두 단계로 나뉜다.

```
k3_arm64_load(addr, size)
  ti_sci_proc_request()          이 코어를 다루겠다고 TIFS에 요청
  power_domain_on(gtc)           GTC 전원
  writel(gtc_rate, GTC_CNTFID0)  레지스터 직접 쓰기
  writel(GTC_CNTR_EN, GTC_CNTCR)
  power_domain_on(cluster)       클러스터 전원
  ti_sci_proc_set_config(addr)   부트 벡터를 TISCI 메시지로 전달

k3_arm64_start()
  power_domain_on(rproc)         코어 전원
  ti_sci_proc_release()          제어권 반납
```

**부트 벡터도 레지스터에 직접 쓰는 것이 아니라 TISCI 메시지다.** 직접 쓰는 것은 GTC
레지스터 둘뿐이다. `resets` 속성이 노드에 적혀 있지만 이 드라이버에서 assert나
deassert를 부르는 자리는 없다.

## 11-6. R5 자신도 이 구조 위에 있다

`remoteproc0 = &sysctrler`가 SMS의 M4F를 가리킨다. R5 SPL이 TIFS 펌웨어를 올릴 때
쓰는 것이 이 항목이다.

[08. SPL의 C 구간](08-spl-c-code.md)에서 본 `jump_to_image` 구현이 `rproc_init()`을
먼저 부르는 이유도 여기 있다. DM 펌웨어를 R5에 올리고 A53을 깨우는 두 작업이 모두
remoteproc 프레임워크를 거친다.

자원 관리가 둘로 나뉘어 있다. TIFS가 보안 자원을 쥐고, DM이 일반 자원 요청을 처리한다.

## 11-7. 리눅스에서 보기

리눅스가 뜬 뒤에도 같은 구조가 이어진다. [01. 보드와 칩](01-hardware.md)에서 본 M4F
펌웨어 오류가 리눅스 쪽 remoteproc이 같은 경로를 타다가 내는 것이다.

번호를 그대로 믿으면 안 된다. `remoteproc0`이 R5 SPL의 DT에서는 SMS의 M4F를 가리키지만,
리눅스가 쓰는 DT에서는 MCU 도메인의 M4F(`5000000.m4fss`)다. DT가 다르면 번호도 다른
대상을 가리킨다.

이 자리가 [브링업 로드맵](../roadmap.md) 5단계로 이어진다. M4F에 직접 만든 펌웨어를 올려
A53과 메시지를 주고받게 하는 것이 그 단계의 목표이고, 그때 쓰는 것이 이 장에서 본
구조다.

## 정리

- 코어는 자기 전원·클럭·리셋을 직접 못 켠다. TIFS에게 TISCI 메시지로 요청한다.
- TISCI는 프로토콜, Secure Proxy는 전송 수단, TIFS는 상대편이다.
- 요청 내용은 대개 디바이스 트리의 `power-domains`·`clocks`·`resets`에 적혀 있고
  프레임워크가 메시지로 바꾼다.
- `SYSFW ABI` 줄이 나왔다면 TISCI 경로가 살아 있다는 표지다.
- A53을 깨우는 것도 같은 구조다. 전원·클럭 확보, 부트 벡터 기록, 리셋 해제 순이다.
