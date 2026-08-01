# CB Storage System Landing Page — Image Slots

Replace the placeholder `.png` files in this folder with real images. Keep the **exact same file name and extension** so the page keeps working — only swap the file contents.

> The current files are simple gradient placeholders so the page renders before you add real art.

## Image slots

| File | Suggested size | What to put there |
|------|---------------|-------------------|
| `hero-dashboard.png` | 1200×780 | A clean screenshot of the CB Storage dashboard (login, then capture the Dashboard / Files page). Wide, landscape. |
| `feature-secure.png` | 640×440 | Illustration of security / encryption / a locked vault (green theme). |
| `feature-organize.png` | 640×440 | Illustration of folders / auto-categorisation (blue theme). |
| `feature-duplicate.png` | 640×440 | Illustration of two identical files / a "no duplicates" check (amber theme). |
| `feature-search.png` | 640×440 | Illustration of a search bar / magnifier over files (sky-blue theme). |
| `feature-backup.png` | 640×440 | Illustration of backup / restore arrows, shield with database (purple theme). |
| `feature-audit.png` | 640×440 | Illustration of an activity log / audit trail timeline (pink theme). |
| `how-upload.png` | 400×400 | Step 1: uploading a file (drag & drop). |
| `how-organize.png` | 400×400 | Step 2: automatic categorisation and sorting. |
| `how-protect.png` | 400×400 | Step 3: backup and recovery protection. |
| `security-shield.png` | 560×460 | Big security illustration: shield, lock, key, padlock. |
| `cta-background.png` | 1600×600 | Wide background image for the bottom call-to-action banner (subtle, dark). |

## Tips
- Prefer **PNG or WebP** for crispness. JPG also works if you keep the same `.png` name is not possible — then update the `src` in `frontend/landing.html` and rename here.
- Keep each image under ~300 KB for fast loading.
- All images are referenced from `frontend/landing.html` as `images/<name>`.
