import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    property var devices: []
    property string errorText: ""
    property string lastUpdate: ""
    property bool busy: false
    property double busySince: 0

    readonly property string scriptPath:
        Qt.resolvedUrl("../code/cudy_fetch.py").toString().replace("file://", "")

    toolTipMainText: i18n("Cudy Router")
    toolTipSubText: errorText !== "" ? errorText : i18n("%1 devices", devices.length)

    function shq(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    function poll() {
        // Skip if a request is still running (but give up on it after 60 s)
        if (busy && (Date.now() - busySince) < 60000) {
            return;
        }
        var cfg = Plasmoid.configuration;
        if (!cfg.password) {
            errorText = i18n("Set the router password in the widget settings");
            return;
        }
        busy = true;
        busySince = Date.now();
        // Trailing comment makes every command string unique so it always re-runs
        var cmd = "CUDY_URL=" + shq(cfg.routerUrl)
                + " CUDY_PASSWORD=" + shq(cfg.password)
                + " " + (cfg.pythonCommand || "python3")
                + " " + shq(scriptPath)
                + " # " + Date.now();
        executable.connectSource(cmd);
    }

    function handleResult(data) {
        busy = false;
        var out = (data["stdout"] || "").trim().split("\n");
        var line = out.length ? out[out.length - 1] : "";
        var parsed = null;
        try {
            parsed = JSON.parse(line);
        } catch (e) {
            var err = (data["stderr"] || "").trim().split("\n");
            errorText = err[err.length - 1] || i18n("Helper script returned no data");
            return;
        }
        if (parsed.ok) {
            devices = parsed.devices;
            errorText = "";
            lastUpdate = Qt.formatTime(new Date(), "hh:mm:ss");
        } else {
            errorText = parsed.error;
        }
    }

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            root.handleResult(data);
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
        function onRouterUrlChanged() { root.busy = false; root.poll(); }
        function onPasswordChanged() { root.busy = false; root.poll(); }
    }

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
                            text: modelData.type || ""
                            opacity: 0.7
                        }
                    }
                    PlasmaComponents3.Label {
                        text: {
                            var parts = [modelData.ip || modelData.mac || ""];
                            if (modelData.signal !== null && modelData.signal !== undefined)
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
    }
}
