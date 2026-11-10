"""Quick Share (Android's Nearby Share) over Wi-Fi, for memora-share.

Phones and tablets with Quick Share see this computer in their share sheet
and can send it files; this computer sees the Android devices around it and
sends files to them, all on the same Wi-Fi, end-to-end encrypted, with the
same 4-digit PIN shown on both screens.

The protocol, as reverse engineered by NearDrop (github.com/grishka/NearDrop,
PROTOCOL.md): an mDNS service `_FC9F5ED42C8A._tcp`, then over TCP: a
connection request, a UKEY2 key exchange (P-256), and frames encrypted with
AES-256-CBC + HMAC-SHA256 carrying the "Nearby Connections" payload layer,
inside which the "Sharing" frames (introduction, response) and the files go.
Android only answers on mDNS after it hears a Quick Share BLE beacon, so
while you look for devices this computer sends that beacon too (BlueZ).

The protobuf messages are few and small, so they're written by hand here
(field numbers from NearDrop's .proto files) rather than generated.
"""
import base64
import hashlib
import hmac
import os
import queue
import secrets
import socket
import struct
import subprocess
import threading
import time

from cryptography.hazmat.primitives import hashes, padding
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

PORT = 53318
SERVICE = "_FC9F5ED42C8A._tcp.local."
MAX_FRAME = 5 * 1024 * 1024
CHUNK = 512 * 1024
KEEPALIVE = 10            # seconds; Android hangs up if it hears nothing for longer
ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
TYPES = {1: "mobile", 2: "tablet", 3: "desktop", 5: "mobile"}   # endpoint device type -> sheet icon


# ----------------------------------------------------------------- protobuf ---
def _varint(v):
    v &= (1 << 64) - 1
    out = bytearray()
    while True:
        b, v = v & 0x7F, v >> 7
        if v:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def pb(*fields):
    """A message from (number, value) pairs: ints and bools are varints, bytes
    and str length-delimited (nested messages are bytes), lists repeat, None is left out."""
    out = bytearray()
    for num, val in fields:
        if val is None:
            continue
        for v in (val if isinstance(val, list) else [val]):
            if isinstance(v, (bool, int)):
                out += _varint(num << 3) + _varint(int(v))
            else:
                v = v.encode() if isinstance(v, str) else bytes(v)
                out += _varint(num << 3 | 2) + _varint(len(v)) + v
    return bytes(out)


class Msg(dict):
    """A parsed message: field number -> list of raw values."""

    def int(self, n, default=0):
        v = self.get(n)
        if not v or not isinstance(v[0], int):
            return default
        return v[0] - (1 << 64) if v[0] >= 1 << 63 else v[0]

    def bytes(self, n, default=b""):
        v = self.get(n)
        return v[0] if v and isinstance(v[0], bytes) else default

    def str(self, n, default=""):
        return self.bytes(n).decode("utf-8", "replace") if n in self else default

    def sub(self, n):
        return parse(self.bytes(n))

    def subs(self, n):
        return [parse(v) for v in self.get(n, []) if isinstance(v, bytes)]


def _read_varint(b, i):
    shift = v = 0
    while True:
        if i >= len(b) or shift > 63:
            raise ValueError("bad varint")
        c = b[i]
        i += 1
        v |= (c & 0x7F) << shift
        if not c & 0x80:
            return v, i
        shift += 7


def parse(b):
    m, i = Msg(), 0
    while i < len(b):
        key, i = _read_varint(b, i)
        num, wt = key >> 3, key & 7
        if wt == 0:
            v, i = _read_varint(b, i)
        elif wt == 2:
            n, i = _read_varint(b, i)
            if i + n > len(b):
                raise ValueError("truncated")
            v, i = bytes(b[i:i + n]), i + n
        elif wt == 1:
            v, i = bytes(b[i:i + 8]), i + 8
        elif wt == 5:
            v, i = bytes(b[i:i + 4]), i + 4
        else:
            raise ValueError("bad wire type")
        m.setdefault(num, []).append(v)
    return m


# Nearby Connections "offline frames" (offline_wire_formats.proto).
def offline(ftype, field=None, body=None):
    return pb((1, 1), (2, pb((1, ftype), (field, body) if field else (0, None))))


def connection_request(endpoint_id, name, info):
    return offline(1, 2, pb((1, endpoint_id), (2, name), (5, [5]), (6, info)))   # medium 5 = Wi-Fi LAN


def connection_response():
    return offline(2, 3, pb((1, 0), (3, 1), (4, pb((1, 100)))))   # accept; OS: Linux


def keep_alive(ack=False):
    return offline(5, 6, pb((1, ack)))


def disconnection():
    return offline(6, 7, b"")


def payload(pid, ptype, total, offset, body, last):
    header = pb((1, pid), (2, ptype), (3, total), (4, False))
    chunk = pb((1, 1 if last else 0), (2, offset), (3, body or None))
    return offline(3, 4, pb((1, 1), (2, header), (3, chunk)))


# Sharing frames (wire_format.proto), sent as BYTES payloads.
def sharing(ftype, field=None, body=None):
    return pb((1, 1), (2, pb((1, ftype), (field, body) if field else (0, None))))


PAIRED_KEY_ENCRYPTION = lambda: sharing(3, 4, pb((1, os.urandom(72)), (2, os.urandom(6))))
PAIRED_KEY_RESULT = lambda: sharing(4, 5, pb((1, 3)))   # UNABLE: no Google account pairing here
RESPONSE = lambda status: sharing(2, 3, pb((1, status)))
CANCEL = lambda: sharing(6)
INTRO, RESP, PKE, PKR, CANCEL_T = 1, 2, 3, 4, 6


# --------------------------------------------------------------- endpoints ---
def b64(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def unb64(s):
    s = s.decode() if isinstance(s, bytes) else s
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def endpoint_info(name, device_type=3):
    raw = name.encode()[:255]
    return bytes([device_type << 1]) + os.urandom(16) + bytes([len(raw)]) + raw


def read_endpoint_info(b):
    """(name or None if hidden, device type)."""
    if len(b) < 17:
        return None, 0
    dtype = (b[0] & 7) >> 1
    if b[0] & 0x10 or len(b) < 18:
        return None, dtype
    n = b[17]
    if len(b) < 18 + n:
        return None, dtype
    return b[18:18 + n].decode("utf-8", "replace"), dtype


def pin_code(auth):
    h, mult = 0, 1
    for byte in auth:
        s = byte - 256 if byte > 127 else byte
        h = (h + s * mult) % 9973
        mult = (mult * 31) % 9973
    return f"{abs(h):04d}"


# ------------------------------------------------------------- encryption ---
def _hkdf(ikm, salt, info, n=32):
    return HKDF(algorithm=hashes.SHA256(), length=n, salt=salt, info=info).derive(ikm)


def _coord(n):
    b = n.to_bytes(32, "big")
    return b"\x00" + b if b[0] & 0x80 else b      # protobuf wants it as a signed big integer


def public_key_message(priv):
    nums = priv.public_key().public_numbers()
    return pb((1, 1), (2, pb((1, _coord(nums.x)), (2, _coord(nums.y)))))


class Ukey2Error(Exception):
    pass


class Conn:
    """One TCP connection: length-prefixed frames, then the SecureMessage
    layer and the payload layer once the keys are known."""

    def __init__(self, sock):
        self.sock = sock
        self.wlock = threading.Lock()
        self.seq_out = self.seq_in = 0
        self.keys = None
        self.events = queue.Queue(maxsize=64)   # a sender waits for us, instead of filling memory
        self.closed = threading.Event()
        self.pin = ""

    # -- raw frames
    def _exact(self, n):
        buf = bytearray()
        while len(buf) < n:
            c = self.sock.recv(min(n - len(buf), 1 << 20))
            if not c:
                raise ConnectionError("closed")
            buf += c
        return bytes(buf)

    def recv_raw(self):
        (n,) = struct.unpack(">I", self._exact(4))
        if n > MAX_FRAME:
            raise ValueError("frame too large")
        return self._exact(n)

    def send_raw(self, data):
        with self.wlock:
            self.sock.sendall(struct.pack(">I", len(data)) + data)

    # -- keys (UKEY2 result -> SecureMessage keys)
    def derive(self, priv, peer_key, client_init, server_init, server):
        gp = parse(peer_key)
        if gp.int(1) != 1:
            raise Ukey2Error("not a P-256 key")
        pt = gp.sub(2)
        x, y = int.from_bytes(pt.bytes(1)[-32:], "big"), int.from_bytes(pt.bytes(2)[-32:], "big")
        try:
            pub = ec.EllipticCurvePublicNumbers(x, y, ec.SECP256R1()).public_key()
        except ValueError:
            raise Ukey2Error("bad public key")
        dhs = hashlib.sha256(priv.exchange(ec.ECDH(), pub)).digest()
        info = client_init + server_init
        auth = _hkdf(dhs, b"UKEY2 v1 auth", info)
        nxt = _hkdf(dhs, b"UKEY2 v1 next", info)
        d2d = hashlib.sha256(b"D2D").digest()
        client, srv = _hkdf(nxt, d2d, b"client"), _hkdf(nxt, d2d, b"server")
        sm = hashlib.sha256(b"SecureMessage").digest()
        ck, cm = _hkdf(client, sm, b"ENC:2"), _hkdf(client, sm, b"SIG:1")
        sk, sms = _hkdf(srv, sm, b"ENC:2"), _hkdf(srv, sm, b"SIG:1")
        self.keys = (sk, sms, ck, cm) if server else (ck, cm, sk, sms)   # (encrypt, send hmac, decrypt, receive hmac)
        self.pin = pin_code(auth)

    # -- encrypted frames
    def send(self, frame):
        enc, sig = self.keys[0], self.keys[1]
        with self.wlock:
            self.seq_out += 1
            plain = pb((1, frame), (2, self.seq_out))
            iv = os.urandom(16)
            p = padding.PKCS7(128).padder()
            e = Cipher(algorithms.AES(enc), modes.CBC(iv)).encryptor()
            body = e.update(p.update(plain) + p.finalize()) + e.finalize()
            header = pb((1, 1), (2, 2), (5, iv), (6, pb((1, 13), (2, 1))))   # HMAC-SHA256, AES-256-CBC, D2D message v1
            hb = pb((1, header), (2, body))
            msg = pb((1, hb), (2, hmac.new(sig, hb, hashlib.sha256).digest()))
            self.sock.sendall(struct.pack(">I", len(msg)) + msg)

    def recv(self):
        dec, sig = self.keys[2], self.keys[3]
        sm = parse(self.recv_raw())
        hb = sm.bytes(1)
        if not hmac.compare_digest(hmac.new(sig, hb, hashlib.sha256).digest(), sm.bytes(2)):
            raise ValueError("bad signature")
        hbm = parse(hb)
        iv, body = hbm.sub(1).bytes(5), hbm.bytes(2)
        if len(iv) != 16 or not body or len(body) % 16:
            raise ValueError("bad message")
        d = Cipher(algorithms.AES(dec), modes.CBC(iv)).decryptor()
        u = padding.PKCS7(128).unpadder()
        plain = u.update(d.update(body) + d.finalize()) + u.finalize()
        d2d = parse(plain)
        self.seq_in += 1
        if d2d.int(2) != self.seq_in:
            raise ValueError("out of order")
        return parse(d2d.bytes(1))

    def send_bytes(self, data, pid=None):
        """A BYTES payload, the way Android sends them: all of it, then an empty last chunk."""
        pid = pid if pid is not None else secrets.randbits(63)
        self.send(payload(pid, 1, len(data), 0, data, False))
        self.send(payload(pid, 1, len(data), len(data), b"", True))

    # -- after the handshake: one thread reads, one keeps the line alive
    def start(self):
        threading.Thread(target=self._reader, daemon=True).start()
        threading.Thread(target=self._alive, daemon=True).start()

    def _alive(self):
        while not self.closed.wait(KEEPALIVE):
            try:
                self.send(keep_alive())
            except OSError:
                return

    def _emit(self, ev):
        while not self.closed.is_set():
            try:
                return self.events.put(ev, timeout=1)
            except queue.Full:
                pass

    def _reader(self):
        buffers = {}
        try:
            while True:
                v1 = self.recv().sub(2)
                t = v1.int(1)
                if t == 5:                                   # keep-alive
                    if not v1.sub(6).int(1):
                        self.send(keep_alive(True))
                elif t == 6:                                 # they hung up
                    self._emit(("disconnect",))
                    return
                elif t == 3:
                    pt = v1.sub(4)
                    h, c = pt.sub(2), pt.sub(3)
                    pid, ptype, total = h.int(1), h.int(2), h.int(3)
                    off, flags, body = c.int(2), c.int(1), c.bytes(3)
                    if pt.int(1) != 1:                       # control packets (cancel, errors)
                        if pt.sub(4).int(1) in (1, 2):
                            self._emit(("cancel",))
                        continue
                    if ptype == 1:
                        if total > MAX_FRAME:
                            raise ValueError("payload too large")
                        if pid not in buffers and len(buffers) >= 8:
                            raise ValueError("too many payloads")
                        buf = buffers.setdefault(pid, bytearray())
                        if off != len(buf) or len(buf) + len(body) > MAX_FRAME:
                            raise ValueError("bad offset")
                        buf += body
                        if flags & 1:
                            self._emit(("bytes", pid, bytes(buffers.pop(pid))))
                    elif ptype == 2:
                        self._emit(("file", pid, off, body, bool(flags & 1)))
        except Exception as e:   # closed, or garbage
            try:
                self.events.put_nowait(("closed", str(e)))
            except queue.Full:
                pass
        finally:
            self.closed.set()

    def next_sharing(self, timeout=60):
        """The next Sharing frame's V1 part, skipping file data."""
        deadline = time.time() + timeout
        while True:
            left = deadline - time.time()
            if left <= 0:
                raise TimeoutError("no answer")
            try:
                ev = self.events.get(timeout=min(left, 1))
            except queue.Empty:
                if self.closed.is_set():
                    raise ConnectionError("closed")
                continue
            if ev[0] in ("closed", "disconnect", "cancel"):
                raise ConnectionError(ev[0])
            if ev[0] == "bytes":
                try:
                    f = parse(ev[2])
                except ValueError:
                    continue
                if f.int(1) == 1:
                    v1 = f.sub(2)
                    if v1.int(1) == CANCEL_T:
                        raise ConnectionError("cancel")
                    return v1, ev

    def close(self, polite=True):
        if polite and self.keys:
            try:
                self.send(disconnection())
            except OSError:
                pass
        self.closed.set()
        try:
            self.sock.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        self.sock.close()


def alert(conn, kind):
    try:
        conn.send_raw(pb((1, 1), (2, pb((1, kind)))))
    except OSError:
        pass


# ------------------------------------------------------------------ receive ---
def sanitize(name):
    name = os.path.basename(name.replace("\\", "/")).strip()
    name = "".join("_" if ch in '/\\?%*:|"<>' or ord(ch) < 32 else ch for ch in name)[:200]
    name = name.lstrip(".")           # never a hidden file: it has to show in Downloads
    return name or "file"


def receive(sock, ask, received, unique, folder):
    """Handle one sender. ask(who, files, texts, pin) -> True to accept;
    received(who, paths, texts) when it's all here."""
    conn = Conn(sock)
    sock.settimeout(30)
    try:
        # Who is it.
        v1 = parse(conn.recv_raw()).sub(2)
        if v1.int(1) != 1:
            return
        who, _ = read_endpoint_info(v1.sub(2).bytes(6))
        who = " ".join((who or v1.sub(2).str(2) or "A device nearby").split())[:60] or "A device nearby"

        # UKEY2: their ClientInit, our ServerInit, their ClientFinish.
        raw_ci = conn.recv_raw()
        m = parse(raw_ci)
        if m.int(1) != 2:
            return alert(conn, 2)
        ci = parse(m.bytes(2))
        commit = next((c.bytes(2) for c in ci.subs(3) if c.int(1) == 100), None)
        if ci.int(1) != 1 or len(ci.bytes(2)) != 32 or commit is None:
            return alert(conn, 102 if commit is None else 100)
        if ci.str(4) != "AES_256_CBC-HMAC_SHA256":
            return alert(conn, 103)
        priv = ec.generate_private_key(ec.SECP256R1())
        raw_si = pb((1, 3), (2, pb((1, 1), (2, os.urandom(32)), (3, 100), (4, public_key_message(priv)))))
        conn.send_raw(raw_si)
        raw_cf = conn.recv_raw()
        if hashlib.sha512(raw_cf).digest() != commit:
            return alert(conn, 3)
        cf = parse(raw_cf)
        if cf.int(1) != 4:
            return alert(conn, 2)
        conn.derive(priv, parse(cf.bytes(2)).bytes(1), raw_ci, raw_si, server=True)

        # Both say yes to the connection; everything after is encrypted.
        if parse(conn.recv_raw()).sub(2).int(1) != 2:
            return
        conn.send_raw(connection_response())
        sock.settimeout(None)
        conn.start()
        conn.send_bytes(PAIRED_KEY_ENCRYPTION())
        v1, _ = conn.next_sharing()
        if v1.int(1) != PKE:
            return
        conn.send_bytes(PAIRED_KEY_RESULT())
        v1, _ = conn.next_sharing()
        if v1.int(1) != PKR:
            return

        # What they want to send.
        v1, _ = conn.next_sharing()
        if v1.int(1) != INTRO:
            return
        intro = v1.sub(2)
        files = [{"name": sanitize(f.str(1)), "pid": f.int(3), "size": max(0, f.int(4)), "mime": f.str(5)} for f in intro.subs(1)[:500]]
        texts = [{"title": t.str(2), "kind": t.int(3), "pid": t.int(4), "size": t.int(5)} for t in intro.subs(2)]
        if not files and not texts:
            conn.send_bytes(RESPONSE(4))   # unsupported (Wi-Fi passwords, apps)
            return
        if not ask(who, files, texts, conn.pin):
            conn.send_bytes(RESPONSE(2))
            return
        conn.send_bytes(RESPONSE(1))

        # Take it.
        folder.mkdir(parents=True, exist_ok=True)
        open_files, paths, got_texts, idle = {}, [], [], 0
        for f in files:
            if f["pid"] in open_files:
                continue
            dest = unique(folder / f["name"])
            part = dest.with_name(dest.name + ".part")
            open_files[f["pid"]] = {"meta": f, "dest": dest, "part": part, "fh": open(part, "wb"), "n": 0}
        text_ids = {t["pid"]: t for t in texts}
        try:
            while open_files or text_ids:
                try:
                    ev = conn.events.get(timeout=1)
                    idle = 0
                except queue.Empty:
                    idle += 1
                    if conn.closed.is_set() or idle > 120:
                        raise ConnectionError("closed")
                    continue
                if ev[0] == "file" and ev[1] in open_files:
                    o = open_files[ev[1]]
                    if ev[2] != o["n"] or o["n"] + len(ev[3]) > o["meta"]["size"]:
                        raise ValueError("bad file data")
                    if ev[3]:
                        o["fh"].write(ev[3])
                        o["n"] += len(ev[3])
                    if ev[4]:
                        o["fh"].close()
                        if o["n"] != o["meta"]["size"]:
                            raise ValueError("short file")
                        o["part"].replace(o["dest"])
                        paths.append(str(o["dest"]))
                        del open_files[ev[1]]
                elif ev[0] == "bytes" and ev[1] in text_ids:
                    got_texts.append({**text_ids.pop(ev[1]), "text": ev[2].decode("utf-8", "replace")})
                elif ev[0] in ("closed", "disconnect", "cancel"):
                    raise ConnectionError(ev[0])
        finally:
            for o in open_files.values():      # anything not finished goes away
                o["fh"].close()
                o["part"].unlink(missing_ok=True)
        received(who, paths, got_texts)
    except (OSError, ValueError, ConnectionError, TimeoutError, queue.Empty, Ukey2Error):
        pass
    finally:
        conn.close()


# --------------------------------------------------------------------- send ---
def send(ip, port, files, my_id, my_name, say, mime):
    """Send files to an Android device; say() gets the lines memora-share prints
    (PIN, WAITING, PROGRESS n, DONE, ERROR why). Returns the exit code."""
    try:
        sock = socket.create_connection((ip, port), timeout=10)
    except OSError:
        say("ERROR Couldn't reach it. Is it still on the same Wi-Fi?")
        return 1
    conn = Conn(sock)
    try:
        conn.send_raw(connection_request(my_id, my_name, endpoint_info(my_name)))
        priv = ec.generate_private_key(ec.SECP256R1())
        raw_cf = pb((1, 4), (2, pb((1, public_key_message(priv)))))
        ci = pb((1, 1), (2, os.urandom(32)), (3, [pb((1, 100), (2, hashlib.sha512(raw_cf).digest()))]), (4, "AES_256_CBC-HMAC_SHA256"))
        raw_ci = pb((1, 2), (2, ci))
        conn.send_raw(raw_ci)
        raw_si = conn.recv_raw()
        m = parse(raw_si)
        if m.int(1) != 3:
            raise Ukey2Error("no server init")
        si = parse(m.bytes(2))
        if si.int(1) != 1 or len(si.bytes(2)) != 32 or si.int(3) != 100:
            alert(conn, 102)
            raise Ukey2Error("unsupported")
        conn.derive(priv, si.bytes(4), raw_ci, raw_si, server=False)
        conn.send_raw(raw_cf)
        conn.send_raw(connection_response())
        r = parse(conn.recv_raw()).sub(2)
        if r.int(1) != 2 or r.sub(3).int(3, 1) != 1:
            say("ERROR It refused the connection.")
            return 1
        sock.settimeout(None)
        conn.start()
        say(f"PIN {conn.pin}")

        conn.send_bytes(PAIRED_KEY_ENCRYPTION())
        v1, _ = conn.next_sharing(30)
        if v1.int(1) != PKE:
            raise ConnectionError("unexpected")
        conn.send_bytes(PAIRED_KEY_RESULT())
        v1, _ = conn.next_sharing(30)
        if v1.int(1) != PKR:
            raise ConnectionError("unexpected")

        metas, items = [], []
        for f in files:
            pid, size, mt = secrets.randbits(63), os.path.getsize(f), mime(f)
            kind = 1 if mt.startswith("image/") else 2 if mt.startswith("video/") else 4 if mt.startswith("audio/") \
                else 3 if f.lower().endswith(".apk") else 0
            metas.append(pb((1, sanitize(os.path.basename(f))), (2, kind), (3, pid), (4, size), (5, mt), (6, secrets.randbits(63))))
            items.append((f, pid, size))
        conn.send_bytes(sharing(INTRO, 2, pb((1, metas))))
        say("WAITING")

        v1, _ = conn.next_sharing(120)
        status = v1.sub(3).int(1) if v1.int(1) == RESP else 0
        if status != 1:
            say("ERROR " + {2: "They declined.", 3: "There's not enough space on it.", 4: "It can't take this kind of file.",
                            5: "It took too long to answer."}.get(status, "They declined."))
            return 1

        total, sent, last = sum(s for _, _, s in items) or 1, 0, -1
        say("PROGRESS 0")
        for f, pid, size in items:
            off = 0
            with open(f, "rb") as fh:
                while off < size:
                    if not conn.events.empty():       # they cancelled or hung up meanwhile
                        ev = conn.events.get()
                        if ev[0] in ("closed", "disconnect", "cancel"):
                            raise ConnectionError(ev[0])
                    elif conn.closed.is_set():
                        raise ConnectionError("closed")
                    body = fh.read(min(CHUNK, size - off))
                    if not body:
                        raise OSError("file changed")
                    conn.send(payload(pid, 2, size, off, body, False))
                    off += len(body)
                    sent += len(body)
                    pct = int(sent * 100 / total)
                    if pct != last:
                        say(f"PROGRESS {pct}")
                        last = pct
            conn.send(payload(pid, 2, size, size, b"", True))
        # Let it finish writing before we hang up: it disconnects when it has everything.
        deadline = time.time() + 15
        while time.time() < deadline:
            try:
                ev = conn.events.get(timeout=deadline - time.time())
            except queue.Empty:
                break
            if ev[0] in ("closed", "disconnect"):
                break
        say("PROGRESS 100")
        say("DONE")
        return 0
    except TimeoutError:
        say("ERROR It didn't answer.")
        return 1
    except (OSError, ValueError, ConnectionError, Ukey2Error, queue.Empty) as e:
        say("ERROR " + ("They cancelled." if str(e) == "cancel" else "The transfer stopped."))
        return 1
    finally:
        conn.close()


# ---------------------------------------------------- discovery & presence ---
VIRTUAL = ("docker", "br-", "veth", "virbr", "vmnet", "vboxnet", "lxc", "lxd", "podman", "cni", "flannel", "tailscale", "wg", "tun", "tap", "zt")


def local_ipv4():
    """Our addresses on real networks (not containers or VPNs), the one the
    default route uses first: phones try them in order."""
    try:
        out = subprocess.run(["ip", "-4", "-o", "addr", "show", "scope", "global"], capture_output=True, text=True).stdout
        route = subprocess.run(["ip", "-4", "route", "get", "1.1.1.1"], capture_output=True, text=True).stdout.split()
    except OSError:
        return []
    ips = []
    for ln in out.splitlines():
        f = ln.split()
        if len(f) > 3 and not f[1].startswith(VIRTUAL):
            ip = f[3].split("/")[0]
            if ip not in ips:
                ips.append(ip)
    main = route[route.index("src") + 1] if "src" in route[:-1] else ""
    return sorted(ips, key=lambda ip: ip != main)


class Presence:
    """Our mDNS service (so phones see us) and the browser (so we see them)."""

    def __init__(self, name, on_change):
        from zeroconf import Zeroconf, ServiceBrowser
        self.endpoint_id = "".join(secrets.choice(ALPHABET) for _ in range(4))
        self.name = name
        self.on_change = on_change
        self.devices = {}               # mDNS name -> device
        self.info = None
        self.ips = []
        self.lock = threading.Lock()
        self.zc = Zeroconf()
        self.browser = ServiceBrowser(self.zc, SERVICE, handlers=[self._changed])

    # -- being visible
    def visible(self, on, name=None):
        from zeroconf import ServiceInfo
        ips = local_ipv4() if on else []
        name = name or self.name
        with self.lock:
            if self.info and (not on or ips != self.ips or name != self.name):
                try:
                    self.zc.unregister_service(self.info)
                except Exception:
                    pass
                self.info = None
            self.name, self.ips = name, ips
            if on and ips and not self.info:
                inst = b64(b"\x23" + self.endpoint_id.encode() + b"\xfc\x9f\x5e\x00\x00")
                self.info = ServiceInfo(SERVICE, f"{inst}.{SERVICE}", port=PORT,
                                        properties={"n": b64(endpoint_info(name))},
                                        server=f"memora-{self.endpoint_id.lower()}.local.",
                                        addresses=[socket.inet_aton(ip) for ip in ips])
                try:
                    self.zc.register_service(self.info, allow_name_change=True)
                except Exception:
                    self.info = None

    # -- seeing others
    def _changed(self, zeroconf, service_type, name, state_change):
        threading.Thread(target=self._resolve, args=(name, state_change.name), daemon=True).start()

    def _resolve(self, name, change):
        if change == "Removed":
            with self.lock:
                gone = self.devices.pop(name, None)
            if gone:
                self.on_change()
            return
        try:
            raw = unb64(name[:-len(SERVICE) - 1])
        except ValueError:
            return
        if len(raw) < 10 or raw[0] != 0x23 or raw[5:8] != b"\xfc\x9f\x5e":
            return
        eid = raw[1:5].decode("ascii", "replace")
        if eid == self.endpoint_id:
            return
        info = self.zc.get_service_info(SERVICE, name, timeout=3000)
        if not info or not info.port:
            return
        try:
            alias, dtype = read_endpoint_info(unb64(info.properties.get(b"n") or b""))
        except ValueError:
            return
        ips = [a for a in info.parsed_addresses() if ":" not in a]
        if not alias or not ips:
            return
        with self.lock:
            self.devices[name] = {"id": "qs:" + eid, "alias": alias, "type": TYPES.get(dtype, "mobile"), "model": "Quick Share",
                                  "ip": ips[0], "port": info.port, "protocol": "quickshare"}
        self.on_change()

    def list(self):
        with self.lock:
            return list(self.devices.values())


class Beacon:
    """The BLE advertisement that wakes Android's Quick Share up so it shows on
    mDNS. Best effort: no Bluetooth (or it's off) means only devices that
    already advertise (a phone with its Quick Share screen open) show up."""

    def __init__(self):
        self.until = 0
        self.thread = None

    def extend(self, seconds=30):
        self.until = time.time() + seconds
        if not (self.thread and self.thread.is_alive()):
            self.thread = threading.Thread(target=self._run, daemon=True)
            self.thread.start()

    def _run(self):
        try:
            from gi.repository import Gio, GLib
        except ImportError:
            return
        ctx = GLib.MainContext.new()
        ctx.push_thread_default()
        loop = GLib.MainLoop.new(ctx, False)
        try:
            bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
            objs = bus.call_sync("org.bluez", "/", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects", None,
                                 GLib.VariantType("(a{oa{sa{sv}}})"), 0, 3000, None).unpack()[0]
            adapter = next((p for p, i in objs.items() if "org.bluez.LEAdvertisingManager1" in i
                            and i.get("org.bluez.Adapter1", {}).get("Powered")), None)
            if not adapter:
                return
            data = bytes([0xFC, 0x12, 0x8E, 0x01, 0x42] + [0] * 9) + os.urandom(10)
            node = Gio.DBusNodeInfo.new_for_xml(
                '<node><interface name="org.bluez.LEAdvertisement1"><method name="Release"/>'
                '<property name="Type" type="s" access="read"/>'
                '<property name="ServiceData" type="a{sv}" access="read"/></interface></node>')
            path = f"/org/memora/nearby/beacon{os.getpid()}"

            def method(conn, sender, obj, iface, name, params, inv):
                inv.return_value(None)

            def prop(conn, sender, obj, iface, name):
                if name == "Type":
                    return GLib.Variant("s", "broadcast")
                return GLib.Variant("a{sv}", {"0000fe2c-0000-1000-8000-00805f9b34fb": GLib.Variant("ay", data)})

            reg = bus.register_object(path, node.interfaces[0], method, prop, None)
            ok = {"registered": False}

            def registered(b, res):
                try:
                    b.call_finish(res)
                    ok["registered"] = True
                except GLib.Error:
                    loop.quit()

            bus.call("org.bluez", adapter, "org.bluez.LEAdvertisingManager1", "RegisterAdvertisement",
                     GLib.Variant("(oa{sv})", (path, {})), None, 0, 5000, None, registered)

            def check():
                if time.time() < self.until:
                    return True
                loop.quit()
                return False

            src = GLib.timeout_source_new(1000)
            src.set_callback(lambda *_: check())
            src.attach(ctx)
            loop.run()
            if ok["registered"]:
                try:
                    bus.call_sync("org.bluez", adapter, "org.bluez.LEAdvertisingManager1", "UnregisterAdvertisement",
                                  GLib.Variant("(o)", (path,)), None, 0, 3000, None)
                except GLib.Error:
                    pass
            bus.unregister_object(reg)
        except Exception:
            pass
        finally:
            ctx.pop_thread_default()
