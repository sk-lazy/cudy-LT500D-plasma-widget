import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_routerUrl: urlField.text
    property alias cfg_password: passwordField.text
    property alias cfg_pollIntervalMs: intervalSpin.value
    property alias cfg_pythonCommand: pythonField.text

    property string cfg_routerUrlDefault
    property string cfg_passwordDefault
    property int cfg_pollIntervalMsDefault
    property string cfg_pythonCommandDefault

    Kirigami.FormLayout {
        QQC2.TextField {
            id: urlField
            Kirigami.FormData.label: i18n("Router URL:")
            placeholderText: "https://192.168.10.1"
            Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        }
        QQC2.TextField {
            id: passwordField
            Kirigami.FormData.label: i18n("Password:")
            echoMode: TextInput.Password
            Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        }
        QQC2.SpinBox {
            id: intervalSpin
            Kirigami.FormData.label: i18n("Refresh interval (ms):")
            from: 1000
            to: 3600000
            stepSize: 500
            editable: true
        }
        QQC2.TextField {
            id: pythonField
            Kirigami.FormData.label: i18n("Python command:")
            placeholderText: "python3"
            Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        }
        QQC2.Label {
            text: i18n("Use a full path (e.g. /home/you/venv/bin/python) if cudypy is installed in a virtualenv.")
            wrapMode: Text.Wrap
            opacity: 0.7
            Layout.maximumWidth: Kirigami.Units.gridUnit * 16
        }
    }
}
