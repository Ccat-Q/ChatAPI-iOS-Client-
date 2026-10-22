"""Local protocol fixture for the macOS Actions regression job; no external services."""
import base64
import hashlib
import json
import struct
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CONVERSATION = {"id": "c1", "title": "Fixture", "last_user_text": "Hello", "last_message_preview": "Hello", "request_id": "r1", "status": "waiting", "updated_at": "2026-10-22T12:00:00.123456789Z"}
MESSAGE = {"id": "m1", "kind": "message", "message": {"id": "m1", "role": "user", "content": "Hello", "created_at": "2026-10-22T12:00:00Z"}}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):
        pass

    def reply(self, value, status=200, cookie=None):
        data = json.dumps(value).encode() if value is not None else b""
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        if cookie:
            self.send_header("Set-Cookie", cookie)
        self.end_headers()
        self.wfile.write(data)

    def body(self):
        return self.rfile.read(int(self.headers.get("Content-Length", "0")))

    def do_GET(self):
        if self.body():
            return self.reply({"error": "GET must not have a body"}, 400)
        if self.path == "/api/ws":
            return self.websocket()
        if self.path == "/api/auth/session":
            authenticated = "fixture_session=valid" in self.headers.get("Cookie", "")
            return self.reply({"authenticated": authenticated, "user": {"id": "u1", "username": "operator", "role": "admin"} if authenticated else None})
        if self.path == "/fixture/unauthorized":
            return self.reply({"error": "expired"}, 401)
        if self.path == "/fixture/forbidden":
            return self.reply({"error": "forbidden"}, 403)
        if self.path == "/fixture/oversize":
            return self.reply({"text": "x" * 1_048_576})
        if self.path == "/fixture/headers":
            return self.reply({"origin": self.headers.get("Origin", ""), "authorization": self.headers.get("Authorization", "")})
        self.reply({"error": "unknown fixture"}, 404)

    def do_POST(self):
        body = json.loads(self.body() or b"{}")
        if self.path == "/api/auth/login":
            if body == {"username": "operator", "password": "password", "totp": "123456"}:
                return self.reply({"ok": True}, cookie="fixture_session=valid; Path=/; HttpOnly")
            return self.reply({"ok": False})
        self.reply({"error": "unknown fixture"}, 404)

    def do_DELETE(self):
        if self.body():
            return self.reply({"error": "DELETE must not have a body"}, 400)
        self.reply(None, 204)

    def write_frame(self, payload, opcode=1):
        data = json.dumps(payload).encode() if opcode == 1 else payload
        header = bytes([0x80 | opcode])
        if len(data) < 126:
            header += bytes([len(data)])
        else:
            header += bytes([126]) + struct.pack("!H", len(data))
        self.wfile.write(header + data)
        self.wfile.flush()

    def read_exact(self, count):
        data = self.rfile.read(count)
        if len(data) != count:
            raise EOFError
        return data

    def read_frame(self):
        first, second = self.read_exact(2)
        size = second & 127
        if size == 126:
            size = struct.unpack("!H", self.read_exact(2))[0]
        elif size == 127:
            size = struct.unpack("!Q", self.read_exact(8))[0]
        if size > 1_048_576:
            raise ValueError("oversized frame")
        mask = self.read_exact(4) if second & 128 else None
        data = self.read_exact(size)
        if mask:
            data = bytes(value ^ mask[index % 4] for index, value in enumerate(data))
        return first & 15, data

    def websocket(self):
        if "fixture_session=valid" not in self.headers.get("Cookie", ""):
            return self.reply({"error": "unauthorized"}, 401)
        accept = base64.b64encode(hashlib.sha1((self.headers["Sec-WebSocket-Key"] + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
        self.send_response(101)
        self.send_header("Upgrade", "websocket")
        self.send_header("Connection", "Upgrade")
        self.send_header("Sec-WebSocket-Accept", accept)
        self.end_headers()
        self.write_frame({"type": "workspace.snapshot", "conversations": [CONVERSATION], "has_more": True, "next_cursor": "page-1"})
        try:
            while True:
                opcode, data = self.read_frame()
                if opcode == 8:
                    return
                if opcode == 9:
                    self.write_frame(data, 10)
                    continue
                value = json.loads(data)
                if value["type"] == "timeline.subscribe":
                    self.write_frame({"type": "timeline.reset", "conversation_id": "c1", "items": [MESSAGE]})
                elif value["type"] == "conversation.page.get":
                    self.write_frame({"type": "conversation.page", "command_id": value["command_id"], "conversations": [{**CONVERSATION, "id": "c2"}], "has_more": False})
                elif value["type"] == "workspace.command":
                    command = value["command"]
                    if command["text"] == "__noack__":
                        continue
                    if command["text"] == "__disconnect__":
                        self.write_frame(struct.pack("!H", 1001), 8)
                        return
                    valid = command["kind"] == "stream_complete" and command["mode"] in ["assistant_message", "tool_call", "tool_result"]
                    if command["text"] == "__reject__" or not valid:
                        self.write_frame({"type": "workspace.command_error", "command_id": command["command_id"], "message": "Rejected by fixture"})
                    else:
                        self.write_frame({"type": "workspace.command_ack", "command_id": command["command_id"], "conversation_id": command["conversation_id"], "request_id": "other" if command["text"] == "__mismatch__" else command["request_id"]})
        except (EOFError, ConnectionError, OSError):
            pass
        finally:
            self.close_connection = True


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
with open(sys.argv[1], "w", encoding="utf-8") as output:
    output.write(str(server.server_port))
server.serve_forever()
