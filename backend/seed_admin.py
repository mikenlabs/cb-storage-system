"""
Seed the default CB Storage System administrator account.

Usage:
    python seed_admin.py

Creates (or promotes) an admin account:
    Email:    admin@silas.com
    Password: SilasAdmin#2026

Change the credentials below BEFORE running if you prefer different ones.
"""
from supabase_client import service_supabase

ADMIN_EMAIL = "admin@silas.com"
ADMIN_PASSWORD = "SilasAdmin#2026"
ADMIN_NAME = "System Administrator"


def main():
    # 1) Try to create the auth user (email confirmation auto-approved).
    try:
        result = service_supabase.auth.admin.create_user({
            "email": ADMIN_EMAIL,
            "password": ADMIN_PASSWORD,
            "email_confirm": True,
            "user_metadata": {"full_name": ADMIN_NAME, "role": "admin"},
        })
        user_id = result.user.id
        print(f"[OK] Created admin user {ADMIN_EMAIL} ({user_id})")
    except Exception as e:
        # User already exists -> fetch it instead.
        msg = str(e)
        if "already" in msg.lower() or "exists" in msg.lower():
            users = service_supabase.auth.admin.list_users()
            match = next((u for u in users if getattr(u, "email", None) == ADMIN_EMAIL), None)
            if not match:
                print(f"[FAIL] Admin user exists but could not be located: {e}")
                return
            user_id = match.id
            print(f"[OK] Admin user already registered ({ADMIN_EMAIL})")
        else:
            print(f"[FAIL] Could not create admin user: {e}")
            return

    # 2) Make sure the profile row has the admin role.
    profile = service_supabase.table("profiles").update(
        {"role": "admin", "full_name": ADMIN_NAME}
    ).eq("id", user_id).execute()

    if profile.data:
        print(f"[OK] Profile role set to 'admin' for {ADMIN_NAME}")
    else:
        print("[WARN] Profile row missing; sign in once as the admin to create it.")

    print("\n── Default administrator login ─────────────────────────────")
    print(f"  Email:    {ADMIN_EMAIL}")
    print(f"  Password: {ADMIN_PASSWORD}")
    print("  Change these in backend/seed_admin.py before first use.")
    print("─────────────────────────────────────────────────────────────")


if __name__ == "__main__":
    main()
