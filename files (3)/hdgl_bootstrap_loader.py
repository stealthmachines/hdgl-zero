with open('hdgl_bootstrap.c') as f: s = f.read()

# Add include for analog engine
old = '#include <string.h>\n#include <stdarg.h>\n'
new = '#include <string.h>\n#include <stdarg.h>\n#include "hdgl_analog_engine.c"\n'
s = s.replace(old, new, 1)

# Add analog run after print graph, before emit
old = ('    /* Print the graph state */\n'
       '    hdgl_print_graph();\n')
new = ('    /* Print the graph state */\n'
       '    hdgl_print_graph();\n'
       '\n'
       '    /* Run analog-over-digital phase */\n'
       '    if (M.graph_size > 1) {\n'
       '        uint64_t ids[256] = {0};\n'
       '        uint32_t types[256] = {0};\n'
       '        uint32_t states[256] = {0};\n'
       '        for (size_t _i = 0; _i < M.graph_size && _i < 256; _i++) {\n'
       '            ids[_i]    = M.graph[_i].identity;\n'
       '            types[_i]  = (uint32_t)M.graph[_i].type;\n'
       '            states[_i] = (uint32_t)M.graph[_i].state;\n'
       '        }\n'
       '        hdgl_analog_run(ids, types, states, M.graph_size, 1);\n'
       '    }\n'
       '\n')

if old in s:
    s = s.replace(old, new, 1)
    print("Analog run integrated")
else:
    print("Pattern not found")
    idx = s.find('hdgl_print_graph()')
    print(repr(s[idx:idx+80]))

with open('hdgl_bootstrap.c', 'w') as f: f.write(s)