// Kept in sync with tasklimits.py, which enforces the same bounds in the
// read and write helpers. Duplicated here so the QML side stays bounded on
// its own: nothing reaches the ListModel (one delegate per row, inside the
// shared shell process) without passing these, and adding tasks in-app is
// held to the same ceiling as loading them from disk.
var MAX_TASKS = 1000
var MAX_TEXT_CHARS = 1000
var MAX_ID_CHARS = 64

function normalizeTask(raw) {
  if (!raw || typeof raw !== "object") return null
  var text = String(raw.text !== undefined ? raw.text : "").trim().slice(0, MAX_TEXT_CHARS)
  if (!text) return null

  var id = String(raw.id || "").slice(0, MAX_ID_CHARS)
  if (!id) id = Date.now() + "-" + Math.floor(Math.random() * 1000000)

  return {
    id: id,
    text: text,
    done: !!raw.done,
    createdAt: Number(raw.createdAt) || Date.now()
  }
}

function parseTasks(raw) {
  var data
  try {
    data = JSON.parse(raw || "[]")
  } catch (e) {
    data = []
  }
  if (!Array.isArray(data)) return []

  var out = []
  for (var i = 0; i < data.length && out.length < MAX_TASKS; i++) {
    var task = normalizeTask(data[i])
    if (task) out.push(task)
  }
  return out
}

function serializeTasks(tasks) {
  return JSON.stringify(tasks, null, 2) + "\n"
}

function addTask(tasks, text) {
  if (tasks.length >= MAX_TASKS) return tasks
  var task = normalizeTask({ text: text })
  if (!task) return tasks
  return tasks.concat([task])
}

function atTaskLimit(tasks) {
  return tasks.length >= MAX_TASKS
}

function toggleTaskAt(tasks, index) {
  if (index < 0 || index >= tasks.length) return tasks
  var next = tasks.slice()
  var task = next[index]
  next[index] = { id: task.id, text: task.text, done: !task.done, createdAt: task.createdAt }
  return next
}

function removeTaskAt(tasks, index) {
  if (index < 0 || index >= tasks.length) return tasks
  var next = tasks.slice()
  next.splice(index, 1)
  return next
}

function clearCompleted(tasks) {
  var next = []
  for (var i = 0; i < tasks.length; i++) {
    if (!tasks[i].done) next.push(tasks[i])
  }
  return next
}

function pendingCount(tasks) {
  var count = 0
  for (var i = 0; i < tasks.length; i++) {
    if (!tasks[i].done) count++
  }
  return count
}

function doneCount(tasks) {
  return tasks.length - pendingCount(tasks)
}

// Display order: pending tasks first (insertion order), then completed
// tasks (insertion order) — checking a task off moves it into the
// completed group at the bottom without reshuffling anything else.
function displayRows(tasks) {
  var pending = []
  var done = []
  for (var i = 0; i < tasks.length; i++) {
    var row = { taskIndex: i, taskId: tasks[i].id, text: tasks[i].text, done: tasks[i].done }
    if (tasks[i].done) done.push(row)
    else pending.push(row)
  }
  return pending.concat(done)
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizeTask: normalizeTask,
    parseTasks: parseTasks,
    serializeTasks: serializeTasks,
    addTask: addTask,
    atTaskLimit: atTaskLimit,
    toggleTaskAt: toggleTaskAt,
    removeTaskAt: removeTaskAt,
    clearCompleted: clearCompleted,
    pendingCount: pendingCount,
    doneCount: doneCount,
    displayRows: displayRows
  }
}
