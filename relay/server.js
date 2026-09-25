// OTP Bridge relay.
//
// A dumb, zero-knowledge fan-out. Clients join a room (a random id agreed at
// pairing time) and every encrypted message is forwarded to the other members
// of that room. The server never has the key, so `nonce`/`ct` are opaque to it.
//
// Env:
//   PORT       listen port (default 8080)
//   AUTH_TOKEN optional shared secret; if set, clients must send it as the
//              `token` query param (?token=...). A weak gate to keep strangers
//              off your relay — real confidentiality comes from E2E encryption.

import { WebSocketServer } from "ws";

const PORT = Number(process.env.PORT || 8080);
const AUTH_TOKEN = process.env.AUTH_TOKEN || null;

// room id -> Set<WebSocket>
const rooms = new Map();

const wss = new WebSocketServer({ port: PORT });

function join(ws, room) {
  if (typeof room !== "string" || room.length < 8 || room.length > 64) return false;
  if (ws.room && ws.room !== room) leave(ws);
  ws.room = room;
  let set = rooms.get(room);
  if (!set) rooms.set(room, (set = new Set()));
  set.add(ws);
  return true;
}

function leave(ws) {
  const set = ws.room && rooms.get(ws.room);
  if (!set) return;
  set.delete(ws);
  if (set.size === 0) rooms.delete(ws.room);
  ws.room = null;
}

wss.on("connection", (ws, req) => {
  if (AUTH_TOKEN) {
    const url = new URL(req.url, "http://x");
    if (url.searchParams.get("token") !== AUTH_TOKEN) {
      ws.close(4001, "unauthorized");
      return;
    }
  }

  ws.isAlive = true;
  ws.on("pong", () => { ws.isAlive = true; });

  ws.on("message", (data) => {
    let msg;
    try {
      msg = JSON.parse(data.toString());
    } catch {
      return; // ignore malformed frames
    }

    if (msg.type === "join") {
      const ok = join(ws, msg.room);
      const peers = ok ? (rooms.get(msg.room)?.size ?? 1) - 1 : 0;
      ws.send(JSON.stringify({ type: ok ? "joined" : "error", room: msg.room, peers }));
      return;
    }

    if (msg.type === "msg") {
      if (!ws.room || msg.room !== ws.room) return; // must join the room first
      const frame = JSON.stringify({
        type: "msg",
        room: ws.room,
        nonce: msg.nonce,
        ct: msg.ct,
      });
      const set = rooms.get(ws.room);
      if (!set) return;
      for (const peer of set) {
        if (peer !== ws && peer.readyState === peer.OPEN) peer.send(frame);
      }
    }
  });

  ws.on("close", () => leave(ws));
  ws.on("error", () => leave(ws));
});

// Drop dead sockets so rooms don't leak.
const heartbeat = setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.isAlive) { ws.terminate(); continue; }
    ws.isAlive = false;
    ws.ping();
  }
}, 30000);

wss.on("close", () => clearInterval(heartbeat));

console.log(`otp-bridge relay listening on :${PORT}${AUTH_TOKEN ? " (auth on)" : ""}`);
