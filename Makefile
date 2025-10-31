# fstore-sql Makefile

.PHONY: help start stop test test-verbose test-event-sourcing clean logs

# Database connection
DB_HOST := localhost
DB_PORT := 5432
DB_USER := postgres
DB_NAME := postgres
export PGPASSWORD := mysecretpassword

help: ## Show this help message
	@echo "Available commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

start: ## Start the PostgreSQL database
	docker compose up -d
	@echo "Waiting for database to be ready..."
	@for i in $$(seq 1 30); do \
		if psql -h $(DB_HOST) -p $(DB_PORT) -U $(DB_USER) -d $(DB_NAME) -c "SELECT 1;" > /dev/null 2>&1; then \
			echo "Database is ready!"; \
			break; \
		fi; \
		sleep 1; \
	done

stop: ## Stop the PostgreSQL database
	docker compose down

logs: ## Show database logs
	docker compose logs -f db

test: start ## Run all tests
	./run-tests.sh

test-verbose: start ## Run all tests with verbose output
	./run-tests.sh --verbose

test-event-sourcing: start ## Run only event sourcing tests
	./run-tests.sh tests/unit/event-sourcing/

test-event-streaming: start ## Run only event streaming tests
	./run-tests.sh tests/unit/event-streaming/

test-register: start ## Run register_decider_event tests
	psql -h $(DB_HOST) -p $(DB_PORT) -U $(DB_USER) -d $(DB_NAME) -f tests/unit/event-sourcing/test_register_decider_event.sql

test-append: start ## Run append_event tests
	psql -h $(DB_HOST) -p $(DB_PORT) -U $(DB_USER) -d $(DB_NAME) -f tests/unit/event-sourcing/test_append_event.sql

test-get: start ## Run get_events tests
	psql -h $(DB_HOST) -p $(DB_PORT) -U $(DB_USER) -d $(DB_NAME) -f tests/unit/event-sourcing/test_get_events.sql

test-register-view: start ## Run register_view tests
	psql -h $(DB_HOST) -p $(DB_PORT) -U $(DB_USER) -d $(DB_NAME) -f tests/unit/event-streaming/test_register_view.sql

test-stream-events: start ## Run stream_events tests
	psql -h $(DB_HOST) -p $(DB_PORT) -U $(DB_USER) -d $(DB_NAME) -f tests/unit/event-streaming/test_stream_events.sql

test-acknowledgment: start ## Run acknowledgment functions tests
	psql -h $(DB_HOST) -p $(DB_PORT) -U $(DB_USER) -d $(DB_NAME) -f tests/unit/event-streaming/test_acknowledgment_functions.sql

clean: ## Clean up database and containers
	docker compose down -v
	docker system prune -f

psql: start ## Connect to database with psql
	psql -h $(DB_HOST) -p $(DB_PORT) -U $(DB_USER) -d $(DB_NAME)

schema: start ## Reload schema
	psql -h $(DB_HOST) -p $(DB_PORT) -U $(DB_USER) -d $(DB_NAME) -f schema.sql