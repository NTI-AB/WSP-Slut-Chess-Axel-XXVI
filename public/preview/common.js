(function () {
  var ns = window.PiecePreview = window.PiecePreview || {};

  function parseJsonSafe(raw, fallback) {
    try {
      return JSON.parse(raw);
    } catch (e) {
      return fallback;
    }
  }

  function insideBoard(x, y, size) {
    return x >= 0 && x < size && y >= 0 && y < size;
  }

  function coordKey(x, y) {
    return x + ',' + y;
  }

  function keyToPoint(key) {
    var parts = String(key).split(',');
    return { x: parseInt(parts[0], 10), y: parseInt(parts[1], 10) };
  }

  function toBoardCoord(x, y, size) {
    var file = String.fromCharCode(97 + x);
    var rank = size - y;
    return file + rank;
  }

  function positiveInt(value) {
    var num = parseInt(value, 10);
    return isFinite(num) && num > 0 ? num : null;
  }

  function closestForm(el) {
    var node = el;
    while (node) {
      if (node.tagName && node.tagName.toLowerCase() === 'form') return node;
      node = node.parentElement;
    }
    return null;
  }

  function forEachNode(nodeList, callback) {
    Array.prototype.forEach.call(nodeList, callback);
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
