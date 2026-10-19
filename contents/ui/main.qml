import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import "parse.js" as Parse

PlasmoidItem {
    id: root

    property bool loading: false
    property string errorText: ""
    property string lastUpdate: ""
    property int weekOffset: 0
    property var allLessons: []      // every lesson of the semester, from the parser
    property var days: []            // [{date,label,isToday,events:[...]}]
    property int startMin: 8 * 60
    property int endMin: 18 * 60
    property int nowMin: -1
    property date monday: new Date()
    readonly property var cfg: Plasmoid.configuration

    readonly property string cfgKey: [cfg.files, cfg.showCancelled].join("|")
    onCfgKeyChanged: refresh()

    Plasmoid.icon: "view-calendar-timeline"
    toolTipMainText: cfg.courseLabel || i18n("Orario UniPD")
    toolTipSubText: errorText

    Timer {
        interval: Math.max(5, cfg.refreshMinutes) * 60000
        running: true; repeat: true
        onTriggered: root.refresh()
    }
    Timer {
        interval: 60000
        running: true; repeat: true; triggeredOnStart: true
        onTriggered: { var n = new Date(); root.nowMin = n.getHours() * 60 + n.getMinutes() }
    }

    // ---------- helpers ----------
    function pad(n) { return (n < 10 ? "0" : "") + n }
    function fmtDate(d) { return pad(d.getDate()) + "-" + pad(d.getMonth() + 1) + "-" + d.getFullYear() }
    function isoDate(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) }
    function parseDate(s) {
        var m = /^(\d{1,2})-(\d{1,2})-(\d{4})/.exec(s)
        if (m) return new Date(+m[3], +m[2] - 1, +m[1])
        m = /^(\d{4})-(\d{2})-(\d{2})/.exec(s)
        if (m) return new Date(+m[1], +m[2] - 1, +m[3])
        return null
    }
    function toMin(s) {
        var m = /(\d{1,2})[:.](\d{2})/.exec(String(s))
        return m ? (+m[1]) * 60 + (+m[2]) : NaN
    }
    function esc(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
    // Each subject gets the next hue on the golden-angle wheel, so colours stay well apart
    property var colorMap: ({})
    property int colorCount: 0
    function colorFor(t) {
        if (colorMap[t] === undefined) {
            var hue = (colorCount * 137.508) % 360
            var light = (colorCount % 2 === 0) ? 0.38 : 0.44
            colorMap[t] = Qt.hsla(hue / 360, 0.55, light, 1)
            colorCount++
        }
        return colorMap[t]
    }
    function mondayOf(offset) {
        var d = new Date(); d.setHours(0, 0, 0, 0)
        d.setDate(d.getDate() - ((d.getDay() + 6) % 7) + offset * 7)
        return d
    }

    // side-by-side lanes for overlapping lessons
    function layoutDay(evs) {
        evs.sort(function (a, b) { return a.s - b.s || a.e - b.e })
        var cluster = [], clusterEnd = -1, lanesEnd = []
        function flush() {
            cluster.forEach(function (c) { c.lanes = lanesEnd.length })
            cluster = []; lanesEnd = []; clusterEnd = -1
        }
        evs.forEach(function (ev) {
            if (cluster.length && ev.s >= clusterEnd) flush()
            var lane = 0
            while (lane < lanesEnd.length && lanesEnd[lane] > ev.s) lane++
            lanesEnd[lane] = ev.e
            ev.lane = lane
            cluster.push(ev)
            clusterEnd = Math.max(clusterEnd, ev.e)
        })
        flush()
    }

    // Download every selected teaching's semester XML once; week navigation is then purely local
    function refresh() {
        var files = cfg.files.split(",").filter(function (f) { return f })
        if (!files.length) {
            allLessons = []
            errorText = i18n("Widget non configurato: clic destro → Configura")
            render()
            return
        }
        loading = true
        errorText = ""
        var pending = files.length, acc = [], failed = ""
        files.forEach(function (f) {
            var xhr = new XMLHttpRequest()
            xhr.onreadystatechange = function () {
                if (xhr.readyState !== XMLHttpRequest.DONE) return
                if (xhr.status === 200) acc = acc.concat(Parse.parseLessons(xhr.responseText))
                else if (!failed) failed = f + ": HTTP " + xhr.status
                if (--pending > 0) return
                var titles = []
                acc.forEach(function (l) { if (titles.indexOf(l.title) < 0) titles.push(l.title) })
                titles.sort().forEach(function (t) { colorFor(t) }) // stable colours across weeks
                allLessons = acc
                errorText = failed ? i18n("Download non riuscito: %1", failed) : ""
                lastUpdate = Qt.formatTime(new Date(), "hh:mm")
                loading = false
                render()
            }
            xhr.open("GET", Parse.API + "//App/zipped.php?file=" + f) // double slash exactly as the official app
            xhr.send()
        })
    }

    function render() {
        var mon = mondayOf(weekOffset)
        monday = mon
        var next = new Date(mon.getFullYear(), mon.getMonth(), mon.getDate() + 7)
        var seen = {}, found = []
        allLessons.forEach(function (l) {
            var d = parseDate(l.date), s = toMin(l.start), e = toMin(l.end)
            if (!d || d < mon || d >= next || isNaN(s) || isNaN(e)) return
            if (l.cancelled && !cfg.showCancelled) return
            var key = l.date + l.start + l.title + l.room
            if (seen[key]) return
            seen[key] = true
            found.push({ date: d, start: l.start, end: l.end, s: s, e: e > s ? e : s + 60, title: l.title,
                         room: l.room, site: l.site, teacher: l.teacher, cancelled: l.cancelled, color: colorFor(l.title) })
        })
        var today = isoDate(new Date()), out = [], minS = 8 * 60, maxE = 18 * 60
        for (var i = 0; i < 7; i++) {
            var d2 = new Date(mon.getFullYear(), mon.getMonth(), mon.getDate() + i)
            var evs = found.filter(function (n) { return isoDate(n.date) === isoDate(d2) })
            if (i >= 5 && evs.length === 0) continue
            layoutDay(evs)
            evs.forEach(function (n) {
                minS = Math.min(minS, Math.floor(n.s / 60) * 60)
                maxE = Math.max(maxE, Math.ceil(n.e / 60) * 60)
            })
            out.push({ date: d2, label: Qt.locale().toString(d2, "ddd d/M"), isToday: isoDate(d2) === today, events: evs })
        }
        startMin = minS
        endMin = maxE
        days = out
    }

    Component.onCompleted: refresh()

    // ---------- UI ----------
    fullRepresentation: ColumnLayout {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 28
        Layout.minimumHeight: Kirigami.Units.gridUnit * 20
        Layout.preferredWidth: Kirigami.Units.gridUnit * 40
        Layout.preferredHeight: Kirigami.Units.gridUnit * 28
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            PlasmaComponents.ToolButton {
                icon.name: "go-previous"
                onClicked: { root.weekOffset--; root.render() }
            }
            PlasmaComponents.ToolButton {
                text: i18n("Oggi")
                enabled: root.weekOffset !== 0
                onClicked: { root.weekOffset = 0; root.render() }
            }
            PlasmaComponents.ToolButton {
                icon.name: "go-next"
                onClicked: { root.weekOffset++; root.render() }
            }
            Kirigami.Heading {
                Layout.fillWidth: true
                level: 4
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                text: (cfg.courseLabel ? cfg.courseLabel + "  ·  " : "")
                      + Qt.locale().toString(root.monday, "d MMM") + " – "
                      + Qt.locale().toString(new Date(root.monday.getTime() + 6 * 86400000), "d MMM yyyy")
            }
            PlasmaComponents.ToolButton {
                icon.name: "view-refresh"
                enabled: !root.loading
                onClicked: root.refresh()
            }
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            visible: root.errorText !== ""
            wrapMode: Text.WordWrap
            color: Kirigami.Theme.negativeTextColor
            text: root.errorText
        }

        Item {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true

            readonly property real hourW: Kirigami.Units.gridUnit * 2.5
            readonly property real headerH: Kirigami.Units.gridUnit * 1.8
            readonly property int nCols: Math.max(1, root.days.length)
            readonly property real colW: (width - hourW) / nCols
            readonly property real bodyH: height - headerH
            readonly property real pxPerMin: bodyH / Math.max(60, root.endMin - root.startMin)
            readonly property int nHours: (root.endMin - root.startMin) / 60

            // day headers
            Repeater {
                model: root.days
                delegate: Rectangle {
                    x: grid.hourW + index * grid.colW
                    width: grid.colW
                    height: grid.headerH
                    color: modelData.isToday ? Qt.alpha(Kirigami.Theme.highlightColor, 0.25) : "transparent"
                    PlasmaComponents.Label {
                        anchors.centerIn: parent
                        font.bold: true
                        text: modelData.label
                    }
                }
            }

            // hour lines + labels
            Repeater {
                model: grid.nHours + 1
                delegate: Item {
                    y: grid.headerH + index * 60 * grid.pxPerMin
                    width: grid.width
                    Rectangle {
                        x: grid.hourW; width: parent.width - grid.hourW; height: 1
                        color: Kirigami.Theme.textColor; opacity: 0.15
                    }
                    PlasmaComponents.Label {
                        x: 0; width: grid.hourW - 4
                        y: -height / 2
                        horizontalAlignment: Text.AlignRight
                        opacity: 0.6
                        font: Kirigami.Theme.smallFont
                        text: root.pad(root.startMin / 60 + index) + ":00"
                    }
                }
            }

            // column separators
            Repeater {
                model: grid.nCols + 1
                delegate: Rectangle {
                    x: grid.hourW + index * grid.colW
                    y: grid.headerH
                    width: 1; height: grid.bodyH
                    color: Kirigami.Theme.textColor; opacity: 0.15
                }
            }

            // lessons
            Repeater {
                model: root.days
                delegate: Item {
                    x: grid.hourW + index * grid.colW
                    y: grid.headerH
                    width: grid.colW
                    height: grid.bodyH

                    Repeater {
                        model: modelData.events
                        delegate: Rectangle {
                            readonly property real laneW: parent.width / modelData.lanes
                            x: modelData.lane * laneW + 1
                            width: laneW - 2
                            y: (modelData.s - root.startMin) * grid.pxPerMin + 1
                            height: Math.max(Kirigami.Units.gridUnit, (modelData.e - modelData.s) * grid.pxPerMin - 2)
                            radius: 3
                            color: modelData.color
                            opacity: modelData.cancelled ? 0.4 : 1
                            clip: true

                            PlasmaComponents.Label {
                                anchors.fill: parent
                                anchors.margins: 3
                                color: "white"
                                font: Kirigami.Theme.smallFont
                                wrapMode: Text.Wrap
                                elide: Text.ElideRight
                                textFormat: Text.StyledText
                                text: "<b>" + root.esc(modelData.title) + (modelData.cancelled ? " (" + i18n("annullata") + ")" : "") + "</b><br>"
                                      + modelData.start + "–" + modelData.end
                                      + (modelData.room ? "<br>" + root.esc(modelData.room) : "")
                            }
                            HoverHandler { id: hh }
                            QQC2.ToolTip.visible: hh.hovered
                            QQC2.ToolTip.delay: 400
                            QQC2.ToolTip.text: modelData.title + "\n" + modelData.start + " – " + modelData.end
                                               + (modelData.room ? "\n" + modelData.room + (modelData.site ? ", " + modelData.site : "") : "")
                                               + (modelData.teacher ? "\n" + modelData.teacher : "")
                        }
                    }

                    // current-time marker
                    Rectangle {
                        visible: modelData.isToday && root.weekOffset === 0
                                 && root.nowMin >= root.startMin && root.nowMin <= root.endMin
                        y: (root.nowMin - root.startMin) * grid.pxPerMin
                        width: parent.width; height: 2
                        color: Kirigami.Theme.negativeTextColor
                    }
                }
            }
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            visible: root.lastUpdate !== ""
            opacity: 0.5
            font: Kirigami.Theme.smallFont
            text: i18n("Aggiornato alle %1", root.lastUpdate)
        }
    }
}
