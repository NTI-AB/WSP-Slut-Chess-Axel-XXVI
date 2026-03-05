(function () {
  var ns = window.PiecePreview = window.PiecePreview || {};
  var util = ns.util || {};
  var renderer = ns.boardRenderer || {};
  var insideBoard = util.insideBoard;
  var positiveInt = util.positiveInt;
  var coordKey = util.coordKey;
  var closestForm = util.closestForm;
  var forEachNode = util.forEachNode;

  // Initializes one interactive preview instance for a root element.
  function createPreview(root) {
    var preview = {
      root: root,
      elements: {
        boardEl: root.querySelector('[data-preview-board]'),
        statusEl: root.querySelector('[data-preview-status]'),
        movesEl: root.querySelector('[data-preview-moves]'),
        boardSizeInput: root.querySelector('[data-preview-board-size]'),
        pieceColorInput: root.querySelector('[data-preview-piece-color]'),
        firstMoveInput: root.querySelector('[data-preview-first-move]'),
        resetBoardButton: root.querySelector('[data-preview-reset-board]'),
        clearBlockersButton: root.querySelector('[data-preview-clear-blockers]'),
        toolButtons: root.querySelectorAll('[data-preview-tool]')
      },
      state: {
        size: 8,
        pieceColor: 'white',
        pieceIconPath: '',
        iconBaseColor: 'black',
        iconFileObjectUrl: '',
        iconFileRef: null,
        firstMove: false,
        tool: 'piece',
        piecePos: null,
        blockers: {}
      }
    };

    initStateFromInputs(preview);
    bindUi(preview);

    renderer.resetPieceToCenter(preview.state);
    renderer.sanitizeBoardState(preview.state);
    setActiveTool(preview, 'piece');
    render(preview);
  }

  // Pulls initial state values from root attributes and preview controls.
  function initStateFromInputs(preview) {
    var elements = preview.elements;
    var root = preview.root;
    var state = preview.state;
    state.size = positiveInt(elements.boardSizeInput && elements.boardSizeInput.value) || 8;
    state.pieceColor = (elements.pieceColorInput && elements.pieceColorInput.value) || 'white';
    state.pieceIconPath = (root.getAttribute('data-preview-piece-icon') || '').trim();
    state.iconBaseColor = (root.getAttribute('data-preview-piece-icon-base-color') || 'black').trim() === 'white' ? 'white' : 'black';
    state.firstMove = !!(elements.firstMoveInput && elements.firstMoveInput.checked);
  }

  // Releases previous object URL when uploaded icon file changes.
  function clearIconFileObjectUrl(preview) {
    if (!preview.state.iconFileObjectUrl) return;
    if (window.URL && typeof window.URL.revokeObjectURL === 'function') {
      window.URL.revokeObjectURL(preview.state.iconFileObjectUrl);
    }
    preview.state.iconFileObjectUrl = '';
    preview.state.iconFileRef = null;
  }

  // Reads icon from form upload in live mode, otherwise keeps static value.
  function readPieceIconFromForm(preview) {
    var staticPath = (preview.root.getAttribute('data-preview-piece-icon') || '').trim();
    if ((preview.root.getAttribute('data-preview-source') || 'static') !== 'form') {
      return staticPath || preview.state.pieceIconPath || '';
    }

    var form = closestForm(preview.root);
    if (!form) return staticPath || preview.state.pieceIconPath || '';
    var input = form.querySelector('[name="icon_file"]');
    if (!input) return staticPath || preview.state.pieceIconPath || '';

    var file = input.files && input.files[0];
    if (!file) {
      clearIconFileObjectUrl(preview);
      return staticPath || '';
    }

    if (!window.URL || typeof window.URL.createObjectURL !== 'function') {
      return staticPath || preview.state.pieceIconPath || '';
    }

    if (preview.state.iconFileRef !== file) {
      clearIconFileObjectUrl(preview);
      preview.state.iconFileObjectUrl = window.URL.createObjectURL(file);
      preview.state.iconFileRef = file;
    }

    return preview.state.iconFileObjectUrl || staticPath || '';
  }

  // Reads icon base color from form in live mode.
  function readIconBaseColorFromForm(preview) {
    if ((preview.root.getAttribute('data-preview-source') || 'static') !== 'form') {
      return preview.state.iconBaseColor || 'black';
    }

    var form = closestForm(preview.root);
    if (!form) return preview.state.iconBaseColor || 'black';
    var input = form.querySelector('[name="icon_base_color"]');
    if (!input) return preview.state.iconBaseColor || 'black';

    return String(input.value || '') === 'white' ? 'white' : 'black';
  }

  // Runs a full render pass with current dynamic state.
  function render(preview) {
    preview.state.pieceIconPath = readPieceIconFromForm(preview);
    preview.state.iconBaseColor = readIconBaseColorFromForm(preview);
    renderer.renderBoard(preview.root, preview.elements, preview.state);
  }

  // Updates active placement tool and button active styling.
  function setActiveTool(preview, nextTool) {
    preview.state.tool = nextTool;
    forEachNode(preview.elements.toolButtons, function (button) {
      button.classList.toggle('is-active', button.getAttribute('data-preview-tool') === nextTool);
    });
  }

  // Applies selected tool action to clicked square.
  function applyToolOnSquare(preview, x, y) {
    var state = preview.state;
    var key = coordKey(x, y);

    if (state.tool === 'piece') {
      state.piecePos = { x: x, y: y };
      delete state.blockers[key];
      render(preview);
      return;
    }

    if (state.piecePos && state.piecePos.x === x && state.piecePos.y === y) {
      if (state.tool === 'erase') {
        state.piecePos = null;
        render(preview);
      }
      return;
    }

    if (state.tool === 'ally' || state.tool === 'enemy') {
      state.blockers[key] = state.tool;
      render(preview);
      return;
    }

    if (state.tool === 'erase') {
      delete state.blockers[key];
      render(preview);
    }
  }

  // Handles board square clicks.
  function onBoardClick(preview, event) {
    var target = event.target;
    if (!target || !target.hasAttribute('data-preview-square')) return;

    var x = parseInt(target.getAttribute('data-x'), 10);
    var y = parseInt(target.getAttribute('data-y'), 10);
    if (!insideBoard(x, y, preview.state.size)) return;

    applyToolOnSquare(preview, x, y);
  }

  // Handles board size input changes.
  function onBoardSizeChange(preview) {
    var input = preview.elements.boardSizeInput;
    if (!input) return;
    preview.state.size = positiveInt(input.value) || 8;
    if (preview.state.size < 4) preview.state.size = 4;
    if (preview.state.size > 20) preview.state.size = 20;
    input.value = String(preview.state.size);
    renderer.sanitizeBoardState(preview.state);
    render(preview);
  }

  // Handles preview piece color changes.
  function onPieceColorChange(preview) {
    var input = preview.elements.pieceColorInput;
    if (!input) return;
    preview.state.pieceColor = input.value === 'black' ? 'black' : 'white';
    render(preview);
  }

  // Handles first-move toggle changes.
  function onFirstMoveChange(preview) {
    var input = preview.elements.firstMoveInput;
    if (!input) return;
    preview.state.firstMove = !!input.checked;
    render(preview);
  }

  // Resets blockers and piece position to default center.
  function onResetBoard(preview) {
    preview.state.blockers = {};
    renderer.resetPieceToCenter(preview.state);
    render(preview);
  }

  // Clears only blockers while keeping piece placement.
  function onClearBlockers(preview) {
    preview.state.blockers = {};
    render(preview);
  }

  // Triggers live rerender for movement config inputs.
  function onFormInput(preview, event) {
    if (event.target && event.target.name && event.target.name.indexOf('ray_limit[') === 0) {
      render(preview);
    }
  }

  // Attaches all DOM event listeners used by the preview app.
  function bindUi(preview) {
    var elements = preview.elements;
    var form = closestForm(preview.root);

    elements.boardEl.addEventListener('click', function (event) {
      onBoardClick(preview, event);
    });

    forEachNode(elements.toolButtons, function (button) {
      button.addEventListener('click', function () {
        setActiveTool(preview, button.getAttribute('data-preview-tool') || 'piece');
      });
    });

    if (elements.boardSizeInput) {
      elements.boardSizeInput.addEventListener('change', function () {
        onBoardSizeChange(preview);
      });
    }

    if (elements.pieceColorInput) {
      elements.pieceColorInput.addEventListener('change', function () {
        onPieceColorChange(preview);
      });
    }

    if (elements.firstMoveInput) {
      elements.firstMoveInput.addEventListener('change', function () {
        onFirstMoveChange(preview);
      });
    }

    if (elements.resetBoardButton) {
      elements.resetBoardButton.addEventListener('click', function () {
        onResetBoard(preview);
      });
    }

    if (elements.clearBlockersButton) {
      elements.clearBlockersButton.addEventListener('click', function () {
        onClearBlockers(preview);
      });
    }

    if (form) {
      form.addEventListener('change', function () {
        render(preview);
      });
      form.addEventListener('input', function (event) {
        onFormInput(preview, event);
      });
    }
  }

  ns.createPreview = createPreview;
})();
