(() => {
  const params = new URLSearchParams(window.location.search);
  const theme = params.get("theme");
  if (theme === "light" || theme === "dark") {
    document.documentElement.setAttribute("data-theme", theme);
  } else {
    const stored = localStorage.getItem("phx:theme");
    if (stored && stored !== "system") {
      document.documentElement.setAttribute("data-theme", stored);
    }
  }
})();
