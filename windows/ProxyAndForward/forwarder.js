// atrust TCP forwarder for WSL2
// atrust VPN 会阻止 Hyper-V 虚拟交换机的 TCP 流量（ICMP 可过，TCP 不可过）。
// 此脚本在 Windows 侧监听端口，转发到 atrust 内网 IP。
//
// 镜像模式：WSL 与 Windows 共享 127.0.0.1，监听 127.0.0.1 即可。
// NAT 模式：WSL 有独立网络，需监听 0.0.0.0，WSL 通过 Windows 网关 IP 访问。
//
// 转发规则默认读同目录 forwards.json，可用 FORWARDER_CONFIG 或 .json 参数覆盖。
//
// 用法: node forwarder.js [mode] [config.json]
//   node forwarder.js                 # 自动检测模式
//   node forwarder.js mirrored        # 强制镜像模式 (监听 127.0.0.1)
//   node forwarder.js nat             # 强制 NAT 模式 (监听 0.0.0.0)
//   node forwarder.js forwards.json
// 按 Ctrl+C 停止

const fs = require("fs");
const net = require("net");
const path = require("path");
const { execSync } = require("child_process");

function detectMode() {
  try {
    // 镜像模式有 loopback0 接口
    execSync("wsl -d Arch -- ip link show loopback0", { stdio: "pipe", timeout: 3000 });
    return "mirrored";
  } catch {
    return "nat";
  }
}

function resolveConfigPath(args) {
  const fromArg = args.find((a) => a.endsWith(".json"));
  if (fromArg) {
    return path.resolve(fromArg);
  }
  if (process.env.FORWARDER_CONFIG) {
    return path.resolve(process.env.FORWARDER_CONFIG);
  }
  return path.join(__dirname, "forwards.json");
}

function loadForwards(configPath) {
  const data = JSON.parse(fs.readFileSync(configPath, "utf8"));
  const list = Array.isArray(data) ? data : data.forwards;
  if (!Array.isArray(list)) {
    throw new Error(`${configPath} must be an array or { "forwards": [...] }`);
  }
  return list.map((item, i) => {
    const listen = Number(item.listen);
    const port = Number(item.port);
    const target = item.target;
    if (!Number.isInteger(listen) || listen <= 0 || !target || !Number.isInteger(port) || port <= 0) {
      throw new Error(`${configPath} [${i}] needs listen, target, port`);
    }
    return {
      listen,
      target: String(target),
      port,
      name: item.name ? String(item.name) : `${target}:${port}`,
    };
  });
}

const args = process.argv.slice(2).filter((a) => a !== "--");
const modeArg = args.find((a) => a === "mirrored" || a === "nat");
const mode = modeArg || detectMode();
const host = mode === "mirrored" ? "127.0.0.1" : "0.0.0.0";
const configPath = resolveConfigPath(args);
const forwards = loadForwards(configPath);

console.log(`WSL mode: ${mode}, listening on ${host}`);
console.log(`config: ${configPath}`);

forwards.forEach(({ listen, target, port, name }) => {
  const server = net.createServer((clientSocket) => {
    const serverSocket = net.connect(port, target);
    clientSocket.pipe(serverSocket);
    serverSocket.pipe(clientSocket);
    const cleanup = () => {
      clientSocket.destroy();
      serverSocket.destroy();
    };
    clientSocket.on("error", cleanup);
    serverSocket.on("error", cleanup);
    clientSocket.on("close", cleanup);
    serverSocket.on("close", cleanup);
  });
  server.on("error", (err) => {
    if (err.code === "EADDRINUSE") {
      console.error(`[skip] ${host}:${listen} (${name}) already in use`);
    } else {
      console.error(`[error] ${name}:`, err.message);
    }
  });
  server.listen(listen, host, () => {
    console.log(`[ok] ${host}:${listen} -> ${target}:${port} (${name})`);
  });
});

console.log("atrust forwarder running. Ctrl+C to stop.");
