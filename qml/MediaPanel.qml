import QtQuick 2.7
import QtMultimedia 5.6
import QtQuick.Controls 2.15
import Qt.labs.platform 1.1
import Qt.labs.settings 1.0

Item {
    id: root
    anchors.fill: parent
    visible: false
    z: 200

    property real textScale: 1.0
    function ts(v) { return units.gu(v * textScale) }

    // ── API pública para MediaWidget y Main ───────────────────────────────
    readonly property bool   isPlaying:   player.playbackState === Audio.PlayingState
    readonly property bool   hasTrack:    _selIdx >= 0 && musicModel.count > 0
    readonly property string currentName: _nameAt(_selIdx)

    // Referencia al objeto NavHttp (Rust): expone la biblioteca de música local.
    // La música se incorpora vía el selector de ficheros nativo (ver FileDialog más
    // abajo), que copia/symlinka los ficheros elegidos a ~/.local/share/navius/Music/.
    property var navHttpObj: null

    // Referencia al objeto NavTts para poder llamar set_music_volume().
    // AalMediaPlayerService::setVolume es un no-op en media-hub; la única
    // forma de cambiar el volumen del stream de media-hub-server es via
    // pa_context_set_sink_input_volume (implementado en NavTts.set_music_volume).
    property var  ttsObj:      null
    property real duckVolume:  0.70   // fracción de volumen durante TTS (0.10–1.00)

    signal duckVolumeEdited(real vol) // para que Main.qml actualice appSettings

    onDuckVolumeChanged: if (duckSlider._ready) duckSlider.value = duckVolume

    // Recarga la biblioteca al hacerse visible.
    onVisibleChanged: if (visible) reloadLibrary()

    // Aplica el volumen PA correcto (respetando estado duck).
    // Necesita que el stream PA de media-hub-server ya exista.
    function _applyVolume() {
        if (!root.ttsObj) return
        var v = root._mediaDucked ? root._duckSavedVol * root.duckVolume : mediaSt.volume
        root.ttsObj.set_music_volume(v)
    }

    property int  _selIdx:        -1
    property real _duckSavedVol:  1.0
    property bool _mediaDucked:   false
    property bool _duckActive:    false
    property bool _showHelp:      false

    Settings {
        id: mediaSt
        fileName: "navius-media"
        property bool duckOnTts: true
        property real volume:    1.0
    }

    Component.onCompleted: {
        player.volume = mediaSt.volume
    }

    // ── Modelo de biblioteca ───────────────────────────────────────────────
    ListModel { id: musicModel }

    // Vuelca la lista del sandbox (JSON desde Rust) al modelo, preservando la
    // pista en curso si sigue existiendo.
    function reloadLibrary() {
        if (!root.navHttpObj) return
        var curPath = (_selIdx >= 0 && _selIdx < musicModel.count)
                      ? musicModel.get(_selIdx).path : ""
        musicModel.clear()
        var arr = []
        try { arr = JSON.parse(root.navHttpObj.music_list()) } catch (e) { arr = [] }
        for (var i = 0; i < arr.length; i++)
            musicModel.append({ name: arr[i].name, path: arr[i].path })
        // Re-localizar la pista en curso por ruta.
        if (curPath !== "") {
            _selIdx = -1
            for (var j = 0; j < musicModel.count; j++) {
                if (musicModel.get(j).path === curPath) { _selIdx = j; break }
            }
        }
    }

    function _nameAt(idx) {
        if (idx < 0 || idx >= musicModel.count) return ""
        return _stripExt(musicModel.get(idx).name)
    }

    function _stripExt(n) { return n ? n.replace(/\.[^.]+$/, "") : "" }

    function playPause() {
        if (!hasTrack) return
        if (player.playbackState === Audio.PlayingState) player.pause()
        else player.play()
    }

    function playNext() { _changeTrack(1) }
    function playPrev() { _changeTrack(-1) }
    function stop() { player.stop(); _selIdx = -1 }

    function _changeTrack(dir) {
        if (musicModel.count === 0) return
        var next = _selIdx + dir
        if (next < 0) next = musicModel.count - 1
        if (next >= musicModel.count) next = 0
        _selIdx = next
        _loadAndPlay()
        trackList.positionViewAtIndex(_selIdx, ListView.Center)
    }

    function _loadAndPlay() {
        if (_selIdx < 0 || _selIdx >= musicModel.count) return
        var path = musicModel.get(_selIdx).path
        if (!path) return
        player.source = "file://" + path
        playTimer.restart()   // delay 50 ms para que media-hub procese setMedia antes de play()
    }

    function removeTrack(idx) {
        if (idx < 0 || idx >= musicModel.count || !root.navHttpObj) return
        var name = musicModel.get(idx).name
        var wasPlaying = (idx === _selIdx)
        if (wasPlaying) { player.stop(); _selIdx = -1 }
        if (root.navHttpObj.music_remove(name)) reloadLibrary()
    }

    // ── Ducking: atenúa la música durante TTS y restaura al terminar ───────
    function duck(on) {
        if (!mediaSt.duckOnTts) return
        if (on) {
            duckRestoreTimer.stop()
            _duckActive = true
            if (!_mediaDucked) {
                _duckSavedVol = mediaSt.volume
                _mediaDucked = true
                if (root.ttsObj) root.ttsObj.set_music_volume(_duckSavedVol * root.duckVolume)
            }
        } else {
            _duckActive = false
            duckRestoreTimer.restart()
        }
    }

    Timer {
        id: duckRestoreTimer
        interval: 600; repeat: false
        onTriggered: {
            if (_mediaDucked && !_duckActive) {
                if (root.ttsObj) root.ttsObj.set_music_volume(_duckSavedVol)
                _mediaDucked = false
            }
        }
    }

    signal dismissed()

    // ── Importación de música vía selector de ficheros nativo ──────────────
    // (bajo Wayland + xdg-desktop-portal-phosh usa el picker nativo del
    // sistema; sustituye al ContentPeerPicker/ContentTransfer de Lomiri)
    FileDialog {
        id: musicFileDialog
        title: i18n.tr("Elegir música")
        fileMode: FileDialog.OpenFiles
        nameFilters: [i18n.tr("Audio") + " (*.mp3 *.ogg *.oga *.flac *.wav *.m4a *.opus)"]
        onAccepted: {
            var urls = []
            for (var i = 0; i < files.length; i++) urls.push(files[i].toString())
            console.log("[navius music] picked " + urls.length + " file(s)")
            if (urls.length > 0 && root.navHttpObj) {
                var n = root.navHttpObj.music_import(urls.join("\n"))
                console.log("[navius music] music_import returned " + n)
            }
            root.reloadLibrary()
        }
    }

    // ── Fondo oscuro ──────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent; color: "#CC000000"
        MouseArea { anchors.fill: parent; onClicked: root.dismissed() }
    }

    // ── Panel principal (bottom sheet) ────────────────────────────────────
    Rectangle {
        id: panel
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: parent.height * 0.88
        color: "#1A1F2E"; radius: ts(1.5); clip: true

        // Esquinas superiores redondeadas, inferiores cuadradas
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: parent.radius; color: parent.color
        }

        // ── Header ────────────────────────────────────────────────────────
        Rectangle {
            id: header
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: ts(5.5); color: "#0F1420"
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: panel.radius; color: parent.color
            }
            Label {
                anchors { left: parent.left; leftMargin: ts(2); verticalCenter: parent.verticalCenter }
                text: "🎵 " + i18n.tr("Música"); color: "white"; font.pixelSize: ts(2.2)
            }
            Row {
                anchors { right: parent.right; rightMargin: ts(2); verticalCenter: parent.verticalCenter }
                spacing: ts(2.5)
                Label {
                    text: "＋ " + i18n.tr("Añadir"); color: "#2196F3"; font.pixelSize: ts(2.0)
                    anchors.verticalCenter: parent.verticalCenter
                    MouseArea { anchors.fill: parent; onClicked: musicFileDialog.open() }
                }
                Label {
                    text: "✕"; color: "#90A4AE"; font.pixelSize: ts(2.8)
                    anchors.verticalCenter: parent.verticalCenter
                    MouseArea { anchors.fill: parent; onClicked: root.dismissed() }
                }
            }
        }

        // ── Lista de pistas ───────────────────────────────────────────────
        ListView {
            id: trackList
            anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: controls.top }
            clip: true
            ScrollBar.vertical: ScrollBar {}

            model: musicModel

            delegate: Rectangle {
                width: trackList.width; height: ts(5.5)
                color: index === root._selIdx ? "#182840" : (index % 2 === 0 ? "#1A1F2E" : "#161B2B")

                Rectangle {
                    visible: index === root._selIdx
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: ts(0.4); color: "#2196F3"
                }
                Row {
                    anchors { left: parent.left; right: removeBtn.left; verticalCenter: parent.verticalCenter
                              leftMargin: ts(1.8); rightMargin: ts(1) }
                    spacing: ts(1)
                    Label {
                        text: index === root._selIdx ? (root.isPlaying ? "▶" : "⏸") : "♪"
                        color: index === root._selIdx ? "#2196F3" : "#546E7A"
                        font.pixelSize: ts(2); anchors.verticalCenter: parent.verticalCenter
                    }
                    Label {
                        text: root._stripExt(model.name)
                        color: index === root._selIdx ? "white" : "#B0BEC5"
                        font.pixelSize: ts(1.75); elide: Text.ElideRight
                        width: trackList.width - ts(1.8) - ts(2) - ts(1) * 2 - ts(5)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                MouseArea {
                    anchors { left: parent.left; right: removeBtn.left; top: parent.top; bottom: parent.bottom }
                    onClicked: {
                        root._selIdx = index
                        root._loadAndPlay()
                    }
                }
                Label {
                    id: removeBtn
                    anchors { right: parent.right; rightMargin: ts(1.5); verticalCenter: parent.verticalCenter }
                    text: "🗑"; color: "#546E7A"; font.pixelSize: ts(2)
                    MouseArea { anchors.fill: parent; anchors.margins: -ts(1); onClicked: root.removeTrack(index) }
                }
            }

            // Estado vacío: invita a importar y muestra la ayuda del symlink.
            Column {
                anchors.centerIn: parent
                visible: musicModel.count === 0
                width: parent.width - ts(5); spacing: ts(1.5)
                Label {
                    width: parent.width
                    text: i18n.tr("La biblioteca está vacía")
                    color: "#90A4AE"; font.pixelSize: ts(2.0)
                    horizontalAlignment: Text.AlignHCenter
                }
                Label {
                    width: parent.width
                    text: i18n.tr("Pulsa «＋ Añadir» para importar música desde el gestor de archivos.")
                    color: "#546E7A"; font.pixelSize: ts(1.7)
                    wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        // ── Controles ─────────────────────────────────────────────────────
        Rectangle {
            id: controls
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            color: "#0F1420"
            height: ctrlCol.implicitHeight + ts(3)

            Audio {
                id: player
                autoPlay: false
                onPlaybackStateChanged: {
                    if (playbackState === Audio.PlayingState) volApplyTimer.restart()
                }
                onStatusChanged: {
                    if (status === Audio.Buffered || status === Audio.Loaded)
                        volApplyTimer.restart()
                    if (status === Audio.EndOfMedia) root.playNext()
                }
            }

            // Espera a que el stream PA de media-hub exista (~200 ms tras play).
            Timer {
                id: volApplyTimer
                interval: 200; repeat: false
                onTriggered: root._applyVolume()
            }

            // Retrasa play() 50 ms para que media-hub procese el setMedia
            // D-Bus antes de recibir la orden de reproducción. Sin este retardo
            // play() llega a media-hub antes de que la sesión esté lista y
            // la primera selección de pista no produce audio.
            Timer {
                id: playTimer
                interval: 50; repeat: false
                onTriggered: player.play()
            }

            Column {
                id: ctrlCol
                anchors { left: parent.left; right: parent.right
                          top: parent.top; topMargin: ts(1.5)
                          leftMargin: ts(2); rightMargin: ts(2) }
                spacing: ts(1)

                Label {
                    width: parent.width
                    text: root.hasTrack ? root.currentName : i18n.tr("Sin pista")
                    color: root.hasTrack ? "white" : "#546E7A"
                    font.pixelSize: ts(2.0); elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                }

                Item {
                    width: parent.width; height: ts(3)
                    visible: player.duration > 0

                    Label {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        text: _fmt(player.position); color: "#78909C"; font.pixelSize: ts(1.4)
                    }
                    Label {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        text: _fmt(player.duration); color: "#78909C"; font.pixelSize: ts(1.4)
                    }
                    Item {
                        id: progressTrack
                        anchors { left: parent.left; right: parent.right
                                  leftMargin: ts(4.5); rightMargin: ts(4.5)
                                  verticalCenter: parent.verticalCenter }
                        height: ts(1.5)
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width; height: ts(0.5)
                            color: "#2A3550"; radius: height / 2
                            Rectangle {
                                width: player.duration > 0 ? parent.width * player.position / player.duration : 0
                                height: parent.height; radius: parent.radius; color: "#2196F3"
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -ts(1)
                            onClicked: {
                                if (player.duration > 0)
                                    player.seek(Math.max(0, Math.min(1, mouseX / parent.width)) * player.duration)
                            }
                        }
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: ts(4.5)
                    height: ts(8)

                    Label {
                        text: "⏮"; font.pixelSize: ts(3.5); color: "#90A4AE"
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea { anchors.fill: parent; onClicked: root.playPrev() }
                    }
                    Rectangle {
                        width: ts(8); height: ts(8); radius: width / 2
                        color: root.isPlaying ? "#1565C0" : "#1A2A40"
                        border.color: "#2196F3"; border.width: ts(0.25)
                        anchors.verticalCenter: parent.verticalCenter
                        Label {
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: root.isPlaying ? 0 : ts(0.2)
                            text: root.isPlaying ? "⏸" : "▶"
                            color: "white"; font.pixelSize: ts(3.5)
                        }
                        MouseArea { anchors.fill: parent; onClicked: root.playPause() }
                    }
                    Label {
                        text: "⏭"; font.pixelSize: ts(3.5); color: "#90A4AE"
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea { anchors.fill: parent; onClicked: root.playNext() }
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: ts(1.5)
                    Label { text: "🔈"; font.pixelSize: ts(2.2); anchors.verticalCenter: parent.verticalCenter }
                    Slider {
                        id: volSlider
                        width: ts(20)
                        from: 0; to: 1
                        anchors.verticalCenter: parent.verticalCenter
                        // _ready evita que el onValueChanged=0 espurio de
                        // inicialización de Lomiri Slider sobreescriba player.volume
                        property bool _ready: false
                        Component.onCompleted: { value = mediaSt.volume; _ready = true }
                        onValueChanged: {
                            if (!_ready) return
                            mediaSt.volume = value
                            if (root._mediaDucked) {
                                root._duckSavedVol = value  // restaurar a este nivel al salir del duck
                            } else {
                                if (root.ttsObj) root.ttsObj.set_music_volume(value)
                            }
                        }
                    }
                    Label { text: "🔊"; font.pixelSize: ts(2.2); anchors.verticalCenter: parent.verticalCenter }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: ts(1.5)
                    visible: mediaSt.duckOnTts
                    Label {
                        text: "🔉"; font.pixelSize: ts(2.2); anchors.verticalCenter: parent.verticalCenter
                    }
                    Slider {
                        id: duckSlider
                        width: ts(17)
                        from: 0.10; to: 1.0
                        anchors.verticalCenter: parent.verticalCenter
                        property bool _ready: false
                        Component.onCompleted: { value = root.duckVolume; _ready = true }
                        onValueChanged: {
                            if (!_ready) return
                            root.duckVolumeEdited(value)
                        }
                    }
                    Label {
                        text: Math.round(duckSlider.value * 100) + "%"
                        color: "#78909C"; font.pixelSize: ts(1.6); width: ts(4)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: ts(1)
                    Switch {
                        id: duckSwitch
                        checked: mediaSt.duckOnTts
                        anchors.verticalCenter: parent.verticalCenter
                        onCheckedChanged: mediaSt.duckOnTts = checked
                    }
                    Label {
                        text: i18n.tr("Bajar volumen al hablar")
                        color: "#90A4AE"; font.pixelSize: ts(1.6)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // ── Ayuda: evitar duplicar la música con un symlink ────────
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: (root._showHelp ? "▾ " : "▸ ") + i18n.tr("¿Cómo evitar duplicar la música?")
                    color: "#2196F3"; font.pixelSize: ts(1.6)
                    MouseArea { anchors.fill: parent; anchors.margins: -ts(0.8)
                                onClicked: root._showHelp = !root._showHelp }
                }
                Rectangle {
                    width: parent.width; visible: root._showHelp
                    height: helpCol.implicitHeight + ts(2)
                    color: "#141A28"; radius: ts(1)
                    Column {
                        id: helpCol
                        anchors { left: parent.left; right: parent.right; top: parent.top
                                  margins: ts(1.5) }
                        spacing: ts(1)
                        Label {
                            width: parent.width; wrapMode: Text.WordWrap
                            color: "#B0BEC5"; font.pixelSize: ts(1.55)
                            text: i18n.tr("Al añadir música, los ficheros se copian a la carpeta de la app, ocupando espacio extra. Para no duplicarlos, un usuario avanzado puede crear enlaces simbólicos a su carpeta ~/Music desde una Terminal (o por SSH). Navius reproducirá los enlaces sin copiar nada:")
                        }
                        Rectangle {
                            width: parent.width; height: cmdLabel.implicitHeight + ts(1.5)
                            color: "#0B0F18"; radius: ts(0.8)
                            Label {
                                id: cmdLabel
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                                          margins: ts(1) }
                                wrapMode: Text.WrapAnywhere
                                color: "#80CBC4"; font.pixelSize: ts(1.45)
                                font.family: "Ubuntu Mono"
                                text: "mkdir -p \"" + root._musicDir() + "\"\n" +
                                      "find ~/Music -type f \\( -iname '*.mp3' -o -iname '*.flac' " +
                                      "-o -iname '*.ogg' -o -iname '*.m4a' -o -iname '*.opus' " +
                                      "-o -iname '*.wav' -o -iname '*.aac' \\) " +
                                      "-exec ln -s {} \"" + root._musicDir() + "/\" \\;"
                            }
                        }
                        Label {
                            width: parent.width; wrapMode: Text.WordWrap
                            color: "#607D8B"; font.pixelSize: ts(1.4)
                            text: i18n.tr("Después, vuelve a abrir el reproductor para ver tu música. Para quitar un enlace usa la papelera 🗑 (no borra el fichero original).")
                        }
                    }
                }
            }
        }
    }

    // Ruta real de la biblioteca en el sandbox (para el comando de ayuda).
    function _musicDir() {
        return root.navHttpObj ? root.navHttpObj.music_dir()
                               : "~/.local/share/navius/Music"
    }

    function _fmt(ms) {
        var s = Math.floor(ms / 1000), m = Math.floor(s / 60)
        s = s % 60; return m + ":" + (s < 10 ? "0" : "") + s
    }
}
