# pocket-beagle2

> PocketBeagle 2(Rev A1, AM6254)의 부트 체인을 소스에서 빌드해 보드에 올리는 가이드

U-Boot · TF-A · OP-TEE

ROM 다음 단계부터 U-Boot 셸까지 벤더 이미지 대신 직접 빌드한 이미지로 부팅합니다.

## 시작하기

호스트는 Ubuntu 24.04 기준입니다. 보드 연결, 호스트 패키지, venv, 소스와 blob 받기는 [00. 준비하기](guide/00-setup.md)를 따릅니다.

```bash
./build-r5.sh    # R5 패스
./build-a53.sh   # A53 패스
```

| 산출물 | 내용 |
|---|---|
| `out/r5/tiboot3.bin` | SD 부팅용 |
| `out/r5-dfu/tiboot3.bin` | DFU 이어받기용 |
| `out/a53/tispl.bin` | TF-A, OP-TEE, DM, A53 SPL을 담은 FIT |
| `out/a53/u-boot.img` | U-Boot 본체 |

SD를 건드리지 않고 DFU로 부팅시키는 절차는 [05장](guide/05-dfu.md)에 있습니다.

## 문서

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
| [roadmap.md](roadmap.md) | 브링업 단계별 계획과 진행 상태 |
| `patches/` | u-boot 트리 수정분 |
| `logs/` | 시리얼 콘솔 캡처 |
| `clean-serial-log.py` | 시리얼 로그에서 제어 문자 제거, 원본 옆에 `*-clean.log` 생성 |

## 라이선스

문서와 로그는 CC BY 4.0, 스크립트는 MIT, `patches/`는 U-Boot와 같은 GPL-2.0입니다. 상세는 [LICENSE](LICENSE)에 있습니다.
