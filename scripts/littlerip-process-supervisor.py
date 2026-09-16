#!/usr/bin/env python3
"""Run one LittleRip stage with timeout and process-group cancellation.

The parent Pi command kills only its direct child. This supervisor therefore
owns a new process group for the real stage and forwards TERM/INT/HUP to that
whole group, waits briefly, then uses KILL and reaps the child if necessary.
"""

from __future__ import annotations

import os
import signal
import subprocess
import sys
import time
from typing import Optional


if len(sys.argv) < 3:
    print("usage: littlerip-process-supervisor.py TIMEOUT COMMAND [ARGS...]", file=sys.stderr)
    raise SystemExit(2)

try:
    timeout_seconds = float(sys.argv[1])
except ValueError:
    print("invalid timeout", file=sys.stderr)
    raise SystemExit(2)

argv = sys.argv[2:]
child: Optional[subprocess.Popen[bytes]] = None
termination_signal: Optional[int] = None
termination_deadline: Optional[float] = None
TERM_GRACE_SECONDS = 2.0


def signal_group(sig: int) -> None:
    if child is None:
        return
    # The process-group leader may exit before a stubborn descendant. Keep
    # addressing the original PGID so descendants cannot outlive the stage.
    try:
        os.killpg(child.pid, sig)
    except ProcessLookupError:
        pass


def request_termination(sig: int, _frame: object) -> None:
    global termination_deadline, termination_signal
    if termination_signal is None:
        termination_signal = sig
        termination_deadline = time.monotonic() + TERM_GRACE_SECONDS
        signal_group(signal.SIGTERM)


for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
    signal.signal(sig, request_termination)

try:
    child = subprocess.Popen(argv, start_new_session=True)
except OSError as exc:
    print(str(exc), file=sys.stderr)
    raise SystemExit(127)

started = time.monotonic()
exit_code: Optional[int] = None
child_exit_code: Optional[int] = None
while exit_code is None:
    now = time.monotonic()
    if termination_signal is not None:
        # Never reuse the original stage deadline after cancellation. Poll in
        # short slices so a SIGTERM that interrupts wait() cannot postpone the
        # TERM->KILL escalation when the root ignores TERM.
        remaining = max(0.0, (termination_deadline or now) - now)
        if remaining <= 0.0:
            # Always kill the original PGID, even when the root exited while a
            # stubborn descendant remained alive in that group.
            signal_group(signal.SIGKILL)
            if child_exit_code is None:
                child.wait()
            exit_code = 124 if termination_signal == signal.SIGALRM else 143
            break
        wait_timeout = min(0.1, remaining)
    else:
        remaining = timeout_seconds - (now - started)
        if remaining <= 0.0:
            # A timed-out command gets the same process-group escalation as
            # cancellation, but retains the conventional timeout exit code.
            termination_signal = signal.SIGALRM
            termination_deadline = time.monotonic() + TERM_GRACE_SECONDS
            signal_group(signal.SIGTERM)
            continue
        wait_timeout = min(0.1, remaining)

    if child_exit_code is not None:
        # The root has exited, but keep the two-second grace window so the
        # original process group can still be force-killed before return.
        time.sleep(wait_timeout)
        continue

    try:
        code = child.wait(timeout=wait_timeout)
        if termination_signal is None:
            exit_code = code
        else:
            # Do not leave the loop yet: descendants can outlive the root.
            child_exit_code = code
    except subprocess.TimeoutExpired:
        continue
    except InterruptedError:
        # The signal handler has set termination_deadline and sent TERM. Loop
        # immediately so the new two-second cancellation deadline is honored.
        continue

if termination_signal is not None and termination_signal != signal.SIGALRM:
    raise SystemExit(130 if termination_signal == signal.SIGINT else 129 if termination_signal == signal.SIGHUP else 143)

raise SystemExit(exit_code if exit_code is not None else 124)
