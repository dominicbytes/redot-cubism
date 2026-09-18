# SPDX-License-Identifier: MIT
"""Own and bound one Redot child process; never leave its descendants running."""

import ctypes
from ctypes import wintypes
from contextlib import ExitStack
import os
from pathlib import Path
import signal
import subprocess
import threading
import time


MEMORY_LIMIT = 2 * 1024 * 1024 * 1024
LOG_LIMIT = 256 * 1024
RESULT_LIMIT = 8 * 1024 * 1024
REGULAR_TIMEOUT = 8
BOUNDARY_TIMEOUT = 20
CAMPAIGN_TIMEOUT = 35 * 60
PREFLIGHT_TIMEOUT = 90


if os.name == "nt":
    class IO_COUNTERS(ctypes.Structure):
        _fields_ = [(name, ctypes.c_ulonglong) for name in (
            "ReadOperationCount", "WriteOperationCount", "OtherOperationCount",
            "ReadTransferCount", "WriteTransferCount", "OtherTransferCount")]


    class BASIC_LIMITS(ctypes.Structure):
        _fields_ = [
            ("PerProcessUserTimeLimit", ctypes.c_longlong),
            ("PerJobUserTimeLimit", ctypes.c_longlong),
            ("LimitFlags", wintypes.DWORD),
            ("MinimumWorkingSetSize", ctypes.c_size_t),
            ("MaximumWorkingSetSize", ctypes.c_size_t),
            ("ActiveProcessLimit", wintypes.DWORD),
            ("Affinity", ctypes.c_size_t),
            ("PriorityClass", wintypes.DWORD),
            ("SchedulingClass", wintypes.DWORD),
        ]


    class EXTENDED_LIMITS(ctypes.Structure):
        _fields_ = [("BasicLimitInformation", BASIC_LIMITS), ("IoInfo", IO_COUNTERS),
                    ("ProcessMemoryLimit", ctypes.c_size_t), ("JobMemoryLimit", ctypes.c_size_t),
                    ("PeakProcessMemoryUsed", ctypes.c_size_t), ("PeakJobMemoryUsed", ctypes.c_size_t)]


    class PROCESS_MEMORY_COUNTERS_EX(ctypes.Structure):
        _fields_ = [("cb", wintypes.DWORD), ("PageFaultCount", wintypes.DWORD),
                    ("PeakWorkingSetSize", ctypes.c_size_t), ("WorkingSetSize", ctypes.c_size_t),
                    ("QuotaPeakPagedPoolUsage", ctypes.c_size_t), ("QuotaPagedPoolUsage", ctypes.c_size_t),
                    ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t), ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                    ("PagefileUsage", ctypes.c_size_t), ("PeakPagefileUsage", ctypes.c_size_t),
                    ("PrivateUsage", ctypes.c_size_t)]


    KERNEL = ctypes.WinDLL("kernel32", use_last_error=True)
    PSAPI = ctypes.WinDLL("psapi", use_last_error=True)
    KERNEL.CreateJobObjectW.argtypes = (ctypes.c_void_p, wintypes.LPCWSTR)
    KERNEL.CreateJobObjectW.restype = wintypes.HANDLE
    KERNEL.SetInformationJobObject.argtypes = (wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD)
    KERNEL.SetInformationJobObject.restype = wintypes.BOOL
    KERNEL.QueryInformationJobObject.argtypes = (wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p,
                                                  wintypes.DWORD, ctypes.c_void_p)
    KERNEL.QueryInformationJobObject.restype = wintypes.BOOL
    KERNEL.AssignProcessToJobObject.argtypes = (wintypes.HANDLE, wintypes.HANDLE)
    KERNEL.AssignProcessToJobObject.restype = wintypes.BOOL
    KERNEL.TerminateJobObject.argtypes = (wintypes.HANDLE, wintypes.UINT)
    KERNEL.TerminateJobObject.restype = wintypes.BOOL
    KERNEL.CloseHandle.argtypes = (wintypes.HANDLE,)
    KERNEL.CloseHandle.restype = wintypes.BOOL
    PSAPI.GetProcessMemoryInfo.argtypes = (wintypes.HANDLE, ctypes.c_void_p, wintypes.DWORD)
    PSAPI.GetProcessMemoryInfo.restype = wintypes.BOOL


class ProcessOwner:
    def __init__(self):
        self.handle = None
        self.assigned = False
        self.actual_limits = {"memory_bytes": MEMORY_LIMIT,
                              "method": "Windows JobObject" if os.name == "nt" else "Unix RLIMIT_AS"}
        if os.name == "nt":
            self.handle = KERNEL.CreateJobObjectW(None, None)
            if not self.handle:
                raise OSError(ctypes.get_last_error(), "CreateJobObjectW failed")
            limits = EXTENDED_LIMITS()
            limits.BasicLimitInformation.LimitFlags = 0x200 | 0x2000  # JOB_MEMORY, KILL_ON_JOB_CLOSE
            limits.JobMemoryLimit = MEMORY_LIMIT
            if not KERNEL.SetInformationJobObject(self.handle, 9, ctypes.byref(limits), ctypes.sizeof(limits)):
                error = ctypes.get_last_error()
                KERNEL.CloseHandle(self.handle)
                self.handle = None
                raise OSError(error, "SetInformationJobObject failed")
            checked = EXTENDED_LIMITS()
            if not KERNEL.QueryInformationJobObject(self.handle, 9, ctypes.byref(checked),
                                                      ctypes.sizeof(checked), None):
                error = ctypes.get_last_error()
                KERNEL.CloseHandle(self.handle)
                self.handle = None
                raise OSError(error, "QueryInformationJobObject failed")
            flags = checked.BasicLimitInformation.LimitFlags
            if checked.JobMemoryLimit != MEMORY_LIMIT or flags & (0x200 | 0x2000) != (0x200 | 0x2000):
                KERNEL.CloseHandle(self.handle)
                self.handle = None
                raise RuntimeError("Windows JobObject limits did not take effect")
            self.actual_limits["flags"] = int(flags)

    def attach(self, process):
        if os.name == "nt":
            if not KERNEL.AssignProcessToJobObject(self.handle, wintypes.HANDLE(process._handle)):
                raise OSError(ctypes.get_last_error(), "AssignProcessToJobObject failed")
        self.assigned = True

    def peak_bytes(self, process):
        if os.name == "nt":
            counters = PROCESS_MEMORY_COUNTERS_EX()
            counters.cb = ctypes.sizeof(counters)
            if PSAPI.GetProcessMemoryInfo(wintypes.HANDLE(process._handle), ctypes.byref(counters), counters.cb):
                return int(counters.PeakWorkingSetSize)
            return 0
        try:
            status = Path(f"/proc/{process.pid}/status").read_text(encoding="ascii")
            for line in status.splitlines():
                if line.startswith("VmHWM:"):
                    return int(line.split()[1]) * 1024
        except OSError:
            pass
        return 0

    def stop(self, process):
        if os.name == "nt":
            if self.assigned:
                KERNEL.TerminateJobObject(self.handle, 1)
            elif process.poll() is None:
                process.kill()
        else:
            # The group may still contain descendants after its leader exits.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        process.wait(timeout=5)

    def peak_job_bytes(self):
        if os.name != "nt":
            return 0
        checked = EXTENDED_LIMITS()
        if KERNEL.QueryInformationJobObject(self.handle, 9, ctypes.byref(checked),
                                              ctypes.sizeof(checked), None):
            return int(checked.PeakJobMemoryUsed)
        return 0

    def close(self):
        if self.handle is not None:
            KERNEL.CloseHandle(self.handle)  # KILL_ON_JOB_CLOSE also removes descendants.
            self.handle = None


def _unix_limit():
    import resource
    resource.setrlimit(resource.RLIMIT_AS, (MEMORY_LIMIT, MEMORY_LIMIT))


def run_owned(command, *, cwd, env, log_path, result_path=None, ready_path=None,
              stop_path=None, timeout=REGULAR_TIMEOUT, job_required=True, on_start=None):
    """Capture at most LOG_LIMIT bytes; gate fuzz calls until Job assignment."""
    if stop_path is not None and Path(stop_path).exists():
        raise RuntimeError("stop requested before child launch")
    if ready_path is not None and not job_required:
        raise ValueError("a gated worker requires Job assignment")
    owner = ProcessOwner()
    process = None
    violation = None
    peak = 0
    peak_job = 0
    pipe_thread = None
    pipe_overflow = threading.Event()
    pipe_errors = []
    start = time.monotonic()
    def finish_owned():
        try:
            if process is not None and (os.name != "nt" or process.poll() is None):
                owner.stop(process)
        finally:
            if pipe_thread is not None:
                pipe_thread.join(timeout=5)

    try:
        with ExitStack() as stack:
            log = stack.enter_context(open(log_path, "wb"))
            stack.callback(finish_owned)  # Stop descendants and drain before closing the log.
            process = subprocess.Popen(
                command, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=0,
                creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
                start_new_session=os.name != "nt",
                preexec_fn=_unix_limit if os.name != "nt" else None,
            )
            def drain():
                written = 0
                try:
                    while True:
                        chunk = process.stdout.read(4096)
                        if not chunk:
                            break
                        room = LOG_LIMIT - written
                        if room > 0:
                            log.write(chunk[:room])
                            written += min(room, len(chunk))
                        if len(chunk) > room:
                            pipe_overflow.set()
                            break
                    log.flush()
                except (OSError, ValueError) as exc:
                    pipe_errors.append(repr(exc))
                finally:
                    process.stdout.close()

            pipe_thread = threading.Thread(target=drain, name="fuzz-log-drain", daemon=True)
            pipe_thread.start()
            try:
                if job_required:
                    owner.attach(process)
            except OSError:
                process.kill()  # Assignment failed: the child is not in our Job.
                process.wait(timeout=5)
                raise
            if ready_path is not None:
                Path(ready_path).write_text("assigned\n", encoding="ascii")
            if on_start is not None:
                on_start(process.pid)
            while process.poll() is None:
                peak = max(peak, owner.peak_bytes(process))
                if time.monotonic() - start > timeout:
                    violation = "timeout"
                elif stop_path is not None and Path(stop_path).exists():
                    violation = "stop_requested"
                elif pipe_overflow.is_set():
                    violation = "log_limit"
                elif result_path is not None and Path(result_path).exists() and Path(result_path).stat().st_size > RESULT_LIMIT:
                    violation = "result_poll_limit"
                if violation:
                    owner.stop(process)
                    break
                time.sleep(0.02)
            peak = max(peak, owner.peak_bytes(process))
            code = process.wait(timeout=5)
            if os.name != "nt":
                owner.stop(process)  # A leader may exit while descendants still own stdout.
            pipe_thread.join(timeout=5)
            if pipe_thread.is_alive() or pipe_errors:
                violation = violation or "log_reader_failure"
            if pipe_overflow.is_set():
                violation = violation or "log_limit"
            peak_job = owner.peak_job_bytes()
    finally:
        owner.close()  # KILL_ON_JOB_CLOSE even if stop/wait raised.
    return {"exit_code": code, "violation": violation, "elapsed_seconds": round(time.monotonic() - start, 3),
            "peak_working_set_bytes": peak, "peak_job_memory_bytes": peak_job,
            "limits": owner.actual_limits, "job_assigned": owner.assigned, "pid": process.pid}
