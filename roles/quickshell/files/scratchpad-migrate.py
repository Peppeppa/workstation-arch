#!/usr/bin/env python3
# Managed by Ansible (roles/quickshell/files/scratchpad-migrate.py) - run by
# the bootstrap as the user, never at runtime.
#
# scratchpad-migrate.py OLD_DIR NEW_FILE [--check]
#
# Moves the scratchpad from the former four files OLD_DIR/{1..4}.txt into ONE
# Markdown file NEW_FILE (format = ScratchpadWindow.qml composeNotes: a
# marker line "<!-- scratchpad note N -->" before each note, each note
# followed by one newline). Safe by construction:
#   - the old files are never changed or deleted; a marker file
#     OLD_DIR/MIGRATED records the migration (later runs do nothing)
#   - NEW_FILE is written only when it does not exist yet (atomically)
#   - NEW_FILE exists, no marker: same notes -> just the marker; different
#     notes -> nothing is written, exit 3 + "ACTION REQUIRED" (the user
#     decides; the bootstrap stops before the new scratchpad is deployed)
# Output: one word - unchanged | migrated | adopted | conflict (with --check:
# what WOULD happen, nothing written). Exit 0, or 3 on conflict.
import os
import re
import sys
import tempfile

COUNT = 4
MARKER = re.compile(r"^<!-- scratchpad note ([1-9]) -->$")


def compose(notes):
    return "".join("<!-- scratchpad note %d -->\n%s\n" % (i + 1, t) for i, t in enumerate(notes))


def parse(text):
    """Same rules as ScratchpadWindow.qml parseNotes."""
    out = [""] * COUNT
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    cur, buf, started = 0, [], False

    def commit():
        t = "\n".join(buf)
        out[cur] = t if out[cur] == "" else (out[cur] if t == "" else out[cur] + "\n" + t)

    for line in lines:
        m = MARKER.match(line)
        if m and 1 <= int(m.group(1)) <= COUNT:
            if started or buf:
                commit()
            cur, buf, started = int(m.group(1)) - 1, [], True
        else:
            buf.append(line)
    if started or buf:
        commit()
    return out


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return None


def write_atomic(path, text):
    d = os.path.dirname(path)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".scratchpad-migrate-")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(text)
        f.flush()
        os.fsync(f.fileno())
    os.chmod(tmp, 0o600)
    os.rename(tmp, path)


def main():
    args = [a for a in sys.argv[1:] if a != "--check"]
    check = "--check" in sys.argv[1:]
    if len(args) != 2:
        sys.exit("usage: scratchpad-migrate.py OLD_DIR NEW_FILE [--check]")
    old_dir, new_file = args
    marker = os.path.join(old_dir, "MIGRATED")

    if os.path.exists(marker):
        print("unchanged")
        return 0
    old = [read(os.path.join(old_dir, "%d.txt" % (i + 1))) for i in range(COUNT)]
    if all(t is None for t in old):
        print("unchanged")          # never used the old scratchpad: nothing to move
        return 0
    old = [t or "" for t in old]
    current = read(new_file)

    def mark(what):
        if not check:
            with open(marker, "w", encoding="utf-8") as f:
                f.write("%s -> %s\n" % (what, new_file))
        print(what)

    if current is None:
        if not check:
            write_atomic(new_file, compose(old))
        mark("migrated")
        return 0
    if parse(current) == old:
        mark("adopted")
        return 0
    print("conflict")
    print("ACTION REQUIRED: %s already exists with other notes than %s/{1..4}.txt - "
          "nothing was changed. Merge them by hand into %s, then: touch %s"
          % (new_file, old_dir, new_file, marker), file=sys.stderr)
    return 3


if __name__ == "__main__":
    sys.exit(main())
