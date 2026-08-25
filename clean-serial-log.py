#!/usr/bin/env python3
"""시리얼 콘솔 로그에서 터미널 제어 문자를 걷어낸다.

사용법:
    ./clean-serial-log.py logs/pb2-boot-20260820.log [...]

원본 옆에 `<이름>-clean.log`를 만든다. 원본은 수정하지 않는다.

처리 내용:
    - ANSI 이스케이프 시퀀스(CSI, OSC, 2문자형) 제거
    - BEL(0x07) 제거, BS(0x08)는 앞 글자를 지우는 동작으로 반영
    - CR을 커서 복귀로 해석해 덮어쓰기를 확정한다. systemd가 "Starting X"를
      찍었다가 "[  OK  ] Started X"로 덮은 경우 최종 상태만 남는다
    - 잘린 UTF-8 바이트 제거

함정:
    커널 printk가 유저스페이스 출력 한가운데로 끼어든 줄은 분리되지 않는다.
    시리얼 콘솔 하나를 커널과 유저스페이스가 공유해서 생기는 원본의 성질이며
    제어 문자 문제가 아니다. 잘린 UTF-8 바이트와 고아 ESC도 같은 원인이다.
"""

import re
import sys
from pathlib import Path

ANSI = re.compile(
    r'\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)'   # OSC
    r'|\x1b\[[0-?]*[ -/]*[@-~]'            # CSI
    r'|\x1b[@-Z\\-_]'                      # 2문자형
)


def apply_cursor(line):
    """줄 안의 CR·BS를 실제 터미널처럼 반영한다."""
    buf, col = [], 0
    for ch in line:
        if ch == '\r':
            col = 0
        elif ch == '\b':
            col = max(0, col - 1)
        elif col < len(buf):
            buf[col] = ch
            col += 1
        else:
            buf.append(ch)
            col += 1
    return ''.join(buf).rstrip()


def clean(path):
    raw = Path(path).read_bytes()
    text = raw.decode('utf-8', errors='replace')

    broken = text.count('�')
    text = text.replace('�', '')

    ansi_hits = len(ANSI.findall(text))
    text = ANSI.sub('', text)
    text = text.replace('\x07', '')

    # 커널 printk가 시퀀스 도중에 끼어들면 ESC만 남는다. 뒤따르는 문자가
    # 유효한 시퀀스를 이루지 않으므로 위 정규식에 걸리지 않는다. 그대로
    # 두면 뷰어가 다음 글자를 삼키므로 고아 ESC만 따로 지운다.
    orphan = text.count('\x1b')
    text = text.replace('\x1b', '')

    lines = [apply_cursor(ln) for ln in text.split('\n')]
    out = Path(path).with_name(Path(path).stem + '-clean.log')
    out.write_text('\n'.join(lines), encoding='utf-8')

    print('%s -> %s' % (path, out.name))
    print('  ANSI 시퀀스 %d개, 고아 ESC %d개, 잘린 바이트 %d개 제거, %d줄'
          % (ansi_hits, orphan, broken, len(lines)))
    return out


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    for arg in sys.argv[1:]:
        clean(arg)
