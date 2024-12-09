create or replace package builder_pattern_generator as

  subtype column_name_type is all_tab_cols.column_name%type;
  subtype data_type_type is all_tab_cols.data_type%type;
  subtype data_scale_type is varchar2(20);
  subtype column_id_type is all_tab_cols.column_id%type;

  type r_table_column_type is record(
    column_id column_id_type
    ,column_name column_name_type
    ,data_type data_type_type
    ,data_type_scale data_scale_type
  );

  type t_table_columns_type is table of r_table_column_type;



  function get_attributes(
    i_table_columns t_table_columns_type
  ) return clob;


  function get_table_columns(
    i_table_owner varchar2
    ,i_table_name varchar2
  ) return t_table_columns_type;


  function generate_builder_object_sql(
    i_table_owner varchar2
    ,i_table_name varchar2
  ) return clob;


  procedure generate_builder_object(
    i_table_owner varchar2
    ,i_table_name varchar2
  );

end builder_pattern_generator;
/
