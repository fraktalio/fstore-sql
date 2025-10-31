# Implementation Plan

- [x] 1. Set up test framework foundation
  - Create tests directory structure with setup, unit, integration, and performance subdirectories
  - Implement core SQL test helper functions for assertions, setup, and cleanup
  - Create test database initialization scripts
  - _Requirements: 1.1, 3.1, 3.2_

- [x] 1.1 Create test directory structure
  - Create tests/ directory with all required subdirectories (setup/, unit/, integration/, performance/, utils/)
  - Set up proper file organization following the design architecture
  - _Requirements: 1.1, 3.1_

- [x] 1.2 Implement SQL test framework utilities
  - Create utils/test-helpers.sql with core testing functions (test_assert, test_expect_error, test_setup, test_cleanup)
  - Create utils/assertions.sql with specialized assertion functions for event store testing
  - Implement test result tracking and reporting functions
  - _Requirements: 1.1, 1.4, 1.5_

- [x] 1.3 Create database setup and teardown scripts
  - Create setup/test-database.sql for initializing clean test database
  - Create setup/test-data.sql for common test data patterns
  - Implement database reset and cleanup procedures
  - _Requirements: 3.1, 3.2, 3.3_

- [x] 2. Implement event sourcing API tests
  - Create comprehensive tests for register_decider_event, append_event, get_events, and get_last_event functions
  - Test positive cases, error conditions, and edge cases for each API function
  - Validate all constraint enforcement and data integrity rules
  - _Requirements: 1.1, 2.1, 2.2, 5.1_

- [x] 2.1 Test register_decider_event function
  - Write tests for successful decider and event registration
  - Test duplicate registration handling and constraint validation
  - Test invalid parameters and error conditions
  - _Requirements: 1.1, 2.1, 5.2_

- [x] 2.2 Test append_event function
  - Write tests for successful event appending with proper sequencing
  - Test optimistic locking with previous_id validation
  - Test constraint violations (invalid decider/event combinations, duplicate events)
  - Test final event handling and stream closure
  - _Requirements: 1.1, 2.1, 2.2, 2.3_

- [x] 2.3 Test get_events and get_last_event functions
  - Write tests for event retrieval by decider_id and decider type
  - Test proper event ordering and filtering
  - Test empty result handling and edge cases
  - _Requirements: 1.1, 5.1_

- [x] 3. Implement event streaming API tests
  - Create comprehensive tests for register_view, stream_events, ack_event, nack_event, and schedule_nack_event functions
  - Test concurrent consumer scenarios and lock management
  - Validate proper event streaming behavior and acknowledgment handling
  - _Requirements: 1.2, 4.2, 4.3, 4.4_

- [x] 3.1 Test register_view function
  - Write tests for view registration with different configurations
  - Test view updates and parameter validation
  - Test edge function URL and pooling delay configurations
  - _Requirements: 1.2, 5.4_

- [x] 3.2 Test stream_events function
  - Write tests for basic event streaming to single consumer
  - Test concurrent consumer coordination and lock management
  - Test event filtering by view start_at timestamp
  - Test limit parameter and pagination behavior
  - _Requirements: 1.2, 4.2, 4.4_

- [x] 3.3 Test acknowledgment functions (ack_event, nack_event, schedule_nack_event)
  - Write tests for successful event acknowledgment and lock release
  - Test negative acknowledgment and retry behavior
  - Test scheduled retry with delay functionality
  - Test lock timeout scenarios and automatic unlock
  - _Requirements: 1.2, 4.3, 5.5_

- [x] 4. Implement database constraint and integrity tests
  - Create tests that validate all database triggers, rules, and constraints
  - Test immutability enforcement for events and deciders tables
  - Test data integrity under various failure scenarios
  - _Requirements: 1.3, 2.1, 2.4, 2.5_

- [x] 4.1 Test immutability constraints
  - Write tests verifying that UPDATE and DELETE operations on events table are ignored
  - Write tests verifying that UPDATE and DELETE operations on deciders table are ignored
  - Test that immutability rules work correctly under various conditions
  - _Requirements: 2.5_

- [x] 4.2 Test event sequencing and validation triggers
  - Write tests for check_final_event_for_decider trigger
  - Write tests for check_first_event_for_decider trigger
  - Write tests for check_previous_id_in_same_decider trigger
  - _Requirements: 2.1, 2.2, 2.3_

- [x] 4.3 Test foreign key and uniqueness constraints
  - Write tests for decider-event foreign key constraint enforcement
  - Write tests for event_id uniqueness constraint
  - Write tests for previous_id uniqueness constraint with null handling
  - _Requirements: 2.1, 2.4_

- [x] 5. Create main test runner script
  - Implement run-tests.sh script with Docker container management
  - Add support for test category selection and execution options
  - Implement test result collection and reporting
  - Add proper error handling and cleanup procedures
  - _Requirements: 1.4, 3.1, 3.2, 3.3, 3.5_

- [x] 5.1 Implement Docker container management
  - Create functions for starting and stopping PostgreSQL test containers
  - Implement database health checks and readiness verification
  - Add proper container cleanup and resource management
  - _Requirements: 3.5_

- [x] 5.2 Implement test discovery and execution
  - Create test file discovery mechanism for different categories
  - Implement test execution with proper isolation and error handling
  - Add support for running individual tests or test categories
  - _Requirements: 1.4, 3.4_

- [x] 5.3 Implement result reporting and logging
  - Create test result collection and aggregation
  - Implement multiple output formats (text, JSON)
  - Add detailed error reporting with context information
  - Add execution time tracking and performance metrics
  - _Requirements: 1.4, 1.5, 4.1, 4.5_

- [x] 6. Implement integration and performance tests
  - Create end-to-end workflow tests that combine event sourcing and streaming
  - Implement concurrent access tests with multiple consumers and producers
  - Create performance benchmarks and load testing scenarios
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

- [x] 6.1 Create end-to-end integration tests
  - Write tests that exercise complete event sourcing and streaming workflows
  - Test scenarios from the README examples to ensure documentation accuracy
  - Test complex multi-decider, multi-view scenarios
  - _Requirements: 5.1_

- [x] 6.2 Implement concurrent access tests
  - Write tests for multiple concurrent consumers accessing different partitions
  - Write tests for concurrent producers appending events to same decider
  - Test lock contention and proper coordination between consumers
  - _Requirements: 4.2, 4.4_

- [x] 6.3 Create performance and load tests
  - Implement high-volume event insertion tests
  - Create concurrent consumer performance tests
  - Add benchmark tests for all API functions with timing measurements
  - Test system behavior under stress conditions
  - _Requirements: 4.1, 4.2, 4.5_

- [ ]* 6.4 Add performance monitoring and metrics collection
  - Implement detailed performance metrics collection during test execution
  - Create performance regression detection
  - Add resource usage monitoring (memory, CPU, connections)
  - _Requirements: 4.1, 4.5_

- [x] 7. Create documentation and examples
  - Write comprehensive README for the test suite
  - Create example test files demonstrating testing patterns
  - Document test runner usage and configuration options
  - _Requirements: 1.4, 1.5_

- [x] 7.1 Write test suite documentation
  - Create README.md in tests/ directory explaining test structure and usage
  - Document all test helper functions and their usage
  - Provide examples of writing new tests
  - _Requirements: 1.4_

- [x] 7.2 Create test configuration and setup guide
  - Document test runner command-line options and configuration
  - Provide setup instructions for different environments
  - Create troubleshooting guide for common test issues
  - _Requirements: 1.5, 3.1_
