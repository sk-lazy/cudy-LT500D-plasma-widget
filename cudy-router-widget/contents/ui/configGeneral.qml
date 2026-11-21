import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_routerUrl: urlField.text
    property alias cfg_password: passwordField.text
    property alias cfg_pollIntervalMs: intervalSpin.value
    property alias cfg_salt: saltField.text
    property alias cfg_cellularInterface: cellularField.text
    property alias cfg_displayTheme: themeCombo.currentIndex
    property alias cfg_displayFont: fontField.text
    property alias cfg_displayFontScale: scaleSpin.value
    property alias cfg_transparentBackground: transparentCheck.checked   // [TRANSPARENT-BG]
    property alias cfg_showRaw: rawCheck.checked

    property string cfg_routerUrlDefault
    property string cfg_passwordDefault
    property int cfg_pollIntervalMsDefault
    property string cfg_saltDefault
    property string cfg_cellularInterfaceDefault
    property int cfg_displayThemeDefault
    property string cfg_displayFontDefault
    property int cfg_displayFontScaleDefault
    property bool cfg_transparentBackgroundDefault   // [TRANSPARENT-BG]
    property bool cfg_showRawDefault

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
            id: saltField
            Kirigami.FormData.label: i18n("Login salt:")
            placeholderText: i18n("auto-discover")
            Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        }
        QQC2.Label {
            text: i18n("Leave empty to find it automatically with avahi-browse (package avahi-utils). Or run: avahi-browse -rt _http._tcp and copy the value after salt=")
            wrapMode: Text.Wrap
            opacity: 0.7
            Layout.maximumWidth: Kirigami.Units.gridUnit * 16
        }
        QQC2.TextField {
            id: cellularField
            Kirigami.FormData.label: i18n("Cellular interface:")
            placeholderText: "4g"
            Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        }
        QQC2.Label {
            text: i18n("Lowercase name as the router expects it. Leave empty to hide cellular info.")
            wrapMode: Text.Wrap
            opacity: 0.7
            Layout.maximumWidth: Kirigami.Units.gridUnit * 16
        }
        QQC2.ComboBox {
            id: themeCombo
            Kirigami.FormData.label: i18n("Display style:")
            model: [
                i18n("System (Plasma theme)"),
                i18n("LCD - white / blue"),
                i18n("LCD - orange backlight"),
                i18n("VFD - cyan glow")
            ]
        }
        QQC2.TextField {
            id: fontField
            Kirigami.FormData.label: i18n("Display font:")
            placeholderText: "monospace"
            Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        }
        QQC2.Label {
            text: i18n("Any installed font family. A segment font such as DSEG14 Classic gives the real LCD/VFD look. Not used by the System style.")
            wrapMode: Text.Wrap
            opacity: 0.7
            Layout.maximumWidth: Kirigami.Units.gridUnit * 16
        }
        QQC2.SpinBox {
            id: scaleSpin
            Kirigami.FormData.label: i18n("Display font size (%):")
            from: 40
            to: 200
            stepSize: 5
            editable: true
        }
        // [TRANSPARENT-BG] begin - remove this block to drop the option
        QQC2.CheckBox {
            id: transparentCheck
            Kirigami.FormData.label: i18n("Background:")
            text: i18n("Transparent background")
        }
        // [TRANSPARENT-BG] end
        QQC2.CheckBox {
            id: rawCheck
            Kirigami.FormData.label: i18n("Debug:")
            text: i18n("Show raw data of the first device")
        }
    }
}
