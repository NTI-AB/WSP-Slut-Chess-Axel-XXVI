(function () {
  // Boots the preview module for every preview root on the page.
  document.addEventListener('DOMContentLoaded', function () {
    var ns = window.PiecePreview || {};
    if (typeof ns.createPreview !== 'function') return;

    Array.prototype.forEach.call(
      document.querySelectorAll('[data-piece-preview-root]'),
      ns.createPreview
    );
  });
})();
