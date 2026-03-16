(function () {
  var ns = window.PiecePreview = window.PiecePreview || {};

  // Parses JSON safely and returns fallback on parse errors.
  function parseJsonSafe(raw, fallback) {
    try {
      return JSON.parse(raw);
    } catch (e) {
      return fallback;
    }
  }

  // Checks whether coordinates are inside current board bounds.
  function insideBoard(x, y, size) {
    return x >= 0 && x < size && y >= 0 && y < size;
  }

  // Builds a stable "x,y" key for hash-based board maps.
  function coordKey(x, y) {
    return x + ',' + y;
  }

  // Converts a "x,y" key back into numeric coordinates.
  function keyToPoint(key) {
    var parts = String(key).split(',');
    return { x: parseInt(parts[0], 10), y: parseInt(parts[1], 10) };
  }

  // Converts internal board coordinates to chess-style notation.
  function toBoardCoord(x, y, size) {
    var file = String.fromCharCode(97 + x);
    var rank = size - y;
    return file + rank;
  }

  // Parses a positive integer or returns null.
  function positiveInt(value) {
    var num = parseInt(value, 10);
    return isFinite(num) && num > 0 ? num : null;
  }

  // Finds the nearest parent form for a given DOM node.
  function closestForm(el) {
    var node = el;
    while (node) {
      if (node.tagName && node.tagName.toLowerCase() === 'form') return node;
      node = node.parentElement;
    }
    return null;
  }

  // Runs Array.forEach on NodeLists without depending on modern polyfills.
  function forEachNode(nodeList, callback) {
    for (var i = 0; i < nodeList.length; i += 1) {
      callback(nodeList[i], i);
    }
  }

  ns.util = {
    parseJsonSafe: parseJsonSafe,
    insideBoard: insideBoard,
    coordKey: coordKey,
    keyToPoint: keyToPoint,
    toBoardCoord: toBoardCoord,
    positiveInt: positiveInt,
    closestForm: closestForm,
    forEachNode: forEachNode
  };
})();
