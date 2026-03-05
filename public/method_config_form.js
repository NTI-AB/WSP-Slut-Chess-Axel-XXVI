(function () {
  // Shows/hides the secondary ray config and updates its opposite mode label.
  function syncSecondary(methodId) {
    var panel = document.querySelector('[data-secondary-ray-config="' + methodId + '"]');
    if (!panel) return;

    var modeInput = document.querySelector('[name="mode[' + methodId + ']"]');
    if (!modeInput) {
      panel.style.display = 'none';
      return;
    }

    var mode = modeInput.value;
    var visible = (mode === 'move' || mode === 'capture');
    panel.style.display = visible ? 'block' : 'none';

    var otherMode = mode === 'move' ? 'capture' : 'move';
    panel.querySelectorAll('[data-secondary-ray-mode-label]').forEach(function (el) {
      el.textContent = otherMode;
    });
  }

  // Shows/hides one method config block based on checkbox state.
  function sync(toggle) {
    var methodId = toggle.getAttribute('data-method-toggle');
    var panel = document.querySelector('[data-method-config="' + methodId + '"]');
    if (!panel) return;

    panel.style.display = toggle.checked ? 'block' : 'none';
    if (toggle.checked) syncSecondary(methodId);
  }

  // Wires all method toggles and mode selects after DOM is ready.
  document.addEventListener('DOMContentLoaded', function () {
    var toggles = document.querySelectorAll('[data-method-toggle]');
    if (toggles.length === 0) return;

    document.querySelectorAll('select[name^="mode["]').forEach(function (select) {
      select.addEventListener('change', function () {
        var match = select.name.match(/^mode\[(\d+)\]$/);
        if (!match) return;
        syncSecondary(match[1]);
      });
    });

    toggles.forEach(function (toggle) {
      sync(toggle);
      toggle.addEventListener('change', function () { sync(toggle); });
    });
  });
})();
