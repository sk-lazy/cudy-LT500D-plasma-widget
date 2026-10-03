import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami
import "../code/cudy.js" as Cudy

PlasmoidItem {
    id: root

    readonly property string authPath: "/cgi-bin/luci/rpc/auth"
    readonly property string apiPath: "/cgi-bin/luci/rpc/app"

    property var devices: []
    property var cellular: null
    property string rawSample: ""
    property string errorText: ""
    property string lastUpdate: ""

    // connection state
    property bool busy: false
    property double busySince: 0
    property string token: ""
    property string discoveredSalt: ""
    property int seq: 0
    property var pending: ({})

    toolTipMainText: i18n("Cudy Router")
    toolTipSubText: errorText !== "" ? errorText
        : (i18n("%1 devices", devices.length)
           + ((cellular && !cellular.error) ? "\n" + cellular.operator + " " + cellular.net + "  " + cellular.quality + " signal" : ""))

    // ------------------------------------------------------------ plumbing

    // Runs a shell command through the "executable" engine; cb gets the result map.
    function run(cmd, cb) {
        var key = cmd + " # " + (++seq);   // unique source name, trailing shell comment
        pending[key] = cb;
        executable.connectSource(key);
    }

    function rpc(path, method, params, useToken, cb) {
        var cmd = Cudy.curlCommand(Plasmoid.configuration.routerUrl, path, method, params,
                                   useToken ? token : "");
        run(cmd, function (data) { cb(Cudy.parseRpc(data)); });
    }

    function fail(message) {
        busy = false;
        errorText = message;
    }

    function effectiveSalt() {
        return (Plasmoid.configuration.salt || "").trim() || discoveredSalt;
    }

    // ------------------------------------------------------------ connect

    function ensureSalt(cb) {
        if (effectiveSalt() !== "") { cb(null); return; }
        var host = Cudy.hostFromUrl(Plasmoid.configuration.routerUrl);
        run("avahi-browse -rtp _http._tcp", function (data) {
            var found = Cudy.parseAvahiSalt(data["stdout"] || "", host);
            if (found === "") {
                cb(i18n("Could not discover the router's login salt (needs avahi-utils). Enter it in the widget settings."));
                return;
            }
            discoveredSalt = found;
            cb(null);
        });
    }

    function login(cb) {
        var cfg = Plasmoid.configuration;
        rpc(authPath, "token", [], false, function (r) {
            if (!r.ok) { cb(r.message); return; }
            var challenge = r.result;
            if (typeof challenge !== "string" || challenge === "" || /^0*$/.test(challenge)) {
                cb(i18n("Router returned an invalid challenge (busy?)"));
                return;
            }
            var hash = Cudy.loginHash(cfg.password, effectiveSalt(), challenge);
            rpc(authPath, "login", ["admin", hash], false, function (r2) {
                if (!r2.ok) { cb(r2.message); return; }
                var t = r2.cookieToken || (typeof r2.result === "string" ? r2.result : "");
                if (t.length < 10) {
                    discoveredSalt = "";   // maybe a stale auto-discovered salt; retry discovery next time
                    cb(i18n("Login failed - check the password (and the salt)"));
                    return;
                }
                token = t;
                cb(null);
            });
        });
    }

    function ensureToken(cb) {
        if (token !== "") { cb(null); return; }
        login(cb);
    }

    // ------------------------------------------------------------ data

    // Same pagination as the old library: first call without params, then inclusive 1-based ranges.
    function fetchDevices(cb) {
        var records = [];
        function page(params) {
            rpc(apiPath, "devices.get_devlist_ex", params, true, function (r) {
                if (!r.ok) { cb(r); return; }
                var res = r.result;
                if (res === null || typeof res !== "object" || !Array.isArray(res.devlist)) {
                    cb({ ok: false, kind: "error", message: i18n("Unexpected device list response") });
                    return;
                }
                records = records.concat(res.devlist);
                var count = res.devcnt;
                if (count === undefined || count === null || records.length >= count || res.devlist.length === 0) {
                    cb({ ok: true, records: records });
                    return;
                }
                page([records.length + 1, Math.min(records.length + 100, count)]);
            });
        }
        page([]);
    }

    function fetchCellular(cb) {
        var iface = (Plasmoid.configuration.cellularInterface || "").trim();
        if (iface === "") { cb(null); return; }
        rpc(apiPath, "cellular.getstatus", [iface], true, function (r) {
            if (r.ok) {
                var c = Cudy.mapCellular(r.result);
                cb(c === null ? { error: i18n("unexpected answer") } : c);
            } else if (r.kind === "unsupported") {
                cb({ error: i18n("not supported by this firmware") });
            } else {
                cb({ error: r.message });
            }
        });
    }

    function fetchAll(retried) {
        fetchDevices(function (r) {
            if (!r.ok) {
                if (r.kind === "auth" && !retried) {   // token expired: log in once more
                    token = "";
                    login(function (err) {
                        if (err) { fail(err); return; }
                        fetchAll(true);
                    });
                    return;
                }
                if (r.kind === "auth") token = "";
                fail(r.message);
                return;
            }
            fetchCellular(function (cell) {
                devices = r.records.map(function (rec) { return Cudy.mapDevice(rec); });
                rawSample = (Plasmoid.configuration.showRaw && r.records.length > 0)
                            ? JSON.stringify(r.records[0], null, 2) : "";
                cellular = cell;
                errorText = "";
                lastUpdate = Qt.formatTime(new Date(), "hh:mm:ss");
                busy = false;
            });
        });
    }

    function poll() {
        // Skip while a cycle is running (give up on it after 60 s)
        if (busy && (Date.now() - busySince) < 60000) return;
        var cfg = Plasmoid.configuration;
        if (!cfg.routerUrl || !cfg.password) {
            errorText = i18n("Enter the router URL and password in the widget settings");
            return;
        }
        busy = true;
        busySince = Date.now();
        ensureSalt(function (e1) {
            if (e1) { fail(e1); return; }
            ensureToken(function (e2) {
                if (e2) { fail(e2); return; }
                fetchAll(false);
            });
        });
    }

    function reconnect() {
        token = "";
        discoveredSalt = "";
        busy = false;
        poll();
    }

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            var cb = root.pending[sourceName];
            delete root.pending[sourceName];
            if (cb) cb(data);
        }
    }

    Timer {
        interval: Math.max(1000, Plasmoid.configuration.pollIntervalMs)
        running: true
        repeat: true
        triggeredOnStart: true   // connect + fetch as soon as the widget loads
        onTriggered: root.poll()
    }

    Connections {
        target: Plasmoid.configuration
        function onRouterUrlChanged() { root.reconnect(); }
        function onPasswordChanged() { root.reconnect(); }
        function onSaltChanged() { root.reconnect(); }
    }

    // ------------------------------------------------------------ UI

    compactRepresentation: MouseArea {
        onClicked: root.expanded = !root.expanded
        Kirigami.Icon {
            anchors.fill: parent
            source: root.errorText !== "" ? "network-disconnect" : "network-wireless"
        }
        PlasmaComponents3.Label {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            text: root.devices.length
            font.bold: true
            visible: root.errorText === ""
        }
    }

    fullRepresentation: ColumnLayout {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 22
        Layout.minimumHeight: Kirigami.Units.gridUnit * 14
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            Kirigami.Heading {
                level: 3
                text: i18n("Devices: %1", root.devices.length)
                Layout.fillWidth: true
            }
            PlasmaComponents3.Label {
                text: root.lastUpdate
                opacity: 0.6
            }
        }

        // Cellular block: signal bars, operator, public IP
        RowLayout {
            visible: root.cellular !== null && !root.cellular.error
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing

            Row {
                spacing: 2
                Repeater {
                    model: 4
                    Item {
                        width: Kirigami.Units.smallSpacing * 1.5
                        height: Kirigami.Units.gridUnit * 1.4
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: parent.height * (index + 1) / 4
                            radius: 1
                            color: Kirigami.Theme.textColor
                            opacity: root.cellular && index < root.cellular.bars ? 1.0 : 0.25
                        }
                    }
                }
            }
            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true
                PlasmaComponents3.Label {
                    text: root.cellular ? ((root.cellular.operator || "?") + "  ·  " + root.cellular.net
                                           + (root.cellular.band ? " " + root.cellular.band : "")) : ""
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                PlasmaComponents3.Label {
                    text: root.cellular ? (root.cellular.quality + " signal"
                                           + (root.cellular.ip ? "  ·  " + root.cellular.ip : "")) : ""
                    opacity: 0.7
                    font: Kirigami.Theme.smallFont
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }
        PlasmaComponents3.Label {
            visible: root.cellular !== null && !!root.cellular.error
            text: i18n("Cellular: %1", root.cellular ? root.cellular.error : "")
            color: Kirigami.Theme.neutralTextColor
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        PlasmaComponents3.Label {
            visible: root.errorText !== ""
            text: root.errorText
            color: Kirigami.Theme.negativeTextColor
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        PlasmaComponents3.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                model: root.devices
                clip: true
                spacing: Kirigami.Units.smallSpacing
                delegate: ColumnLayout {
                    width: ListView.view.width
                    spacing: 0
                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents3.Label {
                            text: modelData.name
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        PlasmaComponents3.Label {
                            text: modelData.type
                            opacity: 0.7
                        }
                    }
                    PlasmaComponents3.Label {
                        text: {
                            var parts = [modelData.ip || modelData.mac];
                            if (modelData.signalLabel)
                                parts.push(i18n("%1 signal", modelData.signalLabel));
                            else if (modelData.signal !== null)
                                parts.push(i18n("signal %1", modelData.signal));
                            if (modelData.down)
                                parts.push("↓ " + modelData.down);
                            if (modelData.up)
                                parts.push("↑ " + modelData.up);
                            return parts.filter(function (p) { return p !== ""; }).join("  ·  ");
                        }
                        opacity: 0.7
                        font: Kirigami.Theme.smallFont
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }
        }

        // Debug: raw record of the first device, to check the field mapping
        PlasmaComponents3.TextArea {
            visible: root.rawSample !== ""
            text: root.rawSample
            readOnly: true
            wrapMode: TextEdit.Wrap
            font.family: "monospace"
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 8
        }
    }
}
