import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import "parse.js" as Parse

KCM.SimpleKCM {
    id: page

    // Fixed on purpose: when content (long course names, checkbox texts) changed the implicit width,
    // the settings dialog re-laid the page out with a slide animation.
    implicitWidth: Kirigami.Units.gridUnit * 30

    property string cfg_cdl
    property string cfg_period
    property string cfg_files
    property string cfg_courseLabel
    property alias cfg_refreshMinutes: refreshSpin.value
    property alias cfg_showCancelled: cancelledCheck.checked

    property var allCdl: []
    property var shown: []
    property var periods: []
    property var teachings: []
    property bool editing: false
    property string status: i18n("Carico l'elenco dei corsi…")

    function getJson(url, cb) {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            try { cb(JSON.parse(xhr.responseText)) }
            catch (e) { status = i18n("Errore di rete o risposta non valida (HTTP %1)", xhr.status) }
        }
        xhr.open("GET", url)
        xhr.send()
    }

    function idxOf(arr, key, val) {
        for (var i = 0; i < arr.length; i++) if (arr[i][key] === val) return i
        return -1
    }

    // Live search: every typed word must appear in the course name (any order)
    function applyFilter() {
        var q = search.text === cfg_courseLabel ? "" : search.text.toLowerCase()
        var words = q.split(/\s+/).filter(function (w) { return w })
        shown = allCdl.filter(function (c) {
            var t = c.text.toLowerCase()
            return words.every(function (w) { return t.indexOf(w) >= 0 })
        }).slice(0, 50)
        suggestions.currentIndex = 0
    }

    function pickCdl(i) {
        var c = shown[i]
        if (!c) return
        if (c.id !== cfg_cdl) cfg_files = ""
        cfg_cdl = c.id
        cfg_courseLabel = c.text
        search.text = c.text
        editing = false
        periods = c.periodi
        var p = idxOf(periods, "id", cfg_period)
        if (p < 0) { p = 0; cfg_period = periods.length ? periods[0].id : "" }
        periodBox.currentIndex = p
        loadTeachings()
    }

    function pickPeriod(i) {
        if (periods[i].id !== cfg_period) cfg_files = ""
        cfg_period = periods[i].id
        loadTeachings()
    }

    function loadTeachings() {
        teachings = []
        if (!cfg_cdl || !cfg_period) return
        status = i18n("Carico gli insegnamenti…")
        getJson(Parse.API + "/api_profilo_lista_insegnamenti.php?cdl=" + cfg_cdl + "&periodo_didattico=" + cfg_period,
                function (list) {
            list.sort(function (a, b) { return (a.anno - b.anno) || a.nome.localeCompare(b.nome) })
            teachings = list
            status = i18n("%1 insegnamenti", list.length)
        })
    }

    function files() { return cfg_files.split(",").filter(function (f) { return f }) }

    function setFile(f, on) {
        var a = files().filter(function (x) { return x !== f })
        if (on) a.push(f)
        cfg_files = a.join(",")
    }

    // The network round-trip finishes after Plasma has filled in the cfg_* values
    Component.onCompleted: getJson(Parse.API + "/api_profilo_aa_scuola_tipo_cdl_pd.php", function (schools) {
        var all = []
        schools.forEach(function (s) {
            (s.elenco_lauree || []).forEach(function (l) {
                (l.elenco_cdl || []).forEach(function (c) {
                    all.push({ text: c.label, id: c.valore, periodi: c.pub_periodi || [] })
                })
            })
        })
        allCdl = all
        search.text = cfg_courseLabel
        applyFilter()
        var i = idxOf(allCdl, "id", cfg_cdl)
        if (i >= 0) {
            periods = allCdl[i].periodi
            periodBox.currentIndex = idxOf(periods, "id", cfg_period)
            loadTeachings()
        } else {
            status = ""
        }
    })

    Kirigami.FormLayout {
        // One control: the field and its suggestions
        ColumnLayout {
            Kirigami.FormData.label: i18n("Corso di studio:")
            Kirigami.FormData.labelAlignment: Qt.AlignTop
            spacing: 0

            QQC2.TextField {
                id: search
                Layout.fillWidth: true
                implicitWidth: Kirigami.Units.gridUnit * 20
                placeholderText: i18n("Scrivi per cercare (es. informatica)…")
                onTextEdited: { page.editing = true; page.applyFilter() }
                onActiveFocusChanged: if (activeFocus && page.allCdl.length) { page.editing = true; page.applyFilter(); selectAll() }
                onAccepted: if (page.editing) page.pickCdl(suggestions.currentIndex)
                Keys.onDownPressed: suggestions.incrementCurrentIndex()
                Keys.onUpPressed: suggestions.decrementCurrentIndex()
                Keys.onEscapePressed: (event) => { page.editing = false; event.accepted = true }
            }

            ListView {
                id: suggestions
                Layout.fillWidth: true
                implicitWidth: 0
                implicitHeight: Math.min(contentHeight, Kirigami.Units.gridUnit * 10)
                visible: page.editing && page.shown.length > 0
                clip: true
                model: page.shown
                delegate: QQC2.ItemDelegate {
                    width: ListView.view.width
                    highlighted: ListView.isCurrentItem
                    contentItem: QQC2.Label { text: modelData.text; elide: Text.ElideRight }
                    onClicked: page.pickCdl(index)
                }
            }
        }

        QQC2.ComboBox {
            id: periodBox
            Kirigami.FormData.label: i18n("Periodo:")
            implicitWidth: Kirigami.Units.gridUnit * 12
            model: page.periods
            textRole: "label"
            onActivated: page.pickPeriod(currentIndex)
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            wrapMode: Text.Wrap
            text: page.status
            opacity: 0.7
            visible: text !== ""
        }

        ColumnLayout {
            Kirigami.FormData.label: i18n("Insegnamenti:")
            Kirigami.FormData.labelAlignment: Qt.AlignTop
            Layout.fillWidth: true
            Repeater {
                model: page.teachings
                delegate: QQC2.CheckBox {
                    id: cb
                    Layout.fillWidth: true
                    implicitWidth: 0
                    checked: page.files().indexOf(modelData.file) >= 0
                    onToggled: page.setFile(modelData.file, checked)
                    // text lives on the CheckBox so the indicator stays left-aligned; the label only wraps it
                    text: modelData.anno + "° · " + modelData.nome
                          + (modelData.docente ? " — " + modelData.docente : "")
                          + (modelData.terza_riga ? "  [" + modelData.terza_riga + "]" : "")
                    contentItem: QQC2.Label {
                        text: cb.text
                        wrapMode: Text.Wrap
                        leftPadding: cb.indicator.width + cb.spacing
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }

        Kirigami.Separator { Kirigami.FormData.isSection: true }

        QQC2.SpinBox { id: refreshSpin; Kirigami.FormData.label: i18n("Aggiorna ogni (min):"); from: 5; to: 1440; stepSize: 30 }
        QQC2.CheckBox { id: cancelledCheck; Kirigami.FormData.label: i18n("Lezioni annullate:"); text: i18n("Mostra") }
    }
}
