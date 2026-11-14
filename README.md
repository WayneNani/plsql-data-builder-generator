# PL/SQL Data Builder

This project aims to streamline the creation of test data directly within the Oracle database. Unit tests for database code turn into integration tests quite quickly and often require a number of tables to be populated beforehand. Using the builder pattern has proven to be a good practice for integration tests in other languages. It makes the inserted data more obvious and also allows for leveraging defaults to minimize setup.

The goal: a test only states what matters for it. Everything else, including the parent rows a table depends on, is filled in automatically:

```sql
begin
  -- creates an order item, its order and the order's customer
  order_item_builder.build(quantity => 3);
end;
```

In Java the builder pattern exists because the language has neither named parameters nor parameter defaults. PL/SQL has both, so the generated builder is simply a package whose parameters map to the table's columns, each with a sensible default.

## Usage

This project consists of two packages:

1. `builder_pattern_generator` is the main interface to use when actually generating builders for arbitrary tables.
2. `builder_pattern_templates` holds the templates of the generated code and is called by `builder_pattern_generator`.

Install both by executing the `install.sql` script. Then generate the builders for all tables of a schema (or the ones matching a `like` pattern), parent tables first:

```sql
begin
  builder_pattern_generator.generate_builder_packages(
    i_table_owner => 'MY_USER'
    ,i_table_name_like => '%'
  );
end;
```

or for a single table:

```sql
begin
  builder_pattern_generator.generate_builder_package(
    i_table_owner => 'MY_USER'
    ,i_table_name => 'ORDERS'
  );
end;
```

This compiles the package `my_user.orders_builder`. Pass `i_package_name` to choose a different name. If you want to look at the source before compiling it, use `builder_pattern_generator.generate_builder_package_sql`, which returns it as a script.

## The generated builder

For these tables

```sql
create table customer (
  id           number generated always as identity primary key
  ,name        varchar2(50) not null
  ,email       varchar2(100)
);

create table orders (
  id           number generated always as identity primary key
  ,customer_id number not null references customer
  ,ordered_at  date default sysdate not null
  ,amount      number(10, 2) not null
  ,note        varchar2(100)
);
```

the builder for `orders` looks like this (shortened):

```sql
create or replace package my_user.orders_builder authid current_user as

  procedure build(
    customer_id in my_user.orders.customer_id%type default my_user.customer_builder.build_row().id
    ,ordered_at in my_user.orders.ordered_at%type default sysdate
    ,amount in my_user.orders.amount%type default my_user.orders_defaults.amount
    ,note in my_user.orders.note%type default null
  );

  function build_row(
    -- same parameters
  ) return my_user.orders%rowtype;

  function new_row return my_user.orders%rowtype;
  procedure build(i_row in my_user.orders%rowtype);
  function build_row(i_row in my_user.orders%rowtype) return my_user.orders%rowtype;

end orders_builder;
```

### Building rows

Every parameter has a default, so a call without arguments creates a valid row. Use named notation and only pass what matters for your test:

```sql
begin
  orders_builder.build;                      -- creates a customer and an order
  orders_builder.build(amount => 0);         -- the same, with a specific amount
end;
```

`build_row` does the same but returns the inserted row, including generated values such as identity columns, column defaults, values set by triggers and virtual columns:

```sql
declare
  l_customer customer%rowtype;
begin
  l_customer := customer_builder.build_row(name => 'ACME');

  -- two orders for the same customer: no additional customer is created
  orders_builder.build(customer_id => l_customer.id);
  orders_builder.build(customer_id => l_customer.id, amount => 0);
end;
```

> No commit is issued! It is a best practice to not commit in a unit test and let the testing framework handle the transaction instead.

### Where the defaults come from

For each column the first of these that applies is used:

1. **Your own default**: a function without parameters with the same name as the column in the hand written package `<table_name>_defaults` (see below).
2. **The column default of the table**, e.g. `sysdate`, `'NEW'` or `my_seq.nextval`. Table defaults keep working although all columns are part of the insert.
3. **A new parent row** for mandatory foreign key columns, created by the parent table's builder: `default customer_builder.build_row().id`. PL/SQL only evaluates a default when the parameter is not passed, so the parent row is only created if you do not pass a value yourself. This works across any number of levels.
4. **A dummy value** for mandatory columns: `'name_1'`, `'name_2'`, ... for text (shortened to the column length), a counter for numbers (respecting the precision), `trunc(sysdate)`, `systimestamp`, `sys_guid()` for `raw(16)`, `empty_blob()`, `json('{}')`, `false`, ... The values are unique per session and builder, so simple unique constraints are satisfied.
5. **`null`**: optional columns stay empty.

### Your own defaults

Defaults that need domain knowledge belong in a hand written package named `<table_name>_defaults` in the schema of the table. Every function without parameters that has the name of a column becomes the default of that column:

```sql
create or replace package orders_defaults as
  function amount return orders.amount%type;
end;
/

create or replace package body orders_defaults as
  function amount return orders.amount%type is
  begin
    return 100;
  end;
end;
/
```

This package is never touched by the generator, so you can regenerate the builders at any time. The defaults package is detected at generation time: after adding a function, regenerate the builder.

Typical use cases: values that have to satisfy check constraints (`status in ('NEW', 'DONE')`), primary keys without identity or default (`return my_seq.nextval;`), or foreign keys that should point to existing reference data instead of creating a new parent row.

### Presets with records

To reuse more complex setups, write functions that return a preconfigured record and let the test change only what it needs. `new_row` returns a record with all defaults applied; `build` and `build_row` accept such a record:

```sql
create or replace package order_presets as
  function large_order return orders%rowtype;
end;
/

create or replace package body order_presets as
  function large_order return orders%rowtype is
    l_order orders%rowtype := orders_builder.new_row;
  begin
    l_order.amount := 100000;
    l_order.note := 'needs approval';
    return l_order;
  end;
end;
/

-- in a test
declare
  l_order orders%rowtype := order_presets.large_order;
begin
  l_order.ordered_at := date '2024-12-24';
  orders_builder.build(l_order);
end;
```

`new_row` has no side effects on other tables: mandatory foreign keys stay `null` in the record, and `build`/`build_row` create the parent row only if the field is still `null` when the record is inserted.

### Details and limitations

- Every parameter is anchored with `%type`, so there is no data type mapping. Changing a column's length or precision does not require regenerating the builder; the package is invalidated and recompiled automatically. Exception: generated dummy values are sized at generation time, so regenerate after shrinking a mandatory column. Adding or dropping columns, constraints or defaults does require regenerating it.
- Columns that cannot be inserted are left out: virtual columns, identity columns `generated always` and system generated hidden columns. Invisible columns are included as parameters; in the record API they get their default.
- Parent rows are only created for mandatory foreign keys with a single column that reference another table. Composite and self referencing foreign keys get no automatic default; use the defaults package for them. Parent builders are expected to have the default name `<parent_table>_builder`. `generate_builder_package` raises an error if a parent builder does not exist yet; `generate_builder_packages` generates parents first.
- Primary key columns that an enabled `before insert for each row` trigger assigns (`:new.id := ...`) get no dummy value, as they are usually filled by the trigger from a sequence.
- Dummy values start at 1 in every session. Unique columns may collide with data that already exists in the table, and check constraints are not considered; use the defaults package in these cases.
- Table defaults are copied at generation time and evaluated in PL/SQL. This works for typical defaults, but an expression that is only valid in SQL makes the generated package fail to compile.
- Identifiers that are not plain upper case (e.g. `"MixedCase"`) or that are reserved words in SQL or PL/SQL (e.g. `"DATE"`, `"END"`, `"EXCEPTION"`) are quoted, so the parameter has to be quoted in the call as well: `build("END" => 5)`.
- Tables with `LONG` or `LONG RAW` columns are not supported: `build_row` returns the row with `returning ... into`, which does not support these types.
- Requires Oracle 12.2 or newer. `generate_builder_package` and `generate_builder_packages` use invoker rights, so `CREATE PROCEDURE` may also be granted through a role.

## Tests

`test/builder_test.sql` creates tables with tricky column kinds and a customer → order → order item hierarchy, generates their builders, inserts rows through them and checks the results. Run it in a scratch schema after `install.sql`.
