.pragma library

// qmltestrunner cannot resolve the shell's qs.* modules (their singletons
// import Quickshell), so a view is compiled from its own source with those
// imports and the plugin's components folder pointed at tests/qml/stubs.
// Everything else in the view, including its JS imports, is the real file.
function createView(repoRoot, relPath, parent, testCase, props) {
  var url = "file://" + repoRoot + "/" + relPath
  var xhr = new XMLHttpRequest()
  xhr.open("GET", url, false)
  xhr.send()
  var source = String(xhr.responseText)
  var stubs = 'import "file://' + repoRoot + '/tests/qml/stubs"\n'
  testCase.verify(source.indexOf("import qs.Commons\n") >= 0, relPath + " imports qs.Commons")
  source = source.replace("import qs.Commons\n", stubs)
  source = source.replace("import qs.Ui\n", "")
  source = source.replace('import "components"\n', "")
  source = source.replace('import "../components"\n', "")
  var view = Qt.createQmlObject(source, parent, url)
  testCase.verify(view !== null, relPath + " compiles against the stubs")
  for (var key in props)
    view[key] = props[key]
  return view
}

function findAll(item, predicate, out) {
  var found = out || []
  if (!item)
    return found
  if (predicate(item))
    found.push(item)
  var kids = item.children || []
  for (var i = 0; i < kids.length; i++)
    findAll(kids[i], predicate, found)
  return found
}

function buttonsWithText(root, texts) {
  return findAll(root, function (item) {
    return item.bordered !== undefined && texts.indexOf(String(item.text)) >= 0
  })
}
