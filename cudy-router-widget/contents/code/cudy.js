.pragma library

// Cudy router local API: protocol helpers (no I/O, no Qt dependencies).
// Transport is done by main.qml via curl; everything else lives here.

// ---------------------------------------------------------------- SHA-256

var SHA_K = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
];

function utf8Bytes(s) {
    var out = [];
    for (var i = 0; i < s.length; i++) {
        var c = s.charCodeAt(i);
        if (c >= 0xd800 && c <= 0xdbff && i + 1 < s.length) {
            var d = s.charCodeAt(i + 1);
            if (d >= 0xdc00 && d <= 0xdfff) {
                c = 0x10000 + ((c - 0xd800) << 10) + (d - 0xdc00);
                i++;
            }
        }
        if (c < 0x80) out.push(c);
        else if (c < 0x800) out.push(0xc0 | (c >> 6), 0x80 | (c & 63));
        else if (c < 0x10000) out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
        else out.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
    }
    return out;
}

function rotr(x, n) {
    return (x >>> n) | (x << (32 - n));
}

function sha256Hex(str) {
    var m = utf8Bytes(String(str));
    var bitLen = m.length * 8;
    m.push(0x80);
    while (m.length % 64 !== 56) m.push(0);
    var hi = Math.floor(bitLen / 4294967296), lo = bitLen >>> 0;
    m.push((hi >>> 24) & 255, (hi >>> 16) & 255, (hi >>> 8) & 255, hi & 255,
           (lo >>> 24) & 255, (lo >>> 16) & 255, (lo >>> 8) & 255, lo & 255);

    var H = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
             0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
    var w = new Array(64);
    for (var off = 0; off < m.length; off += 64) {
        var i;
        for (i = 0; i < 16; i++) {
            w[i] = (m[off + 4 * i] << 24) | (m[off + 4 * i + 1] << 16)
                 | (m[off + 4 * i + 2] << 8) | m[off + 4 * i + 3];
        }
        for (i = 16; i < 64; i++) {
            var s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
            var s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
            w[i] = (w[i - 16] + s0 + w[i - 7] + s1) | 0;
        }
        var a = H[0], b = H[1], c = H[2], d = H[3], e = H[4], f = H[5], g = H[6], h = H[7];
        for (i = 0; i < 64; i++) {
            var S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
            var ch = (e & f) ^ (~e & g);
            var t1 = (h + S1 + ch + SHA_K[i] + w[i]) | 0;
            var S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
            var maj = (a & b) ^ (a & c) ^ (b & c);
            var t2 = (S0 + maj) | 0;
            h = g; g = f; f = e; e = (d + t1) | 0;
            d = c; c = b; b = a; a = (t1 + t2) | 0;
        }
        H[0] = (H[0] + a) | 0; H[1] = (H[1] + b) | 0; H[2] = (H[2] + c) | 0; H[3] = (H[3] + d) | 0;
        H[4] = (H[4] + e) | 0; H[5] = (H[5] + f) | 0; H[6] = (H[6] + g) | 0; H[7] = (H[7] + h) | 0;
    }
    var hex = "";
    for (var j = 0; j < 8; j++) {
        var part = (H[j] >>> 0).toString(16);
        hex += "00000000".substring(part.length) + part;
    }
    return hex;
}

// Same scheme as the router web UI: sha256(sha256(password + salt) + challenge)
function loginHash(password, salt, challenge) {
    return sha256Hex(sha256Hex(password + salt) + challenge);
}

// ---------------------------------------------------------------- transport helpers

function shq(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'";
}

function hostFromUrl(url) {
    var m = /^https?:\/\/(\[[^\]]+\]|[^\/:?#]+)/i.exec(String(url).trim());
    return m ? m[1] : "";
}

// Router uses a self-signed certificate on https, so TLS verification is
// skipped (-k), exactly like the Python library did. Proxies are ignored.
function curlCommand(baseUrl, path, method, params, token) {
    var url = String(baseUrl).trim().replace(/\/+$/, "") + path
            + (token ? "?auth=" + encodeURIComponent(token) : "");
    var body = JSON.stringify({ method: method, params: params || [] });
    return "curl -sS -k -i --noproxy '*' --max-time 10"
         + " -H 'Content-Type: application/json'"
         + " --data-binary " + shq(body) + " " + shq(url);
}

function curlFailure(code, stderr) {
    var lines = String(stderr || "").trim().split("\n");
    var last = lines[lines.length - 1];
    switch (code) {
    case 127: return "curl is not installed (or not in PATH)";
    case 6: return "Cannot resolve the router address";
    case 7: return "Cannot connect to the router";
    case 28: return "Router request timed out";
    case 35: case 51: case 58: case 60: return "TLS error: " + last;
    default: return last || ("curl failed (exit code " + code + ")");
    }
}

function splitResponse(out) {
    var rest = String(out), status = 0, headers = "";
    while (/^HTTP\/\S+\s+\d+/.test(rest)) {
        var sep = /\r?\n\r?\n/.exec(rest);
        if (!sep) { headers = rest; rest = ""; }
        else {
            headers = rest.substring(0, sep.index);
            rest = rest.substring(sep.index + sep[0].length);
        }
        status = parseInt(/^HTTP\/\S+\s+(\d+)/.exec(headers)[1], 10);
        if (status !== 100) break;   // skip "100 Continue" blocks
    }
    return { status: status, headers: headers, body: rest };
}

function cookieToken(headers) {
    var found = { sysauth: "", stok: "" };
    var lines = String(headers).split(/\r?\n/);
    for (var i = 0; i < lines.length; i++) {
        var m = /^set-cookie:\s*(sysauth|stok)=([^;]*)/i.exec(lines[i]);
        if (m) found[m[1].toLowerCase()] = m[2];
    }
    return found.sysauth || found.stok || "";
}

// Turn one finished curl run into {ok, result, cookieToken} or
// {ok:false, kind: "auth"|"unsupported"|"error", message, code}
function parseRpc(data) {
    var exitCode = data["exit code"];
    if (exitCode !== undefined && exitCode !== 0) {
        return { ok: false, kind: "error", message: curlFailure(exitCode, data["stderr"]) };
    }
    var resp = splitResponse(data["stdout"] || "");
    if (resp.status === 401 || resp.status === 403) {
        return { ok: false, kind: "auth", message: "Router rejected authentication" };
    }
    if (resp.status >= 300 && resp.status < 400) {
        return { ok: false, kind: "error",
                 message: "Router redirected the request - try the other of http:// and https:// in the URL" };
    }
    if (resp.status < 200 || resp.status >= 300) {
        return { ok: false, kind: "error",
                 message: resp.status ? "Router answered HTTP " + resp.status : "Empty answer from router" };
    }
    var obj;
    try { obj = JSON.parse(resp.body); } catch (e) {
        return { ok: false, kind: "error", message: "Router returned invalid JSON" };
    }
    if (obj === null || typeof obj !== "object" || Array.isArray(obj)) {
        return { ok: false, kind: "error", message: "Router returned a non-object RPC response" };
    }
    if (obj.error !== undefined && obj.error !== null) {
        var code = obj.error && obj.error.code;
        if (code === -32003) return { ok: false, kind: "auth", message: "Router rejected authentication", code: code };
        if (code === -32601) return { ok: false, kind: "unsupported", message: "Not supported by this firmware", code: code };
        return { ok: false, kind: "error", message: "Router RPC failed (code " + code + ")", code: code };
    }
    if (!("result" in obj)) {
        return { ok: false, kind: "error", message: "Router RPC response is missing a result" };
    }
    return { ok: true, result: obj.result, cookieToken: cookieToken(resp.headers) };
}

// `avahi-browse -rtp _http._tcp` -> salt advertised by the router at `ip`
function parseAvahiSalt(out, ip) {
    var lines = String(out).split("\n");
    for (var i = 0; i < lines.length; i++) {
        if (lines[i].charAt(0) !== "=") continue;
        var f = lines[i].split(";");
        if (f.length < 10 || f[7] !== ip) continue;
        var m = /"salt=([^"]*)"/.exec(f.slice(9).join(";"));
        if (m && m[1]) {
            return m[1].replace(/\\(\d{3})/g, function (_, n) { return String.fromCharCode(parseInt(n, 10)); });
        }
    }
    return "";
}

// ---------------------------------------------------------------- data mapping

function num(v) {
    if (v === null || v === undefined || v === "") return null;
    var n = Number(v);
    return isFinite(n) ? n : null;
}

function str(v) {
    return v === undefined || v === null ? "" : String(v);
}

// int from number/string, truncated; null when missing/invalid (like safe_int)
function safeInt(v) {
    if (typeof v === "boolean") return null;
    var n = num(v);
    if (n === null) return null;
    return n < 0 ? Math.ceil(n) : Math.floor(n);
}

// like nonnegative_int in the Device model: numbers/strings only, >= 0
function nonNegInt(v) {
    if (typeof v !== "number" && typeof v !== "string") return null;
    var n = safeInt(v);
    return n !== null && n >= 0 ? n : null;
}

function wifiQuality(dbm) {
    if (dbm === null || dbm >= 0) return null;
    if (dbm >= -55) return "Excellent";
    if (dbm >= -67) return "Good";
    if (dbm >= -75) return "Fair";
    return "Poor";
}

// upspeed/downspeed are bytes/s; same units as the Python Device model
function formatRate(v) {
    if (v === null) return "";
    var units = ["B/s", "KiB/s", "MiB/s", "GiB/s"];
    var rate = v, i = 0;
    while (rate >= 1024 && i < units.length - 1) { rate /= 1024; i++; }
    return rate.toFixed(1) + " " + units[i];
}

// Mirrors Device.from_api_response of the Python library
function mapDevice(rec) {
    var iface = str(rec.interface).toLowerCase();
    var rawIface = str(rec.iface).toLowerCase();
    var isWifi = /^(ra|wlan|wl|ath)/.test(iface) || rawIface.indexOf("wlan") === 0;
    var isEth = iface.indexOf("eth") === 0 || rawIface === "eth";

    var signal = safeInt(rec.signal);
    if (signal === null) {
        var rssi = safeInt(rec.rssi);
        signal = rssi !== null ? rssi - 100 : null;
    }
    if (!isWifi || signal === 0) signal = null;   // wired clients have no meaningful signal

    var mac = (str(rec.macaddr) || str(rec.mac)).toLowerCase();
    var inactive = nonNegInt(rec.inactive);
    return {
        name: str(rec.name) || str(rec.hostname) || mac || "unknown",
        ip: str(rec.ipaddr) || str(rec.ip),
        mac: mac,
        type: isWifi ? "wifi" : isEth ? "ethernet" : "",
        signal: signal,
        signalLabel: wifiQuality(signal) || "",
        down: formatRate(nonNegInt(rec.downspeed)),
        up: formatRate(nonNegInt(rec.upspeed)),
        active: inactive === null ? null : inactive < 30
    };
}

var QUALITY = ["Very poor", "Poor", "Fair", "Good", "Excellent"];

function signalBars(rsrp) {
    if (rsrp === null) return 0;
    if (rsrp >= -85) return 4;
    if (rsrp >= -95) return 3;
    if (rsrp >= -105) return 2;
    if (rsrp >= -115) return 1;
    return 0;
}

// Whitelisted modem fields only (raw status also contains IMSI etc.)
function mapCellular(raw) {
    if (raw === null || typeof raw !== "object" || Array.isArray(raw)) return null;
    var rsrp = num(raw.rsrp);
    var bars = signalBars(rsrp);
    return {
        operator: raw.reg_status ? String(raw.reg_status) : "",
        ip: raw.inetip ? String(raw.inetip) : "",
        net: raw.net ? String(raw.net) : "",
        band: raw.band ? String(raw.band) : "",
        bars: bars,
        quality: rsrp === null ? "Unknown" : QUALITY[bars]
    };
}
