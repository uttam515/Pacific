import express, {
  type Request,
  type Response,
  type NextFunction,
} from "express";
import { createServer, type Server } from "node:http";
import { randomUUID } from "node:crypto";
import { WebSocketServer, WebSocket } from "ws";
import { fileURLToPath } from "node:url";
import { Engine } from "./engine.js";
import { ApiError, validate, CONTRACT_SHA } from "./contract.js";
import { authenticate, hash, token, type Actor } from "./database.js";
import { Emergency } from "./emergency.js";
export type Options = { origin: string; insecureLocal?: boolean };
export function createHttp(
  engine: Engine,
  options: Options,
): {
  app: express.Express;
  server: Server;
  contractSha: string;
  close: () => Promise<void>;
} {
  const app = express();
  app.disable("x-powered-by");
  const emergency = new Emergency(engine);
  const rates = new Map<string, { count: number; until: number }>();
  const rateSweep = setInterval(() => { for (const [key, v] of rates) if (v.until < Date.now()) rates.delete(key); }, 60000);
  rateSweep.unref();
  app.use((req,res,next) => {
    if (!req.path.startsWith("/api/") && req.path !== "/login") return next();
    const key = req.socket.remoteAddress || "unknown", now=Date.now();
    let v=rates.get(key);
    if (!v || v.until<now) { if(rates.size>10000) {res.status(503).json({error:{code:"TEMPORARY_FAILURE",retryable:true}});return;} v={count:0,until:now+60000}; rates.set(key,v); }
    if(++v.count>600){res.setHeader("Retry-After","60");res.status(429).json({schemaVersion:1,error:{code:"RATE_LIMITED",message:"Retry later",retryable:true}});return;}
    next();
  });
  const server = createServer(app),
    sockets = new WebSocketServer({ noServer: true, maxPayload: 1024 });
  const actors = new WeakMap<WebSocket, Actor>();
  const asyncRoute =
    (fn: (req: Request, res: Response) => Promise<unknown>) =>
    (req: Request, res: Response, next: NextFunction) => {
      Promise.resolve(fn(req, res)).catch(next);
    };
  const isAllowedOrigin = (origin: string | undefined) => {
    if (!origin) return true;
    if (origin === options.origin) return true;
    if (options.insecureLocal) {
      if (
        origin.startsWith("http://localhost:") ||
        origin.startsWith("http://127.0.0.1:") ||
        origin.startsWith("http://192.168.") ||
        origin.startsWith("http://10.") ||
        origin.startsWith("http://172.")
      ) return true;
    }
    return false;
  };
  const cookie = (req: { headers: { cookie?: string } }) =>
    req.headers.cookie
      ?.split(";")
      .map((x) => x.trim())
      .find((x) => x.startsWith("offgrid_session="))
      ?.slice("offgrid_session=".length) || "";
  const bearer = (req: { headers: { authorization?: string } }) =>
    req.headers.authorization?.match(/^Bearer ([A-Za-z0-9_-]{43})$/)?.[1] || "";
  async function actor(req: Request): Promise<Actor> {
    const secret = bearer(req);
    if (secret) return authenticate(engine.db, secret, "bearer");
    if (
      !["GET", "HEAD"].includes(req.method) &&
      !isAllowedOrigin(req.headers.origin)
    )
      throw new ApiError(403, "FORBIDDEN", "Origin verification required");
    return authenticate(engine.db, cookie(req), "session");
  }
  app.use((req, _res, next) => {
    if (req.url.includes("%3F")) {
      req.url = req.url.replaceAll("%3F", "?");
    }
    next();
  });
  app.use(express.json({ limit: 1048576, strict: true }));
  app.use(express.urlencoded({ extended: false, limit: 4096 }));
  app.use((req, res, next) => {
    res.setHeader("Cache-Control", "no-store");
    if (req.path.startsWith("/api/")) {
      console.log(`[API] ${req.method} ${req.path} (${req.socket.remoteAddress || "local"})`);
    }
    if (req.headers.origin && !isAllowedOrigin(req.headers.origin))
      return next(new ApiError(403, "FORBIDDEN", "Origin not permitted"));
    next();
  });
  let scheduled = false;
  async function notify() {
    if (scheduled) return;
    scheduled = true;
    setTimeout(async () => {
      scheduled = false;
      try {
        const message = JSON.stringify(
          validate("Notification", {
            schemaVersion: 1,
            type: "SYNC_NOTIFICATION",
            eventId: randomUUID(),
            timestamp: Date.now(),
            latestCursor: await engine.latestCursor(),
          }),
        );
        for (const socket of sockets.clients) {
          const a = actors.get(socket);
          if (!a) continue;
          const valid = await engine.db.query(
            "SELECT 1 FROM credentials WHERE token_hash=$1 AND NOT revoked AND (expires_at IS NULL OR expires_at>now())",
            [(socket as WebSocket & { credentialHash: string }).credentialHash],
          );
          if (!valid.rowCount) {
            socket.close(1008, "Session expired");
            continue;
          }
          if (socket.readyState === WebSocket.OPEN) {
            if (socket.bufferedAmount > 65536)
              socket.close(1013, "Refresh via REST");
            else socket.send(message);
          }
        }
      } catch {
        console.error(
          "Notification unavailable; REST refresh remains available",
        );
      }
    }, 25).unref();
  }
  engine.onCommit = () => {
    void notify();
  };
  app.get("/api/v1/health", (_req, res) =>
    res.json({ schemaVersion: 1, status: "ok" }),
  );
  app.get("/login", (_req, res) => {
    res.setHeader(
      "Content-Security-Policy",
      "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'",
    );
    res
      .type("html")
      .send(
        '<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>OFFGRID operator sign in</title><body><h1>OFFGRID operator sign in</h1><p>Enter the operator credential printed by your local provisioning command.</p><form action="/login" method="post"><label>Operator credential <input name="credential" type="password" required autocomplete="off"></label><button>Sign in</button></form></body></html>',
      );
  });
  const login = asyncRoute(async (req, res) => {
    if (!isAllowedOrigin(req.headers.origin))
      throw new ApiError(403, "FORBIDDEN", "Login origin not permitted");
    const raw =
      typeof req.body?.credential === "string"
        ? req.body.credential
        : bearer(req);
    const a = await authenticate(engine.db, raw, "bearer");
    if (a.role !== "operator")
      throw new ApiError(403, "FORBIDDEN", "Operator credential required");
    const session = token();
    await engine.db.query(
      "INSERT INTO credentials(token_hash,node_id,kind,expires_at) VALUES($1,$2,'session',now()+interval '8 hours')",
      [hash(session), a.node_id],
    );
    res.cookie("offgrid_session", session, {
      httpOnly: true,
      secure: !options.insecureLocal,
      sameSite: options.insecureLocal ? "lax" : "strict",
      path: "/",
      maxAge: 8 * 3600000,
    });
    if (req.path === "/login") res.redirect(303, "/");
    else res.json({ authenticated: true });
  });
  app.post("/login", login);
  app.post("/api/v1/operator/session", login);
  app.post(
    "/api/v1/sync/push",
    asyncRoute(async (req, res) =>
      res.json(
        await engine.push(await actor(req), validate("PushRequest", req.body)),
      ),
    ),
  );
  app.get(
    "/api/v1/sync/pull",
    asyncRoute(async (req, res) =>
      res.json(
        await engine.pull(
          await actor(req),
          String(req.query.cursor || "c0"),
          limit(req.query.limit),
        ),
      ),
    ),
  );
  app.post(
    "/api/v1/receipts",
    asyncRoute(async (req, res) =>
      res.json(
        await engine.receipt(
          await actor(req),
          validate("ReceiptRequest", req.body),
        ),
      ),
    ),
  );
  app.get(
    "/api/v1/conflicts",
    asyncRoute(async (req, res) =>
      res.json(
        await engine.pull(
          await actor(req),
          String(req.query.cursor || "c0"),
          limit(req.query.limit),
          true,
        ),
      ),
    ),
  );
  app.get(
    "/api/v1/conflicts/:id",
    asyncRoute(async (req, res) => {
      const id = validate("UUID", req.params.id);
      res.json(await engine.conflict(await actor(req), id));
    }),
  );
  app.post(
    "/api/v1/conflicts/:id/resolve",
    asyncRoute(async (req, res) => {
      const id = validate("UUID", req.params.id);
      res.json(
        await engine.resolve(
          await actor(req),
          id,
          validate("ResolveRequest", req.body),
        ),
      );
    }),
  );
  app.get(
    "/api/v1/dashboard/snapshot",
    asyncRoute(async (req, res) =>
      res.json(await engine.snapshot(await actor(req))),
    ),
  );
  app.get("/api/v1/connectivity", (_req,res)=>res.type("text/plain").send("OFFGRID_INTERNET_OK_V1"));
  app.get("/api/v1/emergency/incidents", asyncRoute(async(req,res)=>res.json(await emergency.list(await actor(req),String(req.query.cursor||""),Number(req.query.limit||100)))));
  app.get(
    "/api/v1/gateway/ready",
    asyncRoute(async (req, res) =>
      res.json(
        await emergency.ready(
          await actor(req),
          (req.query.nodeId as string) || (req.headers["x-node-id"] as string),
        ),
      ),
    ),
  );
  app.post("/api/v1/gateway/heartbeat", asyncRoute(async (req,res) => res.json(await emergency.heartbeat(await actor(req),req.body))));
  app.post("/api/v1/gateway/observations", asyncRoute(async (req,res) => res.json(await emergency.observation(await actor(req),req.body))));
  app.get("/api/v1/emergency/snapshot", asyncRoute(async (req,res) => res.json(await emergency.snapshot(await actor(req)))));
  app.get("/api/v1/incidents/:id", asyncRoute(async (req,res) => res.json(await emergency.detail(await actor(req),String(req.params.id)))));
  app.post("/api/v1/emergency/commands", asyncRoute(async (req,res) => res.json(await emergency.command(await actor(req),req.body))));
  app.post("/api/v1/operator/logout", asyncRoute(async (req,res) => {
    const a=await actor(req);
    if(a.kind==="session") await engine.db.query("UPDATE credentials SET revoked=true WHERE token_hash=$1",[hash(cookie(req))]);
    res.clearCookie("offgrid_session",{path:"/"});res.json({authenticated:false});
  }));
  // The existing dashboard action adapter is deliberately gated until it sends
  // candidate operation IDs and version guards. Core conflict API is available.
  app.post(
    "/api/v1/dashboard/actions",
    asyncRoute(async (req) => {
      await actor(req);
      throw new ApiError(
        422,
        "VALIDATION_ERROR",
        "Operator action adapter pending; use versioned conflict/receipt APIs",
      );
    }),
  );
  app.use(
    express.static(
      fileURLToPath(
        new URL("../../../apps/web-dashboard/dist/", import.meta.url),
      ),
      { index: "index.html" },
    ),
  );
  app.use((_req, _res, next) =>
    next(new ApiError(404, "ENTITY_NOT_FOUND", "Endpoint not found")),
  );
  app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
    const bodyError = err as { type?: string };
    const e =
      err instanceof ApiError
        ? err
        : bodyError.type === "entity.too.large"
          ? new ApiError(413, "TOO_LARGE", "JSON body exceeds limit")
          : bodyError.type === "entity.parse.failed"
            ? new ApiError(400, "VALIDATION_ERROR", "Malformed JSON")
            : new ApiError(
                503,
                "TEMPORARY_FAILURE",
                "Backend request unavailable",
                true,
              );
    if (!(err instanceof ApiError) && !bodyError.type)
      console.error("Backend request failed");
    res
      .status(e.status)
      .json({
        schemaVersion: 1,
        error: { code: e.code, message: e.message, retryable: e.retryable },
      });
  });
  server.on("upgrade", (req, socket, head) => {
    void (async () => {
      const parsedUrl = new URL(req.url || "", "http://localhost");
      if (parsedUrl.pathname !== "/ws") throw new Error("path");
      const queryToken = parsedUrl.searchParams.get("token") || "";
      const b = bearer(req) || queryToken;
      if (req.headers.origin && !isAllowedOrigin(req.headers.origin))
        throw new Error("origin");
      const secret = b || cookie(req);
      const a = await authenticate(
        engine.db,
        secret,
        b ? "bearer" : "session",
      );
      sockets.handleUpgrade(req, socket, head, (ws) => {
        actors.set(ws, a);
        (ws as WebSocket & { credentialHash: string }).credentialHash = hash(
          secret,
        );
        ws.on("error", () => {});
        ws.on("message", () => ws.close(1008, "Notifications only"));
        ws.on("pong", () => {
          (ws as WebSocket & { alive: boolean }).alive = true;
        });
        (ws as WebSocket & { alive: boolean }).alive = true;
        void notify();
      });
    })().catch(() => {
      socket.write("HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n");
      socket.destroy();
    });
  });
  const heartbeat = setInterval(() => {
    for (const ws of sockets.clients) {
      const w = ws as WebSocket & { alive: boolean };
      if (!w.alive) {
        w.terminate();
        continue;
      }
      w.alive = false;
      w.ping();
    }
  }, 30000);
  heartbeat.unref();
  return {
    app,
    server,
    contractSha: CONTRACT_SHA,
    close: async () => {
      clearInterval(heartbeat);
      clearInterval(rateSweep);
      for (const ws of sockets.clients) ws.terminate();
      await new Promise<void>((resolve) => sockets.close(() => resolve()));
      await new Promise<void>((resolve, reject) =>
        server.close((e) => (e ? reject(e) : resolve())),
      );
    },
  };
}
function limit(raw: unknown) {
  if (raw === undefined) return 100;
  if (
    typeof raw !== "string" ||
    !/^\d+$/.test(raw) ||
    Number(raw) < 1 ||
    Number(raw) > 100
  )
    throw new ApiError(400, "VALIDATION_ERROR", "limit must be 1..100");
  return Number(raw);
}
