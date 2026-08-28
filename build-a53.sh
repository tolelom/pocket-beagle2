#!/bin/bash
# PocketBeagle 2 - 1e: A53 패스 빌드
#
# 산출물: out/a53/tispl.bin    (TF-A + OP-TEE + DM + A53 SPL 을 담은 FIT)
#         out/a53/u-boot.img   (U-Boot 본체)
#
# R5 패스와 달리 소스가 셋이다. tispl.bin 이 FIT 컨테이너라서 조각을 각기 다른
# 프로젝트에서 빌드해 binman 에 넘긴다. DM 펌웨어만 소스 빌드가 아니라
# ti-linux-firmware 에서 받은 blob 이다.
set -u

WS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UB="$WS/u-boot"
FW="$WS/ti-linux-firmware"
TFA="$WS/trusted-firmware-a"
OPTEE="$WS/optee_os"
VENV="$WS/venv"

CC32=arm-linux-gnueabihf-
CC64=aarch64-linux-gnu-
J=$(nproc)

# 보드 고유 주소. TI 문서의 표준 빌드 인자에는 없고, PocketBeagle 2 가 K3 기본
# 메모리 맵과 다르기 때문에 넘겨야 한다. 틀리면 콘솔이 조용한 채로 멈춘다.
#
#                      TF-A 기본값    PocketBeagle 2
#   BL32 (OP-TEE)      0x9e800000     0x80080000
#   BL33 (A53 SPL)     0x80080000     0x82000000
#
# 두 자리가 서로 엇갈려 있어서 기본값으로 빌드하면 BL31 이 A53 SPL 을 OP-TEE
# 자리에서 시작하려 한다. 콘솔 UART 도 다르다. k3-am62-r5-pocketbeagle2.dts 의
# stdout-path 가 main_uart6(0x02860000)이고 TF-A·OP-TEE 기본값은 0 번이다.
UART=6                      # 0x02800000 + 0x10000 * 6
OPTEE_ADDR=0x80080000       # u-boot 의 CONFIG_K3_OPTEE_LOAD_ADDR 과 같아야 한다
A53_SPL_ADDR=0x82000000     # tispl.bin 안 spl 조각의 로드 주소

preflight() {
    local miss=()

    for t in "${CC64}gcc" "${CC32}gcc"; do
        command -v "$t" >/dev/null 2>&1 || miss+=("크로스 컴파일러 $t")
    done

    local t
    for t in make bison flex dtc pkg-config; do
        command -v "$t" >/dev/null 2>&1 || miss+=("호스트 도구 $t")
    done

    [ -d "$UB" ]    || miss+=("u-boot 소스 $UB  -> README 의 클론 명령")
    [ -d "$TFA" ]   || miss+=("TF-A 소스 $TFA  -> README 의 클론 명령")
    [ -d "$OPTEE" ] || miss+=("OP-TEE 소스 $OPTEE  -> README 의 클론 명령")

    [ -f "$UB/configs/am62_pocketbeagle2_a53_defconfig" ] \
        || miss+=("defconfig am62_pocketbeagle2_a53_defconfig 가 u-boot 트리에 없음")

    # R5 패스가 쓰는 TIFS blob 2개에 더해 DM 펌웨어가 필요하다. 요구하는 쪽은
    # k3-am62-pocketbeagle2-u-boot.dtsi 의 ti-dm 노드다. 없으면 binman 이
    # 그 자리를 비운 이미지를 만들고 빌드는 통과한다.
    [ -f "$FW/ti-dm/am62xx/ipc_echo_testb_mcu1_0_release_strip.xer5f" ] \
        || miss+=("DM 펌웨어 blob  -> README 의 curl 명령")

    [ -f "$VENV/bin/activate" ] || miss+=("venv $VENV  -> README 의 venv 구성 명령")

    if [ ${#miss[@]} -ne 0 ]; then
        echo "빌드 전제가 갖춰지지 않았다:"
        printf '  - %s\n' "${miss[@]}"
        exit 1
    fi

    # shellcheck disable=SC1091
    . "$VENV/bin/activate"

    # OP-TEE 의 서명 스크립트가 cryptography 를, binman 이 elftools 를 쓴다.
    # venv 는 만든 자리에 묶이므로 저장소를 옮겼으면 여기서 걸린다. 그때는
    # 패키지를 더 넣는 게 아니라 venv 를 다시 만든다.
    local m
    for m in cryptography elftools setuptools; do
        python3 -c "import $m" 2>/dev/null || {
            echo "venv 에 $m 이(가) 없다. README 의 venv 구성 명령을 다시 실행한다:"
            echo "  rm -rf venv && /usr/bin/python3 -m venv venv"
            echo "  venv/bin/python3 -m pip install -r u-boot/tools/binman/requirements.txt setuptools cryptography"
            exit 1
        }
    done
}

preflight

echo
echo "############################################################"
echo "# 1/3  TF-A (BL31)"
echo "############################################################"
make -C "$TFA" CROSS_COMPILE=$CC64 ARCH=aarch64 PLAT=k3 SPD=opteed \
     TARGET_BOARD=lite \
     K3_USART=$UART \
     BL32_BASE=$OPTEE_ADDR \
     PRELOADED_BL33_BASE=$A53_SPL_ADDR \
     -j"$J" > "$WS/out/tfa.build.log" 2>&1
RC1=$?
echo "make exit: $RC1"
[ $RC1 -ne 0 ] && { echo "!!! 마지막 30줄:"; tail -30 "$WS/out/tfa.build.log"; exit 1; }
BL31="$TFA/build/k3/lite/release/bl31.bin"
ls -l "$BL31"

echo
echo "############################################################"
echo "# 2/3  OP-TEE"
echo "############################################################"
make -C "$OPTEE" CROSS_COMPILE=$CC32 CROSS_COMPILE64=$CC64 \
     PLATFORM=k3-am62x CFG_ARM64_core=y CFG_WITH_SOFTWARE_PRNG=y \
     CFG_CONSOLE_UART=$UART \
     CFG_TZDRAM_START=$OPTEE_ADDR \
     -j"$J" > "$WS/out/optee.build.log" 2>&1
RC2=$?
echo "make exit: $RC2"
[ $RC2 -ne 0 ] && { echo "!!! 마지막 30줄:"; tail -30 "$WS/out/optee.build.log"; exit 1; }
TEE="$OPTEE/out/arm-plat-k3/core/tee-raw.bin"
ls -l "$TEE"

echo
echo "############################################################"
echo "# 3/3  U-Boot A53"
echo "############################################################"
rm -rf "${WS:?}/out/a53"
mkdir -p "$WS/out/a53"

if ! make -C "$UB" O="$WS/out/a53" CROSS_COMPILE=$CC64 \
        am62_pocketbeagle2_a53_defconfig > "$WS/out/a53.cfg.log" 2>&1; then
    echo "!!! defconfig 실패:"; tail -20 "$WS/out/a53.cfg.log"; exit 1
fi
echo "defconfig OK"

make -C "$UB" O="$WS/out/a53" CROSS_COMPILE=$CC64 BINMAN_INDIRS="$FW" \
     BL31="$BL31" TEE="$TEE" -j"$J" > "$WS/out/a53.build.log" 2>&1
RC3=$?
echo "make exit: $RC3"
[ $RC3 -ne 0 ] && { echo "!!! 마지막 30줄:"; tail -30 "$WS/out/a53.build.log"; exit 1; }

echo
echo "=== 산출물 ==="
ls -l "$WS/out/a53/tispl.bin" "$WS/out/a53/u-boot.img"

# 조각이 다 들어갔는지 본다. DM 이 빠져도 빌드는 통과하므로 여기서 확인한다.
echo
echo "=== tispl.bin 구성 ==="
"$WS/out/a53/tools/dumpimage" -l "$WS/out/a53/tispl.bin" 2>/dev/null \
    | grep -E "^ Image|Data Size|Load Address"

# 세 프로젝트가 서로의 주소를 각자 하드코딩한다. 어긋나도 빌드는 통과하고
# 실행 시 콘솔이 조용한 채로 멈추므로, 부팅시키기 전에 여기서 대조한다.
echo
echo "=== 주소 정합성 ==="
verify() {
    local name="$1" want="$2" got="$3"
    if [ "$want" = "$got" ]; then
        printf "  OK    %-26s %s\n" "$name" "$got"
    else
        printf "  틀림  %-26s 기대 %s, 실제 %s\n" "$name" "$want" "$got"
        FAIL=1
    fi
}
FAIL=0

UB_OPTEE=$(grep -o '^CONFIG_K3_OPTEE_LOAD_ADDR=.*' "$WS/out/a53/.config" | cut -d= -f2)
UB_SPL=$(grep -o '^CONFIG_SPL_TEXT_BASE=.*' "$WS/out/a53/.config" | cut -d= -f2)
verify "u-boot OPTEE 로드"  "$OPTEE_ADDR"   "$UB_OPTEE"
verify "u-boot A53 SPL"     "$A53_SPL_ADDR" "$UB_SPL"

DUMP="$TFA/build/k3/lite/release/bl31/bl31.dump"
for pair in "BL32_BASE:$OPTEE_ADDR" "PRELOADED_BL33_BASE:$A53_SPL_ADDR"; do
    n=${pair%%:*}; v=${pair#*:}
    if grep -q "${v#0x}" "$DUMP" 2>/dev/null; then
        printf "  OK    %-26s %s\n" "TF-A $n" "$v"
    else
        printf "  틀림  %-26s %s 가 bl31 에 없음\n" "TF-A $n" "$v"
        FAIL=1
    fi
done

TEE_ENTRY=$(${CC64}readelf -h "$OPTEE/out/arm-plat-k3/core/tee.elf" 2>/dev/null \
            | awk '/Entry point/ {print $NF}')
verify "OP-TEE entry"        "$OPTEE_ADDR"   "$TEE_ENTRY"

if [ "$FAIL" -ne 0 ]; then
    echo
    echo "주소가 어긋난다. 이 상태로 부팅시키면 콘솔이 조용한 채로 멈춘다."
    exit 1
fi

echo
echo "=== 전송 (보드가 R5 SPL 의 DFU 가젯을 띄운 상태에서) ==="
echo "  dfu-util -R -d 0451:6165 -a tispl.bin  -D out/a53/tispl.bin"
echo "  dfu-util -R -d 0451:6165 -a u-boot.img -D out/a53/u-boot.img"
