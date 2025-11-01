# Product Overview

fstore-sql is a PostgreSQL-based event store that provides a seamless SQL model for event-sourcing and event-streaming patterns. 

## Core Purpose
- Enable rapid prototyping of event-sourced systems using only PostgreSQL
- Provide event-streaming capabilities with concurrent consumer support
- Eliminate the need for additional frameworks or programming languages at the database level

## Key Features
- **Event Sourcing**: Durable event storage with optimistic locking and immutable event streams
- **Event Streaming**: Kafka-like partitioning with concurrent consumers and automatic acknowledgment handling
- **Pure SQL Implementation**: All functionality implemented as PostgreSQL functions and triggers
- **Real-time Processing**: Support for edge functions and HTTP endpoint integration via pg_cron and pg_net extensions

## Target Use Cases
- Event-sourced application prototyping
- CQRS (Command Query Responsibility Segregation) implementations
- Real-time event streaming to serverless functions
- Distributed system coordination with PostgreSQL as the backbone

## Architecture Philosophy
The project follows functional domain modeling principles inspired by DDD (Domain-Driven Design) and functional programming, with clear separation between:
- **Commands** (intent to change state)
- **Events** (facts about state changes)  
- **State** (current system state derived from events)