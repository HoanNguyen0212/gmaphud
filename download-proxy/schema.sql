CREATE TABLE IF NOT EXISTS download_counts (
  day TEXT NOT NULL,
  version TEXT NOT NULL,
  architecture TEXT NOT NULL,
  requests INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, version, architecture)
) WITHOUT ROWID;
