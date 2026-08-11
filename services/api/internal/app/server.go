package app

import (
	"context"
	"database/sql"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	_ "github.com/lib/pq"

	"github.com/kakao-ent/dayflow/services/api/internal/httpapi"
	"github.com/kakao-ent/dayflow/services/api/internal/store"
)

const (
	StoreModeMemory   = "memory"
	StoreModeHybrid   = "hybrid"
	StoreModePostgres = "postgres"

	SeedModeNone = "none"
	SeedModeDemo = "demo"
	SeedModeTest = "test"
)

type Config struct {
	Addr          string
	StoreMode     string
	SeedMode      string
	DatabaseURL   string
	AutoMigrate   bool
	MigrationsDir string
}

func ConfigFromEnv() Config {
	return Config{
		Addr:          envOrDefault("DAYFLOW_ADDR", ":8080"),
		StoreMode:     strings.ToLower(envOrDefault("DAYFLOW_STORE_MODE", StoreModeMemory)),
		SeedMode:      strings.ToLower(envOrDefault("DAYFLOW_SEED_MODE", SeedModeNone)),
		DatabaseURL:   os.Getenv("DAYFLOW_DATABASE_URL"),
		AutoMigrate:   envOrDefault("DAYFLOW_AUTO_MIGRATE", "false") == "true",
		MigrationsDir: envOrDefault("DAYFLOW_MIGRATIONS_DIR", "./migrations"),
	}
}

func NewServer() *http.Server {
	server, err := NewServerFromConfig(ConfigFromEnv())
	if err != nil {
		panic(err)
	}
	return server
}

func NewServerFromEnv() (*http.Server, error) {
	return NewServerFromConfig(ConfigFromEnv())
}

func NewServerFromConfig(cfg Config) (*http.Server, error) {
	repository, cleanup, err := newRepository(cfg)
	if err != nil {
		return nil, err
	}

	server := &http.Server{
		Addr:              cfg.Addr,
		Handler:           httpapi.NewRouter(repository),
		ReadHeaderTimeout: 5 * time.Second,
	}
	if cleanup != nil {
		server.RegisterOnShutdown(func() {
			_ = cleanup()
		})
	}
	return server, nil
}

func newRepository(cfg Config) (store.Repository, func() error, error) {
	mode := cfg.StoreMode
	if mode == "" {
		mode = StoreModeMemory
	}

	memory := store.NewMemoryStore()
	if mode == StoreModeMemory {
		return memory, nil, nil
	}
	if mode != StoreModeHybrid && mode != StoreModePostgres {
		return nil, nil, fmt.Errorf("unsupported DAYFLOW_STORE_MODE %q", cfg.StoreMode)
	}
	if cfg.DatabaseURL == "" {
		return nil, nil, fmt.Errorf("DAYFLOW_DATABASE_URL is required for %s mode", mode)
	}

	db, err := sql.Open("postgres", cfg.DatabaseURL)
	if err != nil {
		return nil, nil, fmt.Errorf("open postgres: %w", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := db.PingContext(ctx); err != nil {
		_ = db.Close()
		return nil, nil, fmt.Errorf("ping postgres: %w", err)
	}
	if cfg.AutoMigrate {
		if err := applyMigrations(ctx, db, cfg.MigrationsDir); err != nil {
			_ = db.Close()
			return nil, nil, err
		}
	}
	postgresStore := store.NewPostgresStore(db)
	if mode == StoreModePostgres && (cfg.SeedMode == SeedModeDemo || cfg.SeedMode == SeedModeTest) {
		if err := postgresStore.EnsureDemoSeed(ctx); err != nil {
			_ = db.Close()
			return nil, nil, fmt.Errorf("seed postgres runtime fixtures: %w", err)
		}
	}
	topology, err := topologyFromEnv()
	if err != nil {
		_ = db.Close()
		return nil, nil, fmt.Errorf("deployment readiness: %w", err)
	}
	if err := applyTwoPersonTopology(ctx, db, topology); err != nil {
		_ = db.Close()
		return nil, nil, fmt.Errorf("deployment readiness: %w", err)
	}

	if mode == StoreModeHybrid {
		hybrid := store.NewHybridStore(memory, store.NewPostgresBudgetStore(db))
		if err := hybrid.EnsureBudgetUsers(ctx); err != nil {
			_ = db.Close()
			return nil, nil, fmt.Errorf("seed hybrid budget users: %w", err)
		}
		return hybrid, db.Close, nil
	}

	switch cfg.SeedMode {
	case "", SeedModeNone:
	case SeedModeDemo, SeedModeTest:
	default:
		_ = db.Close()
		return nil, nil, fmt.Errorf("unsupported DAYFLOW_SEED_MODE %q", cfg.SeedMode)
	}
	return postgresStore, db.Close, nil
}

func applyMigrations(ctx context.Context, db *sql.DB, dir string) error {
	if _, err := db.ExecContext(ctx, `
CREATE TABLE IF NOT EXISTS schema_migrations (
    name TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
)`); err != nil {
		return fmt.Errorf("ensure schema_migrations: %w", err)
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		return fmt.Errorf("read migrations dir: %w", err)
	}

	migrationFiles := make([]string, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() || filepath.Ext(entry.Name()) != ".sql" {
			continue
		}
		migrationFiles = append(migrationFiles, filepath.Join(dir, entry.Name()))
	}
	sort.Strings(migrationFiles)

	applied := make(map[string]struct{}, len(migrationFiles))
	rows, err := db.QueryContext(ctx, `SELECT name FROM schema_migrations`)
	if err != nil {
		return fmt.Errorf("load schema_migrations: %w", err)
	}
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			rows.Close()
			return fmt.Errorf("scan schema_migrations: %w", err)
		}
		applied[name] = struct{}{}
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return fmt.Errorf("iterate schema_migrations: %w", err)
	}
	rows.Close()

	for _, migrationFile := range migrationFiles {
		name := filepath.Base(migrationFile)
		if _, ok := applied[name]; ok {
			continue
		}

		contents, err := os.ReadFile(migrationFile)
		if err != nil {
			return fmt.Errorf("read migration %s: %w", migrationFile, err)
		}

		tx, err := db.BeginTx(ctx, nil)
		if err != nil {
			return fmt.Errorf("begin migration %s: %w", name, err)
		}
		statements := strings.Split(string(contents), ";")
		for _, statement := range statements {
			sqlStatement := strings.TrimSpace(statement)
			if sqlStatement == "" {
				continue
			}
			if _, err := tx.ExecContext(ctx, sqlStatement); err != nil {
				_ = tx.Rollback()
				return fmt.Errorf("apply migration %s: %w", name, err)
			}
		}
		if _, err := tx.ExecContext(ctx, `INSERT INTO schema_migrations (name) VALUES ($1)`, name); err != nil {
			_ = tx.Rollback()
			return fmt.Errorf("record migration %s: %w", name, err)
		}
		if err := tx.Commit(); err != nil {
			return fmt.Errorf("commit migration %s: %w", name, err)
		}
	}

	return nil
}

func envOrDefault(name, fallback string) string {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return fallback
	}
	return value
}
