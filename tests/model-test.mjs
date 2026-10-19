import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const modelPath = path.join(__dirname, "..", "Model.js");
const rawCode = fs.readFileSync(modelPath, "utf8").replace(/^\.pragma\s+library\s*/m, "");

const ctx = vm.createContext({});
vm.runInContext(rawCode, ctx);

// 1. Test icons
assert.equal(ctx.typeIcon("ethernet"), "󰈀");
assert.equal(ctx.typeIcon("wifi"), "󰤨");
assert.equal(ctx.typeIcon("vpn"), "󰖂");
assert.equal(ctx.typeIcon("tailscale"), "󰖂");
assert.equal(ctx.typeIcon("bridge"), "󰖲");
assert.equal(ctx.typeIcon("disconnected"), "󰖪");
assert.equal(ctx.publicIcon, "󰖟");
assert.equal(ctx.copyIcon, "󰅍");

// 2. Test sanitizeText
assert.equal(ctx.sanitizeText("hello\x00world\n", 20), "helloworld");
assert.equal(ctx.sanitizeText("abcdef", 3), "abc");
assert.equal(ctx.sanitizeText(null), "");

// 3. Test formatPing
assert.equal(ctx.formatPing(null), "—");
assert.equal(ctx.formatPing(-1), "—");
assert.equal(ctx.formatPing(0.4), "<1 ms");
assert.equal(ctx.formatPing(3.45), "3.5 ms");
assert.equal(ctx.formatPing(24.7), "25 ms");

// 4. Test formatSpeedCompact & formatSpeedFull
const sZero = ctx.formatSpeedCompact(0);
assert.equal(sZero.compact, "0.0K");
assert.equal(ctx.formatSpeedFull(0), "0.0 KB/s");

const sMeg = ctx.formatSpeedCompact(2.5 * 1024 * 1024);
assert.equal(sMeg.compact, "2.5M");
assert.equal(ctx.formatSpeedFull(2.5 * 1024 * 1024), "2.5 MB/s");

// 5. Test formatBytes
assert.equal(ctx.formatBytes(512), "512 B");
assert.equal(ctx.formatBytes(2048), "2.0 KB");
assert.equal(ctx.formatBytes(5 * 1024 * 1024 * 1024), "5.0 GB");

// 6. Test parseDev
const sampleDev = [
  "Inter-|   Receive                                                |  Transmit",
  " face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed",
  "    lo: 1000000    1000    0    0    0     0          0         0  1000000    1000    0    0    0     0       0          0",
  "  eth0: 5000000    4000    0    0    0     0          0         0  2000000    2000    0    0    0     0       0          0",
  " wlan0: 3000000    3000    0    0    0     0          0         0  1000000    1000    0    0    0     0       0          0",
  "docker0: 900000     900    0    0    0     0          0         0   900000     900    0    0    0     0       0          0"
].join("\n");

const parsedPrimary = ctx.parseDev(sampleDev, "primary", "eth0");
assert.equal(parsedPrimary.rx, 5000000);
assert.equal(parsedPrimary.tx, 2000000);
assert.equal(parsedPrimary.iface, "eth0");
assert.equal(parsedPrimary.interfaces.wlan0.rx, 3000000);

const parsedAll = ctx.parseDev(sampleDev, "all", "eth0");
assert.equal(parsedAll.rx, 8000000);
assert.equal(parsedAll.tx, 3000000);
assert.equal(parsedAll.iface, "all");

// 7. Test parseSS
const sampleSS = [
  "State      Recv-Q Send-Q Local Address:Port               Peer Address:PortProcess",
  'ESTAB      0      1024   192.168.1.50:54322               1.1.1.1:443       users:(("brave",pid=1234,fd=45))',
  'ESTAB      512    0      192.168.1.50:54323               8.8.8.8:443       users:(("brave",pid=1234,fd=46))',
  'ESTAB      0      0      192.168.1.50:54324               9.9.9.9:22        users:(("ssh",pid=5678,fd=3))'
].join("\n");

const apps = ctx.parseSS(sampleSS);
assert.equal(apps.length, 2);
assert.equal(apps[0].name, "brave");
assert.equal(apps[0].conns, 2);
assert.equal(apps[0].rxQueue, 512);
assert.equal(apps[0].txQueue, 1024);
assert.equal(apps[1].name, "ssh");
assert.equal(apps[1].conns, 1);

console.log("All Model.js unit tests passed!");
