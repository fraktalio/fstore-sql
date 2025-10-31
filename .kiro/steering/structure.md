# Project Structure

## Root Directory Layout

```
fstore-sql/
├── .assets/                    # Visual documentation and diagrams
├── .git/                      # Git repository metadata
├── .kiro/                     # Kiro AI assistant configuration
├── .vscode/                   # VS Code workspace settings
├── docker-compose.yml         # PostgreSQL container configuration
├── schema.sql                 # Core event store database schema
├── extensions.sql             # Optional PostgreSQL extensions
├── README.md                  # Project documentation
├── LICENSE.md                 # Apache 2.0 license
└── .gitignore                # Git ignore patterns
```

## Key Files

### Database Schema Files
- **`schema.sql`**: Core event sourcing and streaming implementation
  - Event sourcing tables: `deciders`, `events`
  - Event streaming tables: `views`, `locks`
  - SQL API functions for all operations
  - Triggers and constraints for data integrity

- **`extensions.sql`**: Optional extensions for advanced features
  - pg_cron integration for scheduled event streaming
  - pg_net integration for HTTP endpoint publishing
  - Automatic cron job management via triggers

### Configuration Files
- **`docker-compose.yml`**: Local development environment
  - Uses Supabase PostgreSQL 15.1.0.82 image
  - Automatically imports schema.sql on startup
  - Exposes PostgreSQL on port 5432

### Documentation Assets
- **`.assets/`**: Contains architectural diagrams and visual documentation
  - CQRS pattern illustrations
  - Event sourcing flow diagrams
  - Component interaction visuals

## Database Schema Organization

### Event Sourcing Components
- `deciders` table: Registry of event types per decider
- `events` table: Immutable event log with optimistic locking
- Event sourcing API functions: `register_decider_event`, `append_event`, `get_events`

### Event Streaming Components  
- `views` table: Consumer registration and configuration
- `locks` table: Concurrent consumer coordination
- Event streaming API functions: `register_view`, `stream_events`, `ack_event`, `nack_event`

## Naming Conventions
- **Tables**: Lowercase with underscores (e.g., `decider_events`)
- **Functions**: Lowercase with underscores (e.g., `append_event`)
- **Columns**: Lowercase with underscores (e.g., `decider_id`)
- **Constraints**: Descriptive names with table prefix

## File Organization Principles
- Core functionality in `schema.sql` (required)
- Optional features in `extensions.sql` (manual import)
- Documentation assets in dedicated `.assets/` folder
- Single docker-compose.yml for complete local setup