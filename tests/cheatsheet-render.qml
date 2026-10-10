// The cheatsheet documents rendered the way the cheatsheet window renders
// them (TextEdit, MarkdownText, read-only) - run by tests/run.sh:
//   qml6 tests/cheatsheet-render.qml -- <dir with hyprland.md>
// (hyprland.md = the laptop's rendering of cheatsheet.md.j2, written by
// tests/keybindings.py; neovim.md = roles/apps/files/cheatsheet-neovim.md).
// Checks: the shown text has no Markdown syntax left (tables are real
// tables, code/bold rendered), and the window's own search (findMatches,
// cut out of CheatsheetWindow.qml) selects exactly the hit - also inside a
// table cell. Exit 0 = passed, 1 = failed.

import QtQuick

Item {
    width: 800
    height: 600

    property int failures: 0
    readonly property string repo: Qt.resolvedUrl("..").toString()

    function read(url) {
        const x = new XMLHttpRequest();
        x.open("GET", url, false);
        x.send();
        return x.responseText;
    }

    function fail(msg) {
        failures++;
        console.warn("FAIL " + msg);
    }

    TextEdit {
        id: view
        width: 760
        readOnly: true
        textFormat: TextEdit.MarkdownText
        wrapMode: TextEdit.Wrap
        font.pixelSize: 13
    }

    function checkDoc(name, url, terms) {
        const md = read(url);
        if (md.length < 200) { fail(name + ": not read (" + url + ")"); return; }
        view.text = md;
        const plain = view.getText(0, view.length);
        if (plain.length !== view.length) fail(name + ": shown text does not map to positions");
        // Blocks come back joined by spaces, so count instead of looking at
        // lines: a shown "|" must be an escaped one (\|) of the source - any
        // other is a table that was not recognised.
        const pipes = (plain.match(/\|/g) || []).length, escaped = (md.match(/\\\|/g) || []).length;
        if (pipes !== escaped) fail(name + ": " + pipes + " '|' shown, " + escaped + " escaped in the source - a table is not rendered");
        if (/(^|\s)#{1,6} |\*\*|-{3,}/.test(plain)) fail(name + ": Markdown syntax (#, **, ---) shown as text");
        if (plain.indexOf("`") >= 0 && name !== "neovim") fail(name + ": a backtick is shown");
        const src = read(repo + "roles/quickshell/files/quickshell/cheatsheet/CheatsheetWindow.qml");
        const i = src.indexOf("function findMatches(");
        const body = src.slice(src.indexOf("{", i) + 1, src.indexOf("\n    }\n", i));
        const find = new Function("text", "query", body);
        for (const t of terms) {
            const hits = find(plain, t);
            if (hits.length === 0) { fail(name + ": '" + t + "' not found"); continue; }
            for (const p of hits) {
                view.select(p, p + t.length);
                if (view.selectedText.toLowerCase() !== t.toLowerCase())
                    fail(name + ": hit for '" + t + "' selects '" + view.selectedText + "'");
            }
            const r = view.positionToRectangle(hits[hits.length - 1]);
            if (!(r.y >= 0 && r.y <= view.contentHeight)) fail(name + ": hit '" + t + "' has no position");
        }
        console.info(name + ": " + plain.length + " characters, " + terms.length + " terms ok");
    }

    Component.onCompleted: {
        const args = Qt.application.arguments;
        const dir = args[args.length - 1];
        // table cells, headings, inline code, the last table row of a document
        checkDoc("hyprland", "file://" + dir + "/hyprland.md",
                 ["bitwarden", "Night light", "Super + E", "Timer popup", "Power menu", "Media player", "Esc"]);
        checkDoc("neovim", repo + "roles/apps/files/cheatsheet-neovim.md",
                 ["\\ll", "forward search", "Lazygit", "Space s r", "Shift + h", "documentation of the package"]);
        console.info(failures === 0 ? "cheatsheet-render: all checks passed" : "cheatsheet-render: " + failures + " FAILED");
        Qt.exit(failures === 0 ? 0 : 1);
    }
}
