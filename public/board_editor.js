(function () {
  // Starts all board editor instances after DOM content is ready.
  function bootBoardEditors() {
    var roots = document.querySelectorAll('[data-board-editor-root]');
    for (var i = 0; i < roots.length; i += 1) {
      createBoardEditor(roots[i]);
    }
  }

  // Creates one board editor state, binds events, and renders first frame.
  function createBoardEditor(root) {
    var form = findParentForm(root);
    if (!form) return;

      var elements = {
        root: root,
        form: form,
        grid: root.querySelector('[data-board-grid]'),
        sizeInput: form.querySelector('[data-board-size-input]'),
        placementsInput: form.querySelector('[data-board-placements-input]'),
        toolButtons: root.querySelectorAll('[data-board-tool]'),
        resetButton: root.querySelector('[data-board-reset]'),
        pieceButtons: root.querySelectorAll('[data-piece-picker]'),
        selectedText: root.querySelector('[data-board-selected-text]')
      };

    if (!elements.grid || !elements.sizeInput || !elements.placementsInput) return;

    var state = {
      size: normalizeBoardSize(elements.sizeInput.value || root.getAttribute('data-board-size')),
      tool: 'piece',
      selectedPieceId: null,
      selectedPieceName: '',
      piecesById: readPiecesById(root.getAttribute('data-board-pieces')),
      placementsByKey: {}
    };

    loadPlacementsFromInput(state, elements.placementsInput.value);
    bindEditorEvents(state, elements);
    selectFirstPieceIfAvailable(state, elements);
    renderBoardEditor(state, elements);
  }

  // Finds closest parent form element.
  function findParentForm(node) {
    var current = node;
    while (current) {
      if (current.tagName && current.tagName.toLowerCase() === 'form') return current;
      current = current.parentElement;
    }
    return null;
  }

  // Converts value to supported board size (4..20).
  function normalizeBoardSize(value) {
    var size = parseInt(value, 10);
    if (!isFinite(size)) size = 8;
    if (size < 4) size = 4;
    if (size > 20) size = 20;
    return size;
  }

  // Builds a piece lookup table by id from root JSON data.
  function readPiecesById(rawJson) {
    var parsed = [];
    try {
      parsed = JSON.parse(rawJson || '[]');
    } catch (error) {
      parsed = [];
    }

    var map = {};
    if (!Array.isArray(parsed)) return map;

    for (var i = 0; i < parsed.length; i += 1) {
      var piece = parsed[i];
      if (!piece || typeof piece !== 'object') continue;
      var id = parseInt(piece.id, 10);
      if (!isFinite(id)) continue;
      map[id] = {
        id: id,
        name: String(piece.name || ''),
        image_path: String(piece.image_path || ''),
        icon_base_color: String(piece.icon_base_color || 'black') === 'white' ? 'white' : 'black'
      };
    }

    return map;
  }

  // Reads initial placements JSON and keeps only valid entries.
  function loadPlacementsFromInput(state, rawJson) {
    var parsed = [];
    try {
      parsed = JSON.parse(rawJson || '[]');
    } catch (error) {
      parsed = [];
    }
    if (!Array.isArray(parsed)) parsed = [];

    state.placementsByKey = {};
    for (var i = 0; i < parsed.length; i += 1) {
      var placement = sanitizePlacement(parsed[i], state);
      if (!placement) continue;
      var key = coordKey(placement.x, placement.y);
      state.placementsByKey[key] = placement;
    }
  }

  // Converts one placement into normalized shape or returns null.
  function sanitizePlacement(rawPlacement, state) {
    if (!rawPlacement || typeof rawPlacement !== 'object') return null;

    var x = parseInt(rawPlacement.x, 10);
    var y = parseInt(rawPlacement.y, 10);
    var pieceId = parseInt(rawPlacement.piece_id, 10);
    var color = String(rawPlacement.color || '');

    if (!isFinite(x) || !isFinite(y) || !isFinite(pieceId)) return null;
    if (x < 0 || y < 0 || x >= state.size || y >= state.size) return null;
    if (!isPlayerZone(y, state.size)) return null;
    if (!state.piecesById[pieceId]) return null;
    if (color !== 'white') return null;

    return { x: x, y: y, piece_id: pieceId, color: 'white' };
  }

  // Selects first palette piece so user can place immediately.
  function selectFirstPieceIfAvailable(state, elements) {
    if (!elements.pieceButtons.length) return;

    var firstButton = elements.pieceButtons[0];
    var pieceId = parseInt(firstButton.getAttribute('data-piece-id'), 10);
    if (!isFinite(pieceId)) return;
    setSelectedPiece(state, elements, pieceId);
  }

  // Attaches all editor event handlers.
  function bindEditorEvents(state, elements) {
    elements.grid.addEventListener('click', function (event) {
      onGridClick(state, elements, event);
    });

    elements.sizeInput.addEventListener('change', function () {
      state.size = normalizeBoardSize(elements.sizeInput.value);
      elements.sizeInput.value = String(state.size);
      keepPlacementsInsideBoard(state);
      renderBoardEditor(state, elements);
    });

    forEachNode(elements.toolButtons, function (button) {
      button.addEventListener('click', function () {
        state.tool = button.getAttribute('data-board-tool') === 'erase' ? 'erase' : 'piece';
        renderToolButtons(state, elements);
      });
    });

    forEachNode(elements.pieceButtons, function (button) {
      button.addEventListener('click', function () {
        var pieceId = parseInt(button.getAttribute('data-piece-id'), 10);
        if (!isFinite(pieceId)) return;
        setSelectedPiece(state, elements, pieceId);
      });
    });

    if (elements.resetButton) {
      elements.resetButton.addEventListener('click', function () {
        state.placementsByKey = {};
        renderBoardEditor(state, elements);
      });
    }
  }

  // Handles one board square click for place/erase tools.
  function onGridClick(state, elements, event) {
    var square = event.target;
    if (square && square.tagName !== 'BUTTON') {
      square = square.closest('button[data-board-square]');
    }
    if (!square || !square.hasAttribute('data-board-square')) return;

    var x = parseInt(square.getAttribute('data-x'), 10);
    var y = parseInt(square.getAttribute('data-y'), 10);
    if (!isFinite(x) || !isFinite(y)) return;
    if (!isPlayerZone(y, state.size)) return;

    var key = coordKey(x, y);
    if (state.tool === 'erase') {
      delete state.placementsByKey[key];
      renderBoardEditor(state, elements);
      return;
    }

    if (!state.selectedPieceId) return;

    state.placementsByKey[key] = {
      x: x,
      y: y,
      piece_id: state.selectedPieceId,
      color: 'white'
    };
    renderBoardEditor(state, elements);
  }

  // Removes placements that are outside current board size.
  function keepPlacementsInsideBoard(state) {
    var nextPlacements = {};
    var keys = Object.keys(state.placementsByKey);

    for (var i = 0; i < keys.length; i += 1) {
      var key = keys[i];
      var placement = state.placementsByKey[key];
      if (!placement) continue;
      if (placement.x < 0 || placement.y < 0 || placement.x >= state.size || placement.y >= state.size) continue;
      if (!isPlayerZone(placement.y, state.size)) continue;
      placement.color = 'white';
      nextPlacements[key] = placement;
    }

    state.placementsByKey = nextPlacements;
  }

  // Stores selected piece id and updates palette styles.
  function setSelectedPiece(state, elements, pieceId) {
    if (!state.piecesById[pieceId]) return;
    state.selectedPieceId = pieceId;
    state.selectedPieceName = state.piecesById[pieceId].name || ('Piece #' + pieceId);
    state.tool = 'piece';
    renderPieceButtons(state, elements);
    renderToolButtons(state, elements);
    renderSelectedText(state, elements);
  }

  // Rebuilds full board UI and writes placements JSON to hidden input.
  function renderBoardEditor(state, elements) {
    elements.grid.innerHTML = '';
    elements.grid.style.gridTemplateColumns = 'repeat(' + state.size + ', 2.8rem)';

    for (var y = 0; y < state.size; y += 1) {
      for (var x = 0; x < state.size; x += 1) {
        var square = document.createElement('button');
        square.type = 'button';
        square.setAttribute('data-board-square', 'true');
        square.setAttribute('data-x', String(x));
        square.setAttribute('data-y', String(y));
        square.className = 'board-editor__square ' + (((x + y) % 2 === 0) ? 'is-light' : 'is-dark');
        if (!isPlayerZone(y, state.size)) {
          square.classList.add('is-opponent-zone');
        }

        renderSquarePiece(state, square, x, y);
        elements.grid.appendChild(square);
      }
    }

    writePlacementsJson(state, elements.placementsInput);
    renderSelectedText(state, elements);
    renderPieceButtons(state, elements);
    renderToolButtons(state, elements);
  }

  // Draws piece icon or fallback letter in one square.
  function renderSquarePiece(state, square, x, y) {
    var placement = state.placementsByKey[coordKey(x, y)];
    if (!placement) return;

    var piece = state.piecesById[placement.piece_id];
    if (!piece) return;

    if (piece.image_path) {
      var img = document.createElement('img');
      img.className = 'board-editor__piece-icon';
      if (shouldInvertIcon(piece.icon_base_color, placement.color)) {
        img.classList.add('is-inverted');
      }
      img.src = piece.image_path;
      img.alt = piece.name + ' icon';
      square.appendChild(img);
      return;
    }

    var label = document.createElement('span');
    label.className = 'board-editor__piece-label ' + (placement.color === 'white' ? 'is-white' : 'is-black');
    label.textContent = piece.name ? piece.name.charAt(0).toUpperCase() : '?';
    square.appendChild(label);
  }

  // Chooses icon inversion based on icon base color and placed piece color.
  function shouldInvertIcon(iconBaseColor, placementColor) {
    if (iconBaseColor === 'black' && placementColor === 'white') return true;
    if (iconBaseColor === 'white' && placementColor === 'black') return true;
    return false;
  }

  // Updates hidden input with sorted placements array as JSON string.
  function writePlacementsJson(state, placementsInput) {
    var placements = [];
    var keys = Object.keys(state.placementsByKey);

    for (var i = 0; i < keys.length; i += 1) {
      placements.push(state.placementsByKey[keys[i]]);
    }

    placements.sort(function (a, b) {
      if (a.y !== b.y) return a.y - b.y;
      return a.x - b.x;
    });

    placementsInput.value = JSON.stringify(placements);
  }

  // Draws active/inactive style for all piece palette buttons.
  function renderPieceButtons(state, elements) {
    forEachNode(elements.pieceButtons, function (button) {
      var pieceId = parseInt(button.getAttribute('data-piece-id'), 10);
      var selected = isFinite(pieceId) && pieceId === state.selectedPieceId;
      button.classList.toggle('is-selected', selected);
    });
  }

  // Draws active/inactive style for place and erase buttons.
  function renderToolButtons(state, elements) {
    forEachNode(elements.toolButtons, function (button) {
      var tool = button.getAttribute('data-board-tool');
      button.classList.toggle('is-active', tool === state.tool);
    });
  }

  // Writes current selected piece text for user feedback.
  function renderSelectedText(state, elements) {
    if (!elements.selectedText) return;
    if (!state.selectedPieceId) {
      elements.selectedText.textContent = 'No piece selected.';
      return;
    }
    elements.selectedText.textContent = 'Selected: ' + state.selectedPieceName + ' (#' + state.selectedPieceId + '). Places as white on the bottom half.';
  }

  // Returns y-index where the editable player zone starts.
  function playerZoneStartRow(size) {
    return Math.floor(size / 2);
  }

  // Checks if one row belongs to the editable player zone.
  function isPlayerZone(y, size) {
    return y >= playerZoneStartRow(size);
  }

  // Builds stable key for board square maps.
  function coordKey(x, y) {
    return x + ',' + y;
  }

  // Loops over NodeList in older browser-safe style.
  function forEachNode(nodeList, callback) {
    for (var i = 0; i < nodeList.length; i += 1) {
      callback(nodeList[i]);
    }
  }

  document.addEventListener('DOMContentLoaded', bootBoardEditors);
})();
