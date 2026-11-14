# PL/SQL Data Builder

This project aims to streamline the creation of test data directly within the Oracle database. Unit tests for database code turn into integration tests quite quickly and often require a number of tables to be populated beforehand. Using the builder pattern has proven to be a good practice for integration tests in other languages. It makes the inserted data more obvious and also allows for leveraging defaults to minimize setup.

In Java the builder pattern exists because the language has neither named parameters nor parameter defaults. PL/SQL has both, so the generated "builder" is simply a package with one procedure whose parameters map to the table's columns:

```sql
test_table_builder.build(
  column1 => 'Test value'
  ,column2 => 123
);
```

## Usage

This project consists of two packages:

1. `builder_pattern_generator` is the main interface to use when actually generating builders for arbitrary tables.
2. `builder_pattern_templates` holds the templates of the generated code and is called by `builder_pattern_generator`.

Install both by executing the `install.sql` script. Then create the builder package for a table:

```sql
begin
  builder_pattern_generator.generate_builder_package(
    i_table_owner => 'MY_USER'
    ,i_table_name => 'TEST_TABLE'
  );
end;
```

This compiles the package `my_user.test_table_builder`. Pass `i_package_name` to choose a different name. If you want to look at or adapt the source before compiling it, use `builder_pattern_generator.generate_builder_package_sql`, which returns the source as a script.

For a table like

```sql
create table test_table (
  id       number generated always as identity primary key
  ,column1 varchar2(100) not null
  ,column2 number
  ,column3 date default sysdate not null
);
```

the generated package looks like this:

```sql
create or replace package my_user.test_table_builder authid current_user as

  procedure build(
    column1 in my_user.test_table.column1%type default null
    ,column2 in my_user.test_table.column2%type default null
    ,column3 in my_user.test_table.column3%type default sysdate
  );

  function build_row(
    column1 in my_user.test_table.column1%type default null
    ,column2 in my_user.test_table.column2%type default null
    ,column3 in my_user.test_table.column3%type default sysdate
  ) return my_user.test_table%rowtype;

end test_table_builder;
```

Use named notation and only pass the columns that matter for your test:

```sql
begin
  test_table_builder.build(
    column1 => 'Test value'
    ,column2 => 123
  );
end;
```

`build_row` does the same but returns the inserted row, including generated values such as identity columns, column defaults, values set by triggers and virtual columns. This is handy when you need a generated key for dependent test data:

```sql
declare
  l_parent parent_table%rowtype;
begin
  l_parent := parent_table_builder.build_row(name => 'Parent');
  child_table_builder.build(parent_id => l_parent.id);
end;
```

> No commit is issued! It is a best practice to not commit in a unit test and let the testing framework handle the transaction instead.

### How columns are handled

- Every parameter is anchored with `%type`, so there is no data type mapping in the generator. Changing a column's length or precision does not require regenerating the builder; the package is invalidated and recompiled automatically. Adding or dropping columns does require regenerating it.
- Every parameter defaults to the column's `DEFAULT` expression (or `null`), so table defaults keep working although all columns are part of the insert. You can still override any default explicitly.
- Columns that cannot be inserted are left out: virtual columns, identity columns `generated always` and system generated hidden columns. Invisible columns are included.
- Identifiers that are not plain upper case (e.g. `"MixedCase"`) are quoted, so the parameter has to be quoted in the call as well.

The default expressions are copied at generation time and evaluated in PL/SQL. This works for typical defaults (`sysdate`, `systimestamp`, literals, `sequence.nextval`, `sys_guid()`, `sys_context(...)`), but an expression that is only valid in SQL makes the generated package fail to compile. Edit the default in the generated source in that case.

### Custom defaults

If you want a default for a column that has no default in the table, change the parameter default in the generated package (keep in mind that regenerating overwrites it):

```sql
    column1 in my_user.test_table.column1%type default 'my-default'
```

Alternatively, keep the generated package untouched and add your defaults in a wrapper package (see below).

## Tests

`test/builder_test.sql` is a smoke test that creates tables with tricky column kinds (numbers without precision, float, binary_double, intervals, identity and virtual columns, invisible and mixed case columns, CLOBs), generates their builders, inserts rows through them and checks the results. Run it in a scratch schema after `install.sql`.

## Where to go from here?

A great way to leverage this API is to use it to create more complex data setups and make them reproducible with wrapper packages. These cannot be automated as they are highly specific for your domain.
