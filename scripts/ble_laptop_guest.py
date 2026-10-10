"""개발 보조: 노트북을 BLE 게스트로 써서 폰의 [방 열기](호스트)를 시험한다. 합격 판정용이 아니다(합격은 폰 2대).

준비: pip install --user bleak
실행: 폰 BLE 테스트 화면에서 [방 열기] → python scripts/ble_laptop_guest.py
하는 일: 방 찾기 → 연결 → PING 5번(왕복 ms) → 2KB 보내고 폰이 돌려준 해시 비교 → 폰이 보낸 PING에 PONG 응답(10초) → 끊기.
프로토콜은 lib/ble/framing.dart, lib/ble/ble_debug_screen.dart와 같다.
"""

import asyncio
import base64
import hashlib
import json
import os
import time

from bleak import BleakClient, BleakScanner

SERVICE = "6b1f0001-6a52-4c8e-9a3e-2f2b3c4d5e60"
RX = "6b1f0002-6a52-4c8e-9a3e-2f2b3c4d5e60"  # 노트북(게스트) → 폰 write
TX = "6b1f0003-6a52-4c8e-9a3e-2f2b3c4d5e60"  # 폰 → 노트북 notify
HEADER = 5

seq = 0
msg_id = 0
parts: dict[int, dict[int, bytes]] = {}
totals: dict[int, int] = {}
inbox: asyncio.Queue = asyncio.Queue()


def split(msg: bytes, mid: int, chunk: int) -> list[bytes]:
    body = chunk - HEADER
    total = max(1, -(-len(msg) // body))
    return [bytes([mid, i >> 8, i & 0xFF, total >> 8, total & 0xFF]) + msg[i * body : (i + 1) * body] for i in range(total)]


def on_notify(_, data: bytearray):
    mid, idx, total = data[0], data[1] << 8 | data[2], data[3] << 8 | data[4]
    if totals.get(mid) != total:
        parts[mid], totals[mid] = {}, total
    parts[mid][idx] = bytes(data[HEADER:])
    if len(parts[mid]) == total:
        msg = b"".join(parts[mid][i] for i in range(total))
        del parts[mid], totals[mid]
        inbox.put_nowait(json.loads(msg))


async def send(client: BleakClient, m: dict):
    global seq, msg_id
    seq += 1
    msg_id = (msg_id + 1) & 0xFF
    chunk = min(client.mtu_size - 3, 512)
    for c in split(json.dumps({"ver": 1, "seq": seq, **m}).encode(), msg_id, chunk):
        await client.write_gatt_char(RX, c, response=True)


async def expect(kind: str, timeout=10.0) -> dict:
    end = time.monotonic() + timeout
    while True:
        m = await asyncio.wait_for(inbox.get(), max(0.1, end - time.monotonic()))
        if m["type"] == kind:
            return m
        print("  (다른 메시지)", m["type"])


async def main():
    print("방 찾는 중…")
    dev = await BleakScanner.find_device_by_filter(
        lambda d, adv: SERVICE in [u.lower() for u in adv.service_uuids], timeout=20
    )
    if not dev:
        return print("방을 못 찾음. 폰에서 [방 열기]를 눌렀는지 확인")
    async with BleakClient(dev) as client:
        print(f"연결됨, MTU {client.mtu_size}")
        await client.start_notify(TX, on_notify)
        ok = 0
        for i in range(5):
            t0 = time.monotonic()
            await send(client, {"type": "PING", "t": i})
            try:
                await expect("PONG", 5)
                ok += 1
                print(f"PING {i + 1}: 왕복 {(time.monotonic() - t0) * 1000:.0f} ms")
            except asyncio.TimeoutError:
                print(f"PING {i + 1}: 응답 없음")
        data = os.urandom(2048)
        h = hashlib.sha256(data).hexdigest()[:8]
        await send(client, {"type": "TEST", "data": base64.b64encode(data).decode()})
        ack = await expect("TEST_ACK")
        print(f"2KB: 보낸 해시 {h}, 폰 해시 {ack['hash']} → {'일치' if ack['hash'] == h else '불일치'}")
        print(f"요약: ping {ok}/5")
        print("60초 동안 폰에서 보내는 PING/2KB에 응답합니다…", flush=True)
        end = time.monotonic() + 60
        while time.monotonic() < end:
            try:
                m = await asyncio.wait_for(inbox.get(), end - time.monotonic())
            except asyncio.TimeoutError:
                break
            if m["type"] == "PING":
                await send(client, {"type": "PONG", "t": m["t"]})
                print("폰 PING → PONG 보냄")
            elif m["type"] == "TEST":
                d = base64.b64decode(m["data"])
                hh = hashlib.sha256(d).hexdigest()[:8]
                print(f"폰 2KB 받음: {len(d)}B, 해시 {hh}")
                await send(client, {"type": "TEST_ACK", "hash": hh})
    print("끊음")


asyncio.run(main())
