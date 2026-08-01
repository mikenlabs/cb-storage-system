// CB Storage System shared theme switcher (used by index.html and landing.html).
// Applies the saved theme immediately to avoid a flash of the wrong theme,
// then wires up every .theme-toggle button. Persists via localStorage and
// falls back to the OS prefers-color-scheme when nothing is saved.
(function () {
    'use strict';

    var STORAGE_KEY = 'silas-theme';
    var root = document.documentElement;

    function storedTheme() {
        var t = localStorage.getItem(STORAGE_KEY);
        return t === 'dark' || t === 'light' ? t : null;
    }

    function applyTheme(theme) {
        if (theme === 'dark') {
            root.dataset.theme = 'dark';
        } else {
            delete root.dataset.theme;
        }
    }

    function currentTheme() {
        return root.dataset.theme === 'dark' ? 'dark' : 'light';
    }

    applyTheme(storedTheme() || (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'));

    function init() {
        document.querySelectorAll('.theme-toggle').forEach(function (btn) {
            btn.addEventListener('click', function () {
                var next = currentTheme() === 'dark' ? 'light' : 'dark';
                applyTheme(next);
                localStorage.setItem(STORAGE_KEY, next);
            });
        });

        window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', function (e) {
            if (!storedTheme()) {
                applyTheme(e.matches ? 'dark' : 'light');
            }
        });
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
