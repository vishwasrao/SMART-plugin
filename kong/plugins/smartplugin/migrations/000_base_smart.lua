return {
    postgres = {
      up = [[
        CREATE TABLE IF NOT EXISTS "smart_apps" (
          "appName"        TEXT                         NOT NULL,
          "issuer"         TEXT                         NOT NULL,
          "appLaunchUrl"   TEXT,
          "appRedirectUrl" TEXT,
          "scope"          TEXT,
          "clientId"       TEXT,
          "clientSecret"   TEXT,
          "clinicalData"   TEXT,
          "created_at"     TIMESTAMP                    DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
          "updated_at"     TIMESTAMP                    DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
          CONSTRAINT unique_appName_issuer UNIQUE ("appName", "issuer")
        );


        DO $$
        BEGIN
          CREATE INDEX IF NOT EXISTS "smart_apps_appName_idx" ON "smart_apps" ("appName");
          CREATE INDEX IF NOT EXISTS "smart_apps_issuer_idx" ON "smart_apps" ("issuer");
        EXCEPTION WHEN UNDEFINED_COLUMN THEN
          -- Do nothing, accept existing state
        END$$;
      ]],
    },
  }

