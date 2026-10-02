"""
Automated RR-Net tests with nettest_rrnet.prg in VICE.

    python tools/rrnet_test.py wsl  [seconds]   VICE <-> tools/netpeer.py inside WSL (Hyper-V switch)
    python tools/rrnet_test.py vice [seconds]   two VICE instances on the same Npcap adapter

Results: build/shot_rr*.png (VICE screens), build/peer_wsl.log (netpeer output).
Environment: NPCAP_IF (Npcap device, \\Device\\NPF_{InterfaceGuid} from Get-NetAdapter), C64_IP, C64_IP2.
"""
from __future__ import annotations

import os
import socket
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vicemon as vm  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WSL_DISTRO = os.environ.get("WSL_DISTRO", "Ubuntu-24.04")
IF_WSL = r"\Device\NPF_{EDFE5208-3F87-47AB-A7C5-0E25BF4E3A78}"   # vEthernet (WSL (Hyper-V firewall))
IF_WIFI = r"\Device\NPF_{BD187BD7-EF69-4A3B-B098-BEC90E6A20AA}"  # Wi-Fi


def wsl_ip() -> str:
    out = subprocess.run(["wsl", "-d", WSL_DISTRO, "--", "hostname", "-I"], capture_output=True, text=True).stdout
    return out.split()[0]


def monitor(port: int, *cmds: str) -> str:
    s = socket.create_connection(("127.0.0.1", port), timeout=5)
    out = vm.recv_all(s)
    for c in cmds:
        s.sendall((c + "\n").encode("latin-1"))
        out += vm.recv_all(s)
    s.sendall(b"x\n")
    vm.recv_all(s, 0.2)
    s.close()
    return out


def start_vice(iface: str, port: int) -> subprocess.Popen:
    return subprocess.Popen([os.path.join(vm.VICE_DIR, "x64sc.exe"), "-default", "-sounddev", "dummy",
                             "-ethernetcart", "-ethernetcartmode", "1", "-ethernetioif", iface,
                             "-remotemonitor", "-remotemonitoraddress", f"ip4://127.0.0.1:{port}",
                             "-autostart", os.path.join(ROOT, "build", "nettest_rrnet.prg")],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def type_line(port: int, text: str) -> None:
    # the monitor's keybuf understands \x0d as RETURN - the backslash must reach VICE literally
    monitor(port, "keybuf " + text + "\\x0d")


def test_wsl(seconds: float) -> None:
    iface = os.environ.get("NPCAP_IF", IF_WSL)
    me = os.environ.get("C64_IP", "172.27.211.64")
    peer_ip = wsl_ip()
    print(f"C64 {me}  <->  WSL peer {peer_ip}")
    log = open(os.path.join(ROOT, "build", "peer_wsl.log"), "w")
    peer = subprocess.Popen(["wsl", "-d", WSL_DISTRO, "--", "timeout", str(int(seconds + 25)), "python3", "-u",
                             "tools/netpeer.py", "udp", "--interval", "0.1"], cwd=ROOT, stdout=log,
                            stderr=subprocess.STDOUT)
    vice = start_vice(iface, 6510)
    try:
        time.sleep(6)
        type_line(6510, me)
        time.sleep(3)
        type_line(6510, peer_ip)
        time.sleep(seconds)
        monitor(6510, 'screenshot "build/shot_rr.png" 2')
        time.sleep(1)
    finally:
        vice.kill()
        peer.kill()
    print(open(os.path.join(ROOT, "build", "peer_wsl.log")).read()[-800:])


def test_vice(seconds: float) -> None:
    iface = os.environ.get("NPCAP_IF", IF_WIFI)
    a = os.environ.get("C64_IP", "192.168.1.201")
    b = os.environ.get("C64_IP2", "192.168.1.202")
    print(f"VICE A {a}  <->  VICE B {b}  on {iface}")
    va = start_vice(iface, 6510)
    time.sleep(4)  # starting both at the same moment makes the second one miss its monitor port
    vb = start_vice(iface, 6511)
    try:
        time.sleep(7)
        type_line(6510, a)
        type_line(6511, b)
        time.sleep(3)
        type_line(6510, b)
        type_line(6511, a)
        time.sleep(seconds)
        monitor(6510, 'screenshot "build/shot_rr_a.png" 2')
        monitor(6511, 'screenshot "build/shot_rr_b.png" 2')
        time.sleep(1)
    finally:
        va.kill()
        vb.kill()
    print("screens: build/shot_rr_a.png build/shot_rr_b.png")


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "vice"
    secs = float(sys.argv[2]) if len(sys.argv) > 2 else 20
    test_wsl(secs) if mode == "wsl" else test_vice(secs)
