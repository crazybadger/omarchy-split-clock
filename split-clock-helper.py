#!/usr/bin/env python3
"""The split clock's small helper: everything that touches the disk or the
network, kept out of the long-lived shell.

    read NAME          print NAME's saved state (stopwatch, timer, world, alarms)
    write NAME JSON    replace NAME's saved state with JSON
    geocode QUERY      search places (Open-Meteo), print up to 5 as JSON
    offsets ZONE...    print each zone's current UTC offset in minutes

State lives in ~/.local/state/crazybadger.split-clock/ (created 0700). Every
step to it is opened relative to the one before with O_NOFOLLOW, and files
are opened, created and renamed relative to that directory's descriptor, so
a symlink planted anywhere below the home directory -- or swapped in between
a check and a use -- is refused rather than followed. The directory must be
ours and not writable by anyone else; files must be regular, ours, and
small. Output is capped, and the shell additionally runs this under a
deadline and a byte limit.
"""

import json
import os
import pwd
import stat
import sys
import urllib.parse
import urllib.request
import zoneinfo

NAMES = {"stopwatch", "timer", "world", "alarms"}
STATE_DIR = (".local", "state", "crazybadger.split-clock")
MAX_STATE = 64 * 1024
MAX_RESPONSE = 256 * 1024
MAX_QUERY = 100
MAX_FIELD = 100
MAX_ZONES = 12


def fail(msg):
    print(f"split-clock-helper: {msg}", file=sys.stderr)
    sys.exit(1)


def safe_dir(fd):
    st = os.fstat(fd)
    if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid() or st.st_mode & 0o022:
        fail("state directory not owned by you or writable by others; refusing")


def open_state_dir():
    # The home directory itself comes from the password database, not $HOME.
    home = pwd.getpwuid(os.getuid()).pw_dir
    fd = os.open(home, os.O_RDONLY | os.O_DIRECTORY)
    try:
        for i, part in enumerate(STATE_DIR):
            last = i == len(STATE_DIR) - 1
            try:
                nxt = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            except FileNotFoundError:
                try:
                    os.mkdir(part, 0o700 if last else 0o755, dir_fd=fd)
                except FileExistsError:
                    pass
                nxt = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            except OSError:
                # ELOOP / ENOTDIR: a symlink or something that isn't a directory.
                fail(f"~/{'/'.join(STATE_DIR[:i + 1])} is not a plain directory; refusing")
            os.close(fd)
            fd = nxt
            safe_dir(fd)
        return fd
    except BaseException:
        os.close(fd)
        raise


def state_name(name):
    if name not in NAMES:
        fail(f"unknown state {name!r}")
    return f"{name}.json"


def cmd_read(name):
    fname = state_name(name)
    d = open_state_dir()
    try:
        try:
            f = os.open(fname, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=d)
        except FileNotFoundError:
            return
        except OSError:
            fail(f"{fname} is not a regular file; refusing")
        try:
            st = os.fstat(f)
            if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid():
                fail(f"{fname} is not a regular file of yours; refusing")
            if st.st_size > MAX_STATE:
                fail(f"{fname} is larger than {MAX_STATE} bytes; ignoring it")
            data = os.read(f, MAX_STATE + 1)
        finally:
            os.close(f)
    finally:
        os.close(d)
    if len(data) > MAX_STATE:
        fail(f"{fname} is larger than {MAX_STATE} bytes; ignoring it")
    try:
        json.loads(data)
    except ValueError:
        fail(f"{fname} is not JSON; ignoring it")
    sys.stdout.buffer.write(data)


def cmd_write(name, text):
    fname = state_name(name)
    data = text.encode()
    if len(data) > MAX_STATE:
        fail("state too large")
    try:
        json.loads(data)
    except ValueError:
        fail("state is not JSON")
    data = data.rstrip(b"\n") + b"\n"

    d = open_state_dir()
    tmp = f".{fname}.{os.getpid()}.tmp"
    try:
        f = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=d)
        try:
            os.write(f, data)
            os.fsync(f)
        finally:
            os.close(f)
        # rename() replaces the name itself -- it never follows a symlink
        # sitting at the destination.
        os.replace(tmp, fname, src_dir_fd=d, dst_dir_fd=d)
    except BaseException:
        try:
            os.unlink(tmp, dir_fd=d)
        except OSError:
            pass
        raise
    finally:
        os.close(d)


def clean(v):
    return v.strip()[:MAX_FIELD] if isinstance(v, str) else ""


def valid_zone(z):
    if not isinstance(z, str) or not z or len(z) > 64 or ".." in z or z.startswith("/"):
        return False
    try:
        zoneinfo.ZoneInfo(z)
        return True
    except (zoneinfo.ZoneInfoNotFoundError, ValueError):
        return False


class _Refuse(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None  # the one fixed HTTPS endpoint, or nothing


NO_REDIRECTS = urllib.request.build_opener(_Refuse)


def cmd_geocode(query):
    query = query.strip()[:MAX_QUERY]
    if len(query) < 2:
        print("[]")
        return
    url = "https://geocoding-api.open-meteo.com/v1/search?" + urllib.parse.urlencode(
        {"name": query, "count": 5, "language": "en", "format": "json"})
    req = urllib.request.Request(url, headers={"User-Agent": "crazybadger.split-clock"})
    try:
        with NO_REDIRECTS.open(req, timeout=5) as resp:
            body = resp.read(MAX_RESPONSE + 1)
    except OSError as e:
        fail(f"search failed: {e}")
    if len(body) > MAX_RESPONSE:
        fail("search response too large")
    try:
        results = json.loads(body).get("results") or []
    except (ValueError, AttributeError):
        fail("search response is not JSON")

    out = []
    for r in results[:5] if isinstance(results, list) else []:
        if not isinstance(r, dict):
            continue
        name, zone = clean(r.get("name")), r.get("timezone")
        if not name or not valid_zone(zone):
            continue
        out.append({
            "name": name,
            "region": clean(r.get("admin1")),
            "country": clean(r.get("country")),
            "timezone": zone,
        })
    print(json.dumps(out))


def cmd_offsets(zones):
    from datetime import datetime, timezone
    now = datetime.now(timezone.utc)
    out = {}
    for z in zones[:MAX_ZONES]:
        if valid_zone(z):
            out[z] = int(now.astimezone(zoneinfo.ZoneInfo(z)).utcoffset().total_seconds() // 60)
    print(json.dumps(out))


def main(argv):
    os.umask(0o077)
    if len(argv) == 2 and argv[0] == "read":
        cmd_read(argv[1])
    elif len(argv) == 3 and argv[0] == "write":
        cmd_write(argv[1], argv[2])
    elif len(argv) == 2 and argv[0] == "geocode":
        cmd_geocode(argv[1])
    elif len(argv) >= 1 and argv[0] == "offsets":
        cmd_offsets(argv[1:])
    else:
        fail("usage: read NAME | write NAME JSON | geocode QUERY | offsets ZONE...")


if __name__ == "__main__":
    main(sys.argv[1:])
