.pragma library

// Same host/path the official OrariUniPD app uses (found by capturing its traffic)
var API = "https://gestionedidattica.unipd.it/AgendaWeb/Orario"

function dec(s) {
    return s.replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
            .replace(/&#(\d+);/g, function (_, n) { return String.fromCharCode(+n) }).replace(/&amp;/g, "&")
}

function attrs(s) {
    var o = {}, re = /([\w:-]+)="([^"]*)"/g, m
    while ((m = re.exec(s))) o[m[1]] = dec(m[2])
    return o
}

// One teaching's semester XML -> flat lesson list. Regex instead of a DOM: the format is flat and stable.
function parseLessons(xml) {
    var out = [], m
    var re = /<Giorno\b((?:[^>"]|"[^"]*")*?)(?:\/>|>([\s\S]*?)<\/Giorno>)/g
    while ((m = re.exec(xml))) {
        var a = attrs(m[1]), teachers = [], t
        var tre = /<Utilizzatore\b((?:[^>"]|"[^"]*")*?)\/?>/g
        while ((t = tre.exec(m[2] || ""))) {
            var u = attrs(t[1])
            teachers.push(((u.Cognome || "") + " " + (u.Nome || "")).trim())
        }
        out.push({
            date: a.Data || "", start: a.OraInizio || "", end: a.OraFine || "",
            title: a.Titolo || "", room: a.Aula || "", site: a.Sede || "",
            type: a.Tipo || "", teacher: teachers.join(", "), cancelled: a.Annullato === "1"
        })
    }
    return out
}

if (typeof module !== "undefined") module.exports = { parseLessons: parseLessons, API: API }
