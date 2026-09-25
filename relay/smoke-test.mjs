// Quick smoke test: start server, connect two clients to a room, confirm a
// message from A reaches B (and does NOT echo back to A). Exit 0 on success.
import { spawn } from "node:child_process";
import { WebSocket } from "ws";

const PORT = 8099;
const server = spawn("node", ["server.js"], {
  env: { ...process.env, PORT: String(PORT) },
  stdio: "inherit",
});

const url = `ws://127.0.0.1:${PORT}`;
const room = "abc123def456";
let failed = false;

function done(code) {
  server.kill();
  process.exit(code);
}

setTimeout(() => {
  const a = new WebSocket(url);
  const b = new WebSocket(url);
  let ready = 0;

  const onOpen = (ws) => {
    ws.send(JSON.stringify({ type: "join", room }));
    if (++ready === 2) {
      setTimeout(() => {
        a.send(JSON.stringify({ type: "msg", room, nonce: "n", ct: "hello" }));
      }, 100);
    }
  };
  a.on("open", () => onOpen(a));
  b.on("open", () => onOpen(b));

  a.on("message", (d) => {
    const m = JSON.parse(d);
    if (m.type === "msg") { console.error("FAIL: A received its own msg"); failed = true; }
  });

  b.on("message", (d) => {
    const m = JSON.parse(d);
    if (m.type === "msg" && m.ct === "hello") {
      console.log("PASS: B received A's message; A did not echo");
      done(failed ? 1 : 0);
    }
  });

  setTimeout(() => { console.error("FAIL: timeout, B never got the message"); done(1); }, 2000);
}, 500);
