.pragma library

var PROMOTE_AT = 1023.5;

var VIRTUAL_IFACE_RE = /^(lo|docker\d*|br-|veth|virbr|tun|tap|wg|tailscale|cni|flannel|cali|cilium|lxc|dummy)/i;

function typeIcon(type) {
    switch (type) {
    case "ethernet":
        return "󰈀";
    case "wifi":
        return "󰤨";
    case "tailscale":
    case "vpn":
        return "󰖂";
    case "bridge":
        return "󰖲";
    case "disconnected":
        return "󰖪";
    default:
        return "󰛳";
    }
}

var publicIcon  = "󰖟";
var gatewayIcon = "󰌘";
var dnsIcon     = "󰒍";
var copyIcon    = "󰅍";
var checkIcon   = "󰄬";
var refreshIcon = "󰑐";
var ipIcon      = "󰩠";
var appIcon     = "󰏗";
var speedIcon   = "󰓅";

function sanitizeText(val, maxLen) {
    if (val === undefined || val === null) return "";
    var limit = (typeof maxLen === "number" && maxLen > 0) ? maxLen : 256;
    var str = String(val).replace(/[\x00-\x1f\x7f]/g, "");
    if (str.length > limit) {
        return str.slice(0, limit);
    }
    return str;
}

function formatPing(ms) {
    if (ms === undefined || ms === null || ms < 0 || isNaN(ms)) return "\u2014";
    if (ms < 1) return "<1 ms";
    if (ms < 10) return ms.toFixed(1) + " ms";
    return Math.round(ms) + " ms";
}

function formatSpeedCompact(bps) {
    var safeBps = Math.max(0, Number(bps) || 0);
    var k = safeBps / 1024;
    var u = "K";
    if (k >= PROMOTE_AT) {
        k /= 1024;
        u = "M";
    }
    if (k >= PROMOTE_AT) {
        k /= 1024;
        u = "G";
    }
    var num = k < 10 ? k.toFixed(1) : Math.round(k).toString();
    return {
        value: k,
        num: num,
        unit: u,
        text: num + " " + u,
        compact: num + u
    };
}

function formatSpeedFull(bps) {
    var s = formatSpeedCompact(bps);
    return s.num + " " + s.unit + "B/s";
}

function formatBytes(bytes) {
    var b = Math.max(0, Number(bytes) || 0);
    if (b < 1024) return Math.round(b) + " B";
    var units = ["KB", "MB", "GB", "TB"];
    var val = b / 1024;
    var idx = 0;
    while (val >= PROMOTE_AT && idx < units.length - 1) {
        val /= 1024;
        idx++;
    }
    var num = val < 10 ? val.toFixed(1) : Math.round(val).toString();
    return num + " " + units[idx];
}

function parseDev(text, scope, primaryIface) {
    if (!text || typeof text !== "string") return null;
    var lines = text.split("\n");
    var sumRx = 0;
    var sumTx = 0;
    var sumCount = 0;
    var interfaces = {};

    for (var i = 2; i < lines.length; i++) {
        var line = lines[i].trim();
        if (!line) continue;
        var colon = line.indexOf(":");
        if (colon < 0) continue;
        var iface = line.slice(0, colon).trim();
        if (!iface || iface === "lo") continue;

        var fields = line.slice(colon + 1).trim().split(/\s+/);
        if (fields.length < 9) continue;
        var rx = parseInt(fields[0], 10);
        var tx = parseInt(fields[8], 10);
        if (isNaN(rx) || isNaN(tx)) continue;

        interfaces[iface] = { rx: rx, tx: tx };

        if (!VIRTUAL_IFACE_RE.test(iface)) {
            sumRx += rx;
            sumTx += tx;
            sumCount++;
        }
    }

    if (scope === "primary" && primaryIface && interfaces[primaryIface]) {
        return {
            rx: interfaces[primaryIface].rx,
            tx: interfaces[primaryIface].tx,
            iface: primaryIface,
            interfaces: interfaces
        };
    }

    if (sumCount === 0 && primaryIface && interfaces[primaryIface]) {
        return {
            rx: interfaces[primaryIface].rx,
            tx: interfaces[primaryIface].tx,
            iface: primaryIface,
            interfaces: interfaces
        };
    }

    if (sumCount === 0 && Object.keys(interfaces).length === 0) return null;

    return {
        rx: sumRx,
        tx: sumTx,
        iface: scope === "primary" ? (primaryIface || "") : "all",
        interfaces: interfaces
    };
}

function parseSS(text) {
    if (!text || typeof text !== "string") return [];
    var lines = text.split("\n");
    var byApp = {};

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (!line || line.indexOf("Netid") === 0 || line.indexOf("State") === 0) continue;

        var procMatch = line.match(/users:\(\("([^"]+)"/);
        if (!procMatch) continue;
        var appName = sanitizeText(procMatch[1], 48);
        if (!appName) continue;

        var parts = line.split(/\s+/);
        if (parts.length < 6) continue;

        var hasNetid = (parts[0] === "tcp" || parts[0] === "udp" || parts[0] === "raw" || parts[0] === "sctp");
        var offset = hasNetid ? 1 : 0;
        if (parts.length < offset + 5) continue;

        var state = parts[offset];
        var recvQ = parseInt(parts[offset + 1], 10) || 0;
        var sendQ = parseInt(parts[offset + 2], 10) || 0;
        var peer = sanitizeText(parts[offset + 4], 64);

        if (peer.indexOf("127.0.0.1:") === 0 || peer.indexOf("[::1]:") === 0) continue;

        if (!byApp[appName]) {
            byApp[appName] = {
                name: appName,
                conns: 0,
                rxQueue: 0,
                txQueue: 0,
                peers: []
            };
        }
        var entry = byApp[appName];
        entry.conns += 1;
        entry.rxQueue += Math.max(0, recvQ);
        entry.txQueue += Math.max(0, sendQ);

        if (peer && peer !== "*:*" && peer !== "0.0.0.0:*" && peer !== "[::]:*") {
            var peerHost = peer;
            var lastColon = peer.lastIndexOf(":");
            if (lastColon > 0) {
                peerHost = peer.slice(0, lastColon);
            }
            if (entry.peers.indexOf(peerHost) < 0 && entry.peers.length < 3) {
                entry.peers.push(peerHost);
            }
        }
    }

    var list = [];
    var keys = Object.keys(byApp);
    for (var k = 0; k < keys.length; k++) {
        list.push(byApp[keys[k]]);
    }

    list.sort(function(a, b) {
        var qa = a.rxQueue + a.txQueue;
        var qb = b.rxQueue + b.txQueue;
        if (qb !== qa) return qb - qa;
        if (b.conns !== a.conns) return b.conns - a.conns;
        return a.name.localeCompare(b.name);
    });

    return list.slice(0, 8);
}
