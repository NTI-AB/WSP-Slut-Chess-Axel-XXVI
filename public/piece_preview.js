(function () {
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

  function parseMoveSourceFromForm(root) {
    var form = closestForm(root);
    if (!form) return [];

    var toggles = form.querySelectorAll('[data-method-toggle]');
    var moves = [];

    Array.prototype.forEach.call(toggles, function (toggle) {
      if (!toggle.checked) return;

      var methodId = toggle.getAttribute('data-method-toggle');
      var fieldset = form.querySelector('[data-preview-method="' + methodId + '"]');
      if (!fieldset) return;

      var modeInput = form.querySelector('[name="mode[' + methodId + ']"]');
      var colorScopeInput = form.querySelector('[name="color_scope[' + methodId + ']"]');
      var rayLimitInput = form.querySelector('[name="ray_limit[' + methodId + ']"]');
      var firstMoveOnlyInput = form.querySelector('[name="first_move_only[' + methodId + ']"]');

      moves.push({
        movement_method_id: positiveInt(methodId),
        name: fieldset.getAttribute('data-preview-name') || ('Method ' + methodId),
        kind: fieldset.getAttribute('data-preview-kind') || 'ray',
        vectors: parseJsonSafe(fieldset.getAttribute('data-preview-vectors') || '{}', {}),
        ray_limit: rayLimitInput ? positiveInt(rayLimitInput.value) : null,
        mode: modeInput ? modeInput.value : 'both',
        color_scope: colorScopeInput ? colorScopeInput.value : 'any',
        first_move_only: !!(firstMoveOnlyInput && firstMoveOnlyInput.checked)
      });

      var primaryMode = modeInput ? modeInput.value : 'both';
      var secondaryToggle = form.querySelector('[name="secondary_mode_enabled[' + methodId + ']"]');
      var secondaryRayLimitInput = form.querySelector('[name="secondary_ray_limit[' + methodId + ']"]');
      var secondaryEnabled = !!(secondaryToggle && secondaryToggle.checked);
      var isRayLike = !!(rayLimitInput || secondaryRayLimitInput);

      if (secondaryEnabled && isRayLike && (primaryMode === 'move' || primaryMode === 'capture')) {
        moves.push({
          movement_method_id: positiveInt(methodId),
          name: (fieldset.getAttribute('data-preview-name') || ('Method ' + methodId)) + ' (secondary)',
          kind: fieldset.getAttribute('data-preview-kind') || 'ray',
          vectors: parseJsonSafe(fieldset.getAttribute('data-preview-vectors') || '{}', {}),
          ray_limit: secondaryRayLimitInput ? positiveInt(secondaryRayLimitInput.value) : null,
          mode: primaryMode === 'move' ? 'capture' : 'move',
          color_scope: colorScopeInput ? colorScopeInput.value : 'any',
          first_move_only: !!(firstMoveOnlyInput && firstMoveOnlyInput.checked)
        });
      }
    });

    return moves;
  }

  function parseMoveSourceStatic(root) {
    var script = root.querySelector('script[data-preview-static-moves]');
    if (!script) return [];
    var value = parseJsonSafe(script.textContent || '[]', []);
    return Array.isArray(value) ? value : [];
  }

  function createPreview(root) {
    var boardEl = root.querySelector('[data-preview-board]');
    var statusEl = root.querySelector('[data-preview-status]');
    var movesEl = root.querySelector('[data-preview-moves]');
    var boardSizeInput = root.querySelector('[data-preview-board-size]');
    var pieceColorInput = root.querySelector('[data-preview-piece-color]');
    var firstMoveInput = root.querySelector('[data-preview-first-move]');
    var resetBoardButton = root.querySelector('[data-preview-reset-board]');
    var clearBlockersButton = root.querySelector('[data-preview-clear-blockers]');
    var toolButtons = root.querySelectorAll('[data-preview-tool]');

    var state = {
      size: positiveInt(boardSizeInput && boardSizeInput.value) || 8,
      pieceColor: (pieceColorInput && pieceColorInput.value) || 'white',
      firstMove: !!(firstMoveInput && firstMoveInput.checked),
      tool: 'piece',
      piecePos: null,
      blockers: {}
    };

    function resetPieceToCenter() {
      state.piecePos = {
        x: Math.floor(state.size / 2),
        y: Math.floor(state.size / 2)
      };
    }

    function sanitizeBoardState() {
      var nextBlockers = {};
      Object.keys(state.blockers).forEach(function (key) {
        var point = keyToPoint(key);
        if (insideBoard(point.x, point.y, state.size)) {
          nextBlockers[key] = state.blockers[key];
        }
      });
      state.blockers = nextBlockers;

      if (!state.piecePos || !insideBoard(state.piecePos.x, state.piecePos.y, state.size)) {
        if (state.piecePos) resetPieceToCenter();
      }

      if (state.piecePos) {
        delete state.blockers[coordKey(state.piecePos.x, state.piecePos.y)];
      }
    }

    function setActiveTool(nextTool) {
      state.tool = nextTool;
      Array.prototype.forEach.call(toolButtons, function (button) {
        button.classList.toggle('is-active', button.getAttribute('data-preview-tool') === nextTool);
      });
    }

    function readMoveSource() {
      var source = root.getAttribute('data-preview-source') || 'static';
      return source === 'form' ? parseMoveSourceFromForm(root) : parseMoveSourceStatic(root);
    }

    function addDestination(destinations, x, y, kind) {
      var key = coordKey(x, y);
      if (!destinations[key]) {
        destinations[key] = { move: false, capture: false };
      }
      destinations[key][kind] = true;
    }

    function includeMoveMode(mode) {
      return mode === 'both' || mode === 'move';
    }

    function includeCaptureMode(mode) {
      return mode === 'both' || mode === 'capture';
    }

    function applyRayMove(move, origin, destinations) {
      var vectors = move.vectors || {};
      var rays = Array.isArray(vectors.rays) ? vectors.rays : [];
      var configuredLimit = positiveInt(move.ray_limit);
      var defaultLimit = positiveInt(vectors.ray_limit);
      var limit = configuredLimit || defaultLimit || state.size;
      var allowsMove = includeMoveMode(move.mode);
      var allowsCapture = includeCaptureMode(move.mode);

      rays.forEach(function (ray) {
        if (!Array.isArray(ray) || ray.length < 2) return;
        var dx = parseInt(ray[0], 10);
        var dy = parseInt(ray[1], 10);
        if (!isFinite(dx) || !isFinite(dy)) return;
        if (dx === 0 && dy === 0) return;

        for (var step = 1; step <= limit; step += 1) {
          var tx = origin.x + (dx * step);
          var ty = origin.y + (dy * step);
          if (!insideBoard(tx, ty, state.size)) break;

          var blocker = state.blockers[coordKey(tx, ty)];
          if (!blocker) {
            if (allowsMove) addDestination(destinations, tx, ty, 'move');
            continue;
          }

          if (blocker === 'enemy' && allowsCapture) {
            addDestination(destinations, tx, ty, 'capture');
          }

          break;
        }
      });
    }

    function applyLeapMove(move, origin, destinations) {
      var vectors = move.vectors || {};
      var leaps = Array.isArray(vectors.leaps) ? vectors.leaps : [];
      var allowsMove = includeMoveMode(move.mode);
      var allowsCapture = includeCaptureMode(move.mode);

      leaps.forEach(function (leap) {
        if (!Array.isArray(leap) || leap.length < 2) return;
        var tx = origin.x + parseInt(leap[0], 10);
        var ty = origin.y + parseInt(leap[1], 10);
        if (!insideBoard(tx, ty, state.size)) return;

        var blocker = state.blockers[coordKey(tx, ty)];
        if (!blocker) {
          if (allowsMove) addDestination(destinations, tx, ty, 'move');
          return;
        }

        if (blocker === 'enemy' && allowsCapture) {
          addDestination(destinations, tx, ty, 'capture');
        }
      });
    }

    function applyPawnRuleMove(move, origin, destinations) {
      var vectors = move.vectors || {};
      var colorRule = vectors[state.pieceColor];
      if (!colorRule || typeof colorRule !== 'object') return;

      var allowsMove = includeMoveMode(move.mode);
      var allowsCapture = includeCaptureMode(move.mode);

      if (allowsMove && Array.isArray(colorRule.move_only)) {
        colorRule.move_only.forEach(function (stepVec) {
          if (!Array.isArray(stepVec) || stepVec.length < 2) return;
          var tx = origin.x + parseInt(stepVec[0], 10);
          var ty = origin.y + parseInt(stepVec[1], 10);
          if (!insideBoard(tx, ty, state.size)) return;
          if (!state.blockers[coordKey(tx, ty)]) {
            addDestination(destinations, tx, ty, 'move');
          }
        });
      }

      if (allowsCapture && Array.isArray(colorRule.capture_only)) {
        colorRule.capture_only.forEach(function (stepVec) {
          if (!Array.isArray(stepVec) || stepVec.length < 2) return;
          var tx = origin.x + parseInt(stepVec[0], 10);
          var ty = origin.y + parseInt(stepVec[1], 10);
          if (!insideBoard(tx, ty, state.size)) return;
          if (state.blockers[coordKey(tx, ty)] === 'enemy') {
            addDestination(destinations, tx, ty, 'capture');
          }
        });
      }

      if (allowsMove && state.firstMove && colorRule.first_move && Array.isArray(colorRule.first_move.rays)) {
        var rays = colorRule.first_move.rays;
        var limit = positiveInt(colorRule.first_move.ray_limit) || 2;

        rays.forEach(function (ray) {
          if (!Array.isArray(ray) || ray.length < 2) return;
          var dx = parseInt(ray[0], 10);
          var dy = parseInt(ray[1], 10);
          if (!isFinite(dx) || !isFinite(dy)) return;

          for (var step = 1; step <= limit; step += 1) {
            var tx = origin.x + (dx * step);
            var ty = origin.y + (dy * step);
            if (!insideBoard(tx, ty, state.size)) break;
            if (state.blockers[coordKey(tx, ty)]) break;
            addDestination(destinations, tx, ty, 'move');
          }
        });
      }
    }

    function computeDestinations() {
      var destinations = {};
      if (!state.piecePos) return destinations;

      var moves = readMoveSource();
      var origin = state.piecePos;

      moves.forEach(function (move) {
        if (!move || typeof move !== 'object') return;
        if (move.color_scope === 'white' && state.pieceColor !== 'white') return;
        if (move.color_scope === 'black' && state.pieceColor !== 'black') return;
        if (move.first_move_only && !state.firstMove) return;

        if (move.kind === 'ray') {
          applyRayMove(move, origin, destinations);
          return;
        }

        if (move.kind === 'leap') {
          applyLeapMove(move, origin, destinations);
          return;
        }

        if (move.kind === 'rule') {
          applyPawnRuleMove(move, origin, destinations);
        }
      });

      return destinations;
    }

    function renderBoard() {
      sanitizeBoardState();
      boardEl.innerHTML = '';
      boardEl.style.gridTemplateColumns = 'repeat(' + state.size + ', 2.5rem)';

      var destinations = computeDestinations();
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
            square.textContent = 'P';
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
            if (marker.move && marker.capture) {
              square.classList.add('is-both');
            } else if (marker.move) {
              square.classList.add('is-move');
            } else if (marker.capture) {
              square.classList.add('is-capture');
            }

            if (marker.move) moveCoords.push(toBoardCoord(x, y, state.size));
            if (marker.capture) captureCoords.push(toBoardCoord(x, y, state.size));
          }

          boardEl.appendChild(square);
        }
      }

      if (state.piecePos) {
        statusEl.textContent =
          (root.getAttribute('data-preview-piece-name') || 'Piece') +
          ' at ' + toBoardCoord(state.piecePos.x, state.piecePos.y, state.size) +
          ' (' + state.pieceColor + ', ' + (state.firstMove ? 'first move' : 'not first move') + ')';
      } else {
        statusEl.textContent = 'Place the preview piece to compute moves.';
      }

      var moveText = moveCoords.length ? moveCoords.join(', ') : 'none';
      var captureText = captureCoords.length ? captureCoords.join(', ') : 'none';
      movesEl.textContent = 'Moves: ' + moveText + ' | Captures: ' + captureText;
    }

    function applyToolOnSquare(x, y) {
      var key = coordKey(x, y);

      if (state.tool === 'piece') {
        state.piecePos = { x: x, y: y };
        delete state.blockers[key];
        renderBoard();
        return;
      }

      if (state.piecePos && state.piecePos.x === x && state.piecePos.y === y) {
        if (state.tool === 'erase') {
          state.piecePos = null;
          renderBoard();
        }
        return;
      }

      if (state.tool === 'ally' || state.tool === 'enemy') {
        state.blockers[key] = state.tool;
        renderBoard();
        return;
      }

      if (state.tool === 'erase') {
        delete state.blockers[key];
        renderBoard();
      }
    }

    boardEl.addEventListener('click', function (event) {
      var target = event.target;
      if (!target || !target.hasAttribute('data-preview-square')) return;
      var x = parseInt(target.getAttribute('data-x'), 10);
      var y = parseInt(target.getAttribute('data-y'), 10);
      if (!insideBoard(x, y, state.size)) return;
      applyToolOnSquare(x, y);
    });

    Array.prototype.forEach.call(toolButtons, function (button) {
      button.addEventListener('click', function () {
        setActiveTool(button.getAttribute('data-preview-tool') || 'piece');
      });
    });

    if (boardSizeInput) {
      boardSizeInput.addEventListener('change', function () {
        state.size = positiveInt(boardSizeInput.value) || 8;
        if (state.size < 4) state.size = 4;
        if (state.size > 20) state.size = 20;
        boardSizeInput.value = String(state.size);
        sanitizeBoardState();
        renderBoard();
      });
    }

    if (pieceColorInput) {
      pieceColorInput.addEventListener('change', function () {
        state.pieceColor = pieceColorInput.value === 'black' ? 'black' : 'white';
        renderBoard();
      });
    }

    if (firstMoveInput) {
      firstMoveInput.addEventListener('change', function () {
        state.firstMove = !!firstMoveInput.checked;
        renderBoard();
      });
    }

    if (resetBoardButton) {
      resetBoardButton.addEventListener('click', function () {
        state.blockers = {};
        resetPieceToCenter();
        renderBoard();
      });
    }

    if (clearBlockersButton) {
      clearBlockersButton.addEventListener('click', function () {
        state.blockers = {};
        renderBoard();
      });
    }

    var form = closestForm(root);
    if (form) {
      form.addEventListener('change', function () {
        renderBoard();
      });
      form.addEventListener('input', function (event) {
        if (event.target && event.target.name && event.target.name.indexOf('ray_limit[') === 0) {
          renderBoard();
        }
      });
    }

    resetPieceToCenter();
    sanitizeBoardState();
    setActiveTool('piece');
    renderBoard();
  }

  document.addEventListener('DOMContentLoaded', function () {
    Array.prototype.forEach.call(document.querySelectorAll('[data-piece-preview-root]'), createPreview);
  });
})();
