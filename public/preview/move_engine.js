(function () {
  var ns = window.PiecePreview = window.PiecePreview || {};
  var util = ns.util || {};
  var moveSource = ns.moveSource || {};
  var insideBoard = util.insideBoard;
  var coordKey = util.coordKey;
  var positiveInt = util.positiveInt;

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

  function applyRayMove(move, origin, state, destinations) {
    var vectors = move.vectors || {};
    var rays = Array.isArray(vectors.rays) ? vectors.rays : [];
    var configuredLimit = positiveInt(move.ray_limit);
    var defaultLimit = positiveInt(vectors.ray_limit);
    var limit = configuredLimit || defaultLimit || state.size;
    var allowsMove = includeMoveMode(move.mode);
    var allowsCapture = includeCaptureMode(move.mode);

    for (var i = 0; i < rays.length; i += 1) {
      var ray = rays[i];
      if (!Array.isArray(ray) || ray.length < 2) continue;
      var dx = parseInt(ray[0], 10);
      var dy = parseInt(ray[1], 10);
      if (!isFinite(dx) || !isFinite(dy)) continue;
      if (dx === 0 && dy === 0) continue;

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
    }
  }

  function applyLeapMove(move, origin, state, destinations) {
    var vectors = move.vectors || {};
    var leaps = Array.isArray(vectors.leaps) ? vectors.leaps : [];
    var allowsMove = includeMoveMode(move.mode);
    var allowsCapture = includeCaptureMode(move.mode);

    for (var i = 0; i < leaps.length; i += 1) {
      var leap = leaps[i];
      if (!Array.isArray(leap) || leap.length < 2) continue;
      var tx = origin.x + parseInt(leap[0], 10);
      var ty = origin.y + parseInt(leap[1], 10);
      if (!insideBoard(tx, ty, state.size)) continue;

      var blocker = state.blockers[coordKey(tx, ty)];
      if (!blocker) {
        if (allowsMove) addDestination(destinations, tx, ty, 'move');
        continue;
      }

      if (blocker === 'enemy' && allowsCapture) {
        addDestination(destinations, tx, ty, 'capture');
      }
    }
  }

  function applyPawnRuleMove(move, origin, state, destinations) {
    var vectors = move.vectors || {};
    var colorRule = vectors[state.pieceColor];
    if (!colorRule || typeof colorRule !== 'object') return;

    var allowsMove = includeMoveMode(move.mode);
    var allowsCapture = includeCaptureMode(move.mode);

    if (allowsMove && Array.isArray(colorRule.move_only)) {
      for (var i = 0; i < colorRule.move_only.length; i += 1) {
        var stepVec = colorRule.move_only[i];
        if (!Array.isArray(stepVec) || stepVec.length < 2) continue;
        var tx = origin.x + parseInt(stepVec[0], 10);
        var ty = origin.y + parseInt(stepVec[1], 10);
        if (!insideBoard(tx, ty, state.size)) continue;
        if (!state.blockers[coordKey(tx, ty)]) {
          addDestination(destinations, tx, ty, 'move');
        }
      }
    }

    if (allowsCapture && Array.isArray(colorRule.capture_only)) {
      for (var j = 0; j < colorRule.capture_only.length; j += 1) {
        var stepVec = colorRule.capture_only[j];
        if (!Array.isArray(stepVec) || stepVec.length < 2) continue;
        var tx = origin.x + parseInt(stepVec[0], 10);
        var ty = origin.y + parseInt(stepVec[1], 10);
        if (!insideBoard(tx, ty, state.size)) continue;
        if (state.blockers[coordKey(tx, ty)] === 'enemy') {
          addDestination(destinations, tx, ty, 'capture');
        }
      }
    }

    if (allowsMove && state.firstMove && colorRule.first_move && Array.isArray(colorRule.first_move.rays)) {
      var rays = colorRule.first_move.rays;
      var limit = positiveInt(colorRule.first_move.ray_limit) || 2;

      for (var k = 0; k < rays.length; k += 1) {
        var ray = rays[k];
        if (!Array.isArray(ray) || ray.length < 2) continue;
        var dx = parseInt(ray[0], 10);
        var dy = parseInt(ray[1], 10);
        if (!isFinite(dx) || !isFinite(dy)) continue;

        for (var step = 1; step <= limit; step += 1) {
          var tx = origin.x + (dx * step);
          var ty = origin.y + (dy * step);
          if (!insideBoard(tx, ty, state.size)) break;
          if (state.blockers[coordKey(tx, ty)]) break;
          addDestination(destinations, tx, ty, 'move');
        }
      }
    }
  }

  function computeDestinations(root, state) {
    var destinations = {};
    if (!state.piecePos) return destinations;

    var moves = moveSource.readMoveSource(root);
    var origin = state.piecePos;

    for (var i = 0; i < moves.length; i += 1) {
      var move = moves[i];
      if (!move || typeof move !== 'object') continue;
      if (move.color_scope === 'white' && state.pieceColor !== 'white') continue;
      if (move.color_scope === 'black' && state.pieceColor !== 'black') continue;
      if (move.first_move_only && !state.firstMove) continue;

      if (move.kind === 'ray') {
        applyRayMove(move, origin, state, destinations);
        continue;
      }

      if (move.kind === 'leap') {
        applyLeapMove(move, origin, state, destinations);
        continue;
      }

      if (move.kind === 'rule') {
        applyPawnRuleMove(move, origin, state, destinations);
      }
    }

    return destinations;
  }

  ns.moveEngine = {
    computeDestinations: computeDestinations
  };
})();
