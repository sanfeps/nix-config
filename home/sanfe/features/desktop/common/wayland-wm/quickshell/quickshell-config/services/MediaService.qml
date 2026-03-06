pragma Singleton
import QtQuick
import Quickshell.Services.Mpris

QtObject {
    id: root

    property var player: null
    property bool hasPlayer: player !== null && player.isValid

    property string trackTitle:  hasPlayer ? (player.trackTitle  || "") : ""
    property string trackArtist: hasPlayer ? (player.trackArtist || "") : ""
    property string artUrl:      hasPlayer ? (player.artUrl      || "") : ""
    property bool   playing:     hasPlayer ? (player.playbackState === MprisPlaybackState.Playing) : false
    property bool   canPlay:     hasPlayer ? player.canPlay    : false
    property bool   canPause:    hasPlayer ? player.canPause   : false
    property bool   canNext:     hasPlayer ? player.canGoNext  : false
    property bool   canPrev:     hasPlayer ? player.canGoPrevious : false

    Connections {
        target: Mpris
        function onPlayersChanged() { root._updatePlayer() }
    }

    Component.onCompleted: root._updatePlayer()

    function _updatePlayer() {
        var players = Mpris.players
        if (!players || players.length === 0) {
            root.player = null
            return
        }
        // Prefer playing player
        for (var i = 0; i < players.length; i++) {
            if (players[i].playbackState === MprisPlaybackState.Playing) {
                root.player = players[i]
                return
            }
        }
        root.player = players[0]
    }

    function playPause() { if (hasPlayer) player.togglePlaying() }
    function next()      { if (hasPlayer && canNext) player.next() }
    function previous()  { if (hasPlayer && canPrev) player.previous() }
}
