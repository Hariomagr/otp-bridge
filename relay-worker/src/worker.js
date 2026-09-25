// OTP Bridge relay on Cloudflare Workers + Durable Object.
//
// Same wire protocol as the Node relay (join / msg), so the phone and Mac need
// no changes. A single Durable Object instance holds every room in memory and
// fans encrypted `msg` frames out to the other members. Zero-knowledge: the
// Worker never has the key.
//
// Free tier: the DO is declared as a SQLite class in wrangler.toml. We don't
// actually use storage — it's an in-memory relay — but that declaration is
// what keeps it on the no-credit-card plan.

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // Optional shared-secret gate (set with: wrangler secret put AUTH_TOKEN).
    if (env.AUTH_TOKEN && url.searchParams.get("token") !== env.AUTH_TOKEN) {
      return new Response("unauthorized", { status: 401 });
    }

    if (request.headers.get("Upgrade") !== "websocket") {
      return new Response("otp-bridge relay (cloudflare) ok", { status: 200 });
    }

    // Route every socket to the same DO instance.
    const id = env.RELAY.idFromName("relay");
    return env.RELAY.get(id).fetch(request);
  },
};

export class Relay {
  constructor(state, env) {
    this.rooms = new Map();       // room -> Set<WebSocket>
    this.socketRoom = new Map();  // WebSocket -> room
  }

  async fetch(request) {
    const [client, server] = Object.values(new WebSocketPair());
    server.accept();
    server.addEventListener("message", (evt) => this.onMessage(server, evt.data));
    server.addEventListener("close", () => this.leave(server));
    server.addEventListener("error", () => this.leave(server));
    return new Response(null, { status: 101, webSocket: client });
  }

  onMessage(ws, data) {
    let msg;
    try {
      msg = JSON.parse(typeof data === "string" ? data : new TextDecoder().decode(data));
    } catch {
      return; // ignore malformed frames
    }

    if (msg.type === "join") {
      const room = msg.room;
      if (typeof room !== "string" || room.length < 8 || room.length > 64) {
        ws.send(JSON.stringify({ type: "error", room }));
        return;
      }
      this.leave(ws);
      this.socketRoom.set(ws, room);
      let set = this.rooms.get(room);
      if (!set) this.rooms.set(room, (set = new Set()));
      set.add(ws);
      // peers = other members already in the room (presence signal).
      ws.send(JSON.stringify({ type: "joined", room, peers: set.size - 1 }));
      return;
    }

    if (msg.type === "msg") {
      const room = this.socketRoom.get(ws);
      if (!room || msg.room !== room) return; // must join first
      const frame = JSON.stringify({ type: "msg", room, nonce: msg.nonce, ct: msg.ct });
      const set = this.rooms.get(room);
      if (!set) return;
      for (const peer of set) {
        if (peer !== ws) {
          try { peer.send(frame); } catch { /* peer gone; cleaned on close */ }
        }
      }
    }
  }

  leave(ws) {
    const room = this.socketRoom.get(ws);
    if (room) {
      const set = this.rooms.get(room);
      if (set) {
        set.delete(ws);
        if (set.size === 0) this.rooms.delete(room);
      }
    }
    this.socketRoom.delete(ws);
  }
}
