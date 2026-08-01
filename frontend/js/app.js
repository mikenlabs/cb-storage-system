// ─── State ──────────────────────────────────────────────────
function loadState() {
    const saved = localStorage.getItem('silas_auth');
    if (saved) {
        try {
            const s = JSON.parse(saved);
            return { token: s.token || null, user: s.user || null, profile: null };
        } catch (_) {}
    }
    return { token: null, user: null, profile: null };
}

let state = loadState();

function saveAuth(token, user) {
    state.token = token;
    state.user = user;
    localStorage.setItem('silas_auth', JSON.stringify({ token, user }));
}

function clearAuth() {
    state = { token: null, user: null, profile: null };
    localStorage.removeItem('silas_auth');
}

// ─── SIDEBAR TOGGLE (mobile) ────────────
function closeSidebar() {
    document.getElementById('sidebar-nav').classList.remove('open');
    document.getElementById('sidebar-footer').classList.remove('open', 'show');
    document.getElementById('sidebar-overlay').classList.remove('visible');
    document.querySelector('.menu-icon').style.display = '';
    document.querySelector('.close-icon').style.display = 'none';
}

document.getElementById('sidebar-toggle').addEventListener('click', () => {
    const nav = document.getElementById('sidebar-nav');
    const footer = document.getElementById('sidebar-footer');
    const overlay = document.getElementById('sidebar-overlay');
    const isOpen = nav.classList.contains('open');
    nav.classList.toggle('open');
    footer.classList.toggle('open', !isOpen);
    setTimeout(() => footer.classList.toggle('show', !isOpen), 10);
    overlay.classList.toggle('visible');
    document.querySelector('.menu-icon').style.display = isOpen ? '' : 'none';
    document.querySelector('.close-icon').style.display = isOpen ? 'none' : '';
});

document.getElementById('sidebar-overlay').addEventListener('click', closeSidebar);

const API = window.location.origin === 'file://'
    ? 'http://localhost:5000/api'
    : '/api';

// ─── DOM refs ───────────────────────────────────────────────
const $ = (id) => document.getElementById(id);
const authScreen = $('auth-screen');
const mainScreen = $('main-screen');
const loginForm = $('login-form');
const signupForm = $('signup-form');
const showSignup = $('show-signup');
const showLogin = $('show-login');

// ─── PASSWORD TOGGLE ───────────────────────────────────────
document.querySelectorAll('.toggle-password').forEach((btn) => {
    btn.addEventListener('click', () => {
        const input = $(btn.dataset.target);
        const isPassword = input.type === 'password';
        input.type = isPassword ? 'text' : 'password';
        btn.querySelector('.eye-icon').style.display = isPassword ? 'none' : '';
        btn.querySelector('.eye-off-icon').style.display = isPassword ? '' : 'none';
    });
});

// ─── PASSWORD STRENGTH ─────────────────────────────────────
const PASSWORD_REQS = [
    { key: 'length', test: (p) => p.length >= 8 },
    { key: 'upper', test: (p) => /[A-Z]/.test(p) },
    { key: 'lower', test: (p) => /[a-z]/.test(p) },
    { key: 'number', test: (p) => /\d/.test(p) },
    { key: 'special', test: (p) => /[!@#$%^&*(),.?":{}|<>]/.test(p) },
];

function evaluatePassword(password) {
    const met = PASSWORD_REQS.filter((r) => r.test(password)).length;
    let score = (met / PASSWORD_REQS.length) * 100;
    let label, color;
    if (score === 0) { label = ''; color = 'transparent'; }
    else if (score <= 40) { label = 'Weak'; color = '#DC2626'; }
    else if (score <= 60) { label = 'Fair'; color = '#D97706'; }
    else if (score <= 80) { label = 'Good'; color = '#059669'; }
    else { label = 'Strong'; color = '#059669'; }
    return { score, label, color, met, total: PASSWORD_REQS.length };
}

function updatePasswordStrength(inputId, fillId, textId, reqsContainerId) {
    const input = $(inputId);
    const fill = $(fillId);
    const text = $(textId);
    const reqs = document.querySelectorAll(`#${reqsContainerId} li`);

    const result = evaluatePassword(input.value);
    fill.style.width = `${result.score}%`;
    fill.style.background = result.color;
    text.textContent = result.label;
    text.style.color = result.color;

    reqs.forEach((li) => {
        const req = PASSWORD_REQS.find((r) => r.key === li.dataset.req);
        if (req) {
            li.classList.toggle('met', req.test(input.value) && input.value.length > 0);
            li.classList.toggle('invalid', !req.test(input.value) && input.value.length > 0);
        }
    });
}

$('signup-password').addEventListener('input', () => {
    updatePasswordStrength('signup-password', 'signup-strength-fill', 'signup-strength-text', 'signup-password-reqs');
});

// ─── Auth helpers ───────────────────────────────────────────
function getHeaders() {
    const h = { 'Content-Type': 'application/json' };
    if (state.token) h['Authorization'] = `Bearer ${state.token}`;
    return h;
}

async function apiFetch(path, opts = {}) {
    const res = await fetch(`${API}${path}`, {
        ...opts,
        headers: { ...getHeaders(), ...opts.headers },
    });
    let data;
    try {
        data = await res.json();
    } catch (_) {
        data = {};
    }
    if (!res.ok) throw new Error(data.error || `Request failed (${res.status})`);
    return data;
}

// ─── Auth UI ────────────────────────────────────────────────
showSignup.addEventListener('click', (e) => {
    e.preventDefault();
    loginForm.style.display = 'none';
    signupForm.style.display = 'block';
    $('auth-error').textContent = '';
    $('auth-error').style.display = 'none';
});

showLogin.addEventListener('click', (e) => {
    e.preventDefault();
    signupForm.style.display = 'none';
    loginForm.style.display = 'block';
    $('signup-error').textContent = '';
    $('signup-error').style.display = 'none';
});

loginForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const email = $('email').value;
    const password = $('password').value;
    const btn = loginForm.querySelector('.btn-primary');
    btn.disabled = true;
    btn.textContent = 'Signing in...';
    try {
        const data = await apiFetch('/auth/login', {
            method: 'POST',
            body: JSON.stringify({ email, password }),
        });
        state.token = data.access_token;
        state.user = data.user;
        saveAuth(data.access_token, data.user);
        await loadProfile();
        showMainApp();
    } catch (err) {
        $('auth-error').textContent = err.message;
        $('auth-error').style.display = 'block';
    } finally {
        btn.disabled = false;
        btn.textContent = 'Sign In';
    }
});

signupForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const email = $('signup-email').value;
    const password = $('signup-password').value;
    const full_name = $('full-name').value;
    const result = evaluatePassword(password);

    if (result.met < result.total) {
        $('signup-error').textContent = 'Please meet all password requirements';
        $('signup-error').style.color = '#DC2626';
        $('signup-error').style.display = 'block';
        return;
    }

    const btn = signupForm.querySelector('.btn-primary');
    btn.disabled = true;
    btn.textContent = 'Creating...';
    try {
        await apiFetch('/auth/signup', {
            method: 'POST',
            body: JSON.stringify({ email, password, full_name }),
        });
        $('signup-error').textContent = 'Account created! You can now sign in.';
        $('signup-error').style.color = '#059669';
        $('signup-error').style.display = 'block';
    } catch (err) {
        $('signup-error').textContent = err.message;
        $('signup-error').style.color = '#DC2626';
        $('signup-error').style.display = 'block';
    } finally {
        btn.disabled = false;
        btn.textContent = 'Create Account';
    }
});

$('logout-btn').addEventListener('click', async () => {
    try { await apiFetch('/auth/logout', { method: 'POST' }); } catch (_) {}
    clearAuth();
    authScreen.style.display = 'flex';
    mainScreen.style.display = 'none';
    loginForm.style.display = 'block';
    signupForm.style.display = 'none';
});

// ─── Profile ────────────────────────────────────────────────
async function loadProfile() {
    state.profile = await apiFetch('/auth/me');
    const name = state.profile.full_name || state.profile.email || 'User';
    $('user-name').textContent = name;
    $('user-role').textContent = state.profile.role || 'staff';
    $('user-avatar').textContent = name.charAt(0).toUpperCase();
    const isAdmin = (state.profile.role || 'staff') === 'admin';
    $('admin-nav-item').style.display = isAdmin ? '' : 'none';
    return state.profile;
}

// ─── Navigation ─────────────────────────────────────────────
document.querySelectorAll('.nav-link').forEach((link) => {
    link.addEventListener('click', (e) => {
        e.preventDefault();
        document.querySelectorAll('.nav-link').forEach((l) => l.classList.remove('active'));
        link.classList.add('active');
        const page = link.dataset.page;
        document.querySelectorAll('.page').forEach((p) => p.classList.remove('active-page'));
        $(`page-${page}`).classList.add('active-page');
        if (page === 'dashboard') loadDashboard();
        if (page === 'files') loadFiles();
        if (page === 'categories') loadCategories();
        if (page === 'backup') loadBackupLogs();
        if (page === 'admin') loadAdmin();
        if (window.innerWidth <= 768) closeSidebar();
    });
});

// ─── Show Main App ──────────────────────────────────────────
function showMainApp() {
    authScreen.style.display = 'none';
    mainScreen.style.display = 'flex';
    loadDashboard();
    loadCategories();
}

// ─── Dashboard ──────────────────────────────────────────────
async function loadDashboard() {
    try {
        const stats = await apiFetch('/dashboard/stats');
        $('stat-total-files').textContent = stats.total_files ?? 0;
        $('stat-storage').textContent = formatBytes(stats.total_storage_bytes ?? 0);
        $('stat-week-files').textContent = stats.files_this_week ?? 0;
        $('stat-categories').textContent = stats.categories_count ?? 0;
    } catch (_) {}
}

// ─── Files ──────────────────────────────────────────────────
let searchTimeout;
let currentFiles = [];

$('search-input').addEventListener('input', () => {
    clearTimeout(searchTimeout);
    searchTimeout = setTimeout(() => loadFiles(), 300);
});

$('filter-category').addEventListener('change', () => loadFiles());
$('filter-type').addEventListener('change', () => loadFiles());

async function loadFiles() {
    const q = $('search-input').value;
    const cat = $('filter-category').value;
    const type = $('filter-type').value;
    const params = new URLSearchParams();
    if (q) params.set('q', q);
    if (cat) params.set('category', cat);
    if (type) params.set('type', type);

    let data;
    try {
        if (q) {
            data = await apiFetch(`/files/search?${params}`);
        } else {
            data = await apiFetch(`/files?${params}`);
        }
    } catch (err) {
        const container = $('files-container');
        container.innerHTML = `<div class="empty-state">Could not load files: ${escapeHtml(err.message)}</div>`;
        return;
    }

    currentFiles = data || [];
    renderFiles(currentFiles);
}

function renderFiles(files) {
    const container = $('files-container');
    const me = (state.profile && state.profile.id) || '';
    const isAdmin = (state.profile.role || 'staff') === 'admin';

    if (!files.length) {
        container.innerHTML = '<div class="empty-state">No files found</div>';
        return;
    }

    if (isAdmin) {
        container.innerHTML = files.map((f) => fileCard(f, me)).join('');
        return;
    }

    const mine = files.filter((f) => f.uploaded_by === me);
    const general = files.filter((f) => f.is_general && f.uploaded_by !== me);

    let html = `<h3 class="files-section-title">My Files <span class="files-section-count">${mine.length}</span></h3>`;
    html += mine.length
        ? mine.map((f) => fileCard(f, me)).join('')
        : '<div class="empty-state">You have no files yet</div>';
    html += `<h3 class="files-section-title">General Files <span class="files-section-count">${general.length}</span></h3>`;
    html += general.length
        ? general.map((f) => fileCard(f, me)).join('')
        : '<div class="empty-state">No general files shared yet</div>';
    container.innerHTML = html;
}

function fileCard(f, me) {
    const isAdmin = (state.profile.role || 'staff') === 'admin';
    const canModify = isAdmin || f.uploaded_by === me;
    const uploadedByName = f.uploaded_by_name || (f.profiles && f.profiles.full_name) || '';
    const badge = f.is_general ? ' <span class="badge-general">General</span>' : '';
    const actions = `
        <button class="btn btn-sm btn-outline" onclick="downloadFile('${f.id}')">Download</button>
        ${canModify ? `
            <button class="btn btn-sm btn-outline" onclick="toggleGeneral('${f.id}')">${f.is_general ? 'Unshare' : 'Share'}</button>
            <button class="btn btn-sm btn-danger" onclick="deleteFile('${f.id}')">Delete</button>` : ''}`;
    return `
        <div class="file-card">
            <div class="file-info">
                <span class="file-name">${escapeHtml(f.name)}${badge}</span>
                <span class="file-meta">
                    ${escapeHtml(f.type)} &middot; ${formatBytes(f.size)} &middot; ${new Date(f.created_at).toLocaleDateString()}${uploadedByName ? ' &middot; by ' + escapeHtml(uploadedByName) : ''}
                </span>
            </div>
            <div class="file-actions">${actions}</div>
        </div>`;
}

async function toggleGeneral(id) {
    const f = currentFiles.find((x) => x.id === id);
    if (!f) return;
    const target = !f.is_general;
    try {
        await apiFetch(`/files/${id}/general`, {
            method: 'PUT',
            body: JSON.stringify({ is_general: target }),
        });
        loadFiles();
    } catch (err) {
        showAlert({ title: 'Update failed', message: err.message });
    }
}

// ─── Themed modal (replaces alert/confirm) ─────────────────
function showModal({ title, message, okText = 'OK', cancelText = 'Cancel', danger = false }) {
    return new Promise((resolve) => {
        const overlay = $('modal-overlay');
        $('modal-title').textContent = title;
        $('modal-message').textContent = message;
        const ok = $('modal-ok');
        const cancel = $('modal-cancel');
        ok.textContent = okText;
        ok.className = `btn ${danger ? 'btn-danger' : 'btn-primary'}`;
        cancel.textContent = cancelText;
        cancel.style.display = cancelText ? '' : 'none';
        overlay.hidden = false;
        let settled = false;
        const done = (val) => {
            if (settled) return;
            settled = true;
            overlay.hidden = true;
            ok.onclick = cancel.onclick = overlay.onclick = null;
            document.onkeydown = null;
            resolve(val);
        };
        ok.onclick = () => done(true);
        cancel.onclick = () => done(false);
        overlay.onclick = (e) => { if (e.target === overlay) done(false); };
        document.onkeydown = (e) => { if (e.key === 'Escape') done(false); };
    });
}

async function showAlert({ title, message, okText = 'OK' }) {
    await showModal({ title, message, okText, cancelText: '' });
}

async function downloadFile(id) {
    try {
        const data = await apiFetch(`/files/${id}/download`);
        window.open(data.url, '_blank');
    } catch (err) {
        showAlert({ title: 'Download failed', message: err.message });
    }
}

async function deleteFile(id) {
    const ok = await showModal({
        title: 'Delete file',
        message: 'Delete this file?',
        okText: 'Delete',
        danger: true,
    });
    if (!ok) return;
    try {
        await apiFetch(`/files/${id}`, { method: 'DELETE' });
        loadFiles();
    } catch (err) {
        showAlert({ title: 'Delete failed', message: err.message });
    }
}

// ─── Upload ─────────────────────────────────────────────────
$('drop-zone').addEventListener('click', () => $('file-input').click());
$('file-input').addEventListener('change', () => {
    if ($('file-input').files[0]) {
        $('drop-zone').querySelector('p').innerHTML = $('file-input').files[0].name;
        suggestCategory();
    }
});

$('drop-zone').addEventListener('dragover', (e) => {
    e.preventDefault();
    $('drop-zone').classList.add('dragover');
});

$('drop-zone').addEventListener('dragleave', () => {
    $('drop-zone').classList.remove('dragover');
});

$('drop-zone').addEventListener('drop', (e) => {
    e.preventDefault();
    $('drop-zone').classList.remove('dragover');
    if (e.dataTransfer.files[0]) {
        $('file-input').files = e.dataTransfer.files;
        $('drop-zone').querySelector('p').textContent = e.dataTransfer.files[0].name;
        suggestCategory();
    }
});

let suggestTimer = null;
$('upload-description').addEventListener('input', () => {
    clearTimeout(suggestTimer);
    suggestTimer = setTimeout(suggestCategory, 400);
});

$('upload-category').addEventListener('change', () => {
    const banner = $('cat-suggestion');
    if (!banner.hidden && $('upload-category').value !== banner.dataset.suggestedId) {
        banner.hidden = true;
    }
});

$('cat-suggestion-accept').addEventListener('click', () => {
    $('cat-suggestion').hidden = true;
});

async function suggestCategory() {
    const file = $('file-input').files[0];
    if (!file) return;
    const banner = $('cat-suggestion');
    try {
        const res = await fetch(`${API}/categories/suggest`, {
            method: 'POST',
            headers: { ...getHeaders() },
            body: JSON.stringify({
                name: file.name,
                mime_type: file.type || '',
                description: $('upload-description').value,
            }),
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Suggestion failed');
        if (!data.suggested) { banner.hidden = true; return; }
        const s = data.suggested;
        const select = $('upload-category');
        if ([...select.options].some((o) => o.value === s.id)) {
            select.value = s.id;
        }
        banner.dataset.suggestedId = s.id;
        $('cat-suggestion-text').innerHTML =
            `Detected <strong>${escapeHtml(file.name)}</strong> &mdash; suggested category: ` +
            `<strong style="color:${escapeHtml(s.color)}">${escapeHtml(s.name)}</strong> ` +
            `<em>(${escapeHtml(s.reason || '')})</em>`;
        banner.hidden = false;
    } catch (_) {
        banner.hidden = true;
    }
}

$('upload-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const file = $('file-input').files[0];
    const status = $('upload-status');
    if (!file) { status.textContent = 'Please select a file'; status.style.color = '#DC2626'; return; }

    const formData = new FormData();
    formData.append('file', file);
    formData.append('category_id', $('upload-category').value);
    formData.append('description', $('upload-description').value);
    formData.append('is_general', $('upload-general').checked ? 'true' : 'false');

    const btn = e.target.querySelector('.btn-primary');
    btn.disabled = true;
    btn.innerHTML = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/></svg> Uploading...';

    try {
        const res = await fetch(`${API}/files/upload`, {
            method: 'POST',
            headers: { 'Authorization': `Bearer ${state.token}` },
            body: formData,
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error);
        status.textContent = 'File uploaded successfully!';
        status.style.color = '#059669';
        $('file-input').value = '';
        $('drop-zone').querySelector('p').innerHTML = 'Drag & drop a file here or <span>browse</span>';
        $('upload-description').value = '';
        $('upload-general').checked = false;
        if (data.is_duplicate) {
            status.textContent += ' (duplicate detected)';
            status.style.color = '#D97706';
        }
    } catch (err) {
        status.textContent = err.message;
        status.style.color = '#DC2626';
    } finally {
        btn.disabled = false;
        btn.innerHTML = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/></svg> Upload File';
    }
});

// ─── Categories ─────────────────────────────────────────────
async function loadCategories() {
    try {
        const isAdmin = (state.profile.role || 'staff') === 'admin';
        const data = await apiFetch('/categories');
        let kwMap = {};
        try {
            const kws = await apiFetch('/categories/keywords');
            kws.forEach((k) => {
                (kwMap[k.category_id] = kwMap[k.category_id] || []).push(k.keyword);
            });
        } catch (_) {
            kwMap = {};
        }
        const container = $('categories-container');

        const filterSelect = $('filter-category');
        filterSelect.innerHTML = '<option value="">All Categories</option>';
        data.forEach((c) => {
            filterSelect.innerHTML += `<option value="${c.id}">${c.name}</option>`;
        });

        const uploadSelect = $('upload-category');
        uploadSelect.innerHTML = data.map((c) =>
            `<option value="${c.id}">${c.name}</option>`
        ).join('');

        container.innerHTML = data.map((c) => `
            <div class="category-card">
                <div class="category-dot" style="background:${escapeHtml(c.color)}"></div>
                <div class="category-info">
                    <div class="category-name">${escapeHtml(c.name)}</div>
                    <div class="category-desc">${escapeHtml(c.description || '')}</div>
                    ${isAdmin ? `
                    <div class="keyword-editor">
                        <input type="text" class="keyword-input" data-cat-id="${c.id}"
                            value="${escapeHtml((kwMap[c.id] || []).join(', '))}"
                            placeholder="Auto-categorisation keywords, comma separated"
                            title="Files whose name or description contains one of these words are auto-filed into this category">
                        <button class="btn btn-sm keyword-save-btn" data-cat-id="${c.id}" type="button">Save</button>
                        <span class="keyword-status" id="kw-status-${c.id}"></span>
                    </div>` : ''}
                </div>
            </div>
        `).join('');
    } catch (err) {
        const container = $('categories-container');
        container.innerHTML = `<div class="empty-state">Could not load categories: ${escapeHtml(err.message)}</div>`;
    }
}

$('categories-container').addEventListener('click', async (e) => {
    const btn = e.target.closest('.keyword-save-btn');
    if (!btn) return;
    const id = btn.dataset.catId;
    const input = document.querySelector(`.keyword-input[data-cat-id="${id}"]`);
    const status = document.getElementById(`kw-status-${id}`);
    const keywords = input.value.split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);
    try {
        await apiFetch(`/categories/${id}/keywords`, {
            method: 'PUT',
            body: JSON.stringify({ keywords }),
        });
        status.textContent = 'Saved';
        status.style.color = 'var(--success)';
        setTimeout(() => { status.textContent = ''; }, 2500);
    } catch (err) {
        status.textContent = err.message;
        status.style.color = '#DC2626';
    }
});

// ─── Add Category ──────────────────────────────────────────
$('add-category-btn').addEventListener('click', () => {
    const form = $('add-category-form');
    form.style.display = form.style.display === 'none' ? '' : 'none';
    $('cat-status').textContent = '';
});

$('save-category-btn').addEventListener('click', async () => {
    const name = $('new-cat-name').value.trim();
    const color = $('new-cat-color').value;
    const status = $('cat-status');
    if (!name) { status.textContent = 'Name is required'; status.style.color = '#DC2626'; return; }
    try {
        await apiFetch('/categories', {
            method: 'POST',
            body: JSON.stringify({ name, color }),
        });
        $('new-cat-name').value = '';
        $('add-category-form').style.display = 'none';
        status.textContent = '';
        loadCategories();
    } catch (err) {
        status.textContent = err.message;
        status.style.color = '#DC2626';
    }
});

// ─── Backup & Recovery ──────────────────────────────────────
$('run-backup-btn').addEventListener('click', async () => {
    const btn = $('run-backup-btn');
    btn.disabled = true;
    btn.innerHTML = '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/></svg> Running...';
    try {
        const data = await apiFetch('/backup/run', { method: 'POST' });
        loadBackupLogs();
        const count = data.file_count || 0;
        showAlert({ title: 'Backup complete', message: `${count} file(s) snapshotted.` });
    } catch (err) {
        showAlert({ title: 'Backup failed', message: err.message });
    } finally {
        btn.disabled = false;
        btn.innerHTML = '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 11-2.12-9.36L23 10"/></svg> Run Backup';
    }
});

function toggleScheduleGroups() {
    const mode = $('schedule-mode').value;
    $('schedule-interval-group').style.display = mode === 'interval' ? 'flex' : 'none';
    $('schedule-daily-group').style.display = mode === 'daily' ? 'flex' : 'none';
}

function updateScheduleInfo(s) {
    const el = $('backup-schedule-info');
    if (s.mode === 'disabled') {
        el.textContent = 'Automated backup: disabled';
        return;
    }
    if (s.mode === 'interval') {
        el.innerHTML = `Automated backup: every <strong>${s.interval_minutes} minute(s)</strong>`;
        return;
    }
    const h = String(s.hour).padStart(2, '0');
    const m = String(s.minute).padStart(2, '0');
    el.innerHTML = `Automated backup: daily at <strong>${h}:${m} ${s.timezone || 'UTC'}</strong>`;
}

async function loadBackupSchedule() {
    const el = $('backup-schedule-info');
    if (!el) return;
    try {
        const s = await apiFetch('/backup/schedule');
        if (!s) return;
        $('schedule-mode').value = s.mode || 'disabled';
        $('schedule-interval').value = s.interval_minutes || 30;
        const h = String(s.hour ?? 2).padStart(2, '0');
        const m = String(s.minute ?? 0).padStart(2, '0');
        $('schedule-daily-time').value = `${h}:${m}`;
        toggleScheduleGroups();
        updateScheduleInfo(s);
    } catch (_) {
        el.textContent = 'Automated backup: status unavailable';
    }
}

$('schedule-mode').addEventListener('change', toggleScheduleGroups);

$('save-schedule-btn').addEventListener('click', async () => {
    const mode = $('schedule-mode').value;
    const body = { mode };
    if (mode === 'interval') {
        body.interval_minutes = parseInt($('schedule-interval').value, 10) || 30;
    } else if (mode === 'daily') {
        const t = $('schedule-daily-time').value || '02:00';
        const parts = t.split(':').map(Number);
        body.hour = parts[0];
        body.minute = parts[1];
    }
    const btn = $('save-schedule-btn');
    btn.disabled = true;
    btn.textContent = 'Saving...';
    try {
        const s = await apiFetch('/backup/schedule', { method: 'PUT', body: JSON.stringify(body) });
        updateScheduleInfo(s);
        showAlert({ title: 'Schedule saved', message: 'Automated backup schedule updated.' });
    } catch (err) {
        showAlert({ title: 'Save failed', message: err.message });
    } finally {
        btn.disabled = false;
        btn.textContent = 'Save';
    }
});

async function loadBackupLogs() {
    loadBackupSchedule();
    try {
        const data = await apiFetch('/backup/logs');
        const container = $('backup-logs-container');
        if (!data || data.length === 0) {
            container.innerHTML = '<div class="empty-state">No backups yet</div>';
        } else {
            container.innerHTML = `
                <table>
                    <thead>
                        <tr>
                            <th>Date</th>
                            <th>Type</th>
                            <th>Status</th>
                            <th>Files</th>
                            <th>Size</th>
                            <th>Snapshot</th>
                            <th>Action</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${data.map((b) => `
                            <tr>
                                <td>${new Date(b.started_at).toLocaleString()}</td>
                                <td style="text-transform:capitalize">${b.type}</td>
                                <td><span style="color:${b.status === 'completed' ? '#059669' : '#DC2626'};font-weight:600">${b.status}</span></td>
                                <td>${b.file_count}</td>
                                <td>${formatBytes(b.size_bytes)}</td>
                                <td>${b.snapshot ? '<span style="color:#059669;font-weight:600">Yes</span>' : '<span style="color:#94A3B8">No</span>'}</td>
                                <td>
                                    <div style="display:flex;gap:6px">
                                        <button class="btn btn-sm btn-outline" onclick="restoreBackup('${b.id}')" ${b.snapshot ? '' : 'disabled'}>Restore</button>
                                        <button class="btn btn-sm btn-danger" onclick="deleteBackup('${b.id}')">Delete</button>
                                    </div>
                                </td>
                            </tr>
                        `).join('')}
                    </tbody>
                </table>
            `;
        }
    } catch (_) {
        $('backup-logs-container').innerHTML = '<div class="empty-state">No backups yet</div>';
    }

    try {
        const data = await apiFetch('/recovery/logs');
        const container = $('recovery-logs-container');
        if (!data || data.length === 0) {
            container.innerHTML = '<div class="empty-state">No recovery operations yet</div>';
        } else {
            container.innerHTML = `
                <table>
                    <thead>
                        <tr>
                            <th>Date</th>
                            <th>Status</th>
                            <th>Requested By</th>
                            <th>Details</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${data.map((r) => `
                            <tr>
                                <td>${new Date(r.requested_at).toLocaleString()}</td>
                                <td><span style="color:${r.status === 'completed' ? '#059669' : '#DC2626'};font-weight:600">${r.status}</span></td>
                                <td>${r.profiles?.full_name || 'Unknown'}</td>
                                <td style="color:#64748B">${r.backup_logs?.file_count || 0} files in backup</td>
                            </tr>
                        `).join('')}
                    </tbody>
                </table>
            `;
        }
    } catch (_) {
        $('recovery-logs-container').innerHTML = '<div class="empty-state">No recovery operations yet</div>';
    }
}

async function deleteBackup(id) {
    const ok = await showModal({
        title: 'Delete backup',
        message: 'Delete this backup? Only the snapshot is removed; your files stay untouched.',
        okText: 'Delete',
        danger: true,
    });
    if (!ok) return;
    try {
        await apiFetch(`/backup/logs/${id}`, { method: 'DELETE' });
        loadBackupLogs();
    } catch (err) {
        showAlert({ title: 'Delete failed', message: err.message });
    }
}

async function restoreBackup(id) {
    const ok = await showModal({
        title: 'Restore backup',
        message: 'Restore files from this backup? Existing duplicates will be skipped.',
        okText: 'Restore',
    });
    if (!ok) return;
    try {
        const data = await apiFetch('/recovery/restore', {
            method: 'POST',
            body: JSON.stringify({ backup_log_id: id }),
        });
        loadBackupLogs();
        const restored = data.files_restored || 0;
        const skipped = data.duplicates_skipped || 0;
        showAlert({ title: 'Recovery complete', message: `${restored} file(s) restored\n${skipped} duplicate(s) skipped` });
    } catch (err) {
        showAlert({ title: 'Recovery failed', message: err.message });
    }
}

// ─── Admin Panel ─────────────────────────────────────────────
async function loadAdmin() {
    try {
        const [users, logs] = await Promise.all([
            apiFetch('/admin/users'),
            apiFetch('/admin/audit-logs'),
        ]);
        renderAdminUsers(users);
        renderAdminAudit(logs);
    } catch (err) {
        if (err.message.includes('Admin access')) {
            $('admin-users-container').innerHTML = '<div class="empty-state">Admin access required</div>';
            $('admin-audit-container').innerHTML = '';
        } else {
            $('admin-users-container').innerHTML = '<div class="empty-state">Could not load users</div>';
            $('admin-audit-container').innerHTML = '';
        }
    }
}

function renderAdminUsers(users) {
    const list = Array.isArray(users) ? users : [];
    const admins = list.filter((u) => u.role === 'admin').length;
    const totalFiles = list.reduce((sum, u) => sum + (u.file_count || 0), 0);
    const totalSize = list.reduce((sum, u) => sum + (u.storage_bytes || 0), 0);

    $('admin-stat-users').textContent = list.length;
    $('admin-stat-admins').textContent = admins;
    $('admin-stat-files').textContent = totalFiles;
    $('admin-stat-storage').textContent = formatBytes(totalSize);

    const container = $('admin-users-container');
    if (list.length === 0) {
        container.innerHTML = '<div class="empty-state">No users found</div>';
        return;
    }

    container.innerHTML = `
        <table>
            <thead>
                <tr>
                    <th>User</th>
                    <th>Role</th>
                    <th>Files</th>
                    <th>Storage</th>
                    <th>Joined</th>
                    <th>Action</th>
                </tr>
            </thead>
            <tbody>
                ${list.map((u) => `
                    <tr>
                        <td>
                            <div class="admin-user-cell">
                                <span class="user-avatar admin-avatar">${escapeHtml((u.full_name || 'U').charAt(0).toUpperCase())}</span>
                                <div>
                                    <div class="admin-user-name">${escapeHtml(u.full_name || 'User')}</div>
                                    <div class="admin-user-email">${escapeHtml(u.email || '—')}</div>
                                </div>
                            </div>
                        </td>
                        <td>
                            <select class="role-select ${u.role === 'admin' ? 'role-admin' : 'role-staff'}"
                                    onchange="changeUserRole('${u.id}', this.value)"
                                    ${u.id === (state.user && state.user.id) ? 'disabled' : ''}
                                    aria-label="Role for ${escapeHtml(u.full_name || 'user')}">
                                <option value="staff" ${u.role === 'staff' ? 'selected' : ''}>Staff</option>
                                <option value="admin" ${u.role === 'admin' ? 'selected' : ''}>Admin</option>
                            </select>
                        </td>
                        <td>${u.file_count || 0}</td>
                        <td>${formatBytes(u.storage_bytes || 0)}</td>
                        <td>${new Date(u.created_at).toLocaleDateString()}</td>
                        <td>
                            ${u.id === (state.user && state.user.id)
                                ? '<span class="text-muted">You</span>'
                                : `<button class="btn btn-sm btn-danger" onclick="deleteUser('${u.id}', '${escapeHtml(u.full_name || 'this user')}')">Delete</button>`}
                        </td>
                    </tr>
                `).join('')}
            </tbody>
        </table>
    `;
}

function renderAdminAudit(logs) {
    const list = Array.isArray(logs) ? logs : [];
    const container = $('admin-audit-container');
    if (list.length === 0) {
        container.innerHTML = '<div class="empty-state">No activity logged yet</div>';
        return;
    }

    const ACTION_COLORS = {
        upload: '#059669', download: '#3B82F6', delete: '#DC2626',
        backup: '#D97706', recover: '#7C3AED', login: '#0EA5E9',
        restore: '#7C3AED', update: '#64748B',
    };

    container.innerHTML = `
        <table>
            <thead>
                <tr>
                    <th>Date</th>
                    <th>Action</th>
                    <th>Resource</th>
                    <th>User</th>
                    <th>Details</th>
                </tr>
            </thead>
            <tbody>
                ${list.map((l) => `
                    <tr>
                        <td>${new Date(l.created_at).toLocaleString()}</td>
                        <td><span class="badge" style="color:${ACTION_COLORS[l.action] || '#64748B'};background:${(ACTION_COLORS[l.action] || '#64748B')}14">${escapeHtml(l.action)}</span></td>
                        <td>${escapeHtml(l.resource_type)}</td>
                        <td>${escapeHtml((l.profiles && l.profiles.full_name) || 'Unknown')}</td>
                        <td class="admin-audit-detail">${escapeHtml(JSON.stringify(l.details || {}))}</td>
                    </tr>
                `).join('')}
            </tbody>
        </table>
    `;
}

async function changeUserRole(userId, role) {
    try {
        await apiFetch(`/admin/users/${userId}/role`, {
            method: 'PATCH',
            body: JSON.stringify({ role }),
        });
        loadAdmin();
    } catch (err) {
        showAlert({ title: 'Role change failed', message: err.message });
        loadAdmin();
    }
}

async function deleteUser(userId, name) {
    const ok = await showModal({
        title: 'Delete user',
        message: `Delete user "${name}"?\nThis removes their account, files and storage permanently.`,
        okText: 'Delete',
        danger: true,
    });
    if (!ok) return;
    try {
        await apiFetch(`/admin/users/${userId}`, { method: 'DELETE' });
        loadAdmin();
        loadDashboard();
    } catch (err) {
        showAlert({ title: 'Delete failed', message: err.message });
    }
}

// ─── Utilities ──────────────────────────────────────────────
function escapeHtml(value) {
    return String(value ?? '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

function formatBytes(bytes) {
    if (!bytes || bytes === 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    let i = 0;
    let size = bytes;
    while (size >= 1024 && i < units.length - 1) { size /= 1024; i++; }
    return `${size.toFixed(1)} ${units[i]}`;
}

// ─── Init ───────────────────────────────────────────────────
async function restoreSession() {
    if (!state.token) return;
    try {
        await loadProfile();
        showMainApp();
    } catch (_) {
        clearAuth();
    }
}

document.addEventListener('DOMContentLoaded', restoreSession);
