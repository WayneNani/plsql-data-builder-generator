# PL/SQL Data Builder

This project aims to streamline the creation of test data directly within the Oracle database. Unit tests for database code turn into integration tests quite quickly and often require a number of tables to be populated beforehand. Using the builder pattern has proven to be a good practice for integration tests in other languages. I makes the inserted data more obvious and also allows for leveraging defaults to minimize setup.

## Usage

This project consists of two packages:

1. `builder_pattern_generator` is the main interface to use when actually generating data generators for arbitrary tables.
2. `builder_pattern_templates` is the underlying template engine that is called by `builder_pattern_generator` for each requested table.

After these packages have been compiled (just execute the `install.sql` script) you can create the generator object for a table by calling:

```sql
begin
  builder_pattern_generator.generate_builder_object_sql(
    i_table_owner => 'MY_USER'
    ,i_table_name => 'TEST_TABLE'
  );
end;
```

This will generate the source for the corresponding data generator object type. You can change the name but by default it will be your_table_name_builder_type.
If you want to keep the default name anyways, you can also compile the object right away with `builder_pattern_generator.generate_builder_object`.

After you have executed the generated source code (or used `builder_pattern_generator.generate_builder_object`) you can use the data generator by using this pattern:

```sql
begin
  test_table_builder_type()
    .with_column1('Test value')
    .with_column2(123)
    .with_column3(to_date('2024-12-03', 'yyyy-mm-dd'))
    .build();
end;
```

This example creates a row for table `test_table` and enters values for column1, column2 and column3. The final `.build()` simply performs the insert into the table. 

> No commit is issued! It is a best practice to not commit in a unit test and let the testing framework handle the transaction instead. 

If you want to include defaults for certain columns to save some typing, you can include the defaults in the constructor of the object type. If you want to include a default for column1, the constructor would change like this:

```sql
constructor function ...

  self.column1 := 'my-default';

  return;
end;
```