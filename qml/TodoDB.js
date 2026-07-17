var _db = null

function db() {
    if (!_db)
        _db = LocalStorage.openDatabaseSync("NaviusTodos", "1.0", "Navius TODOs", 2 * 1024 * 1024)
    return _db
}

function init() {
    db().transaction(function(tx) {
        tx.executeSql(
            'CREATE TABLE IF NOT EXISTS dest_todos (' +
            '  id        INTEGER PRIMARY KEY AUTOINCREMENT,' +
            '  dest_key  TEXT NOT NULL,' +
            '  dest_name TEXT NOT NULL,' +
            '  todo_text TEXT NOT NULL,' +
            '  done      INTEGER NOT NULL DEFAULT 0,' +
            '  nav_date  TEXT NOT NULL' +
            ')'
        )
    })
}

function destKey(lat, lon) {
    return parseFloat(lat).toFixed(3) + "," + parseFloat(lon).toFixed(3)
}

// Guarda todos los TODOs de un destino para una sesión dada.
// Elimina los registros anteriores de esa sesión (dest_key + nav_date) para evitar duplicados.
function saveTodosForDest(dKey, destName, todos, dateStr) {
    if (!todos || todos.length === 0) return
    db().transaction(function(tx) {
        for (var i = 0; i < todos.length; i++) {
            var r = tx.executeSql(
                'UPDATE dest_todos SET done=?, dest_name=? WHERE dest_key=? AND nav_date=? AND todo_text=?',
                [todos[i].done ? 1 : 0, destName, dKey, dateStr, todos[i].text]
            )
            if (r.rowsAffected === 0) {
                tx.executeSql(
                    'INSERT INTO dest_todos (dest_key, dest_name, todo_text, done, nav_date) VALUES (?,?,?,?,?)',
                    [dKey, destName, todos[i].text, todos[i].done ? 1 : 0, dateStr]
                )
            }
        }
    })
}

// Devuelve array [{id, text, done}] para un destino dado (todas las sesiones, sin duplicados de texto).
function loadPastTodosForDest(dKey) {
    var seen = {}
    var result = []
    db().readTransaction(function(tx) {
        var rs = tx.executeSql(
            'SELECT id, todo_text, done FROM dest_todos WHERE dest_key=? ORDER BY nav_date DESC, id ASC',
            [dKey]
        )
        for (var i = 0; i < rs.rows.length; i++) {
            var row = rs.rows.item(i)
            if (!seen[row.todo_text]) {
                seen[row.todo_text] = true
                result.push({ id: row.id, text: row.todo_text, done: row.done === 1 })
            }
        }
    })
    return result
}

// Devuelve todas las sesiones agrupadas: [{destKey, destName, date, todos:[{id,text,done}]}]
function loadAllDestGroups() {
    var groups = {}
    var order  = []
    db().readTransaction(function(tx) {
        var rs = tx.executeSql(
            'SELECT id, dest_key, dest_name, todo_text, done, nav_date' +
            ' FROM dest_todos ORDER BY nav_date DESC, dest_key, id ASC'
        )
        for (var i = 0; i < rs.rows.length; i++) {
            var row = rs.rows.item(i)
            var gkey = row.dest_key + "|" + row.nav_date
            if (!groups[gkey]) {
                groups[gkey] = { destKey: row.dest_key, destName: row.dest_name,
                                 date: row.nav_date, todos: [] }
                order.push(gkey)
            }
            groups[gkey].todos.push({ id: row.id, text: row.todo_text, done: row.done === 1 })
        }
    })
    var result = []
    for (var j = 0; j < order.length; j++) result.push(groups[order[j]])
    return result
}

function setHistTodoDone(id, done) {
    db().transaction(function(tx) {
        tx.executeSql('UPDATE dest_todos SET done=? WHERE id=?', [done ? 1 : 0, id])
    })
}

function deleteHistTodo(id) {
    db().transaction(function(tx) {
        tx.executeSql('DELETE FROM dest_todos WHERE id=?', [id])
    })
}

function deleteDestGroup(dKey, dateStr) {
    db().transaction(function(tx) {
        tx.executeSql('DELETE FROM dest_todos WHERE dest_key=? AND nav_date=?', [dKey, dateStr])
    })
}

// Devuelve array [{text, done}] de la sesión más reciente para un destino (done=false siempre, nueva sesión).
function loadLatestTodosForDest(dKey) {
    var result = []
    db().readTransaction(function(tx) {
        var rs = tx.executeSql(
            'SELECT MAX(nav_date) as latest FROM dest_todos WHERE dest_key=?', [dKey]
        )
        if (rs.rows.length === 0 || !rs.rows.item(0).latest) return
        var latest = rs.rows.item(0).latest
        var rs2 = tx.executeSql(
            'SELECT todo_text FROM dest_todos WHERE dest_key=? AND nav_date=? ORDER BY id ASC',
            [dKey, latest]
        )
        for (var i = 0; i < rs2.rows.length; i++)
            result.push({ text: rs2.rows.item(i).todo_text, done: false })
    })
    return result
}
