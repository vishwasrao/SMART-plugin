return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "smart_apps" (
        "app_name"        TEXT                         NOT NULL,
        "issuer"         TEXT                         NOT NULL,
        "app_launch_url"   TEXT,
        "app_redirect_url" TEXT,
        "scope"          TEXT,
        "client_id"       TEXT,
        "client_secret"   TEXT,
        "created_at"     TIMESTAMP                    DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "updated_at"     TIMESTAMP                    DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        CONSTRAINT unique_appName_issuer UNIQUE ("app_name", "issuer")
      );

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "smart_apps_app_name_idx" ON "smart_apps" ("app_name");
        CREATE INDEX IF NOT EXISTS "smart_apps_issuer_idx" ON "smart_apps" ("issuer");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      CREATE TABLE IF NOT EXISTS "smart_launches" (
        "session_id"        TEXT                         PRIMARY KEY,
        "client_id"         TEXT                         NOT NULL,
        "client_secret"     TEXT,
        "app_name"          TEXT                         NOT NULL,
        "app_launch_url"    TEXT,
        "app_redirect_url" TEXT,
        "token_endpoint_url" TEXT,
        "fhir_server_url"   TEXT                         NOT NULL,
        "authorization_code" TEXT,
        "access_token"      TEXT,
        "expires_in"        INTEGER,
        "refresh_token"     TEXT,
        "id_token"          TEXT,
        "token_type"        TEXT,
        "scope"             TEXT,
        "patient"           TEXT,
        "encounter"         TEXT,
        "user_type"         TEXT,
        "user_id"           TEXT,
        "appContext"        TEXT,
        "created_at"        TIMESTAMP                    DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "updated_at"        TIMESTAMP                    DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC')
      );

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "smart_launches_session_id_idx" ON "smart_launches" ("session_id");
        CREATE INDEX IF NOT EXISTS "smart_launches_client_id_idx" ON "smart_launches" ("client_id");
         CREATE INDEX IF NOT EXISTS "smart_launches_fhir_server_url_idx" ON "smart_launches" ("fhir_server_url");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;
    ]],
  },
}
