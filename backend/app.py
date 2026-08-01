from datetime import datetime, timezone
import hashlib
import os
import uuid

from apscheduler.schedulers.background import BackgroundScheduler
from flask import Flask, request, jsonify, send_from_directory
from werkzeug.utils import secure_filename

from config import Config
from supabase_client import supabase, service_supabase

app = Flask(__name__)
app.config.from_object(Config)


class CORSMiddleware:
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        def cors_start_response(status, headers, exc_info=None):
            new_headers = [(k, v) for k, v in headers if k.lower() != 'access-control-allow-origin']
            new_headers.append(('Access-Control-Allow-Origin', '*'))
            new_headers.append(('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With'))
            new_headers.append(('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS, PATCH'))
            return start_response(status, new_headers, exc_info)
        return self.app(environ, cors_start_response)


app.wsgi_app = CORSMiddleware(app.wsgi_app)

# ─── HELPERS ──────────────────────────────────────────────────


def get_current_user():
    token = request.headers.get("Authorization", "").replace("Bearer ", "")
    if not token:
        return None
    try:
        user = supabase.auth.get_user(token)
        return user
    except Exception:
        return None


def compute_checksum(file_bytes):
    return hashlib.sha256(file_bytes).hexdigest()


def is_admin(user):
    if not user:
        return False
    try:
        profile = service_supabase.table("profiles").select("role").eq("id", user.user.id).single().execute()
        return profile.data.get("role") == "admin"
    except Exception:
        return False

# ─── AUTH ─────────────────────────────────────────────────────


@app.route("/api/auth/signup", methods=["POST"])
def signup():
    try:
        data = request.get_json()
        email = data.get("email")
        password = data.get("password")
        full_name = data.get("full_name", "User")

        result = supabase.auth.sign_up({
            "email": email,
            "password": password,
            "options": {"data": {"full_name": full_name, "role": "staff"}},
        })
        if result.user:
            return jsonify({"message": "User created", "user": {"id": result.user.id, "email": result.user.email}}), 201
        return jsonify({"error": "Signup failed"}), 400
    except Exception as e:
        print(f"[SIGNUP ERROR] {e}")
        import traceback
        traceback.print_exc()
        return jsonify({"error": str(e)}), 400


@app.route("/api/auth/login", methods=["POST"])
def login():
    data = request.get_json() or {}
    email = data.get("email")
    password = data.get("password")

    try:
        result = supabase.auth.sign_in_with_password({"email": email, "password": password})
    except Exception:
        return jsonify({"error": "Invalid credentials"}), 401

    if result.session:
        role = "staff"
        try:
            profile = service_supabase.table("profiles").select("role").eq("id", result.user.id).single().execute()
            role = profile.data.get("role", "staff")
        except Exception:
            pass
        return jsonify({
            "access_token": result.session.access_token,
            "refresh_token": result.session.refresh_token,
            "role": role,
            "user": {
                "id": result.user.id,
                "email": result.user.email,
            }
        })
    return jsonify({"error": "Invalid credentials"}), 401


@app.route("/api/auth/me", methods=["GET"])
def me():
    user = get_current_user()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401
    try:
        profile = service_supabase.table("profiles").select("*").eq("id", user.user.id).single().execute()
        return jsonify(profile.data)
    except Exception:
        return jsonify({"id": user.user.id, "email": user.user.email}), 200


@app.route("/api/auth/logout", methods=["POST"])
def logout():
    token = request.headers.get("Authorization", "").replace("Bearer ", "")
    try:
        supabase.auth.admin.sign_out(token, scope="global")
    except Exception:
        try:
            supabase.auth.sign_out()
        except Exception:
            pass
    return jsonify({"message": "Logged out"})

# ─── CATEGORIES ───────────────────────────────────────────────


@app.route("/api/categories", methods=["GET"])
def list_categories():
    user = get_current_user()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401
    cats = service_supabase.table("file_categories").select("*").order("name").execute()
    return jsonify(cats.data)


@app.route("/api/categories", methods=["POST"])
def create_category():
    user = get_current_user()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401
    if not is_admin(user):
        return jsonify({"error": "Admin access required"}), 403
    data = request.get_json()
    result = service_supabase.table("file_categories").insert({
        "name": data["name"],
        "description": data.get("description", ""),
        "color": data.get("color", "#6366f1"),
    }).execute()
    return jsonify(result.data[0]), 201


@app.route("/api/categories/keywords", methods=["GET"])
def list_category_keywords():
    user = get_current_user()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401
    result = service_supabase.table("category_keywords").select("*").execute()
    return jsonify(result.data)


@app.route("/api/categories/<category_id>/keywords", methods=["PUT"])
def update_category_keywords(category_id):
    user = get_current_user()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401
    if not is_admin(user):
        return jsonify({"error": "Admin access required"}), 403
    data = request.get_json(silent=True) or {}
    seen = set()
    keywords = []
    for k in (data.get("keywords") or []):
        k = str(k).strip().lower()
        if k and k not in seen:
            seen.add(k)
            keywords.append(k)
    try:
        service_supabase.table("category_keywords").delete().eq("category_id", category_id).execute()
        if keywords:
            service_supabase.table("category_keywords").insert(
                [{"category_id": category_id, "keyword": k} for k in keywords]
            ).execute()
    except Exception as e:
        print(f"[KEYWORDS UPDATE ERROR] {e}")
        return jsonify({"error": "Could not update keywords"}), 500
    return jsonify({"message": "Keywords updated", "keywords": keywords})


@app.route("/api/categories/suggest", methods=["POST"])
def suggest_category():
    """Suggest a category for an upcoming upload, mirroring the database
    auto_assign_category() trigger: keyword match on name/description first,
    then a MIME-type fallback."""
    user = get_current_user()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401
    data = request.get_json(silent=True) or {}
    name = (data.get("name") or "").lower()
    desc = (data.get("description") or "").lower()
    mime = (data.get("mime_type") or "").lower()
    haystack = f"{name} {desc}"
    try:
        kws = service_supabase.table("category_keywords").select("category_id, keyword").execute()
        cats = service_supabase.table("file_categories").select("id, name, color").execute()
    except Exception as e:
        print(f"[CATEGORY SUGGEST ERROR] {e}")
        return jsonify({"error": "Suggestions unavailable"}), 500

    cat_by_id = {c["id"]: c for c in cats.data}
    cat_by_name = {c["name"].lower(): c for c in cats.data}

    hits = {}
    matched_kw = None
    for k in kws.data:
        kw = (k.get("keyword") or "").lower()
        if kw and kw in haystack:
            hits[k["category_id"]] = hits.get(k["category_id"], 0) + 1
            if matched_kw is None:
                matched_kw = kw
    ranked = sorted(hits.items(), key=lambda x: -x[1])

    suggested_id = None
    reason = ""
    if ranked:
        suggested_id = ranked[0][0]
        reason = f"keyword match: {matched_kw}"
    else:
        doc_types = (
            "application/pdf", "application/msword",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "application/vnd.ms-excel",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "text/plain", "text/csv",
        )
        archive_types = ("application/zip", "application/x-rar-compressed", "application/x-7z-compressed")
        if mime in doc_types:
            suggested_id = cat_by_name.get("documents", {}).get("id")
            reason = "file type: document"
        elif mime.startswith("image/"):
            suggested_id = cat_by_name.get("images", {}).get("id")
            reason = "file type: image"
        elif mime in archive_types:
            suggested_id = cat_by_name.get("archives", {}).get("id")
            reason = "file type: archive"
        elif name.endswith((".pdf", ".doc", ".docx", ".xls", ".xlsx", ".csv", ".txt")):
            suggested_id = cat_by_name.get("documents", {}).get("id")
            reason = "file extension"
        else:
            suggested_id = cat_by_name.get("software", {}).get("id")
            reason = "file type: other"

    suggested = dict(cat_by_id.get(suggested_id)) if suggested_id and cat_by_id.get(suggested_id) else None
    if suggested:
        suggested["reason"] = reason
    alternatives = []
    for cid, _ in ranked[1:4]:
        if cat_by_id.get(cid):
            alternatives.append(dict(cat_by_id[cid]))
    return jsonify({"suggested": suggested, "alternatives": alternatives})

# ─── FILES ─────────────────────────────────────────────────────


@app.route("/api/files", methods=["GET"])
def list_files():
    user = get_current_user()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401

    category = request.args.get("category")
    file_type = request.args.get("type")
    sort = request.args.get("sort", "created_at")
    order = request.args.get("order", "desc")
    page = int(request.args.get("page", 1))
    per_page = int(request.args.get("per_page", 20))

    query = service_supabase.table("files").select(
        "*, file_categories(name, color), profiles(full_name)"
    ).is_("deleted_at", "null")

    if category:
        query = query.eq("category_id", category)
    if file_type:
        query = query.eq("type", file_type)

    if not is_admin(user):
        query = query.or_(f"uploaded_by.eq.{user.user.id},is_general.eq.true")

    query = query.order(sort, desc=(order == "desc"))
    query = query.range((page - 1) * per_page, page * per_page - 1)

    result = query.execute()
    return jsonify(result.data)


@app.route("/api/files/upload", methods=["POST"])
def upload_file():
    user = get_current_user()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401

    if "file" not in request.files:
        return jsonify({"error": "No file provided"}), 400

    file = request.files["file"]
    category_id = request.form.get("category_id") or None
    description = request.form.get("description", "")

    original_name = secure_filename(file.filename)
    file_bytes = file.read()
    checksum = compute_checksum(file_bytes)
    storage_path = f"{user.user.id}/{uuid.uuid4()}_{original_name}"

    try:
        service_supabase.storage.from_(Config.STORAGE_BUCKET).upload(
            storage_path, file_bytes, {"content-type": file.content_type}
        )
    except Exception as e:
        print(f"[UPLOAD STORAGE ERROR] {e}")
        return jsonify({"error": "Storage upload failed"}), 500

    file_meta = {
        "name": original_name,
        "type": file.content_type or "application/octet-stream",
        "category_id": category_id,
        "size": len(file_bytes),
        "storage_path": storage_path,
        "uploaded_by": user.user.id,
        "description": description,
        "checksum": checksum,
        "is_general": request.form.get("is_general", "false").lower() in ("1", "true", "yes", "on"),
    }

    try:
        result = service_supabase.table("files").insert(file_meta).execute()
    except Exception as e:
        print(f"[UPLOAD DB ERROR] {e}")
        try:
            service_supabase.storage.from_(Config.STORAGE_BUCKET).remove([storage_path])
        except Exception:
            pass
        return jsonify({"error": "Failed to save file metadata"}), 500

    service_supabase.table("audit_logs").insert({
        "user_id": user.user.id,
        "action": "upload",
        "resource_type": "file",
        "resource_id": result.data[0]["id"],
        "details": {"file_name": original_name, "file_size": len(file_bytes)},
    }).execute()

    return jsonify(result.data[0]), 201


@app.route("/api/files/<file_id>/download", methods=["GET"])
def download_file(file_id):
    user = get_current_user()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401

    file_record = service_supabase.table("files").select("*").eq("id", file_id).maybe_single().execute()
    if not file_record.data:
        return jsonify({"error": "File not found"}), 404

    if file_record.data["uploaded_by"] != user.user.id and not file_record.data.get("is_general") and not is_admin(user):
        return jsonify({"error": "Forbidden"}), 403

    signed_url = service_supabase.storage.from_(Config.STORAGE_BUCKET).create_signed_url(
        file_record.data["storage_path"], 3600
    )

    service_supabase.table("audit_logs").insert({
        "user_id": user.user.id,
        "action": "download",
        "resource_type": "file",
        "resource_id": file_id,
        "details": {"file_name": file_record.data["name"]},
    }).execute()

    return jsonify({"url": signed_url["signedURL"]})


@app.route("/api/files/<file_id>", methods=["DELETE"])
def delete_file(file_id):
    user = get_current_user()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401

    file_record = service_supabase.table("files").select("*").eq("id", file_id).maybe_single().execute()
    if not file_record.data:
        return jsonify({"error": "File not found"}), 404

    if file_record.data["uploaded_by"] != user.user.id and not is_admin(user):
        return jsonify({"error": "Forbidden"}), 403

    service_supabase.table("files").update({"deleted_at": datetime.now(timezone.utc).isoformat()}).eq(
        "id", file_id
    ).execute()

    return jsonify({"message": "File deleted"})


@app.route("/api/files/<file_id>/general", methods=["PUT"])
def set_general(file_id):
    user = get_current_user()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401

    data = request.get_json(silent=True) or {}
    is_general = bool(data.get("is_general"))

    file_record = service_supabase.table("files").select("*").eq("id", file_id).maybe_single().execute()
    if not file_record.data:
        return jsonify({"error": "File not found"}), 404

    if file_record.data["uploaded_by"] != user.user.id and not is_admin(user):
        return jsonify({"error": "Forbidden"}), 403

    service_supabase.table("files").update({"is_general": is_general}).eq("id", file_id).execute()
    return jsonify({"message": "File updated", "is_general": is_general})


@app.route("/api/files/search", methods=["GET"])
def search_files():
    user = get_current_user()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401

    query = request.args.get("q", "")
    if not query:
        return jsonify([])

    try:
        result = service_supabase.rpc(
            "search_files", {"search_query": query, "requesting_user": user.user.id}
        ).execute()
        return jsonify(result.data)
    except Exception as e:
        print(f"[SEARCH RPC ERROR] {e} — using PostgREST fallback")
        try:
            return jsonify(search_files_fallback(query, user)), 200
        except Exception as e2:
            print(f"[SEARCH FALLBACK ERROR] {e2}")
            return jsonify({"error": "Search service unavailable"}), 500


def search_files_fallback(query, user):
    """PostgREST-based search used when the search_files RPC is unavailable
    (e.g. the DB function is stale/broken). Mirrors the RPC result shape."""
    q = query.strip().lower()

    matched_cat_ids = []
    try:
        cats = service_supabase.table("file_categories").select("id, name").execute().data
        for c in cats:
            if q in c["name"].lower():
                matched_cat_ids.append(c["id"])
    except Exception:
        cats = []
    try:
        kws = service_supabase.table("category_keywords").select("category_id, keyword").execute().data
        for k in kws:
            if (k.get("keyword") or "").lower() and q in k["keyword"].lower():
                matched_cat_ids.append(k["category_id"])
    except Exception:
        pass
    matched_cat_ids = list(dict.fromkeys(matched_cat_ids))

    or_clauses = [
        "name.ilike.%{}%".format(q),
        "type.ilike.%{}%".format(q),
        "description.ilike.%{}%".format(q),
    ]
    if matched_cat_ids:
        or_clauses.append("category_id.in.({})".format(",".join(matched_cat_ids)))

    query_builder = service_supabase.table("files").select(
        "id, name, type, size, description, category_id, uploaded_by, is_general, created_at"
    ).is_("deleted_at", "null").or_(",".join(or_clauses))
    if not is_admin(user):
        query_builder = query_builder.or_(f"uploaded_by.eq.{user.user.id},is_general.eq.true")
    rows = query_builder.order("created_at", desc=True).limit(100).execute().data

    cat_map = {c["id"]: c["name"] for c in cats}
    profs = service_supabase.table("profiles").select("id, full_name").execute().data
    prof_map = {p["id"]: p["full_name"] for p in profs}
    return [{
        "id": r["id"],
        "name": r["name"],
        "type": r["type"],
        "category_name": cat_map.get(r["category_id"]),
        "size": r["size"],
        "uploaded_by": r["uploaded_by"],
        "uploaded_by_name": prof_map.get(r["uploaded_by"]),
        "is_general": r.get("is_general", False),
        "created_at": r["created_at"],
    } for r in rows]

# ─── BACKUP ───────────────────────────────────────────────────


def perform_backup(backup_type, triggered_by):
    """Snapshot all active files into backup_logs. Used by the manual
    endpoint and the automated scheduler."""
    try:
        files = service_supabase.table("files").select(
            "id, name, type, category_id, size, storage_path, uploaded_by, description, checksum, is_duplicate, created_at"
        ).is_("deleted_at", "null").execute()
    except Exception as e:
        print(f"[BACKUP FETCH ERROR] {e}")
        return None

    if not files.data:
        return {"message": "No files to back up", "file_count": 0}

    total_size = sum(f["size"] for f in files.data)

    log_entry = service_supabase.table("backup_logs").insert({
        "type": backup_type,
        "status": "completed",
        "file_count": len(files.data),
        "size_bytes": total_size,
        "triggered_by": triggered_by,
        "completed_at": datetime.now(timezone.utc).isoformat(),
        "snapshot": files.data,
    }).execute()

    service_supabase.table("audit_logs").insert({
        "user_id": triggered_by,
        "action": "backup",
        "resource_type": "backup",
        "resource_id": log_entry.data[0]["id"],
        "details": {"type": backup_type, "file_count": len(files.data), "total_size": total_size},
    }).execute()

    return log_entry.data[0]


def scheduled_backup_job():
    """Runs the automated (scheduled) backup. Attributes the run to the
    first admin profile, or leaves triggered_by null if none exists."""
    triggered_by = None
    try:
        admins = service_supabase.table("profiles").select("id").eq("role", "admin").limit(1).execute()
        if admins.data:
            triggered_by = admins.data[0]["id"]
    except Exception as e:
        print(f"[SCHEDULED BACKUP ADMIN LOOKUP ERROR] {e}")

    result = perform_backup("scheduled", triggered_by)
    if result is None:
        print("[SCHEDULED BACKUP] Failed to run automated backup")
    else:
        print(f"[SCHEDULED BACKUP] Done — {result.get('file_count', 0)} file(s)")


@app.route("/api/backup/run", methods=["POST"])
def run_backup():
    user = get_current_user()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401
    if not is_admin(user):
        return jsonify({"error": "Admin access required"}), 403

    entry = perform_backup("manual", user.user.id)
    if entry is None:
        return jsonify({"error": "Backup failed"}), 500
    return jsonify(entry)


@app.route("/api/backup/logs/<log_id>", methods=["DELETE"])
def delete_backup_log(log_id):
    """Deletes a backup snapshot. Files themselves are not affected."""
    user = get_current_user()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401
    if not is_admin(user):
        return jsonify({"error": "Admin access required"}), 403

    try:
        existing = service_supabase.table("backup_logs").select("id").eq("id", log_id).maybe_single().execute()
        if not existing.data:
            return jsonify({"error": "Backup not found"}), 404
        service_supabase.table("backup_logs").delete().eq("id", log_id).execute()
    except Exception as e:
        print(f"[BACKUP DELETE ERROR] {e}")
        return jsonify({"error": "Could not delete backup"}), 500

    try:
        service_supabase.table("audit_logs").insert({
            "user_id": user.user.id,
            "action": "delete",
            "resource_type": "backup",
            "resource_id": log_id,
            "details": {"deleted_backup": True},
        }).execute()
    except Exception as e:
        print(f"[BACKUP DELETE AUDIT ERROR] {e}")

    return jsonify({"message": "Backup deleted"})


@app.route("/api/backup/schedule", methods=["GET"])
def backup_schedule():
    """Returns the configured automated backup schedule for the UI."""
    user = get_current_user()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401
    if not is_admin(user):
        return jsonify({"error": "Admin access required"}), 403

    return jsonify(get_schedule_settings())


@app.route("/api/backup/schedule", methods=["PUT"])
def update_backup_schedule():
    """Lets an admin change the automated backup schedule at runtime.

    mode: 'interval' (every interval_minutes), 'daily' (at hour:minute UTC),
          or 'disabled'. Persisted to system_settings and applied immediately.
    """
    user = get_current_user()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401
    if not is_admin(user):
        return jsonify({"error": "Admin access required"}), 403

    data = request.get_json() or {}
    mode = data.get("mode")
    if mode not in ("interval", "daily", "disabled"):
        return jsonify({"error": "mode must be 'interval', 'daily', or 'disabled'"}), 400

    settings = get_schedule_settings()
    settings["mode"] = mode

    if mode == "interval":
        try:
            minutes = int(data.get("interval_minutes", 30))
        except (TypeError, ValueError):
            minutes = 30
        settings["interval_minutes"] = max(1, min(1440, minutes))
    elif mode == "daily":
        try:
            hour = int(data.get("hour", settings.get("hour", 2)))
            minute = int(data.get("minute", settings.get("minute", 0)))
        except (TypeError, ValueError):
            hour, minute = 2, 0
        settings["hour"] = max(0, min(23, hour))
        settings["minute"] = max(0, min(59, minute))

    try:
        save_schedule_settings(settings)
        reschedule_jobs(settings)
    except Exception as e:
        print(f"[SCHEDULE SAVE ERROR] {e}")
        return jsonify({
            "error": f"Could not save schedule: {e}. "
            "Check that migration 008 (system_settings table) has been applied."
        }), 500

    return jsonify(settings)


@app.route("/api/backup/logs", methods=["GET"])
def backup_logs():
    user = get_current_user()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401
    if not is_admin(user):
        return jsonify({"error": "Admin access required"}), 403

    logs = service_supabase.table("backup_logs").select("*").order("started_at", desc=True).execute()
    return jsonify(logs.data)

# ─── RECOVERY ─────────────────────────────────────────────────


@app.route("/api/recovery/restore", methods=["POST"])
def restore_backup():
    user = get_current_user()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401
    if not is_admin(user):
        return jsonify({"error": "Admin access required"}), 403

    data = request.get_json()
    backup_log_id = data.get("backup_log_id")

    backup = service_supabase.table("backup_logs").select("*").eq("id", backup_log_id).maybe_single().execute()
    if not backup.data:
        return jsonify({"error": "Backup not found"}), 404

    if not backup.data.get("snapshot"):
        return jsonify({"error": "Backup has no snapshot data to restore"}), 400

    # Call the PostgreSQL restore function
    result = service_supabase.rpc("restore_from_backup", {"backup_id": backup_log_id}).execute()
    restore_result = result.data[0] if result.data else {}

    status = "completed" if not restore_result.get("errors") else "failed"

    recovery = service_supabase.table("recovery_logs").insert({
        "backup_log_id": backup_log_id,
        "status": status,
        "requested_by": user.user.id,
        "completed_at": datetime.now(timezone.utc).isoformat(),
    }).execute()

    service_supabase.table("audit_logs").insert({
        "user_id": user.user.id,
        "action": "recover",
        "resource_type": "recovery",
        "resource_id": recovery.data[0]["id"],
        "details": {
            "backup_log_id": backup_log_id,
            "files_restored": restore_result.get("files_restored", 0),
            "duplicates_skipped": restore_result.get("duplicates_skipped", 0),
        },
    }).execute()

    return jsonify({
        "recovery": recovery.data[0],
        "files_restored": restore_result.get("files_restored", 0),
        "duplicates_skipped": restore_result.get("duplicates_skipped", 0),
    })


@app.route("/api/recovery/logs", methods=["GET"])
def recovery_logs():
    user = get_current_user()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401
    if not is_admin(user):
        return jsonify({"error": "Admin access required"}), 403

    logs = service_supabase.table("recovery_logs").select(
        "*, backup_logs!inner(type, started_at, file_count), profiles!inner(full_name)"
    ).order("requested_at", desc=True).execute()
    return jsonify(logs.data)

# ─── DASHBOARD ────────────────────────────────────────────────


@app.route("/api/dashboard/stats", methods=["GET"])
def dashboard_stats():
    user = get_current_user()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401

    try:
        stats = service_supabase.rpc("get_dashboard_stats", {"requesting_user": user.user.id}).execute()
    except Exception as e:
        print(f"[DASHBOARD RPC ERROR] {e}")
        return jsonify({"error": "Statistics service unavailable"}), 500
    return jsonify(stats.data[0] if stats.data else {})

# ─── ADMIN PANEL ─────────────────────────────────────────────


@app.route("/api/admin/users", methods=["GET"])
def admin_users():
    user = get_current_user()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401
    if not is_admin(user):
        return jsonify({"error": "Admin access required"}), 403

    try:
        result = service_supabase.rpc("get_users_admin").execute()
    except Exception as e:
        print(f"[ADMIN USERS RPC ERROR] {e}")
        return jsonify({"error": "Users service unavailable"}), 500
    return jsonify(result.data)


@app.route("/api/admin/users/<user_id>/role", methods=["PATCH"])
def admin_update_role(user_id):
    user = get_current_user()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401
    if not is_admin(user):
        return jsonify({"error": "Admin access required"}), 403

    data = request.get_json()
    new_role = data.get("role")
    if new_role not in ("admin", "staff"):
        return jsonify({"error": "Invalid role"}), 400
    if user_id == user.user.id:
        return jsonify({"error": "You cannot change your own role"}), 400

    try:
        result = service_supabase.rpc("update_user_role", {
            "target_user": user_id,
            "new_role": new_role,
        }).execute()
    except Exception as e:
        print(f"[ADMIN ROLE RPC ERROR] {e}")
        return jsonify({"error": "Role update failed"}), 500
    if not result.data:
        return jsonify({"error": "User not found"}), 404
    return jsonify(result.data[0])


@app.route("/api/admin/users/<user_id>", methods=["DELETE"])
def admin_delete_user(user_id):
    user = get_current_user()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401
    if not is_admin(user):
        return jsonify({"error": "Admin access required"}), 403
    if user_id == user.user.id:
        return jsonify({"error": "You cannot delete your own account"}), 400

    try:
        items = service_supabase.storage.from_(Config.STORAGE_BUCKET).list(user_id)
        if items:
            paths = [f"{user_id}/{item['name']}" for item in items if item.get("name")]
            if paths:
                service_supabase.storage.from_(Config.STORAGE_BUCKET).remove(paths)
    except Exception as e:
        print(f"[ADMIN DELETE STORAGE] {e}")

    try:
        service_supabase.auth.admin.delete_user(user_id)
    except Exception as e:
        print(f"[ADMIN DELETE USER] {e}")
        return jsonify({"error": str(e)}), 400

    return jsonify({"message": "User deleted"})


@app.route("/api/admin/audit-logs", methods=["GET"])
def admin_audit_logs():
    user = get_current_user()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401
    if not is_admin(user):
        return jsonify({"error": "Admin access required"}), 403

    logs = service_supabase.table("audit_logs").select(
        "*, profiles(full_name)"
    ).order("created_at", desc=True).limit(200).execute()
    return jsonify(logs.data)


# ─── ENTRY POINT ──────────────────────────────────────────────

scheduler = BackgroundScheduler(timezone="UTC")

DEFAULT_SCHEDULE = {
    "mode": "disabled" if not Config.BACKUP_SCHEDULE_ENABLED else "daily",
    "interval_minutes": 30,
    "hour": Config.BACKUP_SCHEDULE_HOUR,
    "minute": Config.BACKUP_SCHEDULE_MINUTE,
    "timezone": "UTC",
}


def get_schedule_settings():
    """Return the saved backup schedule from system_settings, falling back
    to the environment configuration when nothing has been saved yet."""
    try:
        row = service_supabase.table("system_settings").select("value").eq(
            "key", "backup_schedule"
        ).maybe_single().execute()
        if row.data and isinstance(row.data.get("value"), dict):
            v = row.data["value"]
            mode = v.get("mode") if v.get("mode") in ("interval", "daily", "disabled") else "disabled"
            try:
                interval_minutes = int(v.get("interval_minutes", 30))
            except (TypeError, ValueError):
                interval_minutes = 30
            try:
                hour = int(v.get("hour", 2))
            except (TypeError, ValueError):
                hour = 2
            try:
                minute = int(v.get("minute", 0))
            except (TypeError, ValueError):
                minute = 0
            return {
                "mode": mode,
                "interval_minutes": max(1, min(1440, interval_minutes)),
                "hour": max(0, min(23, hour)),
                "minute": max(0, min(59, minute)),
                "timezone": "UTC",
            }
    except Exception as e:
        print(f"[SCHEDULE READ ERROR] {e}")
    return dict(DEFAULT_SCHEDULE)


def save_schedule_settings(settings):
    service_supabase.table("system_settings").upsert({
        "key": "backup_schedule",
        "value": settings,
    }).execute()


def reschedule_jobs(settings):
    """Hosted build: automated backups run inside Supabase (pg_cron), which
    re-reads system_settings every minute — nothing to reschedule here."""
    print("[SCHEDULER] Schedule handled by Supabase pg_cron (mode=%s)" % settings.get("mode"))


def start_scheduler():
    """Hosted build: make sure the Supabase pg_cron job exists. The web
    server can sleep (Render free tier) without stopping backups."""
    try:
        service_supabase.rpc("ensure_backup_cron").execute()
        print("[BACKUP] Supabase pg_cron job ensured")
    except Exception as e:
        print(f"[BACKUP] Could not ensure pg_cron job: {e}")
    return None


# ─── FRONTEND (serve the SPA from the backend) ────────────────

FRONTEND_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "frontend"))


@app.route("/")
def landing_page():
    return send_from_directory(FRONTEND_DIR, "landing.html")


@app.route("/app")
@app.route("/index.html")
def app_page():
    return send_from_directory(FRONTEND_DIR, "index.html")


@app.route("/<path:filename>")
def frontend_assets(filename):
    return send_from_directory(FRONTEND_DIR, filename)


if __name__ == "__main__":
    # With the reloader enabled, app.py runs twice; only start the
    # scheduler in the child (real server) process to avoid duplicate jobs.
    if not app.debug or os.environ.get("WERKZEUG_RUN_MAIN") == "true":
        start_scheduler()
    app.run(debug=True, port=5000)
