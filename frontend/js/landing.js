// CB Storage System landing page interactions (nav toggle + scroll reveal).
document.addEventListener('DOMContentLoaded', () => {
    const nav = document.getElementById('nav');
    const toggle = document.getElementById('nav-toggle');
    const links = document.getElementById('nav-links');

    // Mobile nav toggle
    toggle.addEventListener('click', () => {
        const isOpen = links.classList.toggle('open');
        nav.classList.toggle('open', isOpen);
        toggle.setAttribute('aria-expanded', String(isOpen));
    });

    // Close the menu after choosing a link (mobile)
    links.querySelectorAll('a').forEach((link) => {
        link.addEventListener('click', () => {
            links.classList.remove('open');
            nav.classList.remove('open');
            toggle.setAttribute('aria-expanded', 'false');
        });
    });

    // Scroll reveal (respects prefers-reduced-motion via CSS)
    const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    const targets = document.querySelectorAll('.reveal');
    if (reduceMotion || !('IntersectionObserver' in window)) {
        targets.forEach((el) => el.classList.add('visible'));
        return;
    }

    const observer = new IntersectionObserver((entries) => {
        entries.forEach((entry) => {
            if (entry.isIntersecting) {
                entry.target.classList.add('visible');
                observer.unobserve(entry.target);
            }
        });
    }, { threshold: 0.12 });

    targets.forEach((el) => observer.observe(el));
});
