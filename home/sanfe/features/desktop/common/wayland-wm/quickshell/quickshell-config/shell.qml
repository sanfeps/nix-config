//@ pragma UseQApplication

import "./modules/bar/"

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell

ShellRoot {

	property bool enableBar: true

	LazyLoader { active: enableBar; component: Bar {} }

}
