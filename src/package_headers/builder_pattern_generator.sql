create or replace package builder_pattern_generator authid current_user as

  /*
    Generates a test data builder package for a table.

    The generated package (default name: <table_name>_builder) contains

      procedure build(...)                  inserts one row
      function  build_row(...) return %rowtype
                                            inserts one row and returns it

    with one parameter per insertable column. Parameters are anchored with
    %type (no data type mapping, robust against type changes) and default to
    the column default of the table, so table defaults keep working.

    Owner, table and package names are case insensitive unless passed in
    double quotes (e.g. '"MixedCase"').
  */

  function generate_builder_package_sql(
    i_table_owner varchar2
    ,i_table_name varchar2
    ,i_package_name varchar2 default null
  ) return clob;


  procedure generate_builder_package(
    i_table_owner varchar2
    ,i_table_name varchar2
    ,i_package_name varchar2 default null
  );

end builder_pattern_generator;
/
