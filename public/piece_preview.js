(function () {
  // Boots the preview module for every preview root on the page.
  document.addEventListener('DOMContentLoaded', function () {
    var ns = window.PiecePreview || {};
    if (typeof ns.createPreview !== 'function') return;
    var roots = document.querySelectorAll('[data-piece-preview-root]');
    for (var i = 0; i < roots.length; i += 1) {
      ns.createPreview(roots[i]);
    }
  });
})();
