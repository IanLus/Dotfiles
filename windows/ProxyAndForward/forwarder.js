// atrust TCP forwarder for WSL2
// atrust VPN 会阻止 Hyper-V 虚拟交换机的 TCP 流量（ICMP 可过，TCP 不可过）。
// 此脚本在 Windows 侧监听端口，转发到 atrust 内网 IP。
//
// 镜像模式：WSL 与 Windows 共享 127.0.0.1，监听 127.0.0.1 即可。
// NAT 模式：WSL 有独立网络，需监听 0.0.0.0，WSL 通过 Windows 网关 IP 访问。
//
// 用法: node atrust-forwarder.js [mode]
//   node atrust-forwarder.js        # 自动检测模式
//   node atrust-forwarder.js mirrored # 强制镜像模式 (监听 127.0.0.1)
//   node atrust-forwarder.js nat      # 强制 NAT 模式 (监听 0.0.0.0)
// 按 Ctrl+C 停止

const net = require("net");
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

const mode = process.argv[2] || detectMode();
const host = mode === "mirrored" ? "127.0.0.1" : "0.0.0.0";

console.log(`WSL mode: ${mode}, listening on ${host}`);

const forwards = [
  { listen: 34568, target: "10.41.13.22", port: 34568, name: "platform-system" },
  { listen: 34571, target: "10.41.13.23", port: 34571, name: "law-server" },
  { listen: 34572, target: "10.41.13.24", port: 34572, name: "digit-server" },
];

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
