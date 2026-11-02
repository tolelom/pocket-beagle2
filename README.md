# PocketBeagle 2 부트로더 빌드

> PocketBeagle 2(Rev A1, AM6254)의 부트 체인을 소스에서 빌드해 보드에 올린다. ROM 다음 단계부터 U-Boot 셸까지 벤더 이미지 대신 직접 빌드한 이미지로 부팅한다.

## 가이드

| 장 | 내용 |
|---|---|
| [00. 준비하기](guide/00-setup.md) | 보드 연결, 호스트 패키지, venv, 소스·blob·문서 받기 |
| [01. 보드와 칩](guide/01-hardware.md) | 코어 구성, 부팅에 관여하는 코어 셋 |
| [02. 부팅은 어떻게 일어나는가](guide/02-boot-flow.md) | 전체 흐름, 부팅 장치 결정, 바꿀 수 있는 경계 |
| [03. 부트 이미지와 서명](guide/03-images.md) | 파일 셋, FIT 컨테이너, 서명 키 없이 되는 이유 |
| [04. 소스 받기와 빌드](guide/04-building.md) | 2패스 빌드, 세 프로젝트 조립, 맞춰야 하는 주소 |
| [05. DFU로 부팅시키기](guide/05-dfu.md) | SD를 건드리지 않는 실험 경로, 전송 절차, 복구 |
| [06. 직접 확인해보기](guide/06-hands-on.md) | 보드에서 읽기, 이미지 뜯어보기, 부팅 전 검증 |
| [07. SPL 코드 읽기](guide/07-spl-code.md) | 어셈블리 구간, 메모리 배치, C를 부르기까지 |
| [08. SPL의 C 구간](guide/08-spl-c-code.md) | 콘솔 로그와 코드 대응, DDR 초기화, 다음 단계 선택 |
| [09. 이미지는 어떻게 조립되나](guide/09-binman.md) | binman, FIT 생성, 서명, 외부 파일 전달 |
| [10. 디바이스 트리와 SPL](guide/10-devicetree.md) | SPL용 DT, bootph 태그, 참조가 끊기는 경우 |
| [11. 코어 사이의 대화](guide/11-tisci.md) | TISCI, Secure Proxy, 코어 기동 순서 |
| [12. U-Boot에서 리눅스까지](guide/12-to-linux.md) | bootflow, extlinux, 커널 인계, 부팅 시간 |

| 문서 | 내용 |
|---|---|
| [브링업 로드맵](roadmap.md) | 단계별 계획과 진행 상태 |
| [오디오 응용 계획](applications.md) | 이 보드로 만들 오디오 기기 |

## 용어

| 말 | 뜻 |
|---|---|
| SPL | U-Boot의 축소판 로더. SRAM에서 돌며 DRAM을 켜고 다음 단계를 읽는다 |
| TF-A | ARM Trusted Firmware-A. 이 보드에서는 BL31만 쓴다 |
| OP-TEE | TrustZone 위에서 리눅스와 나란히 도는 보안 OS |
| BL31, BL32, BL33 | TF-A의 단계 이름. 보안 감시자, 보안 OS(OP-TEE), 일반 세계 부트로더(U-Boot) |
| FIT | 여러 이미지와 메타데이터를 하나로 묶는 형식 |
| DT, DTB | 디바이스 트리와 그 컴파일 결과 |
| DFU | USB 펌웨어 전송 규격. SD 없이 부트로더를 보낼 때 쓴다 |
| binman | U-Boot 빌드의 이미지 조립 도구 |
| 스트랩 | 전원 인가 시 저항으로 정해지는 설정 |
| phandle | DT에서 다른 노드를 가리키는 번호 |
| bootph | DT 노드를 쓸 부팅 단계를 표시하는 태그 |
| TISCI | 코어가 TIFS에 전원·클럭·리셋을 요청하는 메시지 규격 |
| remoteproc | 다른 코어에 펌웨어를 올리고 리셋을 푸는 리눅스 프레임워크 |

## 저장소 구성

```
guide/              00~12장
roadmap.md          브링업 로드맵
applications.md     오디오 응용 계획
build-r5.sh         R5 패스 빌드 (tiboot3.bin)
build-a53.sh        A53 패스 빌드 (tispl.bin, u-boot.img)
clean-serial-log.py 시리얼 로그에서 제어 문자 제거 (*-clean.log 생성)
patches/            u-boot 트리 수정분
logs/               시리얼 콘솔 캡처
```

아래 경로는 git에 없고 따로 받거나 만든다.

| 경로 | 내용 | 받는 방법 |
|---|---|---|
| `u-boot/`, `trusted-firmware-a/`, `optee_os/` | 소스 트리 | [00장](guide/00-setup.md) 0-4 |
| `ti-linux-firmware/` | TI 펌웨어 blob | [00장](guide/00-setup.md) 0-4 |
| `datasheets/` | SRM, TRM, 데이터시트 | [00장](guide/00-setup.md) 0-4 |
| `venv/` | 빌드용 파이썬 환경 | [00장](guide/00-setup.md) 0-3 |
| `out/` | 빌드 산출물 | `build-r5.sh`, `build-a53.sh` |
| `logs/*-clean.log` | 정리한 로그 | `clean-serial-log.py` |
