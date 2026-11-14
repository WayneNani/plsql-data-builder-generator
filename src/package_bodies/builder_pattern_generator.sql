create or replace package body builder_pattern_generator as

  gc_newline constant varchar2(1) := chr(10);
  gc_whitespace constant varchar2(4) := ' ' || chr(9) || chr(10) || chr(13);

  -- SQL and PL/SQL reserved words: plain upper case, but they still have to
  -- be quoted when used as identifiers
  gc_reserved_words constant varchar2(2000) :=
    ',ACCESS,ADD,ALL,ALTER,AND,ANY,AS,ASC,AT,AUDIT,BEGIN,BETWEEN,BY,CASE,CHAR,CHECK'
    || ',CLUSTER,CLUSTERS,COLAUTH,COLUMN,COLUMNS,COMMENT,COMPRESS,CONNECT,CRASH,CREATE'
    || ',CURRENT,CURSOR,DATE,DECIMAL,DECLARE,DEFAULT,DELETE,DESC,DISTINCT,DROP,ELSE,END'
    || ',EXCEPTION,EXCLUSIVE,EXISTS,FETCH,FILE,FLOAT,FOR,FROM,FUNCTION,GOTO,GRANT,GROUP'
    || ',HAVING,IDENTIFIED,IF,IMMEDIATE,IN,INCREMENT,INDEX,INDEXES,INITIAL,INSERT,INTEGER'
    || ',INTERSECT,INTO,IS,LEVEL,LIKE,LOCK,LONG,MAXEXTENTS,MINUS,MLSLABEL,MODE,MODIFY'
    || ',NOAUDIT,NOCOMPRESS,NOT,NOWAIT,NULL,NUMBER,OF,OFFLINE,ON,ONLINE,OPTION,OR,ORDER'
    || ',OVERLAPS,PCTFREE,PRIOR,PROCEDURE,PUBLIC,RAW,RENAME,RESOURCE,REVOKE,ROW,ROWID'
    || ',ROWNUM,ROWS,SELECT,SESSION,SET,SHARE,SIZE,SMALLINT,SQL,START,SUBTYPE,SUCCESSFUL'
    || ',SYNONYM,SYSDATE,TABAUTH,TABLE,THEN,TO,TRIGGER,UID,UNION,UNIQUE,UPDATE,USER'
    || ',VALIDATE,VALUES,VARCHAR,VARCHAR2,VIEW,VIEWS,WHEN,WHENEVER,WHERE,WITH,';

  subtype identifier_type is varchar2(130 char);
  subtype expression_type is varchar2(32767);

  type t_identifiers_type is table of identifier_type index by pls_integer;
  type t_identifier_set_type is table of boolean index by identifier_type;

  type r_column_type is record(
    identifier identifier_type
    ,default_expression expression_type
    -- part of the table's %rowtype (false for invisible columns)
    ,in_row boolean
    -- default creates a parent row: in the record API it is only applied
    -- when the field is null
    ,is_lazy boolean
  );

  type t_columns_type is table of r_column_type index by pls_integer;

  -- parent row default of a mandatory foreign key column
  type r_parent_type is record(
    expression expression_type
    ,builder_owner identifier_type
    ,builder_name identifier_type
  );

  type t_parent_map_type is table of r_parent_type index by identifier_type;

  e_missing_builders exception;
  pragma exception_init(e_missing_builders, -20002);

  type r_table_type is record(
    owner identifier_type
    ,table_name identifier_type
    ,package_name identifier_type
    ,defaults_package identifier_type
    -- insertable columns: one parameter each
    ,table_columns t_columns_type
    -- columns of the table's %rowtype, in column order
    ,row_columns t_identifiers_type
  );


  ---------------------------------------------------------------------------
  -- Names
  ---------------------------------------------------------------------------

  -- 'my_table' -> 'MY_TABLE', '"MyTable"' -> 'MyTable'
  function normalize_name(
    i_name varchar2
  ) return varchar2 as
  begin

    if i_name like '"%"' then
      return substr(i_name, 2, length(i_name) - 2);
    end if;

    return upper(trim(i_name));

  end normalize_name;


  function is_simple_identifier(
    i_name varchar2
  ) return boolean as
  begin
    return regexp_like(i_name, '^[A-Z][A-Z0-9_$#]*$');
  end is_simple_identifier;


  -- 'MY_TABLE' -> 'my_table', 'MyTable' -> '"MyTable"', 'DATE' -> '"DATE"'
  function format_identifier(
    i_name varchar2
  ) return varchar2 as
  begin

    if is_simple_identifier(i_name)
       and instr(gc_reserved_words, ',' || i_name || ',') = 0
    then
      return lower(i_name);
    end if;

    return '"' || i_name || '"';

  end format_identifier;


  function derived_name(
    i_table_name varchar2
    ,i_suffix varchar2
  ) return varchar2 as
  begin
    return substr(i_table_name, 1, 128 - length(i_suffix)) || i_suffix;
  end derived_name;


  function builder_name(
    i_table_name varchar2
  ) return varchar2 as
  begin
    return derived_name(i_table_name, '_BUILDER');
  end builder_name;


  function defaults_name(
    i_table_name varchar2
  ) return varchar2 as
  begin
    return derived_name(i_table_name, '_DEFAULTS');
  end defaults_name;


  ---------------------------------------------------------------------------
  -- Default expressions
  ---------------------------------------------------------------------------

  function format_table_default(
    i_data_default varchar2
  ) return varchar2 as

    l_default expression_type := rtrim(ltrim(i_data_default, gc_whitespace), gc_whitespace);

  begin

    if upper(l_default) = 'NULL' then
      return null;
    end if;

    return l_default;

  end format_table_default;


  function quote_literal(
    i_text varchar2
  ) return varchar2 as
  begin
    return '''' || replace(i_text, '''', '''''') || '''';
  end quote_literal;


  -- Expression for a dummy value of a mandatory column, null if the data
  -- type is not supported.
  function dummy_expression(
    i_package_name varchar2
    ,i_column_name varchar2
    ,i_data_type varchar2
    ,i_data_length number
    ,i_char_length number
    ,i_data_precision number
    ,i_data_scale number
  ) return varchar2 as

    l_counter constant expression_type := i_package_name || '.next_value';
    l_prefix identifier_type := case
                                  when is_simple_identifier(i_column_name)
                                    then lower(i_column_name)
                                  else i_column_name
                                end;
    l_length pls_integer;
    l_digits pls_integer;

  begin

    case
      when i_data_type in ('VARCHAR2', 'NVARCHAR2', 'CHAR', 'NCHAR', 'VARCHAR') then
        l_length := coalesce(nullif(i_char_length, 0), i_data_length);
        return i_package_name || '.dummy_text(' || quote_literal(l_prefix) || ', ' || l_length || ')';

      when i_data_type in ('CLOB', 'NCLOB', 'LONG') then
        return i_package_name || '.dummy_text(' || quote_literal(l_prefix) || ', 4000)';

      when i_data_type = 'NUMBER' and i_data_precision is not null then
        l_digits := i_data_precision - nvl(i_data_scale, 0);
        if l_digits <= 0 then
          return '0';
        elsif l_digits >= 10 then
          return l_counter;
        end if;
        return 'mod(' || l_counter || ', ' || to_char(power(10, l_digits)) || ')';

      when i_data_type in ('NUMBER', 'FLOAT', 'BINARY_FLOAT', 'BINARY_DOUBLE') then
        return l_counter;

      when i_data_type = 'DATE' then
        return 'trunc(sysdate)';

      when i_data_type like 'TIMESTAMP%' then
        return 'systimestamp';

      when i_data_type like 'INTERVAL DAY%' then
        return 'interval ''0'' second';

      when i_data_type like 'INTERVAL YEAR%' then
        return 'interval ''0'' month';

      when i_data_type = 'RAW' then
        return case when i_data_length >= 16 then 'sys_guid()' else 'hextoraw(''00'')' end;

      when i_data_type = 'BLOB' then
        return 'empty_blob()';

      when i_data_type = 'BOOLEAN' then
        return 'false';

      when i_data_type = 'JSON' then
        return 'json(''{}'')';

      else
        return null;
    end case;

  end dummy_expression;


  ---------------------------------------------------------------------------
  -- Data dictionary
  ---------------------------------------------------------------------------

  -- Functions without parameters in the hand written defaults package
  function get_custom_defaults(
    i_owner varchar2
    ,i_defaults_package varchar2
  ) return t_identifier_set_type as

    l_functions t_identifier_set_type;

  begin

    for r_function in (
      select
        a.object_name
      from
        all_arguments a
      where
        a.owner = i_owner
        and a.package_name = i_defaults_package
      group by
        a.object_name
        ,a.overload
      having
        min(a.position) = 0
        and max(a.position) = 0
    ) loop
      l_functions(r_function.object_name) := true;
    end loop;

    return l_functions;

  end get_custom_defaults;


  function package_exists(
    i_owner varchar2
    ,i_package_name varchar2
  ) return boolean as

    l_count pls_integer;

  begin

    select count(*)
    into l_count
    from all_objects o
    where
      o.owner = i_owner
      and o.object_name = i_package_name
      and o.object_type = 'PACKAGE';

    return l_count > 0;

  end package_exists;


  -- Mandatory foreign key columns -> parent row default
  -- (single column foreign keys only, no self references)
  function get_parent_defaults(
    i_owner varchar2
    ,i_table_name varchar2
  ) return t_parent_map_type as

    l_parents t_parent_map_type;
    l_parent r_parent_type;

  begin

    for r_foreign_key in (
      select
        cc.column_name
        ,rc.owner as parent_owner
        ,rc.table_name as parent_table
        ,rcc.column_name as parent_column
      from
        all_constraints c
        join all_cons_columns cc
          on cc.owner = c.owner
          and cc.constraint_name = c.constraint_name
        join all_tab_cols tc
          on tc.owner = cc.owner
          and tc.table_name = cc.table_name
          and tc.column_name = cc.column_name
        join all_constraints rc
          on rc.owner = c.r_owner
          and rc.constraint_name = c.r_constraint_name
        join all_cons_columns rcc
          on rcc.owner = rc.owner
          and rcc.constraint_name = rc.constraint_name
          and rcc.position = cc.position
      where
        c.owner = i_owner
        and c.table_name = i_table_name
        and c.constraint_type = 'R'
        and c.status = 'ENABLED'
        and tc.nullable = 'N'
        and not (rc.owner = c.owner and rc.table_name = c.table_name)
        and (
          select count(*)
          from all_cons_columns x
          where
            x.owner = c.owner
            and x.constraint_name = c.constraint_name
        ) = 1
      order by
        c.constraint_name
    ) loop
      if not l_parents.exists(r_foreign_key.column_name) then
        l_parent.builder_owner := r_foreign_key.parent_owner;
        l_parent.builder_name := builder_name(r_foreign_key.parent_table);
        l_parent.expression :=
          format_identifier(l_parent.builder_owner)
          || '.' || format_identifier(l_parent.builder_name)
          || '.build_row().' || format_identifier(r_foreign_key.parent_column);
        l_parents(r_foreign_key.column_name) := l_parent;
      end if;
    end loop;

    return l_parents;

  end get_parent_defaults;


  -- Primary key columns that are probably filled by a trigger
  -- (classic "before insert ... :new.id := seq.nextval" pattern): an
  -- enabled before insert row trigger assigns :new.<column>.
  -- They must stay null, a dummy value would bypass the trigger.
  function get_trigger_filled_columns(
    i_owner varchar2
    ,i_table_name varchar2
  ) return t_identifier_set_type as

    l_columns t_identifier_set_type;

  begin

    for r_column in (
      select
        cc.column_name
      from
        all_constraints c
        join all_cons_columns cc
          on cc.owner = c.owner
          and cc.constraint_name = c.constraint_name
      where
        c.owner = i_owner
        and c.table_name = i_table_name
        and c.constraint_type = 'P'
        and exists (
          select null
          from all_triggers t
          where
            t.table_owner = c.owner
            and t.table_name = c.table_name
            and t.status = 'ENABLED'
            and t.trigger_type = 'BEFORE EACH ROW'
            and t.triggering_event like '%INSERT%'
            and exists (
              select null
              from all_trigger_cols tc
              where
                tc.trigger_owner = t.owner
                and tc.trigger_name = t.trigger_name
                and tc.column_name = cc.column_name
                and tc.column_usage like 'NEW%OUT'
            )
        )
    ) loop
      l_columns(r_column.column_name) := true;
    end loop;

    return l_columns;

  end get_trigger_filled_columns;


  function read_table(
    i_table_owner varchar2
    ,i_table_name varchar2
    ,i_package_name varchar2
  ) return r_table_type as

    l_owner constant identifier_type := normalize_name(i_table_owner);
    l_table_name constant identifier_type := normalize_name(i_table_name);
    l_defaults_package constant identifier_type := defaults_name(l_table_name);

    l_table r_table_type;
    l_custom_defaults t_identifier_set_type;
    l_parent_defaults t_parent_map_type;
    l_parent r_parent_type;
    l_trigger_filled t_identifier_set_type;
    l_missing_builders t_identifier_set_type;
    l_missing_builder identifier_type;
    l_missing_list expression_type;
    l_column r_column_type;

  begin

    l_table.owner := format_identifier(l_owner);
    l_table.table_name := format_identifier(l_table_name);
    l_table.defaults_package := format_identifier(l_defaults_package);
    l_table.package_name := format_identifier(
      case
        when i_package_name is not null
          then normalize_name(i_package_name)
        else
          builder_name(l_table_name)
      end
    );

    l_custom_defaults := get_custom_defaults(l_owner, l_defaults_package);
    l_parent_defaults := get_parent_defaults(l_owner, l_table_name);
    l_trigger_filled := get_trigger_filled_columns(l_owner, l_table_name);

    -- data_default is a LONG, hence the cursor loop
    for r_column in (
      select
        c.column_name
        ,c.data_type
        ,c.data_length
        ,c.char_length
        ,c.data_precision
        ,c.data_scale
        ,c.nullable
        ,c.hidden_column
        ,c.data_default
      from
        all_tab_cols c
      where
        c.owner = l_owner
        and c.table_name = l_table_name
        and c.virtual_column = 'NO'
        -- excludes system generated hidden columns (e.g. unused columns),
        -- but keeps invisible columns
        and c.user_generated = 'YES'
        and not exists (
          select null
          from all_tab_identity_cols i
          where
            i.owner = c.owner
            and i.table_name = c.table_name
            and i.column_name = c.column_name
            and i.generation_type = 'ALWAYS'
        )
      order by
        c.column_id nulls last
        ,c.internal_column_id
    ) loop

      l_column := null;
      l_column.identifier := format_identifier(r_column.column_name);
      l_column.in_row := r_column.hidden_column = 'NO';
      l_column.is_lazy := false;

      if l_custom_defaults.exists(r_column.column_name) then
        l_column.default_expression := l_table.owner || '.' || l_table.defaults_package || '.' || l_column.identifier;
      else
        l_column.default_expression := format_table_default(r_column.data_default);
      end if;

      if l_column.default_expression is null
         and l_parent_defaults.exists(r_column.column_name)
      then
        l_parent := l_parent_defaults(r_column.column_name);
        l_column.default_expression := l_parent.expression;
        l_column.is_lazy := true;

        -- only parent builders that are actually used have to exist
        if not package_exists(l_parent.builder_owner, l_parent.builder_name) then
          l_missing_builders(l_parent.builder_owner || '.' || l_parent.builder_name) := true;
        end if;
      end if;

      if l_column.default_expression is null
         and r_column.nullable = 'N'
         and not l_trigger_filled.exists(r_column.column_name)
      then
        l_column.default_expression := dummy_expression(
          i_package_name => l_table.package_name
          ,i_column_name => r_column.column_name
          ,i_data_type => r_column.data_type
          ,i_data_length => r_column.data_length
          ,i_char_length => r_column.char_length
          ,i_data_precision => r_column.data_precision
          ,i_data_scale => r_column.data_scale
        );
      end if;

      l_table.table_columns(l_table.table_columns.count + 1) := l_column;

    end loop;

    if l_table.table_columns.count = 0 then
      raise_application_error(
        -20001
        ,'No insertable columns found for ' || l_owner || '.' || l_table_name
         || '. Does the table exist and is it accessible?'
      );
    end if;

    if l_missing_builders.count > 0 then
      l_missing_builder := l_missing_builders.first;
      while l_missing_builder is not null loop
        l_missing_list := l_missing_list
          || case when l_missing_list is not null then ', ' end
          || l_missing_builder;
        l_missing_builder := l_missing_builders.next(l_missing_builder);
      end loop;

      raise_application_error(
        -20002
        ,'The builder for ' || l_owner || '.' || l_table_name || ' creates parent rows with these builders, '
         || 'which do not exist yet: ' || l_missing_list
         || '. Generate them first or use generate_builder_packages.'
      );
    end if;

    for r_column in (
      select
        c.column_name
      from
        all_tab_cols c
      where
        c.owner = l_owner
        and c.table_name = l_table_name
        and c.hidden_column = 'NO'
      order by
        c.column_id
    ) loop
      l_table.row_columns(l_table.row_columns.count + 1) := format_identifier(r_column.column_name);
    end loop;

    return l_table;

  end read_table;


  ---------------------------------------------------------------------------
  -- Code fragments
  ---------------------------------------------------------------------------

  function get_parameters(
    i_table r_table_type
  ) return clob as

    l_parameters clob;

  begin

    for i in 1 .. i_table.table_columns.count loop
      l_parameters := l_parameters
        || case when i > 1 then gc_newline || '    ,' end
        || i_table.table_columns(i).identifier
        || ' in ' || i_table.owner || '.' || i_table.table_name || '.' || i_table.table_columns(i).identifier || '%type'
        || ' default ' || nvl(i_table.table_columns(i).default_expression, 'null');
    end loop;

    return l_parameters;

  end get_parameters;


  function get_column_list(
    i_table r_table_type
    ,i_prefix varchar2 default null
  ) return clob as

    l_list clob;

  begin

    for i in 1 .. i_table.table_columns.count loop
      l_list := l_list
        || case when i > 1 then gc_newline || '      ,' end
        || i_prefix || i_table.table_columns(i).identifier;
    end loop;

    return l_list;

  end get_column_list;


  function get_returning_list(
    i_table r_table_type
  ) return clob as

    l_list clob;

  begin

    for i in 1 .. i_table.row_columns.count loop
      l_list := l_list
        || case when i > 1 then gc_newline || '      ,' end
        || i_table.row_columns(i);
    end loop;

    return l_list;

  end get_returning_list;


  function get_row_values(
    i_table r_table_type
  ) return clob as

    l_list clob;

  begin

    for i in 1 .. i_table.table_columns.count loop
      l_list := l_list
        || case when i > 1 then gc_newline || '      ,' end
        || case
             when i_table.table_columns(i).in_row
               then 'l_row.' || i_table.table_columns(i).identifier
             -- invisible columns are not part of %rowtype
             else nvl(i_table.table_columns(i).default_expression, 'null')
           end;
    end loop;

    return l_list;

  end get_row_values;


  function get_new_row_defaults(
    i_table r_table_type
  ) return clob as

    l_assignments clob;

  begin

    for i in 1 .. i_table.table_columns.count loop
      if i_table.table_columns(i).in_row
         and not i_table.table_columns(i).is_lazy
         and i_table.table_columns(i).default_expression is not null
      then
        l_assignments := l_assignments
          || 'l_row.' || i_table.table_columns(i).identifier || ' := ' || i_table.table_columns(i).default_expression || ';'
          || gc_newline || '    ';
      end if;
    end loop;

    return l_assignments;

  end get_new_row_defaults;


  function get_row_lazy_defaults(
    i_table r_table_type
  ) return clob as

    l_statements clob;

  begin

    for i in 1 .. i_table.table_columns.count loop
      if i_table.table_columns(i).in_row and i_table.table_columns(i).is_lazy then
        l_statements := l_statements
          || 'if l_row.' || i_table.table_columns(i).identifier || ' is null then' || gc_newline
          || '      l_row.' || i_table.table_columns(i).identifier || ' := ' || i_table.table_columns(i).default_expression || ';' || gc_newline
          || '    end if;' || gc_newline || '    ';
      end if;
    end loop;

    return l_statements;

  end get_row_lazy_defaults;


  function placeholder(
    i_name varchar2
    ,i_value clob
  ) return builder_pattern_templates.r_placeholder_type as

    l_placeholder builder_pattern_templates.r_placeholder_type;

  begin

    l_placeholder.name := i_name;
    l_placeholder.value := i_value;

    return l_placeholder;

  end placeholder;


  function get_placeholders(
    i_table r_table_type
  ) return builder_pattern_templates.t_placeholders_type as
  begin

    return builder_pattern_templates.t_placeholders_type(
      placeholder('OWNER', i_table.owner)
      ,placeholder('TABLE_NAME', i_table.table_name)
      ,placeholder('PACKAGE_NAME', i_table.package_name)
      ,placeholder('DEFAULTS_PACKAGE', i_table.defaults_package)
      ,placeholder('COLUMN_LIST', get_column_list(i_table))
      ,placeholder('BUILD_VALUES', get_column_list(i_table, 'build.'))
      ,placeholder('BUILD_ROW_VALUES', get_column_list(i_table, 'build_row.'))
      ,placeholder('RETURNING_LIST', get_returning_list(i_table))
      ,placeholder('ROW_VALUES', get_row_values(i_table))
      ,placeholder('NEW_ROW_DEFAULTS', get_new_row_defaults(i_table))
      ,placeholder('ROW_LAZY_DEFAULTS', get_row_lazy_defaults(i_table))
      ,placeholder('PARAMETERS', get_parameters(i_table))
    );

  end get_placeholders;


  ---------------------------------------------------------------------------
  -- Public API
  ---------------------------------------------------------------------------

  procedure render_package(
    i_table_owner varchar2
    ,i_table_name varchar2
    ,i_package_name varchar2
    ,o_spec out nocopy clob
    ,o_body out nocopy clob
  ) as

    l_placeholders builder_pattern_templates.t_placeholders_type;

  begin

    l_placeholders := get_placeholders(
      read_table(
        i_table_owner => i_table_owner
        ,i_table_name => i_table_name
        ,i_package_name => i_package_name
      )
    );

    o_spec := builder_pattern_templates.render(builder_pattern_templates.gco_package_spec_source, l_placeholders);
    o_body := builder_pattern_templates.render(builder_pattern_templates.gco_package_body_source, l_placeholders);

  end render_package;


  function generate_builder_package_sql(
    i_table_owner varchar2
    ,i_table_name varchar2
    ,i_package_name varchar2 default null
  ) return clob as

    l_spec clob;
    l_body clob;

  begin

    render_package(i_table_owner, i_table_name, i_package_name, l_spec, l_body);

    -- Runnable as a script (SQL*Plus, SQLcl, SQL Developer)
    return l_spec
      || gc_newline || '/' || gc_newline || gc_newline
      || l_body
      || gc_newline || '/' || gc_newline;

  end generate_builder_package_sql;


  procedure generate_builder_package(
    i_table_owner varchar2
    ,i_table_name varchar2
    ,i_package_name varchar2 default null
  ) as

    l_spec clob;
    l_body clob;

  begin

    render_package(i_table_owner, i_table_name, i_package_name, l_spec, l_body);

    execute immediate l_spec;
    execute immediate l_body;

  end generate_builder_package;


  procedure generate_builder_packages(
    i_table_owner varchar2
    ,i_table_name_like varchar2 default '%'
  ) as

    l_owner constant identifier_type := normalize_name(i_table_owner);
    l_table_name_like constant identifier_type := normalize_name(i_table_name_like);
    l_pending t_identifier_set_type;
    l_table_name identifier_type;
    l_next identifier_type;
    l_progress boolean;

    procedure generate(i_table_name varchar2) is
    begin
      generate_builder_package(
        i_table_owner => '"' || l_owner || '"'
        ,i_table_name => '"' || i_table_name || '"'
      );
      l_pending.delete(i_table_name);
    end generate;

  begin

    for r_table in (
      select
        t.table_name
      from
        all_tables t
      where
        t.owner = l_owner
        and t.table_name like l_table_name_like
        and t.nested = 'NO'
        and t.secondary = 'N'
        and t.dropped = 'NO'
    ) loop
      l_pending(r_table.table_name) := true;
    end loop;

    if l_pending.count = 0 then
      raise_application_error(
        -20003
        ,'No tables found for ' || l_owner || '.' || i_table_name_like
      );
    end if;

    -- Parents first: read_table decides which parent builders a table
    -- actually needs and raises e_missing_builders while one of them does
    -- not exist yet, so such tables are retried in the next pass.
    while l_pending.count > 0 loop

      l_progress := false;
      l_table_name := l_pending.first;

      while l_table_name is not null loop

        l_next := l_pending.next(l_table_name);

        begin
          generate(l_table_name);
          l_progress := true;
        exception
          when e_missing_builders then
            null;
        end;

        l_table_name := l_next;

      end loop;

      -- Cycle of mandatory foreign keys: report the missing builders.
      if not l_progress then
        generate(l_pending.first);
      end if;

    end loop;

  end generate_builder_packages;

end builder_pattern_generator;
/
