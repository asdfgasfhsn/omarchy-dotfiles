#!/usr/bin/env python3
"""System metrics for denon.system, one JSON line every INTERVAL seconds.

Runs for as long as the shell reads it, and exits when its stdout closes.
Reads /proc and /sys directly; the GPU comes from nvidia-smi, or from amdgpu's
sysfs files when there is no NVIDIA card. A section that can't be read is left
out, and the panel hides it.

  {"cpu": {"total": 3.1, "cores": [..], "temp": 47.5, "load": [1.3, 2.4, 2.3]},
   "gpu": {"name": "..", "util": 5, "memUsed": 1734, "memTotal": 8192, "temp": 54, "power": 55.3},
   "mem": {"total": .., "used": .., "swapTotal": .., "swapUsed": ..},      # bytes
   "disks": [{"mount": "/", "total": .., "used": ..}]}                      # bytes
"""
import glob
import json
import os
import shutil
import subprocess
import sys
import time

INTERVAL = float(sys.argv[1]) if len(sys.argv) > 1 else 2.0


def read(path):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return ""


def cpu_times():
    times = {}
    for line in read("/proc/stat").splitlines():
        if not line.startswith("cpu"):
            break
        parts = line.split()
        values = [int(v) for v in parts[1:]]
        idle = values[3] + (values[4] if len(values) > 4 else 0)  # idle + iowait
        times[parts[0]] = (sum(values), idle)
    return times


def busy(before, after):
    total = after[0] - before[0]
    return round(100.0 * (total - (after[1] - before[1])) / total, 1) if total > 0 else 0.0


def cpu_temp():
    # AMD k10temp (Tctl) or Intel coretemp (package), in degrees C.
    for hwmon in glob.glob("/sys/class/hwmon/hwmon*"):
        if read(hwmon + "/name").strip() in ("k10temp", "coretemp", "zenpower"):
            raw = read(hwmon + "/temp1_input").strip()
            if raw:
                return round(int(raw) / 1000, 1)
    return None


def memory():
    info = {}
    for line in read("/proc/meminfo").splitlines():
        key, _, rest = line.partition(":")
        info[key] = int(rest.split()[0]) * 1024 if rest.split() else 0
    if "MemTotal" not in info:
        return None
    return {
        "total": info["MemTotal"],
        "used": info["MemTotal"] - info.get("MemAvailable", info.get("MemFree", 0)),
        "swapTotal": info.get("SwapTotal", 0),
        "swapUsed": info.get("SwapTotal", 0) - info.get("SwapFree", 0),
    }


SKIP_FS = {"squashfs", "tmpfs", "devtmpfs", "overlay", "efivarfs", "iso9660"}


def disks():
    # Real block devices, once each: btrfs subvolumes and bind mounts share a
    # device, and the shortest mount point names it ("/" over "/home").
    seen = {}
    for line in read("/proc/mounts").splitlines():
        dev, mount, fs = line.split()[:3]
        if not dev.startswith("/dev/") or fs in SKIP_FS or mount.startswith(("/boot", "/efi", "/snap")):
            continue
        mount = mount.replace("\\040", " ")
        if dev not in seen or len(mount) < len(seen[dev]):
            seen[dev] = mount
    out = []
    for mount in sorted(set(seen.values())):
        try:
            st = os.statvfs(mount)
        except OSError:
            continue
        total = st.f_blocks * st.f_frsize
        if total <= 0:
            continue
        out.append({"mount": mount, "total": total, "used": total - st.f_bavail * st.f_frsize})
    return out


def gpu():
    if shutil.which("nvidia-smi"):
        try:
            line = subprocess.run(
                ["nvidia-smi", "--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw",
                 "--format=csv,noheader,nounits"],
                capture_output=True, text=True, timeout=3).stdout.splitlines()[0]
            name, util, used, total, temp, power = [v.strip() for v in line.split(",")]
            num = lambda v: float(v) if v.replace(".", "", 1).isdigit() else None
            return {"name": name.replace("NVIDIA GeForce ", "").replace("NVIDIA ", ""), "util": num(util),
                    "memUsed": num(used), "memTotal": num(total), "temp": num(temp), "power": num(power)}
        except (OSError, IndexError, ValueError, subprocess.SubprocessError):
            pass
    for card in sorted(glob.glob("/sys/class/drm/card*/device")):
        util = read(card + "/gpu_busy_percent").strip()
        if not util:
            continue
        mib = lambda f: int(read(card + "/" + f).strip() or 0) / 1048576
        temp = None
        for hwmon in glob.glob(card + "/hwmon/hwmon*"):
            raw = read(hwmon + "/temp1_input").strip()
            temp = round(int(raw) / 1000) if raw else None
        return {"name": "AMD GPU", "util": float(util), "memUsed": mib("mem_info_vram_used"),
                "memTotal": mib("mem_info_vram_total"), "temp": temp, "power": None}
    return None


def main():
    before = cpu_times()
    time.sleep(0.5)
    while True:
        after = cpu_times()
        cores = [busy(before[k], after[k]) for k in sorted((k for k in after if k != "cpu"), key=lambda k: int(k[3:]))
                 if k in before]
        sample = {
            "cpu": {"total": busy(before.get("cpu", (0, 0)), after.get("cpu", (0, 0))), "cores": cores,
                    "temp": cpu_temp(), "load": [float(v) for v in read("/proc/loadavg").split()[:3]]},
            "mem": memory(),
            "disks": disks(),
            "gpu": gpu(),
        }
        before = after
        try:
            sys.stdout.write(json.dumps(sample, separators=(",", ":")) + "\n")
            sys.stdout.flush()
        except BrokenPipeError:
            # The reader went away: point stdout at /dev/null so the exit is quiet.
            os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
            return
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
