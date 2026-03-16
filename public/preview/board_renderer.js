(function () {
  var ns = window.PiecePreview = window.PiecePreview || {};
  var util = ns.util || {};
  var moveEngine = ns.moveEngine || {};
  var insideBoard = util.insideBoard;
  var coordKey = util.coordKey;
  var keyToPoint = util.keyToPoint;
  var toBoardCoord = util.toBoardCoord;

  // Decides if icon colors should be inverted for selected side color.
  function shouldInvertIcon(state) {
    if (!state.pieceIconPath) return false;

    var base = state.iconBaseColor === 'white' ? 'white' : 'black';
    if (base === 'black' && state.pieceColor === 'white') return true;
    if (base === 'white' && state.pieceColor === 'black') return true;
    return false;
  }

  // Renders preview piece content (icon if present, fallback letter otherwise).
  function renderPieceContent(square, state) {
    if (state.pieceIconPath) {
      var img = document.createElement('img');
      img.className = 'piece-preview__piece-icon';
      if (shouldInvertIcon(state)) img.classList.add('is-inverted');
      img.alt = 'preview piece icon';
      img.src = state.pieceIconPath;
      img.onerror = function () {
        square.textContent = 'P';
      };
      square.appendChild(img);
      return;
    }

    square.textContent = 'P';
  }

  // Places the preview piece at board center.
  function resetPieceToCenter(state) {
    state.piecePos = {
      x: Math.floor(state.size / 2),
      y: Math.floor(state.size / 2)
    };
  }

  // Removes out-of-bounds entities and resolves piece/blocker overlap.
  function sanitizeBoardState(state) {
    var nextBlockers = {};
    var blockerKeys = Object.keys(state.blockers);
    for (var i = 0; i < blockerKeys.length; i += 1) {
      var key = blockerKeys[i];
      var point = keyToPoint(key);
      if (insideBoard(point.x, point.y, state.size)) {
        nextBlockers[key] = state.blockers[key];
      }
    }
    state.blockers = nextBlockers;

    if (!state.piecePos || !insideBoard(state.piecePos.x, state.piecePos.y, state.size)) {
      if (state.piecePos) resetPieceToCenter(state);
    }

    if (state.piecePos) {
      delete state.blockers[coordKey(state.piecePos.x, state.piecePos.y)];
    }
  }

  // Applies CSS marker classes for move/capture/both states.
  function applyMarkerClass(square, marker) {
    if (marker.move && marker.capture) {
      square.classList.add('is-both');
      return;
    }
    if (marker.move) {
      square.classList.add('is-move');
      return;
    }
    if (marker.capture) {
      square.classList.add('is-capture');
    }
  }

  // Rebuilds full board UI and textual move summaries.
  function renderBoard(root, elements, state) {
    sanitizeBoardState(state);
    elements.boardEl.innerHTML = '';
    elements.boardEl.style.gridTemplateColumns = 'repeat(' + state.size + ', 2.5rem)';

    var destinations = moveEngine.computeDestinations(root, state);
    var moveCoords = [];
    var captureCoords = [];

    for (var y = 0; y < state.size; y += 1) {
      for (var x = 0; x < state.size; x += 1) {
        var key = coordKey(x, y);
        var square = document.createElement('button');
        square.type = 'button';
        square.className = 'piece-preview__square ' + (((x + y) % 2 === 0) ? 'is-light' : 'is-dark');
        square.setAttribute('data-preview-square', 'true');
        square.setAttribute('data-x', String(x));
        square.setAttribute('data-y', String(y));
        square.title = toBoardCoord(x, y, state.size);

        var blocker = state.blockers[key];
        var isPiece = state.piecePos && state.piecePos.x === x && state.piecePos.y === y;
        if (isPiece) {
          square.classList.add('is-piece');
          renderPieceContent(square, state);
        } else if (blocker === 'ally') {
          square.classList.add('is-ally');
          square.textContent = 'A';
        } else if (blocker === 'enemy') {
          square.classList.add('is-enemy');
          square.textContent = 'E';
        } else {
          square.textContent = '';
        }

        if (destinations[key]) {
          var marker = destinations[key];
          applyMarkerClass(square, marker);
          if (marker.move) moveCoords.push(toBoardCoord(x, y, state.size));
          if (marker.capture) captureCoords.push(toBoardCoord(x, y, state.size));
        }

        elements.boardEl.appendChild(square);
      }
    }

    if (state.piecePos) {
      elements.statusEl.textContent =
        (root.getAttribute('data-preview-piece-name') || 'Piece') +
        ' at ' + toBoardCoord(state.piecePos.x, state.piecePos.y, state.size) +
        ' (' + state.pieceColor + ', ' + (state.firstMove ? 'first move' : 'not first move') + ')';
    } else {
      elements.statusEl.textContent = 'Place the preview piece to compute moves.';
    }

    elements.movesEl.textContent =
      'Moves: ' + (moveCoords.length ? moveCoords.join(', ') : 'none') +
      ' | Captures: ' + (captureCoords.length ? captureCoords.join(', ') : 'none');
  }

  ns.boardRenderer = {
    renderBoard: renderBoard,
    resetPieceToCenter: resetPieceToCenter,
    sanitizeBoardState: sanitizeBoardState
  };
})();
