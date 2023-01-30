# fstore-sql (event store based on the Postgres database)

This project is enabling event-sourcing and *pool-based* event-streaming patterns by using SQL (PostgreSQL) only.
No additional tools, frameworks or programming languages are required at this level.

- `event-sourcing` data pattern (by using PostgreSQL database) to durably store events
    - Append events to the ordered, append-only log, using `entity id`/`decider id` as a key
    - Load all the events for a single entity/decider, in an ordered sequence, using the `entity id`/`decider id` as a
      key
    - Support optimistic locking/concurrency
- `event-streaming` to concurrently coordinate read over a streams of messages from multiple consumer instances
    - Support real-time concurrent consumers to project events to view/query models


The SQL functions and schema we provided you with can help you to persist, query and stream events, but the
decision-making and view-handling logic would be something that you would have to implement on your own.
Check [fmodel libarary](https://github.com/fraktalio/fmodel)!

## Pitch

- Relational model is the widely used transactional model in IT industry, and you can use this project to prototype
  event-sourcing and event-streaming efficiently, without introducing new infrastructural components.
- [PostgreSQL](https://www.postgresql.org/) is setting golden standards for SQL, many DB systems are compatible with its
  syntax and standards (YugabyteDB and Amazon Aurora, for example).
  PostgreSQL is open source object-relational database system with over 30 years of active development that has earned
  it a strong reputation for reliability, feature robustness, and performance.
  [YugabyteDB](https://www.yugabyte.com/) is a high-performance, cloud-native distributed SQL database that aims to
  support all PostgreSQL features.
  [Amazon Aurora (Aurora)](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/CHAP_AuroraOverview.html) is a
  fully managed relational database engine that's compatible with MySQL and PostgreSQL.

### Run PostgreSQL

You can [download](https://www.postgresql.org/download/) as ready-to-use packages or installers for various platforms.

Alternatively, you can run the following command to start PostgreSQL in a Docker container:

```shell
docker run --name some-postgres -e POSTGRES_PASSWORD=mysecretpassword -p 5432:5432 -d postgres
```

### Run YugabyteDB

YugabyteDB is a high-performance, cloud-native distributed SQL database that aims to support all PostgreSQL features. It
is best fit for cloud-native OLTP (i.e. real-time, business critical) applications that need absolute data correctness
and require at least one of the following: scalability, high tolerance to failures, globally-distributed deployments.

> The YSQL API is fully compatible with PostgreSQL.
> API compatibility refers to the fact that the database APIs offered by YugabyteDB servers implement the
> same `wire protocol` and `modeling/query language` as that of an existing database. Since client drivers, command line
> shells, IDE integrations and other ecosystem integrations of the existing database rely on this wire protocol and
> modeling/query language, they are expected to work with YugabyteDB without major modifications.



Read more on [YugabyteDB vs PostgreSQL](https://docs.yugabyte.com/preview/comparisons/postgresql/) - YugabyteDB is
designed to solve the high availability need that monolithic databases such as PostgreSQL were never designed for.

You can [download](https://docs.yugabyte.com/preview/quick-start/install) as ready-to-use packages or installers for
various platforms.

```shell
./bin/yugabyted start --master_flags=ysql_sequence_cache_minval=0 --tserver_flags=ysql_sequence_cache_minval=0
```

Alternatively, you can run the following command
to [start YugabyteDB in a Docker](https://docs.yugabyte.com/preview/quick-start/create-local-cluster/docker/) container:

```shell
docker run -d --name yugabyte  -p7000:7000 -p9000:9000 -p5433:5433 -p9042:9042\
 yugabytedb/yugabyte:latest bin/yugabyted start\
 --daemon=false --master_flags=ysql_sequence_cache_minval=0 --tserver_flags=ysql_sequence_cache_minval=0
```

Web console: [http://127.0.0.1:7000](http://127.0.0.1:7000)

### Examples of usage

#### Event sourcing

1. Registering a simple decider `decider1` with two event types it is able to publish: 'event1', 'event2'

```sql
SELECT *
from register_decider_event('decider1', 'event1');
SELECT *
from register_decider_event('decider1', 'event2');
```

2. Appending two events for the decider `f156a3c4-9bd8-11ed-a8fc-0242ac120002`.

> Notice how `previous_id` of the second event is pointing to `event_id` of the first event (effectively implementing optimistic locking).

```sql
SELECT *
from append_event('event1', '21e19516-9bda-11ed-a8fc-0242ac120002', 'decider1', 'f156a3c4-9bd8-11ed-a8fc-0242ac120002',
                  '{}', 'f156a3c4-9bd8-11ed-a8fc-0242ac120002', null);
SELECT *
from append_event('event2', 'eb411c34-9d64-11ed-a8fc-0242ac120002', 'decider1', 'f156a3c4-9bd8-11ed-a8fc-0242ac120002',
                  '{}', 'f156a3c4-9bd8-11ed-a8fc-0242ac120002', '21e19516-9bda-11ed-a8fc-0242ac120002');
```

3. Get/List events for the decider `f156a3c4-9bd8-11ed-a8fc-0242ac120002`

```sql
SELECT *
from get_events('f156a3c4-9bd8-11ed-a8fc-0242ac120002');
```

#### Event streaming

4. Registering a (materialized) view `view1` with 500 millisecond pooling frequency, starting from 28th Jan.

> Notice how `lock` for the two events with `decider_id`=`f156a3c4-9bd8-11ed-a8fc-0242ac120002` is created in the
> background (using triggers).

```sql
SELECT *
from register_view('view1', 500, '2023-01-28 12:17:17.078384');
```

5. Appending two events for another decider `2ac37f68-9d66-11ed-a8fc-0242ac120002`.

> Notice how `previous_id` of the second event is pointing to `event_id` of the first event.

> Notice how additional `lock` for the registered view and two new events
> with `decider_id`=`2ac37f68-9d66-11ed-a8fc-0242ac120002` is created in the background (using triggers).

```sql
SELECT *
from append_event('event1', 'f7c370aa-9d65-11ed-a8fc-0242ac120002', 'decider1', '2ac37f68-9d66-11ed-a8fc-0242ac120002',
                  '{}', 'f156a3c4-9bd8-11ed-a8fc-0242ac120002', null);
SELECT *
from append_event('event2', '42ee177e-9d66-11ed-a8fc-0242ac120002', 'decider1', '2ac37f68-9d66-11ed-a8fc-0242ac120002',
                  '{}', 'f156a3c4-9bd8-11ed-a8fc-0242ac120002', 'f7c370aa-9d65-11ed-a8fc-0242ac120002');
```

6. Stream the events to concurrent consumers

> Notice that this query can run in a loop within your application

```sql
SELECT *
from stream_events('view1');
SELECT *
from ack_event('view1', 'f156a3c4-9bd8-11ed-a8fc-0242ac120002', 1);
```

## References and further reading

Many thanks to Matt Bishop. We adopted his model for event-sourcing!

Many thanks to Marco Pegoraro. We adopted his model for event-streaming!

- (Marco Pegoraro) https://github.com/marcopeg/postgres-event-sourcing
- (Matt Bishop) https://github.com/mattbishop/sql-event-store


---
Created with :heart: by [Fraktalio](https://fraktalio.com/) 

Excited to launch your next IT project with us? Let's get started! Reach out to our team at `info@fraktalio.com` to begin the journey to success.
