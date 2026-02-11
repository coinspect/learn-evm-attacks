const http = require("http");
const fs = require("fs");
const path = require("path");

const BLOCK_CACHE_DIR = path.join(__dirname, "..", ".block_cache");
const PORT = 8546;

// Load all cached files from .block_cache/
// Numeric filenames (e.g. 17248593.json) → block responses
// Named filenames (e.g. eth_chainId.json) → method responses
const blocks = {};      // blockNumber (int) → parsed JSON response
const methods = {};     // methodName (string) → parsed JSON response
let highestBlock = 0;

for (const file of fs.readdirSync(BLOCK_CACHE_DIR)) {
  if (!file.endsWith(".json")) continue;
  const name = file.replace(".json", "");
  const data = JSON.parse(fs.readFileSync(path.join(BLOCK_CACHE_DIR, file), "utf8"));

  if (/^\d+$/.test(name)) {
    const num = parseInt(name, 10);
    blocks[num] = data;
    if (num > highestBlock) highestBlock = num;
    console.log(`Loaded block ${num}`);
  } else {
    methods[name] = data;
    console.log(`Loaded method ${name}`);
  }
}

const highestBlockHex = "0x" + highestBlock.toString(16);
console.log(`Highest cached block: ${highestBlock} (${highestBlockHex})`);

const server = http.createServer((req, res) => {
  let body = "";
  req.on("data", (c) => (body += c));
  req.on("end", () => {
    let rpc;
    try {
      rpc = JSON.parse(body);
    } catch {
      res.writeHead(400, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } }));
      return;
    }

    const id = rpc.id;
    let result;

    switch (rpc.method) {
      case "eth_blockNumber":
        result = highestBlockHex;
        break;

      case "eth_getBlockByNumber": {
        const requested = rpc.params[0];
        let blockNum;
        if (requested === "latest") {
          blockNum = highestBlock;
        } else {
          blockNum = parseInt(requested, 16);
        }
        if (blocks[blockNum]) {
          // Return a copy with the correct request id
          const resp = Object.assign({}, blocks[blockNum], { id });
          res.writeHead(200, { "Content-Type": "application/json" });
          res.end(JSON.stringify(resp));
          return;
        }
        result = null;
        break;
      }

      default:
        // Check if we have a cached response for this method
        if (methods[rpc.method]) {
          const resp = Object.assign({}, methods[rpc.method], { id });
          res.writeHead(200, { "Content-Type": "application/json" });
          res.end(JSON.stringify(resp));
          return;
        }
        // Fallback: return "0x" for anything that slips past Foundry's cache
        console.warn(`[WARN] Uncached method: ${rpc.method}`, JSON.stringify(rpc.params));
        result = "0x";
        break;
    }

    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ jsonrpc: "2.0", id, result }));
  });
});

server.listen(PORT, () => console.log(`RPC proxy listening on :${PORT}`));
