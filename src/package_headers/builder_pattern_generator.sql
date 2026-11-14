create or replace package builder_pattern_generator authid current_user as

  /*
    Generates test data builder packages for tables.

    The generated package (default name: <table_name>_builder) contains

      procedure build(...)                    inserts one row
      function  build_row(...) return %rowtype
                                              inserts one row and returns it
      function  new_row return %rowtype       a record with all defaults
      procedure build(i_row)                  inserts a record
      function  build_row(i_row) return %rowtype

    with one parameter per insertable column. Parameters are anchored with
    %type and every parameter has a default, so build without arguments
    creates a valid row. Defaults are taken from (in this order)

      1. a function with the same name as the column in the hand written
         package <table_name>_defaults (owner of the table), if it exists
         at generation time
      2. the column default of the table
      3. a new parent row created by the parent table's builder
         (mandatory single column foreign keys)
      4. a generated dummy value (mandatory columns)
      5. null

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


  -- Generates the builders for all tables of an owner whose name matches
  -- i_table_name_like, parent tables first.
  procedure generate_builder_packages(
    i_table_owner varchar2
    ,i_table_name_like varchar2 default '%'
  );

end builder_pattern_generator;
/
