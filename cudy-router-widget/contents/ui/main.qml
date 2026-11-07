import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami
import "../code/cudy.js" as Cudy

PlasmoidItem {
    id: root

    readonly property string authPath: "/cgi-bin/luci/rpc/auth"
    readonly property string apiPath: "/cgi-bin/luci/rpc/app"

    property int presentCount: 0
    property int absentCount: 0
    property bool paused: false            // header button; session only
    property bool trackingStarted: false   // false until the first successful poll
    property double now: Date.now()        // ticks every second, drives "last seen" texts
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
        : (i18n("%1 devices", presentCount)
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

    // First call without params, then inclusive 1-based ranges (as the old library did).
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
                syncDevices(r.records.map(function (rec) { return Cudy.mapDevice(rec); }));
                rawSample = (Plasmoid.configuration.showRaw && r.records.length > 0)
                            ? JSON.stringify(r.records[0], null, 2) : "";
                cellular = cell;
                errorText = "";
                lastUpdate = Qt.formatTime(new Date(), "hh:mm:ss");
                busy = false;
            });
        });
    }

    ListModel { id: deviceModel }

    // Session-only tracking: devices that vanish stay in the list (greyed out)
    function syncDevices(list) {
        var plan = Cudy.planDevices(Cudy.modelRows(deviceModel), list, Date.now(), trackingStarted, 3000);
        Cudy.reconcile(deviceModel, plan.rows);
        presentCount = plan.present;
        absentCount = plan.gone;
        trackingStarted = true;
    }

    function poll() {
        if (paused) return;
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
        running: !root.paused   // resuming fires immediately (triggeredOnStart)
        repeat: true
        triggeredOnStart: true   // connect + fetch as soon as the widget loads
        onTriggered: root.poll()
    }

    Timer {
        interval: 1000
        running: root.absentCount > 0
        repeat: true
        onTriggered: root.now = Date.now()
    }

    Connections {
        target: Plasmoid.configuration
        function onRouterUrlChanged() { root.reconnect(); }
        function onPasswordChanged() { root.reconnect(); }
        function onSaltChanged() { root.reconnect(); }
    }

    // ------------------------------------------------------------ UI

    // Display styles: 0 = Plasma theme, 1 = LCD white/blue, 2 = LCD orange backlight, 3 = VFD
    readonly property var palettes: [
        null,
        { bg: "#dcebfa", ink: "#050f1f", bezel: "#2c3b52", ghost: 0.10, glass: 0.0, glow: false },
        { bg: "#ff9b1f", ink: "#120700", bezel: "#4a2400", ghost: 0.14, glass: 0.0, glow: false },
        { bg: "#030a14", ink: "#78d6ff", bezel: "#0c2234", ghost: 0.10, glass: 0.05, glow: true }
    ]
    readonly property bool styled: Plasmoid.configuration.displayTheme > 0
                                   && Plasmoid.configuration.displayTheme < palettes.length
    readonly property var pal: styled ? palettes[Plasmoid.configuration.displayTheme] : null
    readonly property color ink: pal ? pal.ink : Kirigami.Theme.textColor
    readonly property string fam: styled ? (Plasmoid.configuration.displayFont || "monospace")
                                         : Kirigami.Theme.defaultFont.family
    readonly property int caps: styled ? Font.AllUppercase : Font.MixedCase
    readonly property real letterGap: styled ? 0.6 : 0
    // font sizes: scaled down in the display styles (segment fonts are wide)
    readonly property real fs: styled ? Kirigami.Theme.defaultFont.pointSize * Plasmoid.configuration.displayFontScale / 100
                                      : Kirigami.Theme.defaultFont.pointSize
    readonly property real fsSmall: styled ? fs * 0.85 : Kirigami.Theme.smallFont.pointSize
    readonly property real fsHead: styled ? fs * 1.2 : Kirigami.Theme.defaultFont.pointSize * 1.2

    // On the desktop the display itself is the widget: no Plasma frame around it
    Plasmoid.backgroundHints: styled ? PlasmaCore.Types.NoBackground : PlasmaCore.Types.DefaultBackground

    compactRepresentation: MouseArea {
        onClicked: root.expanded = !root.expanded
        Kirigami.Icon {
            anchors.fill: parent
            source: root.errorText !== "" ? "network-disconnect" : "network-wireless"
        }
        PlasmaComponents3.Label {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            text: root.presentCount
            font.bold: true
            visible: root.errorText === ""
        }
    }

    fullRepresentation: Item {
        id: display
        Layout.minimumWidth: Kirigami.Units.gridUnit * 22
        Layout.minimumHeight: Kirigami.Units.gridUnit * 14

        // Custom colours apply to everything inside; ignored in the System style
        Kirigami.Theme.inherit: !root.styled
        Kirigami.Theme.textColor: root.ink
        Kirigami.Theme.negativeTextColor: root.ink
        Kirigami.Theme.neutralTextColor: root.ink
        Kirigami.Theme.backgroundColor: root.pal ? root.pal.bg : Kirigami.Theme.backgroundColor

        // --- display glass ---------------------------------------------------
        Rectangle {
            z: -3
            anchors.fill: parent
            visible: root.styled
            radius: 6
            border.width: 2
            border.color: root.pal ? root.pal.bezel : "transparent"
            color: root.pal ? root.pal.bg : "transparent"
        }
        // inner bezel shadow
        Rectangle {
            z: -2
            anchors.fill: parent
            anchors.margins: 3
            visible: root.styled
            radius: 4
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.25)
        }
        // glass reflection on the upper part
        Rectangle {
            z: 1
            x: 3
            y: 3
            width: parent.width - 6
            height: parent.height * 0.45
            visible: root.styled && root.pal.glass > 0
            radius: 4
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, root.pal ? root.pal.glass : 0) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
            }
        }
        // VFD phosphor glow: a blurred copy of the content, same colour, behind it
        MultiEffect {
            z: -1
            visible: root.styled && root.pal.glow
            source: content
            anchors.fill: content
            autoPaddingEnabled: true
            shadowEnabled: true
            shadowColor: root.ink
            shadowBlur: 0.9
            shadowOpacity: 0.9
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 0
            blurMax: 28
        }

        // --- content -----------------------------------------------------------
        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: root.styled ? Kirigami.Units.gridUnit * 0.8 : 0
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                Kirigami.Heading {
                    level: 3
                    text: i18n("Devices: %1", root.presentCount)
                          + (root.absentCount > 0 ? "  (" + i18n("%1 gone", root.absentCount) + ")" : "")
                    font.pointSize: root.fsHead
                    font.family: root.fam
                    font.capitalization: root.caps
                    font.letterSpacing: root.letterGap
                    Layout.fillWidth: true
                }
                PlasmaComponents3.Label {
                    text: root.paused ? i18n("paused") : root.lastUpdate
                    opacity: root.styled ? 0.9 : 0.6
                    font.family: root.fam
                    font.pointSize: root.fs
                    font.letterSpacing: root.letterGap
                }
                MouseArea {
                    id: pauseButton
                    implicitWidth: Kirigami.Units.gridUnit * 1.2
                    implicitHeight: Kirigami.Units.gridUnit * 1.2
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    opacity: containsMouse ? 1.0 : 0.7
                    onClicked: root.paused = !root.paused

                    Kirigami.Icon {
                        anchors.fill: parent
                        anchors.margins: 2
                        source: root.paused ? "media-playback-start" : "media-playback-pause"
                        isMask: true                       // draw in the display's ink colour
                        color: Kirigami.Theme.textColor
                    }
                    PlasmaComponents3.ToolTip {
                        visible: pauseButton.containsMouse
                        text: root.paused ? i18n("Resume updates") : i18n("Pause updates")
                    }
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
                                radius: root.styled ? 0 : 1
                                color: Kirigami.Theme.textColor
                                // unlit segments stay faintly visible, like on a real LCD
                                opacity: root.cellular && index < root.cellular.bars
                                         ? 1.0 : (root.pal ? root.pal.ghost : 0.25)
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
                        font.family: root.fam
                        font.pointSize: root.fs
                        font.capitalization: root.caps
                        font.letterSpacing: root.letterGap
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    PlasmaComponents3.Label {
                        text: root.cellular ? (root.cellular.quality + " signal"
                                               + (root.cellular.ip ? "  ·  " + root.cellular.ip : "")) : ""
                        opacity: root.styled ? 0.9 : 0.7
                        font.family: root.fam
                        font.pointSize: root.fsSmall
                        font.capitalization: root.caps
                        font.letterSpacing: root.letterGap
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }
            PlasmaComponents3.Label {
                visible: root.cellular !== null && !!root.cellular.error
                text: (root.cellular && root.cellular.error) ? i18n("Cellular: %1", root.cellular.error) : ""
                color: Kirigami.Theme.neutralTextColor
                font.family: root.fam
                font.pointSize: root.fs
                font.capitalization: root.caps
                font.letterSpacing: root.letterGap
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            PlasmaComponents3.Label {
                visible: root.errorText !== ""
                text: (root.styled ? "! " : "") + root.errorText
                color: Kirigami.Theme.negativeTextColor
                font.family: root.fam
                font.pointSize: root.fs
                font.bold: root.styled
                font.capitalization: root.caps
                font.letterSpacing: root.letterGap
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            PlasmaComponents3.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    model: deviceModel
                    clip: true
                    spacing: Kirigami.Units.smallSpacing
                    delegate: Item {
                        id: row
                        width: ListView.view.width
                        height: rowContent.implicitHeight

                        // vanished devices stay listed, greyed out
                        opacity: model.present ? 1.0 : 0.4
                        Behavior on opacity { NumberAnimation { duration: 400 } }

                        // flash: three inverted-colour blinks when a device appears
                        property bool inverted: false
                        property int blinkLeft: 0
                        property double flashUntil: model.flashUntil
                        property int bars: model.bars   // -1 = wired / unknown
                        property bool wired: model.type === "ethernet"
                        function flash() {
                            inverted = true;
                            blinkLeft = 5;   // 5 toggles: on, off, on, off, on, off
                        }
                        onFlashUntilChanged: if (flashUntil > Date.now()) flash()
                        Component.onCompleted: if (flashUntil > Date.now()) flash()
                        Timer {
                            interval: 250
                            repeat: true
                            running: row.blinkLeft > 0
                            onTriggered: {
                                row.inverted = !row.inverted;
                                row.blinkLeft--;
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            visible: row.inverted
                            color: Kirigami.Theme.textColor
                        }

                        ColumnLayout {
                            id: rowContent
                            width: parent.width
                            spacing: 0
                            RowLayout {
                                Layout.fillWidth: true
                                PlasmaComponents3.Label {
                                    text: model.name
                                    color: row.inverted ? Kirigami.Theme.backgroundColor : Kirigami.Theme.textColor
                                    font.bold: true
                                    font.pointSize: root.fs
                                    font.family: root.fam
                                    font.capitalization: root.caps
                                    font.letterSpacing: root.letterGap
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                PlasmaComponents3.Label {
                                    text: model.type
                                    color: row.inverted ? Kirigami.Theme.backgroundColor : Kirigami.Theme.textColor
                                    opacity: root.styled ? 0.9 : 0.7
                                    font.pointSize: root.fs
                                    font.family: root.fam
                                    font.capitalization: root.caps
                                    font.letterSpacing: root.letterGap
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.largeSpacing
                                // Status slot: Wi-Fi signal bars, or an Ethernet port for wired clients.
                                // Always occupies the same space so IPs line up between rows.
                                Item {
                                    implicitWidth: barsRow.implicitWidth
                                    implicitHeight: barsRow.implicitHeight
                                    Layout.alignment: Qt.AlignVCenter

                                    Row {
                                        id: barsRow
                                        spacing: 2
                                        opacity: (model.present && row.bars >= 0) ? 1 : 0
                                        Repeater {
                                            model: 4
                                            Item {
                                                width: Kirigami.Units.smallSpacing
                                                height: Kirigami.Units.gridUnit * 0.8
                                                Rectangle {
                                                    anchors.bottom: parent.bottom
                                                    width: parent.width
                                                    height: parent.height * (index + 1) / 4
                                                    radius: root.styled ? 0 : 1
                                                    color: row.inverted ? Kirigami.Theme.backgroundColor : Kirigami.Theme.textColor
                                                    opacity: index < row.bars ? 1.0 : (root.pal ? root.pal.ghost : 0.25)
                                                }
                                            }
                                        }
                                    }

                                    // Ethernet port (RJ45 front view): latch on top, frame, four contacts
                                    Item {
                                        id: ethIcon
                                        anchors.fill: parent
                                        opacity: (model.present && row.wired && row.bars < 0) ? 1 : 0
                                        readonly property color ink: row.inverted ? Kirigami.Theme.backgroundColor
                                                                                  : Kirigami.Theme.textColor
                                        Rectangle {          // latch
                                            x: (parent.width - width) / 2
                                            width: parent.width * 0.4
                                            height: 2
                                            color: ethIcon.ink
                                        }
                                        Rectangle {          // frame
                                            anchors.bottom: parent.bottom
                                            width: parent.width
                                            height: parent.height - 3
                                            color: "transparent"
                                            border.width: 1
                                            border.color: ethIcon.ink
                                            Row {            // contacts
                                                anchors.centerIn: parent
                                                spacing: 2
                                                Repeater {
                                                    model: 4
                                                    Rectangle {
                                                        width: 1
                                                        height: Math.max(3, ethIcon.height * 0.35)
                                                        color: ethIcon.ink
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                PlasmaComponents3.Label {
                                    text: (model.ip || model.mac)
                                          + (model.present
                                             ? ((row.bars >= 0 || row.wired) ? "" : "  ·  " + i18n("online"))
                                             : "  ·  " + i18n("last seen %1", Cudy.formatAgo(root.now - model.lastSeen)))
                                    color: row.inverted ? Kirigami.Theme.backgroundColor : Kirigami.Theme.textColor
                                    opacity: root.styled ? 0.9 : 0.7
                                    font.family: root.fam
                                    font.pointSize: root.fsSmall
                                    font.capitalization: root.caps
                                    font.letterSpacing: root.letterGap
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                PlasmaComponents3.Label {
                                    visible: text !== ""
                                    text: {
                                        var rates = [];
                                        if (model.down) rates.push("↓ " + model.down);
                                        if (model.up) rates.push("↑ " + model.up);
                                        return rates.join("  ");
                                    }
                                    color: row.inverted ? Kirigami.Theme.backgroundColor : Kirigami.Theme.textColor
                                    opacity: root.styled ? 0.9 : 0.7
                                    font.family: root.fam
                                    font.pointSize: root.fsSmall
                                    font.letterSpacing: root.letterGap
                                }
                            }
                            // thin divider between entries (display styles only)
                            Rectangle {
                                visible: root.styled
                                Layout.fillWidth: true
                                Layout.topMargin: 2
                                height: 1
                                color: Kirigami.Theme.textColor
                                opacity: 0.15
                            }
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
}
