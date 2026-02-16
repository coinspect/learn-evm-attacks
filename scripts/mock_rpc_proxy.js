const http = require("http");
const fs = require("fs");
const path = require("path");

const BLOCK_CACHE_DIR = path.join(__dirname, "..", "rpc_cache", "blocks");
const PORT = 8546;

// FORK_BLOCK and CHAIN_ID tell us which block's metadata to serve.
// Passed by test_all_cached.sh / attach-run.sh based on the attack being run.
const FORK_BLOCK = parseInt(process.env.FORK_BLOCK || "0", 10);
if (!FORK_BLOCK) {
  console.error("ERROR: FORK_BLOCK env var is required");
  process.exit(1);
}
const CHAIN_ID = process.env.CHAIN_ID || "";
if (!CHAIN_ID) {
  console.error("ERROR: CHAIN_ID env var is required");
  process.exit(1);
}

const FORK_BLOCK_HEX = "0x" + FORK_BLOCK.toString(16);

// Load block responses from all chain/block subdirectories:
//   rpc_cache/blocks/<chainId>/<blocknum>/block.json
// This lets eth_getBlockByNumber serve any cached block for this chain.
const blocks = {};

const chainDir = path.join(BLOCK_CACHE_DIR, CHAIN_ID);
if (fs.existsSync(chainDir)) {
  for (const dir of fs.readdirSync(chainDir)) {
    const dirPath = path.join(chainDir, dir);
    if (!fs.statSync(dirPath).isDirectory()) continue;
    if (!/^\d+$/.test(dir)) continue;

    const blockFile = path.join(dirPath, "block.json");
    if (fs.existsSync(blockFile)) {
      const num = parseInt(dir, 10);
      blocks[num] = JSON.parse(fs.readFileSync(blockFile, "utf8"));
      console.log(`Loaded block ${num} (chain ${CHAIN_ID})`);
    }
  }
}

// Load chain metadata from the active attack's subdirectory.
// These are chain-specific (eth_chainId differs between Ethereum, BSC, Polygon, etc.)
const methods = {};
const metaDir = path.join(BLOCK_CACHE_DIR, CHAIN_ID, String(FORK_BLOCK));

if (fs.existsSync(metaDir)) {
  for (const file of fs.readdirSync(metaDir)) {
    if (file === "block.json" || !file.endsWith(".json")) continue;
    const methodName = file.replace(".json", "");
    methods[methodName] = JSON.parse(fs.readFileSync(path.join(metaDir, file), "utf8"));
    console.log(`Loaded method ${methodName} (chain ${CHAIN_ID}, block ${FORK_BLOCK})`);
  }
} else {
  console.warn(`WARNING: No metadata directory for chain ${CHAIN_ID} block ${FORK_BLOCK}`);
}

console.log(`Active: chain ${CHAIN_ID}, fork block ${FORK_BLOCK} (${FORK_BLOCK_HEX})`);
console.log(`Cached blocks: ${Object.keys(blocks).join(", ")}`);

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
        result = FORK_BLOCK_HEX;
        break;

      case "eth_getBlockByNumber": {
        const requested = rpc.params[0];
        let blockNum;
        if (requested === "latest") {
          blockNum = FORK_BLOCK;
        } else {
          blockNum = parseInt(requested, 16);
        }
        if (blocks[blockNum]) {
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
