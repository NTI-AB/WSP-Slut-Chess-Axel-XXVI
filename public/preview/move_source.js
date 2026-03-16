(function () {
  var ns = window.PiecePreview = window.PiecePreview || {};
  var util = ns.util || {};
  var parseJsonSafe = util.parseJsonSafe;
  var positiveInt = util.positiveInt;
  var closestForm = util.closestForm;

  // Reads one enabled movement method config from the form.
  function readCheckedToggleConfig(form, methodId) {
    var fieldset = form.querySelector('[data-preview-method="' + methodId + '"]');
    if (!fieldset) return null;

    var modeInput = form.querySelector('[name="mode[' + methodId + ']"]');
    var colorScopeInput = form.querySelector('[name="color_scope[' + methodId + ']"]');
    var rayLimitInput = form.querySelector('[name="ray_limit[' + methodId + ']"]');
    var firstMoveOnlyInput = form.querySelector('[name="first_move_only[' + methodId + ']"]');

    return {
      movement_method_id: positiveInt(methodId),
      name: fieldset.getAttribute('data-preview-name') || ('Method ' + methodId),
      kind: fieldset.getAttribute('data-preview-kind') || 'ray',
      vectors: parseJsonSafe(fieldset.getAttribute('data-preview-vectors') || '{}', {}),
      ray_limit: rayLimitInput ? positiveInt(rayLimitInput.value) : null,
      mode: modeInput ? modeInput.value : 'both',
      color_scope: colorScopeInput ? colorScopeInput.value : 'any',
      first_move_only: !!(firstMoveOnlyInput && firstMoveOnlyInput.checked)
    };
  }

  // Builds an optional mirrored secondary mode config for ray-like methods.
  function readSecondaryConfig(form, methodId, baseMove) {
    var secondaryToggle = form.querySelector('[name="secondary_mode_enabled[' + methodId + ']"]');
    var secondaryRayLimitInput = form.querySelector('[name="secondary_ray_limit[' + methodId + ']"]');
    var secondaryEnabled = !!(secondaryToggle && secondaryToggle.checked);
    var primaryMode = baseMove.mode;
    var isRayLike = form.querySelector('[name="ray_limit[' + methodId + ']"]') || secondaryRayLimitInput;

    if (!secondaryEnabled || !isRayLike) return null;
    if (primaryMode !== 'move' && primaryMode !== 'capture') return null;

    return {
      movement_method_id: positiveInt(methodId),
      name: baseMove.name + ' (secondary)',
      kind: baseMove.kind,
      vectors: baseMove.vectors,
      ray_limit: secondaryRayLimitInput ? positiveInt(secondaryRayLimitInput.value) : null,
      mode: primaryMode === 'move' ? 'capture' : 'move',
      color_scope: baseMove.color_scope,
      first_move_only: baseMove.first_move_only
    };
  }

  // Reads live movement config from the create/edit form.
  function parseMoveSourceFromForm(root) {
    var form = closestForm(root);
    if (!form) return [];

    var toggles = form.querySelectorAll('[data-method-toggle]');
    var moves = [];

    for (var i = 0; i < toggles.length; i += 1) {
      var toggle = toggles[i];
      if (!toggle.checked) continue;

      var methodId = toggle.getAttribute('data-method-toggle');
      var baseMove = readCheckedToggleConfig(form, methodId);
      if (!baseMove) continue;
      moves.push(baseMove);

      var secondaryMove = readSecondaryConfig(form, methodId, baseMove);
      if (secondaryMove) moves.push(secondaryMove);
    }

    return moves;
  }

  // Reads fixed movement config embedded as JSON in the preview partial.
  function parseMoveSourceStatic(root) {
    var script = root.querySelector('script[data-preview-static-moves]');
    if (!script) return [];
    var value = parseJsonSafe(script.textContent || '[]', []);
    return Array.isArray(value) ? value : [];
  }

  // Selects the correct source (form or static JSON) for move definitions.
  function readMoveSource(root) {
    var source = root.getAttribute('data-preview-source') || 'static';
    return source === 'form' ? parseMoveSourceFromForm(root) : parseMoveSourceStatic(root);
  }

  ns.moveSource = {
    readMoveSource: readMoveSource
  };
})();
