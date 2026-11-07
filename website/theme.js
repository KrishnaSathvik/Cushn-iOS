// Loaded before the page paints, so a saved theme doesn't flash. With no saved choice the site follows the system.
(function () {
  var root = document.documentElement;
  var dark = window.matchMedia("(prefers-color-scheme: dark)");

  function saved() {
    try { return localStorage.getItem("cushn-theme"); } catch (e) { return null; }
  }
  function current() {
    return root.getAttribute("data-theme") || (dark.matches ? "dark" : "light");
  }
  function label() {
    var button = document.getElementById("theme-toggle");
    if (button) button.setAttribute("aria-label", current() === "dark" ? "Switch to light theme" : "Switch to dark theme");
  }

  var choice = saved();
  if (choice === "light" || choice === "dark") root.setAttribute("data-theme", choice);

  document.addEventListener("DOMContentLoaded", function () {
    label();
    document.getElementById("theme-toggle").addEventListener("click", function () {
      var next = current() === "dark" ? "light" : "dark";
      root.setAttribute("data-theme", next);
      try { localStorage.setItem("cushn-theme", next); } catch (e) {}
      label();
    });
  });
  dark.addEventListener("change", label);
})();
