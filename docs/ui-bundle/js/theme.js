// This file owns the persisted light and dark theme behavior for the docs shell.

/**
 * Returns the currently active theme, falling back to the document attribute.
 */
function activeTheme() {
  return document.documentElement.dataset.theme === 'dark' ? 'dark' : 'light'
}

/**
 * Applies one color theme to the document and stores the reader preference.
 */
function applyTheme(theme) {
  const selected = theme === 'dark' ? 'dark' : 'light'
  document.documentElement.dataset.theme = selected
  localStorage.setItem('agent-awesome-docs-theme', selected)
  updateThemeLabels(selected)
}

/**
 * Updates visible toggle copy and accessible labels after a theme change.
 */
function updateThemeLabels(theme) {
  document.querySelectorAll('.theme-toggle').forEach((button) => {
    const label = button.querySelector('.theme-label')
    if (label) {
      label.textContent = theme === 'dark' ? 'Dark' : 'Light'
    }
    button.setAttribute(
      'aria-label',
      theme === 'dark' ? 'Switch to light theme' : 'Switch to dark theme',
    )
  })
}

/**
 * Wires theme toggles once the generated documentation page is ready.
 */
function initializeThemeControls() {
  const requested = new URLSearchParams(window.location.search).get('theme')
  if (requested === 'dark' || requested === 'light') {
    document.documentElement.dataset.theme = requested
  }
  updateThemeLabels(activeTheme())
  document.querySelectorAll('.theme-toggle').forEach((button) => {
    button.addEventListener('click', () => {
      applyTheme(activeTheme() === 'dark' ? 'light' : 'dark')
    })
  })
}

initializeThemeControls()
