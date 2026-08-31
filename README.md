# PocketBeagle 2 부트로더 직접 만들기

> 개인 학습용 보드(Rev A1, AM6254)로 부트로더를 소스에서 빌드해 올려보는 기록이다. 벤더가 준 이미지를 쓰는 대신 ROM부터 U-Boot 셸까지 전부 자기 손으로 만든 것으로 채우는 과정을 다룬다.

## 이 문서가 다루는 것

PC 개발을 하다 임베디드로 넘어오면 부팅이 낯설다. 전원을 넣으면 알아서 되던 것이,
갑자기 여러 코어와 여러 파일과 여러 프로젝트가 얽힌 과정으로 보인다.

부팅이 왜 여러 단계인지, 각 단계에서 무엇이 실행되는지, 그중 어디를 직접 만든 코드로
바꿀 수 있는지를 다룬다. 대상은 PocketBeagle 2(TI K3 계열)다.

## 목차

| 장 | 내용 |
|---|---|
| [00. 준비하기](guide/00-setup.md) | 보드 연결, 호스트 패키지, venv, 소스와 blob 받기 |
| [01. 보드와 칩](guide/01-hardware.md) | 코어가 왜 이렇게 많은가, 부팅에 관여하는 코어 셋 |
| [02. 부팅은 어떻게 일어나는가](guide/02-boot-flow.md) | 전체 흐름, 부팅 장치 결정, 우리가 바꿀 수 있는 경계 |
| [03. 부트 이미지와 서명](guide/03-images.md) | 파일 셋, FIT 컨테이너, 서명 키를 안 구해도 되는 이유 |
| [04. 소스 받기와 빌드](guide/04-building.md) | 2패스 빌드, 세 프로젝트 조립, 반드시 맞춰야 하는 주소 |
| [05. DFU로 부팅시키기](guide/05-dfu.md) | SD를 건드리지 않는 실험 경로, 전송 절차, 복구 |
| [06. 직접 확인해보기](guide/06-hands-on.md) | 보드에서 읽기, 이미지 뜯어보기, 부팅 전 검증 |
| [07. SPL 코드 읽기](guide/07-spl-code.md) | 어셈블리 구간, 메모리 배치, C를 부르기까지 |
| [08. SPL의 C 구간](guide/08-spl-c-code.md) | 콘솔 로그와 코드 대응, DDR을 켜는 곳, 다음 단계 고르기 |
| [09. 이미지는 어떻게 조립되나](guide/09-binman.md) | binman, FIT 만들기, 서명, 외부 파일 전달 |
| [10. 디바이스 트리와 SPL](guide/10-devicetree.md) | SPL용 DT가 따로인 이유, bootph 태그, 참조가 끊기는 함정 |
| [11. 코어 사이의 대화](guide/11-tisci.md) | TISCI, Secure Proxy, 코어를 깨우는 순서 |
| [12. U-Boot에서 리눅스까지](guide/12-to-linux.md) | bootflow, extlinux, 커널에 넘기는 것, 부팅 시간 |

곁가지 문서 둘이 더 있다.

| 문서 | 내용 |
|---|---|
| [브링업 로드맵](roadmap.md) | 커스텀 보드를 받았을 때의 순서를 연습하는 단계별 계획 |
| [오디오 응용 계획](applications.md) | 이 보드로 만들 오디오 기기 두 가지 |

## 미리 정리하는 용어

뒤에서 계속 나오는 말들이다. 처음에는 이름만 익혀두고 자세한 것은 해당 장에서 본다.

| 말 | 뜻 |
|---|---|
| SPL | Secondary Program Loader. U-Boot가 만드는 축소판 로더. SRAM에 들어갈 크기로 만들어 DRAM을 켜고 다음 단계를 읽어 들인다 |
| TF-A | ARM Trusted Firmware-A. ARM이 정한 보안 펌웨어 표준 구현. 이 보드에서는 BL31 하나만 쓴다 |
| OP-TEE | 리눅스와 나란히 도는 작은 보안 운영체제. ARM TrustZone 위에서 실행된다 |
| BL31, BL32, BL33 | TF-A가 쓰는 단계 이름. 각각 보안 감시자, 보안 OS(OP-TEE), 일반 세계 부트로더(U-Boot) |
| FIT | Flattened Image Tree. 여러 조각과 그 메타데이터를 하나로 묶은 이미지 형식 |
| DT, DTB | 디바이스 트리. 하드웨어 구성을 적은 자료 구조이고, 컴파일된 이진 형태가 DTB다 |
| DFU | USB 표준의 펌웨어 전송 규격. SD 카드 없이 부트로더를 보낼 때 쓴다 |
| binman | U-Boot 빌드가 이미지를 조립할 때 쓰는 도구. 조각을 모아 FIT을 만들고 서명한다 |
| 스트랩 | 전원 인가 시 저항으로 고정해둔 설정. 소프트웨어로 바꿀 수 없다 |
| phandle | 디바이스 트리에서 다른 노드를 가리키는 번호 |
| bootph | 디바이스 트리 노드를 어느 부팅 단계에서 쓸지 표시하는 태그 |
| TISCI | 코어가 TIFS에게 전원·클럭·리셋을 요청할 때 쓰는 메시지 규격 |
| remoteproc | 다른 코어에 펌웨어를 올리고 리셋을 푸는 프레임워크 |

## 저장소 구성

```
guide/           00~12 장 본문
build-r5.sh      R5 패스 빌드 (tiboot3.bin)
build-a53.sh     A53 패스 빌드 (tispl.bin, u-boot.img)
patches/         u-boot 트리에 가한 수정
logs/            시리얼 콘솔 캡처
docs/            SRM, TRM, 데이터시트 (git 제외)
out/             빌드 산출물 (git 제외)
```

`u-boot/`, `trusted-firmware-a/`, `optee_os/`, `venv/`도 git에서 제외된다. 받는 방법은
[00. 준비하기](guide/00-setup.md)에 있다.

## 참고 자료

`docs/pocketbeagle-2-srm.pdf`는 시스템 레퍼런스 매뉴얼 2026-06-04판이다.

```
curl -L -o docs/pocketbeagle-2-srm.pdf https://docs.beagleboard.org/pocketbeagle-2.pdf
```

HTML 원본은 [docs.beagleboard.org](https://docs.beagleboard.org/boards/pocketbeagle-2/)에
있다.

SoC 문서는 TI에서 받는다. 부팅은 TRM 5장이다.

```
curl -L -o docs/am62x-trm-spruiv7c.pdf       https://www.ti.com/lit/pdf/spruiv7
curl -L -o docs/am62x-datasheet-sprsp58c.pdf https://www.ti.com/lit/pdf/sprsp58
curl -L -o docs/mspm0l1105.pdf               https://www.ti.com/lit/gpn/mspm0l1105
```

문헌번호 없이 받으면 최신 리비전으로 리다이렉트된다. 위 파일명은 받은 시점의
리비전(TRM Rev C, 데이터시트 Rev C)이다.
