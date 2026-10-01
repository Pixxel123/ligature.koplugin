#!/usr/bin/env python3
"""Run a Ligature swipe test session on a Kindle over SSH.

Installs a recorder as a KOReader user patch, prompts words to swipe on
the device, follows the recording live, then removes everything and
replays the recording through the plugin's code.
"""
import argparse
import datetime
import json
import os
import random
import re
import select
import shlex
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(ROOT, "tools")
PLUGIN = os.path.join(ROOT, "ligature.koplugin")
WORD = re.compile(r"^[a-z]{2,10}$")
# Long words, for testing how the keyboard finds them.
LONG_WORD = re.compile(r"^[a-z]{8,14}$")


def word_prompts(dictionary, count, rng, pattern=WORD):
    path = os.path.join(PLUGIN, "dictionaries", dictionary,
                        "words.buckets.tsv")
    freq = {}
    with open(path, encoding="utf-8") as tsv:
        for line in tsv:
            fields = line.rstrip("\n").split("\t")
            # The word as typed, not the letters it is filed under: "don't"
            # is filed under "dont", which is no word to prompt.
            if len(fields) >= 3 and pattern.match(fields[1]):
                freq[fields[1]] = max(freq.get(fields[1], 0), int(fields[2]))
    ranked = sorted(freq, key=lambda word: -freq[word])
    bands = [ranked[:1000], ranked[1000:5000], ranked[5000:20000]]
    bands = [band for band in bands if band]
    words = []
    for index, band in enumerate(bands):
        share = count // len(bands) + (1 if index < count % len(bands) else 0)
        words += rng.sample(band, min(share, len(band)))
    rng.shuffle(words)
    return words


def line_prompts(name, count, rng):
    """count lines drawn from tools/prompts/<name>.txt."""
    path = os.path.join(TOOLS, "prompts", name + ".txt")
    with open(path, encoding="utf-8") as text:
        lines = [line.strip() for line in text if line.strip()]
    return rng.sample(lines, min(count, len(lines)))


class Kindle:
    """The Kindle over SSH. Every command shares one connection, opened by
    connect(), so a session logs in once. KOReader's "Login without
    password" takes an empty password; unless ask_password, that is
    answered by an askpass script, so nothing asks for it at all."""

    def __init__(self, host, port, koreader, ask_password=False):
        self.host = host
        self.port = str(port)
        self.koreader = koreader
        self.dev = koreader + "/ligature-dev"
        self.patch = koreader + "/patches/2-ligature-recorder.lua"
        self.temp = tempfile.mkdtemp(prefix="ligature-ssh-")
        self.env = dict(os.environ)
        if not ask_password:
            askpass = os.path.join(self.temp, "askpass.sh")
            with open(askpass, "w") as script:
                script.write("#!/bin/sh\necho\n")
            os.chmod(askpass, 0o700)
            self.env.update(SSH_ASKPASS=askpass, SSH_ASKPASS_REQUIRE="force",
                            DISPLAY=self.env.get("DISPLAY", ":0"))
        # ControlMaster=auto: should the shared connection drop (KOReader
        # restarting its SSH server, say), a command logs in again itself.
        self.options = [
            "-o", "ControlMaster=auto",
            "-o", "ControlPath=" + os.path.join(self.temp, "control"),
            "-o", "PreferredAuthentications=publickey,password",
            # The Kindle drops connections it will not take, rather than
            # refusing them: without this, a wrong address waits minutes.
            "-o", "ConnectTimeout=10",
        ]

    def connect(self):
        """Logs in and keeps the connection open in the background for the
        commands that follow; False if the Kindle refused or is out of
        reach."""
        return subprocess.run(
            ["ssh", "-p", self.port, *self.options, "-o", "ControlPersist=yes",
             "-M", "-N", "-f", self.host],
            env=self.env, stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL).returncode == 0

    def close(self):
        subprocess.run(["ssh", "-p", self.port, *self.options, "-O", "exit",
                        self.host], env=self.env, capture_output=True)
        shutil.rmtree(self.temp, ignore_errors=True)

    def _ssh(self, command):
        return ["ssh", "-p", self.port, *self.options, self.host, command]

    def ssh(self, command, check=True):
        return subprocess.run(self._ssh(command), env=self.env,
                              check=check, capture_output=True, text=True)

    def put(self, local, remote):
        subprocess.run(["scp", "-q", "-P", self.port, *self.options, local,
                        f"{self.host}:{remote}"], env=self.env, check=True)

    def get(self, remote, local):
        return subprocess.run(["scp", "-q", "-P", self.port, *self.options,
                               f"{self.host}:{remote}", local],
                              env=self.env).returncode == 0

    def write(self, remote, text):
        subprocess.run(self._ssh(f"cat > {shlex.quote(remote)}"),
                       env=self.env, input=text, text=True, check=True)

    def follow(self):
        return subprocess.Popen(
            self._ssh(f"tail -n +1 -f "
                      f"{shlex.quote(self.dev + '/session.jsonl')}"),
            env=self.env, stdout=subprocess.PIPE, bufsize=0)


def install(kindle, prompts, mode):
    dev = shlex.quote(kindle.dev)
    kindle.ssh(f"rm -rf {dev} && mkdir -p {dev} "
               f"{shlex.quote(kindle.koreader + '/patches')}")
    kindle.put(os.path.join(TOOLS, "recorder", "recorder.lua"),
               kindle.dev + "/recorder.lua")
    kindle.write(kindle.dev + "/prompts.txt", "\n".join(prompts) + "\n")
    kindle.write(kindle.dev + "/mode", mode + "\n")
    kindle.ssh(f": > {dev}/session.jsonl && : > {dev}/recording")
    kindle.put(os.path.join(TOOLS, "recorder_patch.lua"), kindle.patch)


def uninstall(kindle):
    kindle.ssh(f"rm -f {shlex.quote(kindle.dev + '/recording')} "
               f"{shlex.quote(kindle.patch)}", check=False)
    # follow() started a remote `tail -f` over ssh with no tty; that
    # process can outlive this ssh session, so stop it explicitly rather
    # than rely on it noticing the log file is gone.
    kindle.ssh("pkill -f " + shlex.quote(
        "tail -n +1 -f " + kindle.dev + "/session.jsonl"), check=False)


def collect(kindle):
    os.makedirs(os.path.join(ROOT, "sessions"), exist_ok=True)
    stamp = datetime.datetime.now().strftime("%Y-%m-%d-%H%M%S")
    local = os.path.join(ROOT, "sessions", stamp + ".jsonl")
    if not kindle.get(kindle.dev + "/session.jsonl", local):
        print("Could not copy the session log from the Kindle.")
        return None
    kindle.ssh(f"rm -rf {shlex.quote(kindle.dev)}", check=False)
    dkjson = os.path.join(TOOLS, "dkjson.lua")
    if not os.path.exists(dkjson):
        kindle.get(kindle.koreader + "/common/dkjson.lua", dkjson)
    return local


def fetch_settings(kindle):
    """Copy the Kindle's saved settings to a temporary file, for the word
    counts the keyboard learned; None if they cannot be read. KOReader saves
    them when it exits, and the keyboard learns nothing while a session is
    recorded, so these are the counts the session ran with. The file holds
    all of KOReader's settings: the caller removes it."""
    handle, path = tempfile.mkstemp(prefix="ligature-settings-", suffix=".lua")
    os.close(handle)
    if kindle.get(kindle.koreader + "/settings.reader.lua", path):
        os.chmod(path, 0o600)
        return path
    os.remove(path)
    return None


ONE_HANDED_BELOW = 0.85


def keyboard_mode(path):
    """The keyboard's mode ("one-handed" or "full-width"), its letter
    keys' width and their span as a percent of the screen, from the
    saved session log at path; None if it cannot be told. The recorder
    reports keys only with each attempt -- there is none at the "start"
    record, before the first prompt is swiped -- so this reads the saved
    log rather than the live stream. Mirrors the span check
    tools/replay.lua's Replay.keyboardMode uses to tag sessions."""
    screen = None
    with open(path, encoding="utf-8") as log:
        for line in log:
            try:
                record = json.loads(line)
            except ValueError:
                continue
            if record.get("type") == "start":
                screen = record.get("screen")
            keys = [key for key in record.get("keys") or []
                    if len(key.get("key", "")) == 1
                    and "a" <= key["key"] <= "z"]
            if not keys or not screen:
                continue
            left = min(key["x"] for key in keys)
            right = max(key["x"] + key["w"] for key in keys)
            width = keys[0]["w"]
            # A keyboard rebuild can leave every key read at one point;
            # such a degenerate set says nothing about the mode, so keep
            # reading for a later attempt's keys.
            if right - left <= width:
                continue
            percent = 100 * (right - left) / screen[0]
            mode = ("one-handed" if percent < 100 * ONE_HANDED_BELOW
                    else "full-width")
            return mode, width, percent
    return None


def show(record, stats):
    kind = record.get("type")
    if kind == "start":
        print(f"Recording started ({record.get('prompts')} prompts). "
              "Open any text box on the Kindle and swipe what it shows.")
        print("Press Enter here to stop early.\n")
    elif kind == "attempt":
        target = record.get("target")
        if record.get("short"):
            print(f"  {target:<14} too short, typed as a tap; try again")
            return
        inserted = record.get("inserted")
        shown = [c.get("word") for c in record.get("candidates", [])]
        if inserted is None:
            print(f"  {target:<14} no word found for "
                  f"{record.get('letters')}; try again")
            return
        stats["n"] += 1
        good = (inserted or "").lower() == (target or "").lower()
        stats["top1"] += good
        mark = "✓" if good else "✗"
        others = ", ".join(w for w in shown[1:] if w)
        print(f"{mark} {target:<14} -> {inserted:<14} "
              f"[{record.get('letters')}] {others}   "
              f"{100 * stats['top1'] / stats['n']:.0f}% of {stats['n']}")
    elif kind == "outcome":
        if record.get("outcome") == "deleted":
            print("  deleted; asking for the word again")
        else:
            print(f"  picked suggestion {record.get('index')}: "
                  f"{record.get('word')}")
    elif kind == "end":
        print("\nSession finished.")


def run(kindle):
    stats = {"n": 0, "top1": 0}
    process = kindle.follow()
    started = False
    remainder = b""
    print("Restart KOReader on the Kindle now (Exit > Restart). "
          "Waiting for the recorder...")
    try:
        while True:
            ready, _, _ = select.select(
                [process.stdout] + ([sys.stdin] if started else []), [], [])
            if sys.stdin in ready:
                sys.stdin.readline()
                print("\nStopping.")
                return
            chunk = os.read(process.stdout.fileno(), 65536)
            if not chunk:
                print("Lost the connection to the Kindle.")
                return
            remainder += chunk
            lines = remainder.split(b"\n")
            remainder = lines.pop()
            for raw_line in lines:
                try:
                    record = json.loads(raw_line.decode("utf-8"))
                except ValueError:
                    continue
                started = started or record.get("type") == "start"
                show(record, stats)
                if record.get("type") == "end":
                    return
    except KeyboardInterrupt:
        print("\nStopping.")
    finally:
        process.terminate()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    kind = parser.add_mutually_exclusive_group()
    kind.add_argument("--sentences", action="store_true",
                      help="prompt short sentences instead of words")
    kind.add_argument("--queries", action="store_true",
                      help="prompt search queries: authors, titles, "
                           "characters and words looked up")
    kind.add_argument("--long", action="store_true",
                      help="prompt words of 8 to 14 letters")
    parser.add_argument("--no-replay", action="store_true",
                        help="save the session without replaying it")
    parser.add_argument("--count", type=int,
                        help="words (default 50), sentences (default 20) "
                             "or queries (default 40)")
    parser.add_argument("--seed", type=int, help="repeatable prompts")
    parser.add_argument("--dictionary", default="en")
    parser.add_argument("--host", default="root@10.0.10.166")
    parser.add_argument("--port", type=int, default=2222)
    parser.add_argument("--koreader", default="/mnt/us/koreader")
    parser.add_argument("--print-prompts", action="store_true",
                        help="print the prompts and exit")
    parser.add_argument("--ask-password", action="store_true",
                        help="ask for the Kindle's SSH password once, "
                             "instead of sending the empty password of "
                             "KOReader's \"Login without password\"")
    args = parser.parse_args()

    rng = random.Random(args.seed)
    if args.sentences:
        mode = "sentences"
        prompts = line_prompts("sentences", args.count or 20, rng)
    elif args.queries:
        mode = "queries"
        prompts = line_prompts("queries", args.count or 40, rng)
    else:
        mode = "words"
        prompts = word_prompts(args.dictionary, args.count or 50, rng,
                               LONG_WORD if args.long else WORD)
    if args.print_prompts:
        print("\n".join(prompts))
        return

    kindle = Kindle(args.host, args.port, args.koreader, args.ask_password)
    try:
        if not kindle.connect():
            print("Could not log in to the Kindle. Is KOReader's SSH server "
                  "running, with \"Login without password\" on? With a "
                  "password set, run this with --ask-password.")
            sys.exit(1)
        record(kindle, prompts, mode, args.no_replay)
    finally:
        kindle.close()


def record(kindle, prompts, mode, no_replay):
    install(kindle, prompts, mode)
    try:
        run(kindle)
    finally:
        uninstall(kindle)
        print("Recorder removed; it is gone after the next KOReader restart.")
    log = collect(kindle)
    if log:
        print(f"Saved {os.path.relpath(log, ROOT)}\n")
        mode_info = keyboard_mode(log)
        if mode_info:
            kind, width, percent = mode_info
            print(f"Keyboard: {kind} (keys {width} px, "
                  f"{percent:.0f}% of the screen)")
        if no_replay:
            return
        command = ["luajit", os.path.join(TOOLS, "replay.lua"), "--misses"]
        settings = fetch_settings(kindle)
        if settings:
            # Replay with the words the keyboard had learned, as they stood.
            command += ["--usage", "--usage-settings", settings,
                        "--no-learning"]
        try:
            subprocess.run(command + [log])
        finally:
            if settings:
                os.remove(settings)


if __name__ == "__main__":
    main()
