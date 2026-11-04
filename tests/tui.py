#!/usr/bin/env python3
"""Drive a real Neovim TUI and nested PTY with physical key bytes. No Python deps."""
import errno
import fcntl
import os
from pathlib import Path
import pty
import select
import signal
import struct
import subprocess
import tempfile
import termios
import time

ROOT = Path(__file__).resolve().parent.parent


def run():
    with tempfile.TemporaryDirectory(prefix="task-tools-", dir="/private/tmp" if Path("/private/tmp").exists() else None) as directory:
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 32, 110, 0, 0))
        env = dict(os.environ, TERM="xterm-256color", TASK_TOOLS_TEST_DIR=directory,
                   NVIM_LOG_FILE=directory + "/nvim.log")
        configured = env.get("TASK_TOOLS_CONFIGURED") == "1"
        if configured:
            env.update(NVIM_SMOKE_TEST="1", XDG_STATE_HOME=directory + "/state", XDG_CACHE_HOME=directory + "/cache")
        args = [] if configured else ["-u", "NONE"]
        process = subprocess.Popen([env.get("NVIM_BIN", "nvim"), *args, "-n", "-i", "NONE", "-c", "lua dofile('tests/tui.lua')"],
                                   cwd=ROOT, env=env, stdin=slave, stdout=slave, stderr=slave)
        os.close(slave)
        actions = {
            "list": b":TaskOpen\r", "output": b"\r", "jump": b"\r",
            "terminal_input": b"hello from PTY\r", "terminal_normal": b"\x1d", "hide": b"q",
            "reopen": b"\x1b[17~", "size_input": b"next\r", "finish": b"last\r",
            "save": b"Go// saved by TUI\x1b:w\r",
        }
        handled, output = set(), bytearray()
        deadline = time.monotonic() + (60 if configured else 35)
        try:
            while process.poll() is None and time.monotonic() < deadline:
                if select.select([master], [], [], 0.02)[0]:
                    try:
                        output.extend(os.read(master, 65536))
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                file = Path(directory, "stage")
                stage = file.read_text().strip() if file.exists() else ""
                if stage in handled:
                    continue
                if stage in actions:
                    os.write(master, actions[stage])
                    handled.add(stage)
                elif stage == "resize":
                    fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 25, 72, 0, 0))
                    os.kill(process.pid, signal.SIGWINCH)
                    handled.add(stage)
            if process.poll() is None:
                process.kill()
                raise AssertionError("TUI timeout: " + repr(handled) + "\n" + output.decode(errors="replace")[-4000:])
            file = Path(directory, "result")
            result = file.read_text() if file.exists() else "No result"
            assert process.returncode == 0 and result.startswith("PASS"), result + "\n" + output.decode(errors="replace")[-4000:]
            print(result.splitlines()[0] + (" (configured)" if configured else " (clean)"))
        finally:
            if process.poll() is None:
                process.kill()
            process.wait()
            os.close(master)


if __name__ == "__main__":
    run()
