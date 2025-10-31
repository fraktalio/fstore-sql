#!/bin/bash

# SQL Test Runner for fstore-sql
# Comprehensive test automation with Docker container management
# Usage: ./run-tests.sh [options]

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_CONTAINER_NAME="fstore-sql-test-db"
TEST_DB_PORT="5433"  # Use different port to avoid conflicts
DB_HOST="localhost"
DB_USER="postgres"
DB_NAME="postgres"
DB_PASSWORD="test_password_$(date +%s)"  # Unique password per run
export PGPASSWORD="$DB_PASSWORD"

# Test configuration
TEST_TIMEOUT=300  # 5 minutes timeout for individual tests
CONTAINER_STARTUP_TIMEOUT=60  # 1 minute for container startup
HEALTH_CHECK_INTERVAL=2  # Check every 2 seconds

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Global variables for tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0
START_TIME=""
TEST_RESULTS=()
KEEP_DB=false
VERBOSE=false
REPORT_FORMAT="text"
TEST_CATEGORY="all"

# Function to print colored output
print_status() {
    local message="$1"
    local color="${2:-$NC}"
    echo -e "${color}${message}${NC}"
}

# Function to log with timestamp
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    case "$level" in
        "INFO")  print_status "[$timestamp] INFO: $message" "$BLUE" ;;
        "WARN")  print_status "[$timestamp] WARN: $message" "$YELLOW" ;;
        "ERROR") print_status "[$timestamp] ERROR: $message" "$RED" ;;
        "SUCCESS") print_status "[$timestamp] SUCCESS: $message" "$GREEN" ;;
        "DEBUG") [[ "$VERBOSE" == "true" ]] && print_status "[$timestamp] DEBUG: $message" "$CYAN" || true ;;
    esac
}

# Docker container management functions

# Function to check if Docker is available
check_docker() {
    if ! command -v docker &> /dev/null; then
        log "ERROR" "Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        log "ERROR" "Docker daemon is not running"
        exit 1
    fi
    
    log "INFO" "Docker is available and running"
}

# Function to cleanup existing test containers
cleanup_test_containers() {
    log "DEBUG" "Cleaning up existing test containers"
    
    # Stop and remove any existing test containers
    if docker ps -a --format "table {{.Names}}" | grep -q "^${TEST_CONTAINER_NAME}$"; then
        log "INFO" "Stopping existing test container: $TEST_CONTAINER_NAME"
        docker stop "$TEST_CONTAINER_NAME" &> /dev/null || true
        docker rm "$TEST_CONTAINER_NAME" &> /dev/null || true
    fi
    
    # Clean up any containers using our test port
    local containers_on_port=$(docker ps --format "table {{.Names}}\t{{.Ports}}" | grep ":${TEST_DB_PORT}->" | awk '{print $1}' || true)
    if [[ -n "$containers_on_port" ]]; then
        log "WARN" "Found containers using port $TEST_DB_PORT, stopping them"
        echo "$containers_on_port" | xargs -r docker stop &> /dev/null || true
        echo "$containers_on_port" | xargs -r docker rm &> /dev/null || true
    fi
}

# Function to start PostgreSQL test container
start_test_database() {
    log "INFO" "Starting PostgreSQL test container"
    
    # Create a temporary directory for schema mounting
    local temp_schema_dir=$(mktemp -d)
    cp "$SCRIPT_DIR/schema.sql" "$temp_schema_dir/"
    
    # Start PostgreSQL container with test configuration
    docker run -d \
        --name "$TEST_CONTAINER_NAME" \
        -p "${TEST_DB_PORT}:5432" \
        -e POSTGRES_PASSWORD="$DB_PASSWORD" \
        -e POSTGRES_DB="$DB_NAME" \
        -e POSTGRES_USER="$DB_USER" \
        -v "$temp_schema_dir/schema.sql:/docker-entrypoint-initdb.d/schema.sql:ro" \
        --health-cmd="pg_isready -U $DB_USER -d $DB_NAME" \
        --health-interval=5s \
        --health-timeout=3s \
        --health-retries=5 \
        supabase/postgres:15.1.0.82 \
        postgres -c log_statement=all -c log_min_duration_statement=0 &> /dev/null
    
    if [[ $? -ne 0 ]]; then
        log "ERROR" "Failed to start PostgreSQL test container"
        cleanup_test_containers
        exit 1
    fi
    
    log "SUCCESS" "Test container started: $TEST_CONTAINER_NAME"
    
    # Store temp directory for cleanup
    echo "$temp_schema_dir" > "/tmp/${TEST_CONTAINER_NAME}_temp_dir"
}

# Function to wait for database to be ready with health checks
wait_for_database_ready() {
    log "INFO" "Waiting for database to be ready (timeout: ${CONTAINER_STARTUP_TIMEOUT}s)"
    
    local elapsed=0
    while [[ $elapsed -lt $CONTAINER_STARTUP_TIMEOUT ]]; do
        # Check container health status
        local health_status=$(docker inspect --format='{{.State.Health.Status}}' "$TEST_CONTAINER_NAME" 2>/dev/null || echo "unknown")
        
        if [[ "$health_status" == "healthy" ]]; then
            log "SUCCESS" "Database container is healthy"
            break
        elif [[ "$health_status" == "unhealthy" ]]; then
            log "ERROR" "Database container is unhealthy"
            show_container_logs
            cleanup_test_containers
            exit 1
        fi
        
        # Also test direct connection
        if psql -h "$DB_HOST" -p "$TEST_DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" &> /dev/null; then
            log "SUCCESS" "Database is ready and accepting connections"
            return 0
        fi
        
        sleep $HEALTH_CHECK_INTERVAL
        elapsed=$((elapsed + HEALTH_CHECK_INTERVAL))
        
        if [[ $((elapsed % 10)) -eq 0 ]]; then
            log "DEBUG" "Still waiting for database... (${elapsed}s elapsed)"
        fi
    done
    
    if [[ $elapsed -ge $CONTAINER_STARTUP_TIMEOUT ]]; then
        log "ERROR" "Database failed to start within ${CONTAINER_STARTUP_TIMEOUT} seconds"
        show_container_logs
        cleanup_test_containers
        exit 1
    fi
}

# Function to load test framework utilities into the database
load_test_framework() {
    log "INFO" "Loading test framework utilities"
    
    # Load test helpers and assertions
    local helper_files=("$SCRIPT_DIR/tests/utils/test-helpers.sql" "$SCRIPT_DIR/tests/utils/assertions.sql")
    
    for helper_file in "${helper_files[@]}"; do
        if [[ ! -f "$helper_file" ]]; then
            log "ERROR" "Test helper file not found: $helper_file"
            return 1
        fi
        
        log "DEBUG" "Loading: $(basename "$helper_file")"
        if ! psql -h "$DB_HOST" -p "$TEST_DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$helper_file" &> /dev/null; then
            log "ERROR" "Failed to load test helper: $helper_file"
            return 1
        fi
    done
    
    log "SUCCESS" "Test framework utilities loaded successfully"
    return 0
}

# Function to show container logs for debugging
show_container_logs() {
    log "INFO" "Container logs for debugging:"
    docker logs "$TEST_CONTAINER_NAME" 2>&1 | tail -20 | while read -r line; do
        log "DEBUG" "Container: $line"
    done
}

# Function to stop test database
stop_test_database() {
    if [[ "$KEEP_DB" == "true" ]]; then
        log "INFO" "Keeping test database running (--keep-db flag set)"
        log "INFO" "Connect with: psql -h $DB_HOST -p $TEST_DB_PORT -U $DB_USER -d $DB_NAME"
        return 0
    fi
    
    log "INFO" "Stopping test database"
    
    if docker ps --format "table {{.Names}}" | grep -q "^${TEST_CONTAINER_NAME}$"; then
        docker stop "$TEST_CONTAINER_NAME" &> /dev/null || true
        docker rm "$TEST_CONTAINER_NAME" &> /dev/null || true
        log "SUCCESS" "Test container stopped and removed"
    fi
    
    # Clean up temporary schema directory
    local temp_dir_file="/tmp/${TEST_CONTAINER_NAME}_temp_dir"
    if [[ -f "$temp_dir_file" ]]; then
        local temp_dir=$(cat "$temp_dir_file")
        rm -rf "$temp_dir" 2>/dev/null || true
        rm -f "$temp_dir_file" 2>/dev/null || true
    fi
}

# Function to reset database state between test categories
reset_database_state() {
    log "INFO" "Resetting database state"
    
    # Drop and recreate all test data
    psql -h "$DB_HOST" -p "$TEST_DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
        -- Clean up test data (comprehensive patterns)
        DELETE FROM locks WHERE view LIKE 'test_%' OR view LIKE '%test%' OR view LIKE 'ack_%' OR view LIKE 'stream_%';
        DELETE FROM views WHERE view LIKE 'test_%' OR view LIKE '%test%' OR view LIKE 'ack_%' OR view LIKE 'stream_%';
        DELETE FROM events WHERE decider_id LIKE 'test_%' OR decider_id LIKE '%test%' OR decider_id LIKE 'ack-%' OR decider_id LIKE 'decider-%';
        DELETE FROM deciders WHERE decider LIKE 'test_%' OR decider LIKE '%test%' OR decider LIKE 'ack_%' OR decider LIKE 'stream_%' OR decider LIKE 'final_%' OR decider LIKE 'non_%' OR decider LIKE 'first_%' OR decider LIKE 'nonexistent_%';
        
        -- Reset sequences if they exist
        DO \$\$
        BEGIN
            IF EXISTS (SELECT 1 FROM pg_sequences WHERE sequencename = 'events_id_seq') THEN
                PERFORM setval('events_id_seq', 1, false);
            END IF;
        END
        \$\$;
    " &> /dev/null
    
    if [[ $? -eq 0 ]]; then
        log "SUCCESS" "Database state reset successfully"
    else
        log "WARN" "Database state reset had some issues, but continuing"
    fi
}

# Test discovery and execution functions

# Function to discover test files based on category
discover_test_files() {
    local category="$1"
    local test_files=()
    
    log "DEBUG" "Discovering test files for category: $category"
    
    case "$category" in
        "unit")
            test_files=($(find "$SCRIPT_DIR/tests/unit" -name "*.sql" -type f | sort))
            ;;
        "integration")
            test_files=($(find "$SCRIPT_DIR/tests/integration" -name "*.sql" -type f | sort))
            ;;
        "performance")
            test_files=($(find "$SCRIPT_DIR/tests/performance" -name "*.sql" -type f | sort))
            ;;
        "event-sourcing")
            test_files=($(find "$SCRIPT_DIR/tests/unit/event-sourcing" -name "*.sql" -type f | sort))
            ;;
        "event-streaming")
            test_files=($(find "$SCRIPT_DIR/tests/unit/event-streaming" -name "*.sql" -type f | sort))
            ;;
        "constraints")
            test_files=($(find "$SCRIPT_DIR/tests/unit/constraints" -name "*.sql" -type f | sort))
            ;;
        "all")
            test_files=($(find "$SCRIPT_DIR/tests" -name "*.sql" -type f -not -path "*/setup/*" -not -path "*/utils/*" | sort))
            ;;
        *)
            # Check if it's a specific file or directory
            if [[ -f "$category" ]]; then
                test_files=("$category")
            elif [[ -d "$category" ]]; then
                test_files=($(find "$category" -name "*.sql" -type f | sort))
            else
                log "ERROR" "Unknown test category or invalid path: $category"
                exit 1
            fi
            ;;
    esac
    
    log "INFO" "Found ${#test_files[@]} test files for category '$category'"
    
    if [[ ${#test_files[@]} -eq 0 ]]; then
        log "WARN" "No test files found for category '$category'"
        return 1
    fi
    
    # Return test files via global variable (bash array limitation workaround)
    printf '%s\n' "${test_files[@]}"
}

# Function to execute a single test file with timeout and error handling
execute_test_file() {
    local test_file="$1"
    local test_name=$(basename "$test_file" .sql)
    local test_start_time=$(date +%s.%N)
    local test_output=""
    local test_error=""
    local exit_code=0
    
    log "INFO" "Executing test: $test_name"
    
    # Create temporary files for capturing output
    local temp_output=$(mktemp)
    local temp_error=$(mktemp)
    
    # Execute test with timeout (use gtimeout on macOS if available, otherwise run without timeout)
    local timeout_cmd=""
    if command -v timeout &> /dev/null; then
        timeout_cmd="timeout $TEST_TIMEOUT"
    elif command -v gtimeout &> /dev/null; then
        timeout_cmd="gtimeout $TEST_TIMEOUT"
    else
        log "DEBUG" "No timeout command available, running test without timeout"
        timeout_cmd=""
    fi
    
    if [[ -n "$timeout_cmd" ]]; then
        eval "$timeout_cmd psql -h '$DB_HOST' -p '$TEST_DB_PORT' -U '$DB_USER' -d '$DB_NAME' -v ON_ERROR_STOP=1 -f '$test_file'" > "$temp_output" 2> "$temp_error"
    else
        psql -h "$DB_HOST" -p "$TEST_DB_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$test_file" > "$temp_output" 2> "$temp_error"
    fi
    
    if [[ $? -eq 0 ]]; then
        exit_code=0
        test_output=$(cat "$temp_output")
        log "SUCCESS" "Test passed: $test_name"
    else
        exit_code=$?
        test_output=$(cat "$temp_output")
        test_error=$(cat "$temp_error")
        
        if [[ $exit_code -eq 124 ]]; then
            log "ERROR" "Test timed out after ${TEST_TIMEOUT}s: $test_name"
            test_error="Test execution timed out after ${TEST_TIMEOUT} seconds"
        else
            log "ERROR" "Test failed: $test_name"
        fi
    fi
    
    # Calculate execution time
    local test_end_time=$(date +%s.%N)
    local execution_time
    if command -v bc &> /dev/null; then
        execution_time=$(echo "$test_end_time - $test_start_time" | bc -l 2>/dev/null || echo "0")
    else
        # Fallback to basic arithmetic (less precise)
        local start_int=${test_start_time%.*}
        local end_int=${test_end_time%.*}
        execution_time=$((end_int - start_int))
    fi
    
    # Store test result
    local result_entry="$test_name|$exit_code|$execution_time|$test_error"
    TEST_RESULTS+=("$result_entry")
    
    # Update counters
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [[ $exit_code -eq 0 ]]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    
    # Show output if verbose or if test failed
    if [[ "$VERBOSE" == "true" ]] || [[ $exit_code -ne 0 ]]; then
        if [[ -n "$test_output" ]]; then
            echo "--- Test Output ---"
            echo "$test_output"
        fi
        if [[ -n "$test_error" ]]; then
            echo "--- Test Errors ---"
            echo "$test_error"
        fi
        echo "--- End Test Output ---"
    fi
    
    # Cleanup temporary files
    rm -f "$temp_output" "$temp_error"
    
    return $exit_code
}

# Function to run tests with proper isolation
run_test_category() {
    local category="$1"
    local test_files_output
    
    log "INFO" "Running test category: $category"
    
    # Discover test files
    if ! test_files_output=$(discover_test_files "$category"); then
        return 1
    fi
    
    # Convert output to array
    local test_files=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && test_files+=("$line")
    done <<< "$test_files_output"
    
    if [[ ${#test_files[@]} -eq 0 ]]; then
        log "WARN" "No test files found for category: $category"
        return 0
    fi
    
    # Reset database state before running tests
    reset_database_state
    
    # Execute each test file
    local category_failed=0
    for test_file in "${test_files[@]}"; do
        if [[ ! -f "$test_file" ]]; then
            log "WARN" "Test file not found: $test_file"
            continue
        fi
        
        # Reset database state before each test file
        reset_database_state
        
        if ! execute_test_file "$test_file"; then
            category_failed=$((category_failed + 1))
        fi
        
        # Small delay between tests to avoid connection issues
        sleep 0.1
    done
    
    log "INFO" "Completed test category '$category': ${#test_files[@]} tests, $category_failed failed"
    
    return $category_failed
}

# Function to validate test environment
validate_test_environment() {
    log "INFO" "Validating test environment"
    
    # Check if required directories exist
    local required_dirs=("$SCRIPT_DIR/tests" "$SCRIPT_DIR/tests/unit" "$SCRIPT_DIR/tests/utils")
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log "ERROR" "Required directory not found: $dir"
            exit 1
        fi
    done
    
    # Check if schema file exists
    if [[ ! -f "$SCRIPT_DIR/schema.sql" ]]; then
        log "ERROR" "Schema file not found: $SCRIPT_DIR/schema.sql"
        exit 1
    fi
    
    # Check if test helper files exist
    local helper_files=("$SCRIPT_DIR/tests/utils/test-helpers.sql" "$SCRIPT_DIR/tests/utils/assertions.sql")
    for file in "${helper_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log "WARN" "Test helper file not found: $file"
        fi
    done
    
    log "SUCCESS" "Test environment validation completed"
}

# Result reporting and logging functions

# Function to generate text report
generate_text_report() {
    local total_time="$1"
    
    echo
    print_status "═══════════════════════════════════════════════════════════════" "$CYAN"
    print_status "                        TEST RESULTS SUMMARY                        " "$CYAN"
    print_status "═══════════════════════════════════════════════════════════════" "$CYAN"
    echo
    
    print_status "Execution Summary:" "$BLUE"
    print_status "  Total Tests:    $TOTAL_TESTS" "$NC"
    print_status "  Passed:         $PASSED_TESTS" "$GREEN"
    print_status "  Failed:         $FAILED_TESTS" "$RED"
    print_status "  Skipped:        $SKIPPED_TESTS" "$YELLOW"
    print_status "  Success Rate:   $(( TOTAL_TESTS > 0 ? (PASSED_TESTS * 100) / TOTAL_TESTS : 0 ))%" "$NC"
    print_status "  Total Time:     ${total_time}s" "$NC"
    echo
    
    if [[ $FAILED_TESTS -gt 0 ]]; then
        print_status "Failed Tests:" "$RED"
        for result in "${TEST_RESULTS[@]}"; do
            IFS='|' read -r test_name exit_code exec_time error_msg <<< "$result"
            if [[ $exit_code -ne 0 ]]; then
                print_status "  ✗ $test_name (${exec_time}s)" "$RED"
                if [[ -n "$error_msg" ]]; then
                    echo "    Error: $error_msg" | fold -w 70 -s | sed 's/^/    /'
                fi
            fi
        done
        echo
    fi
    
    if [[ $PASSED_TESTS -gt 0 ]] && [[ "$VERBOSE" == "true" ]]; then
        print_status "Passed Tests:" "$GREEN"
        for result in "${TEST_RESULTS[@]}"; do
            IFS='|' read -r test_name exit_code exec_time error_msg <<< "$result"
            if [[ $exit_code -eq 0 ]]; then
                print_status "  ✓ $test_name (${exec_time}s)" "$GREEN"
            fi
        done
        echo
    fi
    
    # Performance summary
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        print_status "Performance Summary:" "$BLUE"
        local avg_time
        if command -v bc &> /dev/null; then
            avg_time=$(echo "scale=3; $total_time / $TOTAL_TESTS" | bc -l 2>/dev/null || echo "0")
        else
            avg_time=$(( total_time / TOTAL_TESTS ))
        fi
        print_status "  Average Test Time: ${avg_time}s" "$NC"
        
        # Find slowest test
        local slowest_test=""
        local slowest_time=0
        for result in "${TEST_RESULTS[@]}"; do
            IFS='|' read -r test_name exit_code exec_time error_msg <<< "$result"
            local is_slower=0
            if command -v bc &> /dev/null; then
                is_slower=$(echo "$exec_time > $slowest_time" | bc -l 2>/dev/null || echo "0")
            else
                # Simple integer comparison fallback
                local exec_int=${exec_time%.*}
                local slow_int=${slowest_time%.*}
                [[ $exec_int -gt $slow_int ]] && is_slower=1
            fi
            
            if [[ $is_slower -eq 1 ]]; then
                slowest_test="$test_name"
                slowest_time="$exec_time"
            fi
        done
        
        if [[ -n "$slowest_test" ]]; then
            print_status "  Slowest Test:      $slowest_test (${slowest_time}s)" "$NC"
        fi
        echo
    fi
    
    print_status "═══════════════════════════════════════════════════════════════" "$CYAN"
}

# Function to generate JSON report
generate_json_report() {
    local total_time="$1"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    cat << EOF
{
  "summary": {
    "timestamp": "$timestamp",
    "total_tests": $TOTAL_TESTS,
    "passed": $PASSED_TESTS,
    "failed": $FAILED_TESTS,
    "skipped": $SKIPPED_TESTS,
    "success_rate": $(( TOTAL_TESTS > 0 ? (PASSED_TESTS * 100) / TOTAL_TESTS : 0 )),
    "total_execution_time": $total_time,
    "average_test_time": $(if command -v bc &> /dev/null; then echo "scale=3; $total_time / $TOTAL_TESTS" | bc -l 2>/dev/null || echo "0"; else echo $(( total_time / TOTAL_TESTS )); fi)
  },
  "test_results": [
EOF

    local first=true
    for result in "${TEST_RESULTS[@]}"; do
        IFS='|' read -r test_name exit_code exec_time error_msg <<< "$result"
        
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi
        
        # Escape JSON strings
        local escaped_name=$(echo "$test_name" | sed 's/"/\\"/g')
        local escaped_error=$(echo "$error_msg" | sed 's/"/\\"/g' | tr '\n' ' ')
        local status="passed"
        [[ $exit_code -ne 0 ]] && status="failed"
        
        cat << EOF
    {
      "name": "$escaped_name",
      "status": "$status",
      "execution_time": $exec_time,
      "exit_code": $exit_code,
      "error_message": "$escaped_error"
    }
EOF
    done

    cat << EOF

  ],
  "environment": {
    "database_host": "$DB_HOST",
    "database_port": "$TEST_DB_PORT",
    "container_name": "$TEST_CONTAINER_NAME",
    "test_category": "$TEST_CATEGORY"
  }
}
EOF
}

# Function to save report to file
save_report_to_file() {
    local format="$1"
    local total_time="$2"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local report_file="test_report_${timestamp}.${format}"
    
    log "INFO" "Saving $format report to: $report_file"
    
    case "$format" in
        "json")
            generate_json_report "$total_time" > "$report_file"
            ;;
        "text")
            generate_text_report "$total_time" > "$report_file"
            ;;
    esac
    
    if [[ -f "$report_file" ]]; then
        log "SUCCESS" "Report saved: $report_file"
    else
        log "ERROR" "Failed to save report: $report_file"
    fi
}

# Function to display final results
display_final_results() {
    local total_time="$1"
    
    case "$REPORT_FORMAT" in
        "json")
            generate_json_report "$total_time"
            ;;
        "text"|*)
            generate_text_report "$total_time"
            ;;
    esac
    
    # Determine exit code
    if [[ $FAILED_TESTS -gt 0 ]]; then
        log "ERROR" "Test suite completed with failures"
        return 1
    else
        log "SUCCESS" "All tests passed successfully!"
        return 0
    fi
}

# Main execution function
main() {
    START_TIME=$(date +%s.%N)
    
    log "INFO" "Starting fstore-sql comprehensive test suite"
    log "INFO" "Test category: $TEST_CATEGORY"
    log "INFO" "Report format: $REPORT_FORMAT"
    log "INFO" "Verbose mode: $VERBOSE"
    
    # Validate environment
    check_docker
    validate_test_environment
    
    # Setup test database
    cleanup_test_containers
    start_test_database
    wait_for_database_ready
    
    # Load test framework utilities
    if ! load_test_framework; then
        log "ERROR" "Failed to load test framework"
        stop_test_database
        exit 1
    fi
    
    # Setup cleanup trap
    trap 'log "INFO" "Cleaning up..."; stop_test_database; exit 130' INT TERM
    
    # Run tests
    local test_exit_code=0
    if ! run_test_category "$TEST_CATEGORY"; then
        test_exit_code=1
    fi
    
    # Calculate total execution time
    local end_time=$(date +%s.%N)
    local total_time
    if command -v bc &> /dev/null; then
        total_time=$(echo "$end_time - $START_TIME" | bc -l 2>/dev/null || echo "0")
    else
        # Fallback to basic arithmetic (less precise)
        local start_int=${START_TIME%.*}
        local end_int=${end_time%.*}
        total_time=$((end_int - start_int))
    fi
    
    # Display results
    if ! display_final_results "$total_time"; then
        test_exit_code=1
    fi
    
    # Cleanup
    stop_test_database
    
    exit $test_exit_code
}

# Help and usage functions
show_help() {
    cat << EOF
fstore-sql Test Runner

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --category <CATEGORY>     Test category to run (default: all)
                             Categories: all, unit, integration, performance,
                                       event-sourcing, event-streaming, constraints
    
    --verbose                Enable verbose output with detailed test information
    
    --keep-db               Keep test database running after tests complete
                           (useful for debugging)
    
    --report-format <FORMAT> Output format for test results (default: text)
                           Formats: text, json
    
    --save-report           Save test report to file with timestamp
    
    --timeout <SECONDS>     Timeout for individual tests (default: 300)
    
    --help, -h              Show this help message

EXAMPLES:
    $0                                    # Run all tests
    $0 --category unit                    # Run only unit tests
    $0 --category event-sourcing          # Run event sourcing tests
    $0 --verbose --keep-db                # Run with verbose output, keep DB
    $0 --report-format json               # Output results in JSON format
    $0 --category integration --save-report  # Run integration tests, save report

ENVIRONMENT VARIABLES:
    TEST_TIMEOUT            Override default test timeout (seconds)
    PGPASSWORD             Set automatically, do not override

NOTES:
    - Requires Docker to be installed and running
    - Uses port $TEST_DB_PORT for test database (configurable)
    - Test database is isolated and cleaned up automatically
    - All test data uses 'test_' prefixes for easy identification

EOF
}

# Command line argument parsing
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --category)
                TEST_CATEGORY="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --keep-db)
                KEEP_DB=true
                shift
                ;;
            --report-format)
                REPORT_FORMAT="$2"
                if [[ "$REPORT_FORMAT" != "text" && "$REPORT_FORMAT" != "json" ]]; then
                    log "ERROR" "Invalid report format: $REPORT_FORMAT. Use 'text' or 'json'"
                    exit 1
                fi
                shift 2
                ;;
            --save-report)
                SAVE_REPORT=true
                shift
                ;;
            --timeout)
                TEST_TIMEOUT="$2"
                if ! [[ "$TEST_TIMEOUT" =~ ^[0-9]+$ ]]; then
                    log "ERROR" "Invalid timeout value: $TEST_TIMEOUT. Must be a positive integer"
                    exit 1
                fi
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                # Treat as category for backward compatibility
                if [[ -z "$TEST_CATEGORY" || "$TEST_CATEGORY" == "all" ]]; then
                    TEST_CATEGORY="$1"
                else
                    log "ERROR" "Unknown option: $1"
                    show_help
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Apply environment variable overrides
    if [[ -n "${TEST_TIMEOUT_ENV:-}" ]]; then
        TEST_TIMEOUT="$TEST_TIMEOUT_ENV"
    fi
    
    log "DEBUG" "Parsed arguments - Category: $TEST_CATEGORY, Verbose: $VERBOSE, Keep DB: $KEEP_DB, Format: $REPORT_FORMAT"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Parse command line arguments
    parse_arguments "$@"
    
    # Run main function
    main
fi