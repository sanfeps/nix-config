import QtQuick 
import QtQuick.Controls 
import QtQuick.Layouts 

import Quickshell 
import Quickshell.Wayland 

Scope {
    id: bar

    // Este es un ejemplo mínimo, puedes poner aquí tus configuraciones
    property bool showBackground: true

    Variants {
        // Para cada pantalla disponible
        model: Quickshell.screens

        PanelWindow {
            id: barRoot
            required property ShellScreen modelData
            screen: modelData

            // Barra básica
            WlrLayershell.namespace: "quickshell:bar"
            implicitHeight: 32
            color: "transparent"

            anchors {
                top: true
                left: true
                right: true
            }

            Rectangle {
                id: barBackground
                anchors.fill: parent
                color: showBackground ? "#222" : "transparent"
            }

            RowLayout {
                id: mainLayout
                anchors.fill: parent
                spacing: 10
                anchors.margins: 4

                // Lado izquierdo
                Rectangle {
                    width: 100
                    height: parent.height
                    color: "#444"
                    Text {
                        anchors.centerIn: parent
                        text: "Left"
                        color: "white"
                    }
                }

                // Centro
                Rectangle {
                    Layout.fillWidth: true
                    height: parent.height
                    color: "#555"
                    Text {
                        anchors.centerIn: parent
                        text: "Center"
                        color: "white"
                    }
                }

                // Lado derecho
                Rectangle {
                    width: 100
                    height: parent.height
                    color: "#444"
                    Text {
                        anchors.centerIn: parent
                        text: "Right"
                        color: "white"
                    }
                }
            }
        }
    }
}
 
