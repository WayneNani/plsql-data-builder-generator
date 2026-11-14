create or replace package body builder_pattern_templates as

  function render(
    i_template clob
    ,i_placeholders t_placeholders_type
  ) return clob as

    l_source clob := i_template;

  begin

    for i in 1 .. i_placeholders.count loop
      l_source := replace(l_source, '#' || i_placeholders(i).name || '#', i_placeholders(i).value);
    end loop;

    return l_source;

  end render;

end builder_pattern_templates;
/
