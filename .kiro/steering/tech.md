# Technology Stack

## Core Technology
- **Database**: PostgreSQL (specifically Supabase PostgreSQL 15.1.0.82)
- **Language**: Pure SQL (PostgreSQL dialect)
- **Extensions**: pg_cron, pg_net

## Required Extensions
- `pg_cron`: Enables scheduled jobs for automatic event streaming
- `pg_net`: Provides HTTP client functionality for edge function integration

## Development Environment

### Docker Setup
The project uses Docker Compose for local development:

```bash
# Start PostgreSQL with required extensions
docker compose up -d
```

### Database Initialization
- `schema.sql`: Core event store schema (automatically imported)
- `extensions.sql`: Optional extensions for edge function integration (manual import required)

## Common Commands

### Database Management
```bash
# Start database
docker compose up -d

# Stop database  
docker compose down

# View logs
docker logs <container_name>

# Connect to database
psql -h localhost -p 5432 -U postgres -d postgres
```

### Schema Management
```sql
-- Import core schema (done automatically)
\i schema.sql

-- Import extensions (manual step)
\i extensions.sql
```

## Alternative Database Options
- **YugabyteDB**: Fully compatible PostgreSQL alternative for distributed deployments
- **Vanilla PostgreSQL**: Works without pg_cron/pg_net if edge function integration not needed

## Integration Patterns
- **Edge Functions**: Supabase Functions, Deno Deploy
- **HTTP Endpoints**: Any REST API endpoint for event consumption
- **Client Applications**: Any language with PostgreSQL driver support

## Performance Considerations
- Uses PostgreSQL sequences and indexes for optimal event ordering
- Implements row-level locking for concurrent consumer safety
- Supports horizontal scaling via YugabyteDB for high-throughput scenarios