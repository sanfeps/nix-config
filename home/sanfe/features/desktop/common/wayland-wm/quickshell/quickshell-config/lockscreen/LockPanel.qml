import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".." as Root

Item {
    id: panel
    implicitWidth:  360
    implicitHeight: content.implicitHeight + Root.Theme.spacingXxl * 2

    signal unlockSuccess()

    property string _password:    ""
    property string _errorMsg:    ""
    property bool   _checking:    false

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    function pad(n: int): string { return n < 10 ? "0" + n : "" + n }

    Column {
        id: content
        anchors.centerIn: parent
        spacing: Root.Theme.spacingXl
        width: parent.width - Root.Theme.spacingXxl * 2

        // Clock display
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Root.Theme.spacingSm

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: pad(clock.hours) + ":" + pad(clock.minutes)
                font.family:    Root.Theme.fontFamilyAlt
                font.pixelSize: 72
                font.weight:    Font.Light
                color: Root.Colors.surfaceFg
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: {
                    var d = new Date()
                    var days   = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]
                    var months = ["January","February","March","April","May","June","July","August","September","October","November","December"]
                    return days[d.getDay()] + ", " + months[d.getMonth()] + " " + d.getDate()
                }
                font.family:    Root.Theme.fontFamily
                font.pixelSize: Root.Theme.fontSizeLg
                color: Root.Colors.surfaceFgVariant
            }
        }

        // Password input
        Rectangle {
            width:  parent.width
            height: 52
            radius: Root.Theme.radiusLg
            color:  Root.Colors.surfaceVariant
            border.color: panel._checking ? Root.Colors.outline : (panel._errorMsg !== "" ? Root.Colors.error : Qt.rgba(Root.Colors.outline.r, Root.Colors.outline.g, Root.Colors.outline.b, 0.5))
            border.width: 2

            Behavior on border.color { ColorAnimation { duration: Root.Theme.animFast } }

            RowLayout {
                anchors { fill: parent; leftMargin: Root.Theme.spacingMd; rightMargin: Root.Theme.spacingMd }
                spacing: Root.Theme.spacingMd

                Text {
                    text: "lock"
                    font.family:    "Material Symbols Rounded"
                    font.pixelSize: Root.Theme.iconMd
                    color: Root.Colors.surfaceFgVariant
                }

                TextInput {
                    id: passwordInput
                    Layout.fillWidth: true
                    echoMode:         TextInput.Password
                    font.family:      Root.Theme.fontFamilyMono
                    font.pixelSize:   Root.Theme.fontSizeMd
                    color:            Root.Colors.surfaceFg
                    cursorVisible:    activeFocus

                    Keys.onReturnPressed: panel._tryUnlock()
                    Keys.onEscapePressed: panel._clearInput()

                    onTextChanged: {
                        panel._password = text
                        panel._errorMsg = ""
                    }
                }

                // Clear / loading indicator
                Text {
                    visible:        panel._password !== "" && !panel._checking
                    text:           "backspace"
                    font.family:    "Material Symbols Rounded"
                    font.pixelSize: Root.Theme.iconSm
                    color:          Root.Colors.surfaceFgVariant

                    MouseArea {
                        anchors.fill: parent
                        onClicked:    panel._clearInput()
                    }
                }

                Rectangle {
                    visible: panel._checking
                    width:  16
                    height: 16
                    radius: 8
                    color:  "transparent"
                    border.color: Root.Colors.primary
                    border.width: 2

                    RotationAnimation on rotation {
                        running: panel._checking
                        loops: Animation.Infinite
                        from: 0
                        to:   360
                        duration: 800
                    }
                }
            }
        }

        // Error message
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: panel._errorMsg !== ""
            text:    panel._errorMsg
            font.family:    Root.Theme.fontFamily
            font.pixelSize: Root.Theme.fontSizeSm
            color: Root.Colors.error
        }
    }

    // PAM authentication process
    Process {
        id: pamProcess
        command: ["qs-pam-auth", Quickshell.env("USER") || "sanfe"]
        stdin: StdinWriter { id: pamStdin }
        onRunningChanged: {
            if (running) {
                // Write password and close stdin immediately after process starts
                pamStdin.write(panel._password + "\n")
                pamStdin.close()
            } else {
                panel._checking = false
                if (exitCode === 0) {
                    panel._clearInput()
                    panel.unlockSuccess()
                } else {
                    panel._errorMsg = "Incorrect password"
                    panel._clearInput()
                    passwordInput.forceActiveFocus()
                }
            }
        }
    }

    function _tryUnlock() {
        if (_password === "" || _checking) return
        _checking = true
        _errorMsg  = ""
        pamProcess.running = true
    }

    function _clearInput() {
        _password         = ""
        _checking         = false
        passwordInput.text = ""
        passwordInput.forceActiveFocus()
    }

    Component.onCompleted: passwordInput.forceActiveFocus()
}
