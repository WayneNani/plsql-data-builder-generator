create or replace package body builder_pattern_templates as

  function render(
    i_template clob
    ,i_placeholders t_placeholders_type
  ) return clob as

    l_result clob;
    l_position pls_integer := 1;
    l_start pls_integer;
    l_end pls_integer;
    l_name varchar2(30);
    l_found pls_integer;

  begin

    loop
      l_start := instr(i_template, '#', l_position);
      exit when l_start = 0;
      l_end := instr(i_template, '#', l_start + 1);
      exit when l_end = 0;

      l_found := null;
      if l_end - l_start - 1 between 1 and 30 then
        l_name := substr(i_template, l_start + 1, l_end - l_start - 1);
        for i in 1 .. i_placeholders.count loop
          if i_placeholders(i).name = l_name then
            l_found := i;
            exit;
          end if;
        end loop;
      end if;

      if l_found is null then
        -- not a placeholder: keep the "#" and continue after it
        l_result := l_result || substr(i_template, l_position, l_start - l_position + 1);
        l_position := l_start + 1;
      else
        l_result := l_result
          || substr(i_template, l_position, l_start - l_position)
          || i_placeholders(l_found).value;
        l_position := l_end + 1;
      end if;
    end loop;

    return l_result || substr(i_template, l_position);

  end render;

end builder_pattern_templates;
/
