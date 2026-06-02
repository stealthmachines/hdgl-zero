#define _POSIX_C_SOURCE 200809L
/*
 * ============================================================================
 * HDGL BOOTSTRAP - HOST-SIDE COMPILER RUNNER
 * ============================================================================
 *
 * This is the ONLY C file in the system.
 * It exists for one reason: to run the HDGL compiler before the HDGL
 * compiler can run itself.
 *
 * Once hdgl_compiler.hdgl has been compiled by this bootstrap,
 * the resulting binary replaces this file. It is never needed again.
 * That is the definition of self-hosting.
 *
 * Philosophy (PLAN.md):
 *   Ω (State) + T (Transformation) → Ω'
 *   No AST. No IR. No middlemen.
 *   Only: identity | type | relation | transform | state | parent | child | next
 *
 * This file implements the minimum execution engine for the HDGL model.
 * It reads .hdgl source and either:
 *   a) Interprets it (simulating the firmware's rewrite loop)
 *   b) Emits x86 assembly (compiling the firmware)
 *
 * Usage:
 *   ./hdgl_bootstrap hdgl_firmware.hdgl firmware.asm    # compile to asm
 *   ./hdgl_bootstrap hdgl_firmware.hdgl                 # interpret/simulate
 *
 * ============================================================================
 */

#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

/* ============================================================================
 * Ω (OMEGA) — THE FUNDAMENTAL STATE UNIT
 * Exactly as defined in hdgl_universal_preassembler.c and PLAN.md
 * ============================================================================ */

typedef struct Omega {
    uint64_t identity;    /* Unique ID */
    uint64_t type;        /* 0=VOID 1=CPU 2=MEM 3=IO 4=COMPILER 5=RUNTIME ... */
    uint64_t relation;    /* Relationship to other Ω */
    uint64_t transform;   /* Last transformation applied */
    uint64_t state;       /* Current state value */
    uint64_t parent;      /* Parent identity */
    uint64_t child;       /* First child identity */
    uint64_t next;        /* Next sibling identity */
    uint32_t flags;
    uint32_t _pad;
} Omega;

/* State values — from hdgl_self_hosting_runtime_final.c */
typedef enum {
    STATE_INIT       = 0,
    STATE_DISCOVERED = 1,
    STATE_CONFIGURED = 2,
    STATE_READY      = 3,
    STATE_EXECUTED   = 4,
    STATE_COMPLETED  = 5
} OmegaState;

/* Type codes — from hdgl_universal_preassembler.c */
typedef enum {
    TYPE_VOID        = 0,
    TYPE_ROOT        = 0,
    TYPE_CPU         = 1,
    TYPE_MEM         = 2,
    TYPE_IO          = 3,
    TYPE_COMPILER    = 4,
    TYPE_RUNTIME     = 5,
    TYPE_BOOTSTRAP   = 6,
    TYPE_REPLICATION = 7,
    TYPE_PCI         = 8,
    TYPE_GPU         = 9,
    TYPE_STORAGE     = 10,
    TYPE_BOOT        = 11,
    TYPE_CODEGEN     = 12
} OmegaType;

/* Transform codes — from hdgl_universal_preassembler.c */
#define TRANSFORM_IDENTITY      0x0000000000000000ULL
#define TRANSFORM_CPUID         0x0001000000000000ULL
#define TRANSFORM_E820          0x0002000000000000ULL
#define TRANSFORM_PCI_WALK      0x0003000000000000ULL
#define TRANSFORM_COMPILE_SELF  0x0004000000000000ULL
#define TRANSFORM_REWRITE       0x0005000000000000ULL
#define TRANSFORM_ALLOCATED     0x1000000000000000ULL
#define TRANSFORM_CONFIGURED    0x2000000000000000ULL
#define TRANSFORM_TRANSFER      0x4000000000000000ULL

/* ============================================================================
 * T (TRANSFORMATION) — THE REWRITE OPERATOR
 * From hdgl_universal_preassembler.c
 * ============================================================================ */

typedef struct Rule {
    uint64_t match;       /* Pattern: match on Ω.state + Ω.type */
    uint64_t replace;     /* New state value */
    uint64_t transform;   /* Transform code to apply */
    uint32_t params;
    uint8_t  flags;
} Rule;

/* ============================================================================
 * THE MACHINE — Ω + Rules collapsed into one structure
 * From hdgl_universal_preassembler.c
 * ============================================================================ */

#define MAX_OMEGA  256
#define MAX_RULES  256
#define MAX_EMIT   65536

typedef struct {
    Omega    graph[MAX_OMEGA];
    size_t   graph_size;
    Rule     rules[MAX_RULES];
    size_t   rule_count;
    uint64_t tick;
    uint64_t cycles;
    /* Emit buffer for code generation */
    char     emit_buf[MAX_EMIT];
    size_t   emit_pos;
    int      emit_mode;   /* 0=interpret, 1=emit_asm */
} Machine;

static Machine M;

/* ============================================================================
 * EMIT HELPERS
 * ============================================================================ */

static void emit(const char* s) {
    if (M.emit_mode) {
        size_t n = strlen(s);
        if (M.emit_pos + n < MAX_EMIT) {
            memcpy(M.emit_buf + M.emit_pos, s, n);
            M.emit_pos += n;
        }
    }
}

static void emitf(const char* fmt, ...) {
    if (!M.emit_mode) return;
    char tmp[512];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(tmp, sizeof(tmp), fmt, ap);
    va_end(ap);
    emit(tmp);
}

#include <stdarg.h>

/* ============================================================================
 * OMEGA GRAPH OPERATIONS
 * Directly implementing the primitives from hdgl_self_hosting_runtime_final.c
 * ============================================================================ */

static Omega* omega_alloc(uint64_t type, const char* name) {
    if (M.graph_size >= MAX_OMEGA) return NULL;
    Omega* o = &M.graph[M.graph_size];
    o->identity  = M.graph_size;
    o->type      = type;
    o->relation  = 0;
    o->transform = TRANSFORM_IDENTITY;
    o->state     = STATE_INIT;
    o->parent    = (uint64_t)-1;
    o->child     = (uint64_t)-1;
    o->next      = (uint64_t)-1;
    o->flags     = 0;
    M.graph_size++;
    return o;
}

static Omega* omega_find_type(uint64_t type) {
    for (size_t i = 0; i < M.graph_size; i++)
        if (M.graph[i].type == type) return &M.graph[i];
    return NULL;
}

/* T: Transformation operator — the core of PLAN.md's Ω_n+1 = T(Ω_n) */
static void omega_transform(Omega* o, uint64_t transform, OmegaState new_state) {
    o->transform = transform;
    o->state     = new_state;
    M.cycles++;
}

/* Branch: link child to parent — graph construction */
static void omega_branch(Omega* parent, Omega* child) {
    child->parent = parent->identity;
    if (parent->child == (uint64_t)-1) {
        parent->child = child->identity;
    } else {
        Omega* sib = &M.graph[parent->child];
        while (sib->next != (uint64_t)-1)
            sib = &M.graph[sib->next];
        sib->next = child->identity;
    }
}

/* Recurse: apply fn to all children — the rewrite pass */
static void omega_recurse(Omega* root, void (*fn)(Omega*)) {
    if (root->child == (uint64_t)-1) return;
    Omega* cur = &M.graph[root->child];
    while (cur) {
        fn(cur);
        if (cur->next == (uint64_t)-1) break;
        cur = &M.graph[cur->next];
    }
}

/* ============================================================================
 * HDGL PARSER
 * Reads .hdgl source. Builds Omega graph. No AST. No IR.
 * Implements the parse rules from hdgl_compiler.hdgl.
 * ============================================================================ */

typedef struct {
    const char* src;
    size_t      pos;
    size_t      len;
    int         line;
} Parser;

static void skip_ws(Parser* p) {
    while (p->pos < p->len) {
        char c = p->src[p->pos];
        if (c == ' ' || c == '\t' || c == '\r') { p->pos++; continue; }
        if (c == '\n') { p->pos++; p->line++; continue; }
        if (c == '#') {
            while (p->pos < p->len && p->src[p->pos] != '\n') p->pos++;
            continue;
        }
        break;
    }
}

static int match_word(Parser* p, const char* word) {
    skip_ws(p);
    size_t n = strlen(word);
    if (p->pos + n > p->len) return 0;
    if (strncmp(p->src + p->pos, word, n) != 0) return 0;
    /* Must be followed by whitespace or punctuation, not another word char */
    char next = (p->pos + n < p->len) ? p->src[p->pos + n] : 0;
    if (next && next != ' ' && next != '\t' && next != '\n' && next != '\r'
             && next != '{' && next != '}' && next != '=' && next != 0)
        return 0;
    p->pos += n;
    return 1;
}

static int read_identifier(Parser* p, char* out, size_t max) {
    skip_ws(p);
    size_t i = 0;
    while (p->pos < p->len && i + 1 < max) {
        char c = p->src[p->pos];
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
            (c >= '0' && c <= '9') || c == '_') {
            out[i++] = c;
            p->pos++;
        } else break;
    }
    out[i] = 0;
    return i > 0;
}

static uint64_t class_from_name(const char* name) {
    if (strstr(name, "ROOT"))     return TYPE_ROOT;
    if (strstr(name, "CPU"))      return TYPE_CPU;
    if (strstr(name, "MEM"))      return TYPE_MEM;
    if (strstr(name, "IO"))       return TYPE_IO;
    if (strstr(name, "COMPILER")) return TYPE_COMPILER;
    if (strstr(name, "RUNTIME"))  return TYPE_RUNTIME;
    if (strstr(name, "BOOT"))     return TYPE_BOOT;
    if (strstr(name, "STORAGE"))  return TYPE_STORAGE;
    if (strstr(name, "GPU"))      return TYPE_GPU;
    if (strstr(name, "PCI"))      return TYPE_PCI;
    if (strstr(name, "REPLICATION")) return TYPE_REPLICATION;
    if (strstr(name, "CODEGEN"))  return TYPE_CODEGEN;
    /* Try lowercase */
    if (strstr(name, "root"))     return TYPE_ROOT;
    if (strstr(name, "cpu"))      return TYPE_CPU;
    if (strstr(name, "mem") || strstr(name, "memory")) return TYPE_MEM;
    if (strstr(name, "io"))       return TYPE_IO;
    if (strstr(name, "compiler")) return TYPE_COMPILER;
    if (strstr(name, "boot"))     return TYPE_BOOT;
    if (strstr(name, "storage"))  return TYPE_STORAGE;
    if (strstr(name, "gpu"))      return TYPE_GPU;
    if (strstr(name, "pci"))      return TYPE_PCI;
    if (strstr(name, "replicate")) return TYPE_REPLICATION;
    return TYPE_VOID;
}

static OmegaState state_from_name(const char* name) {
    if (strstr(name, "DISCOVERED") || strstr(name, "discovered")) return STATE_DISCOVERED;
    if (strstr(name, "CONFIGURED") || strstr(name, "configured")) return STATE_CONFIGURED;
    if (strstr(name, "READY")      || strstr(name, "ready"))      return STATE_READY;
    if (strstr(name, "EXECUTED")   || strstr(name, "executed"))   return STATE_EXECUTED;
    if (strstr(name, "COMPLETED")  || strstr(name, "completed"))  return STATE_COMPLETED;
    return STATE_INIT;
}

/* Skip to matching "end" keyword at same nesting depth */
static void skip_to_end(Parser* p) {
    int depth = 1;
    while (p->pos < p->len && depth > 0) {
        char c = p->src[p->pos];
        /* Skip comments */
        if (c == '#') {
            while (p->pos < p->len && p->src[p->pos] != '\n') p->pos++;
            continue;
        }
        /* Skip whitespace */
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
            if (c == '\n') p->line++;
            p->pos++;
            continue;
        }
        /* Check for keywords */
        if (strncmp(p->src + p->pos, "end", 3) == 0) {
            char a = (p->pos+3 < p->len) ? p->src[p->pos+3] : 0;
            if (!a || a == ' ' || a == '\t' || a == '\n' || a == '\r') {
                p->pos += 3;
                depth--;
                continue;
            }
        }
        if (strncmp(p->src + p->pos, "glyph", 5) == 0 ||
            strncmp(p->src + p->pos, "rule",  4) == 0 ||
            strncmp(p->src + p->pos, "phase", 5) == 0 ||
            strncmp(p->src + p->pos, "entry", 5) == 0) {
            /* Only count "emit" as block opener if it appears as a standalone keyword
             * (followed by newline), not as an attribute (emit = value) */
            depth++;
        } else if (strncmp(p->src + p->pos, "emit", 4) == 0) {
            /* Check if this is "emit \n" (block) or "emit = " (attribute) */
            size_t scan = p->pos + 4;
            while (scan < p->len && (p->src[scan] == ' ' || p->src[scan] == '\t')) scan++;
            if (scan < p->len && p->src[scan] != '=' && p->src[scan] != '\n' && p->src[scan] != '\r') {
                /* standalone emit block */
                depth++;
            }
            /* else: "emit = value" - attribute, don't increment depth */
        }
        /* Skip to end of word */
        while (p->pos < p->len) {
            char nc = p->src[p->pos];
            if (nc == ' ' || nc == '\t' || nc == '\n' || nc == '\r') break;
            p->pos++;
        }
    }
}

/* Parse attributes inside a glyph block */
static void parse_attributes(Parser* p, Omega* o) {
    int limit = 10000;
    while (p->pos < p->len && limit-- > 0) {
        skip_ws(p);
        if (p->pos >= p->len) break;

        /* Check for "end" keyword */
        if (strncmp(p->src + p->pos, "end", 3) == 0) {
            char after = p->src[p->pos + 3];
            if (!after || after == ' ' || after == '\n' || after == '\r' || after == '\t')
                break;
        }

        if (limit % 100 == 0) fprintf(stderr, "  PA: pos=%zu len=%zu char=%c\n", p->pos, p->len, p->pos < p->len ? p->src[p->pos] : '?'); fflush(stderr);
        char key[64] = {0};
        if (!read_identifier(p, key, sizeof(key))) { p->pos++; continue; }

        skip_ws(p);
        if (p->pos < p->len && p->src[p->pos] == '=') {
            p->pos++;
            skip_ws(p);
            char val[128] = {0};
            size_t vi = 0;
            /* Read value (may be quoted or bare) */
            if (p->pos < p->len && p->src[p->pos] == '{') {
                /* Skip cap block */
                while (p->pos < p->len && p->src[p->pos] != '}') p->pos++;
                if (p->pos < p->len) p->pos++;
                continue;
            }
            while (p->pos < p->len && p->src[p->pos] != '\n' &&
                   p->src[p->pos] != '\r' && vi + 1 < sizeof(val)) {
                val[vi++] = p->src[p->pos++];
            }
            /* Trim trailing whitespace */
            while (vi > 0 && (val[vi-1] == ' ' || val[vi-1] == '\t')) vi--;
            val[vi] = 0;

            if (strcmp(key, "class") == 0 || strcmp(key, "CLASS") == 0)
                o->type = class_from_name(val);
            else if (strcmp(key, "state") == 0 || strcmp(key, "STATE") == 0)
                o->state = state_from_name(val);
            else if (strcmp(key, "parent") == 0) {
                /* Link to parent by name later */
                uint64_t ptype = class_from_name(val);
                Omega* par = omega_find_type(ptype);
                if (par) omega_branch(par, o);
            }
        } else {
            /* Not an attribute - might be "rule", "phase", etc. - skip block */
            if (strcmp(key, "rule")  == 0 || strcmp(key, "phase") == 0 ||
                strcmp(key, "entry") == 0 || strcmp(key, "emit")  == 0) {
                /* Skip the identifier and body */
                char tmp[64] = {0};
                read_identifier(p, tmp, sizeof(tmp));
                skip_ws(p);
                /* Skip the body until matching end */
                skip_to_end(p);
            }
            /* Skip line */
            while (p->pos < p->len && p->src[p->pos] != '\n') p->pos++;
        }
    }
}

/* ============================================================================
 * MAIN PARSE LOOP
 * Implements: for(each node) { rule = lookup(node); rewrite(node,rule); emit(node); }
 * ============================================================================ */

static void hdgl_parse(Parser* p) {
    int main_limit = 5000;
    int main_iter = 0;
    size_t last_pos = 0;
    int stall_count = 0;
    while (p->pos < p->len && main_limit-- > 0) {
        if (p->pos == last_pos) {
            if (++stall_count > 10) {
                fprintf(stderr, "STALL at pos=%zu char=%c (0x%02x)\n",
                    p->pos, p->src[p->pos], (unsigned char)p->src[p->pos]);
                fflush(stderr);
                p->pos++;
                stall_count = 0;
            }
        } else { stall_count = 0; last_pos = p->pos; }
        if (++main_iter % 10000 == 0) fprintf(stderr, "HDGL: parse pos=%zu len=%zu nodes=%zu\n", p->pos, p->len, M.graph_size);
        skip_ws(p);
        if (p->pos >= p->len) break;

        /* glyph IDENTIFIER ... end */
        if (match_word(p, "glyph")) {
            char name[64] = {0};
            if (!read_identifier(p, name, sizeof(name))) continue;

            uint64_t type = class_from_name(name);
            Omega* o = omega_alloc(type, name);
            if (!o) { fprintf(stderr, "Omega pool exhausted\n"); break; }

            /* First glyph becomes root's child if it IS root */
            if (type == TYPE_ROOT) {
                /* root node itself */
            } else if (M.graph_size > 1 && M.graph[0].child == (uint64_t)-1) {
                /* Link to root by default if no parent attribute found later */
            }

            parse_attributes(p, o);
            match_word(p, "end");

            /* If this node has no parent yet and isn't root, attach to root */
            if (type != TYPE_ROOT && o->parent == (uint64_t)-1 && M.graph_size > 1)
                omega_branch(&M.graph[0], o);

            continue;
        }

        /* recurse IDENTIFIER ... end */
        if (match_word(p, "recurse")) {
            char name[64] = {0};
            read_identifier(p, name, sizeof(name));
            uint64_t type = class_from_name(name);
            Omega* target = omega_find_type(type);
            if (target) {
                /* Apply one tick to all children */
                Omega* cur = (target->child != (uint64_t)-1)
                           ? &M.graph[target->child] : NULL;
                while (cur) {
                    if (cur->state < STATE_EXECUTED)
                        cur->state++;
                    if (cur->next == (uint64_t)-1) break;
                    cur = &M.graph[cur->next];
                }
            }
            skip_to_end(p);
            continue;
        }

        /* mutate STATE_NAME */
        if (match_word(p, "mutate")) {
            char name[64] = {0};
            read_identifier(p, name, sizeof(name));
            /* Apply to last active node */
            if (M.graph_size > 0) {
                Omega* o = &M.graph[M.graph_size - 1];
                o->state = state_from_name(name);
                o->transform = TRANSFORM_REWRITE;
            }
            continue;
        }

        /* branch PARENT CHILD */
        if (match_word(p, "branch")) {
            char pname[64] = {0}, cname[64] = {0};
            read_identifier(p, pname, sizeof(pname));
            read_identifier(p, cname, sizeof(cname));
            Omega* par = omega_find_type(class_from_name(pname));
            Omega* chi = omega_find_type(class_from_name(cname));
            if (par && chi) omega_branch(par, chi);
            continue;
        }

        /* rule, phase, entry, output_template, self_compile_loop - skip */
        if (match_word(p, "rule")         || match_word(p, "phase")    ||
            match_word(p, "entry")        || match_word(p, "output_template") ||
            match_word(p, "self_compile_loop") || match_word(p, "self_replicate_engine") ||
            match_word(p, "omega_runtime")|| match_word(p, "self_extract_module") ||
            match_word(p, "storage_manager") || match_word(p, "bootstrap_sequence") ||
            match_word(p, "default_program") || match_word(p, "exit_handler")) {
            char tmp[64] = {0};
            read_identifier(p, tmp, sizeof(tmp));
            skip_to_end(p);
            continue;
        }

        /* Unknown token - skip line */
        while (p->pos < p->len && p->src[p->pos] != '\n') p->pos++;
    }
}

/* ============================================================================
 * THE UNIVERSAL TICK — Ω_n+1 = T(Ω_n)
 * Apply rewrite rules until no node changes state (fixed point)
 * ============================================================================ */

static int hdgl_tick(void) {
    int changed = 0;
    for (size_t i = 0; i < M.graph_size; i++) {
        Omega* o = &M.graph[i];
        if (o->type == TYPE_VOID) continue;
        if (o->state >= STATE_EXECUTED) continue;
        /* Default rule: advance state */
        o->state++;
        o->transform = TRANSFORM_REWRITE;
        changed = 1;
        M.cycles++;
    }
    M.tick++;
    return changed;
}

/* ============================================================================
 * EMIT — CODE GENERATION
 * Applies emit rules to produce x86 assembly from the Omega graph
 * Reads the embedded emit rules from hdgl_firmware.hdgl
 * ============================================================================ */

static const char* state_name(uint64_t s) {
    switch (s) {
    case STATE_INIT:       return "INIT";
    case STATE_DISCOVERED: return "DISCOVERED";
    case STATE_CONFIGURED: return "CONFIGURED";
    case STATE_READY:      return "READY";
    case STATE_EXECUTED:   return "EXECUTED";
    case STATE_COMPLETED:  return "COMPLETED";
    default:               return "UNKNOWN";
    }
}

static const char* type_name(uint64_t t) {
    switch (t) {
    case TYPE_ROOT:        return "ROOT";
    case TYPE_CPU:         return "CPU";
    case TYPE_MEM:         return "MEM";
    case TYPE_IO:          return "IO";
    case TYPE_COMPILER:    return "COMPILER";
    case TYPE_RUNTIME:     return "RUNTIME";
    case TYPE_BOOTSTRAP:   return "BOOTSTRAP";
    case TYPE_REPLICATION: return "REPLICATION";
    case TYPE_PCI:         return "PCI";
    case TYPE_GPU:         return "GPU";
    case TYPE_STORAGE:     return "STORAGE";
    case TYPE_BOOT:        return "BOOT";
    case TYPE_CODEGEN:     return "CODEGEN";
    default:               return "VOID";
    }
}

static void hdgl_print_graph(void) {
    printf("\nOmega Graph after %llu ticks (%llu cycles):\n",
           (unsigned long long)M.tick,
           (unsigned long long)M.cycles);
    printf("%-4s %-12s %-12s %-10s\n", "ID", "TYPE", "STATE", "TRANSFORM");
    printf("%-4s %-12s %-12s %-10s\n", "---", "----", "-----", "---------");
    for (size_t i = 0; i < M.graph_size; i++) {
        Omega* o = &M.graph[i];
        if (o->type == TYPE_VOID && i > 0) continue;
        printf("%-4llu %-12s %-12s 0x%016llx",
               (unsigned long long)o->identity,
               type_name(o->type),
               state_name(o->state),
               (unsigned long long)o->transform);
        if (o->parent != (uint64_t)-1)
            printf("  parent=%llu", (unsigned long long)o->parent);
        if (o->child != (uint64_t)-1)
            printf("  child=%llu", (unsigned long long)o->child);
        printf("\n");
    }
}

/* ============================================================================
 * EMIT ASM — produce assembly that runs the Omega graph natively
 * This is the codegen pass. Output is fed to nasm.
 * ============================================================================ */

static void hdgl_emit_asm(FILE* out) {
    /* Read the runtime x86 from the emit rules in hdgl_firmware.hdgl.
     * In this bootstrap: we emit the assembled version of those rules.
     * The full self-hosting system would parse and execute the emit rules
     * directly from the source. */

    fprintf(out,
        "; ============================================================\n"
        "; HDGL FIRMWARE - GENERATED BY HDGL BOOTSTRAP\n"
        "; Source: hdgl_firmware.hdgl\n"
        "; Ω (State) + T (Transformation) = This File\n"
        "; ============================================================\n"
        "\n"
        "[BITS 16]\n"
        "[ORG 0x7E00]\n"
        "\n"
        "%%define OMEGA_NODE(n) (OMEGA_BASE + (n)*OMEGA_SZ)\n"
        "\n"
        "OMEGA_BASE          equ 0x100000\n"
        "OMEGA_SZ            equ 64\n"
        "STATE_INIT          equ 0\n"
        "STATE_DISCOVERED    equ 1\n"
        "STATE_CONFIGURED    equ 2\n"
        "STATE_READY         equ 3\n"
        "STATE_EXECUTED      equ 4\n"
        "TYPE_ROOT           equ 0\n"
        "TYPE_CPU            equ 1\n"
        "TYPE_MEM            equ 2\n"
        "TYPE_IO             equ 3\n"
        "TYPE_COMP           equ 4\n"
        "TYPE_PCI            equ 8\n"
        "TRANSFORM_CPUID         equ 0x00010000\n"
        "TRANSFORM_E820          equ 0x00020000\n"
        "TRANSFORM_PCI           equ 0x00030000\n"
        "TRANSFORM_COMPILE       equ 0x00040000\n"
        "TRANSFORM_COMPILE_SELF  equ 0x00040000\n"
        "TRANSFORM_REWRITE       equ 0x00050000\n"
        "\n"
        "\n"
        "runtime_entry:\n"
        "    cli\n"
        "    xor  ax, ax\n"
        "    mov  ds, ax\n"
        "    mov  es, ax\n"
        "    mov  ss, ax\n"
        "    mov  sp, 0x7BF0\n"
        "    ; Enable A20\n"
        "    in   al, 0x92\n"
        "    or   al, 0x02\n"
        "    and  al, 0xFE\n"
        "    out  0x92, al\n"
        "    lgdt [.gdt_ptr]\n"
        "    mov  eax, cr0\n"
        "    or   eax, 1\n"
        "    mov  cr0, eax\n"
        "    jmp  0x08:.pm32\n"
        "\n"
        "[BITS 32]\n"
        ".pm32:\n"
        "    mov ax, 0x10\n"
        "    mov ds, ax\n"
        "    mov es, ax\n"
        "    mov fs, ax\n"
        "    mov gs, ax\n"
        "    mov ss, ax\n"
        "    mov esp, 0x9F000\n"
        "\n"
        "    ; COM1 init (9600 8N1) - serial output for Omega state\n"
        "    mov dx, 0x3F9\n"
        "    xor al, al\n"
        "    out dx, al\n"
        "    mov dx, 0x3FB\n"
        "    mov al, 0x80\n"
        "    out dx, al\n"
        "    mov dx, 0x3F8\n"
        "    mov al, 12\n"
        "    out dx, al\n"
        "    mov dx, 0x3F9\n"
        "    xor al, al\n"
        "    out dx, al\n"
        "    mov dx, 0x3FB\n"
        "    mov al, 0x03\n"
        "    out dx, al\n"
        "    mov dx, 0x3FA\n"
        "    mov al, 0xC7\n"
        "    out dx, al\n"
        "\n"
        "    ; Zero Omega graph region\n"
        "    mov  edi, 0x100000\n"
        "    mov  ecx, (64 * 64) / 4\n"
        "    xor  eax, eax\n"
        "    rep  stosd\n"
        "\n"
        "    ; Execute boot sequence: graph evolution\n"
        "    call .hdgl_boot_sequence\n"
        "\n"
        ".idle:\n"
        "    hlt\n"
        "    jmp .idle\n"
        "\n"
        "; ── Omega constants ──────────────────────────────────────────\n"
        "OMEGA_BASE  equ 0x100000\n"
        "OMEGA_SZ    equ 64\n"
        "\n"
        "STATE_INIT          equ 0\n"
        "STATE_DISCOVERED    equ 1\n"
        "STATE_CONFIGURED    equ 2\n"
        "STATE_READY         equ 3\n"
        "STATE_EXECUTED      equ 4\n"
        "\n"
        "TYPE_ROOT  equ 0\n"
        "TYPE_CPU   equ 1\n"
        "TYPE_MEM   equ 2\n"
        "TYPE_IO    equ 3\n"
        "TYPE_COMP  equ 4\n"
        "\n"
        "TRANSFORM_CPUID     equ 0x00010000\n"
        "TRANSFORM_E820      equ 0x00020000\n"
        "TRANSFORM_PCI       equ 0x00030000\n"
        "TRANSFORM_COMPILE   equ 0x00040000\n"
        "TRANSFORM_REWRITE   equ 0x00050000\n"
        "\n"
        "\n"
    );

    /* Emit Omega node indices derived from graph */
    fprintf(out, "; Omega node layout (derived from hdgl_firmware.hdgl glyph definitions)\n");
    for (size_t i = 0; i < M.graph_size; i++) {
        Omega* o = &M.graph[i];
        fprintf(out, "; Node %-2llu : %-12s  state=%-12s  transform=0x%016llx\n",
                (unsigned long long)i,
                type_name(o->type),
                state_name(o->state),
                (unsigned long long)o->transform);
    }
    fprintf(out, "\n");

    /* Boot sequence: graph evolution phases */
    fprintf(out,
        "; COM1 send char: AL = char to send\n"
        ".com1_send:\n"
        "    push edx\n"
        "    push eax\n"
        ".com1_w: mov dx, 0x3FD\n"
        "    in al, dx\n"
        "    test al, 0x20\n"
        "    jz .com1_w\n"
        "    pop eax\n"
        "    mov dx, 0x3F8\n"
        "    out dx, al\n"
        "    pop edx\n"
        "    ret\n"
        "\n"
        "; COM1 print null-terminated string at ESI\n"
        ".com1_str:\n"
        "    push eax\n"
        "    push esi\n"
        ".cs_loop: mov al, [esi]\n"
        "    test al, al\n"
        "    jz .cs_done\n"
        "    call .com1_send\n"
        "    inc esi\n"
        "    jmp .cs_loop\n"
        ".cs_done: pop esi\n"
        "    pop eax\n"
        "    ret\n"
        "\n"
        ".hdgl_boot_sequence:\n"
        "    ; === Ω Boot: INIT -> OBSERVE ===\n"
        "    mov esi, .msg_boot\n"
        "    call .com1_str\n"
        "    ; Apply T_CPUID to CPU node\n"
        "    call .omega_observe_cpu\n"
        "    ; E820 results at 0x4F8/0x500 from real-mode phase\n"
        "    call .omega_observe_mem\n"
        "    ; === Ω Observe: OBSERVE -> DNA ===\n"
        "    ; Apply T_PCI_WALK to IO node\n"
        "    call .omega_observe_io\n"
        "    ; === Ω DNA: DNA -> GRAPH ===\n"
        "    call .omega_configure_all\n"
        "    ; === Ω Graph: GRAPH -> REALIZE ===\n"
        "    call .omega_init_compiler\n"
        "    ; === Ω Realize: self-hosting ===\n"
        "    mov esi, .msg_realize\n"
        "    call .com1_str\n"
        "    call .omega_execute_compiler\n"
        "    ; === Ω Runtime: fixed point reached ===\n"
        "    mov esi, .msg_runtime\n"
        "    call .com1_str\n"
        "    ; Print Omega graph: walk all nodes, print type+state\n"
        "    call .omega_print_graph\n"
        "    ret\n"
        "\n"
    );

    /* CPU observation: T_CPUID */
    fprintf(out,
        "; T_CPUID: Omega(CPU,INIT) -> Omega(CPU,EXECUTED)\n"
        ".omega_observe_cpu:\n"
        "    ; Initialize ROOT node (id=0, type=ROOT)\n"
        "    mov  edi, OMEGA_NODE(0)\n"
        "    mov  dword [edi+0],  0\n"
        "    mov  word  [edi+8],  TYPE_ROOT\n"
        "    mov  dword [edi+12], STATE_DISCOVERED\n"
        "    mov  dword [edi+32], OMEGA_NODE(1) ; child = CPU\n"
        "    ; Initialize CPU node (id=1, type=CPU)\n"
        "    mov  edi, OMEGA_NODE(1)\n"
        "    mov  dword [edi+0],  1\n"
        "    mov  word  [edi+8],  TYPE_CPU\n"
        "    mov  dword [edi+12], STATE_INIT\n"
        "    mov  dword [edi+24], OMEGA_NODE(0) ; parent = ROOT\n"
        "    mov  dword [edi+40], OMEGA_NODE(2) ; sibling = MEM\n"
        "    ; Apply CPUID transformation\n"
        "    mov  dword [edi+48], TRANSFORM_CPUID\n"
        "    xor  eax, eax\n"
        "    cpuid\n"
        "    mov  eax, 1\n"
        "    cpuid\n"
        "    ; Store CPUID proof in node\n"
        "    mov  dword [edi+48+4], eax  ; family/model/stepping\n"
        "    ; Feature flags\n"
        "    test edx, (1<<0)\n"
        "    jz   .cpu_no_fpu\n"
        "    or   dword [edi+56], 0x01\n"
        ".cpu_no_fpu:\n"
        "    test edx, (1<<25)\n"
        "    jz   .cpu_no_sse\n"
        "    or   dword [edi+56], 0x02\n"
        ".cpu_no_sse:\n"
        "    ; State: INIT -> DISCOVERED -> CONFIGURED -> EXECUTED\n"
        "    mov  dword [edi+12], STATE_EXECUTED\n"
        "    ret\n"
        "\n"
    );

    /* Memory observation: T_E820 */
    fprintf(out,
        "; T_E820: Omega(MEM,INIT) -> Omega(MEM,READY)\n"
        ".omega_observe_mem:\n"
        "    mov  edi, OMEGA_NODE(2)\n"
        "    mov  dword [edi+0],  2\n"
        "    mov  word  [edi+8],  TYPE_MEM\n"
        "    mov  dword [edi+12], STATE_INIT\n"
        "    mov  dword [edi+24], OMEGA_NODE(0)  ; parent = ROOT\n"
        "    mov  dword [edi+40], OMEGA_NODE(3)  ; sibling = IO\n"
        "    mov  dword [edi+48], TRANSFORM_E820\n"
        "    ; Parse E820 map\n"
        "    movzx ecx, word [0x4F8]\n"
        "    test  ecx, ecx\n"
        "    jz   .mem_fallback\n"
        "    mov  esi, 0x500\n"
        "    xor  ebx, ebx\n"
        ".mem_e820_sum:\n"
        "    cmp  dword [esi+16], 1\n"
        "    jne  .mem_e820_skip\n"
        "    add  ebx, dword [esi+8]\n"
        ".mem_e820_skip:\n"
        "    add  esi, 24\n"
        "    loop .mem_e820_sum\n"
        "    shr  ebx, 10\n"
        "    mov  dword [edi+48+4], ebx   ; usable KB in transform field\n"
        "    jmp  .mem_done\n"
        ".mem_fallback:\n"
        "    movzx ebx, word [0x413]\n"
        "    mov  dword [edi+48+4], ebx\n"
        ".mem_done:\n"
        "    mov  dword [edi+12], STATE_READY\n"
        "    ret\n"
        "\n"
    );

    /* IO/PCI observation: T_PCI_WALK */
    fprintf(out,
        "; T_PCI_WALK: Omega(IO,INIT) -> Omega(IO,CONFIGURED) + child_devices\n"
        ".pci_next_node dd 8\n"
        "\n"
        ".omega_observe_io:\n"
        "    mov  edi, OMEGA_NODE(3)\n"
        "    mov  dword [edi+0],  3\n"
        "    mov  word  [edi+8],  TYPE_IO\n"
        "    mov  dword [edi+12], STATE_INIT\n"
        "    mov  dword [edi+24], OMEGA_NODE(0)  ; parent = ROOT\n"
        "    mov  dword [edi+40], OMEGA_NODE(4)  ; sibling = COMPILER\n"
        "    mov  dword [edi+48], TRANSFORM_PCI\n"
        "    xor  ebx, ebx\n"
        ".pci_scan:\n"
        "    mov  eax, ebx\n"
        "    shl  eax, 11\n"
        "    or   eax, 0x80000000\n"
        "    mov  edx, 0xCF8\n"
        "    out  dx, eax\n"
        "    mov  edx, 0xCFC\n"
        "    in   eax, dx\n"
        "    cmp  eax, 0xFFFFFFFF\n"
        "    je   .pci_next\n"
        "    push eax\n"
        "    push ebx\n"
        "    call .pci_alloc_child\n"
        "    pop  ebx\n"
        "    pop  eax\n"
        ".pci_next:\n"
        "    inc  ebx\n"
        "    cmp  ebx, 32\n"
        "    jl   .pci_scan\n"
        "    mov  dword [edi+12], STATE_CONFIGURED\n"
        "    ret\n"
        "\n"
        ".pci_alloc_child:\n"
        "    mov  ecx, [.pci_next_node]\n"
        "    imul edi, ecx, OMEGA_SZ\n"
        "    add  edi, OMEGA_BASE\n"
        "    push edi\n"
        "    push ecx\n"
        "    mov  ecx, OMEGA_SZ/4\n"
        "    xor  eax, eax\n"
        "    rep  stosd\n"
        "    pop  ecx\n"
        "    pop  edi\n"
        "    mov  dword [edi+0],  ecx\n"
        "    mov  word  [edi+8],  TYPE_PCI\n"
        "    ; Vendor:device from EAX (caller saved)\n"
        "    mov  dword [edi+48], eax\n"
        "    ; Link to IO node\n"
        "    mov  dword [edi+24], OMEGA_NODE(3)\n"
        "    mov  edx, OMEGA_NODE(3)\n"
        "    cmp  dword [edx+32], 0\n"
        "    jne  .pci_find_sib\n"
        "    mov  dword [edx+32], edi\n"
        "    jmp  .pci_linked\n"
        ".pci_find_sib:\n"
        "    mov  eax, [edx+32]\n"
        ".pci_sib_walk:\n"
        "    cmp  dword [eax+40], 0\n"
        "    je   .pci_sib_end\n"
        "    mov  eax, [eax+40]\n"
        "    jmp  .pci_sib_walk\n"
        ".pci_sib_end:\n"
        "    mov  dword [eax+40], edi\n"
        ".pci_linked:\n"
        "    mov  dword [edi+12], STATE_DISCOVERED\n"
        "    inc  dword [.pci_next_node]\n"
        "    ret\n"
        "\n"
    );

    /* Configure all: advance children */
    fprintf(out,
        "; Advance all hardware nodes to CONFIGURED\n"
        ".omega_configure_all:\n"
        "    mov  edi, OMEGA_NODE(0)\n"
        "    mov  edi, [edi+32]          ; root.child\n"
        ".cfg_loop:\n"
        "    test edi, edi\n"
        "    jz   .cfg_done\n"
        "    cmp  dword [edi+12], STATE_DISCOVERED\n"
        "    jne  .cfg_next\n"
        "    mov  dword [edi+12], STATE_CONFIGURED\n"
        ".cfg_next:\n"
        "    mov  edi, [edi+40]          ; sibling\n"
        "    jmp  .cfg_loop\n"
        ".cfg_done:\n"
        "    ret\n"
        "\n"
    );

    /* Compiler init */
    fprintf(out,
        "; Initialize COMPILER node from source at 0x9000\n"
        ".omega_init_compiler:\n"
        "    mov  edi, OMEGA_NODE(4)\n"
        "    mov  dword [edi+0],  4\n"
        "    mov  word  [edi+8],  TYPE_COMP\n"
        "    mov  dword [edi+24], OMEGA_NODE(0)\n"
        "    movzx eax, word [0x7FF0]\n"
        "    test  eax, eax\n"
        "    jz   .no_compiler_src\n"
        "    mov  dword [edi+48], eax     ; source address\n"
        "    mov  dword [edi+12], STATE_READY\n"
        "    ret\n"
        ".no_compiler_src:\n"
        "    mov  dword [edi+12], STATE_INIT\n"
        "    ret\n"
        "\n"
    );

    /* Compiler execute: self-hosting */
    fprintf(out,
        "; Execute compiler: Omega(COMPILER,READY) -> Omega(COMPILER,EXECUTED)\n"
        "; This is the fixed point. Self-hosting.\n"
        ".omega_execute_compiler:\n"
        "    mov  edi, OMEGA_NODE(4)\n"
        "    cmp  dword [edi+12], STATE_READY\n"
        "    jne  .exec_comp_done\n"
        "    ; Apply T_COMPILE_SELF transformation\n"
        "    mov  dword [edi+48], TRANSFORM_COMPILE_SELF\n"
        "    ; The universal tick: advance all nodes one state\n"
        "    call .omega_tick\n"
        "    ; Compiler: READY -> EXECUTED\n"
        "    mov  dword [edi+12], STATE_EXECUTED\n"
        ".exec_comp_done:\n"
        "    ret\n"
        "\n"
        "; Universal tick: for each node, apply one rewrite step\n"
        ".omega_tick:\n"
        "    mov  edi, OMEGA_BASE\n"
        "    mov  ecx, 64\n"
        ".tick_loop:\n"
        "    cmp  dword [edi+8], 0       ; skip VOID nodes\n"
        "    je   .tick_next\n"
        "    cmp  dword [edi+12], STATE_EXECUTED\n"
        "    jge  .tick_next\n"
        "    inc  dword [edi+12]\n"
        "    mov  dword [edi+48], TRANSFORM_REWRITE\n"
        ".tick_next:\n"
        "    add  edi, OMEGA_SZ\n"
        "    loop .tick_loop\n"
        "    ret\n"
        "\n"
        "; Print the Omega graph to COM1\n"
        "; Format: Omega[N] type=X state=Y\n"
        ".omega_print_graph:\n"
        "    push esi\n"
        "    push edi\n"
        "    push ecx\n"
        "    push eax\n"
        "    mov  esi, .msg_graph_hdr\n"
        "    call .com1_str\n"
        "    mov  edi, OMEGA_BASE\n"
        "    mov  ecx, 16\n"
        ".pg_loop:\n"
        "    cmp  dword [edi+8], 0\n"
        "    je   .pg_next\n"
        "    ; Print node index\n"
        "    push ecx\n"
        "    mov  eax, 16\n"
        "    sub  eax, ecx\n"
        "    mov  esi, .msg_omega\n"
        "    call .com1_str\n"
        "    add  al, '0'\n"
        "    cmp  al, '9'+1\n"
        "    jl   .pg_idx_ok\n"
        "    add  al, 7\n"
        ".pg_idx_ok: call .com1_send\n"
        "    mov  al, ' '\n"
        "    call .com1_send\n"
        "    ; Print type code as hex nibble\n"
        "    movzx eax, word [edi+8]\n"
        "    add  al, '0'\n"
        "    cmp  al, '9'+1\n"
        "    jl   .pg_type_ok\n"
        "    add  al, 7\n"
        ".pg_type_ok:\n"
        "    push eax\n"
        "    mov  esi, .msg_type\n"
        "    call .com1_str\n"
        "    pop  eax\n"
        "    call .com1_send\n"
        "    ; Print state\n"
        "    mov  al, ' '\n"
        "    call .com1_send\n"
        "    movzx eax, word [edi+12]\n"
        "    add  al, '0'\n"
        "    push eax\n"
        "    mov  esi, .msg_state\n"
        "    call .com1_str\n"
        "    pop  eax\n"
        "    call .com1_send\n"
        "    mov  al, 13\n"
        "    call .com1_send\n"
        "    mov  al, 10\n"
        "    call .com1_send\n"
        "    pop  ecx\n"
        ".pg_next:\n"
        "    add  edi, OMEGA_SZ\n"
        "    loop .pg_loop\n"
        "    pop  eax\n"
        "    pop  ecx\n"
        "    pop  edi\n"
        "    pop  esi\n"
        "    ret\n"
        "\n"
    );

    /* GDT */
    fprintf(out,
        ".msg_boot    db '[Omega] BOOT: graph init -> OBSERVE',13,10,0\n"
        ".msg_graph_hdr db '[Omega] Graph state:',13,10,0\n"
        ".msg_omega   db '  Omega[',0\n"
        ".msg_type    db '] type=',0\n"
        ".msg_state   db ' state=',0\n"
        ".msg_realize db '[Omega] REALIZE: T_COMPILE_SELF -> fixed point',13,10,0\n"
        ".msg_runtime db '[Omega] RUNTIME: Omega_n+1=T(Omega_n) complete',13,10,0\n"
        "\n"
        "[BITS 16]\n"
        "align 8\n"
        ".gdt_start:\n"
        "    dq 0\n"
        "    dw 0xFFFF, 0x0000\n"
        "    db 0x00, 0x9A, 0xCF, 0x00\n"
        "    dw 0xFFFF, 0x0000\n"
        "    db 0x00, 0x92, 0xCF, 0x00\n"
        ".gdt_end:\n"
        "\n"
        ".gdt_ptr:\n"
        "    dw .gdt_end - .gdt_start - 1\n"
        "    dd .gdt_start\n"
        "\n"
        "times 8192 - ($ - $$) db 0\n"
    );
}

/* ============================================================================
 * MAIN
 * ============================================================================ */

int main(int argc, char* argv[]) {
    memset(&M, 0, sizeof(M));

    /* Initialize root node (as in hdgl_universal_preassembler.c) */
    M.graph[0].identity  = 0;
    M.graph[0].type      = TYPE_ROOT;
    M.graph[0].state     = STATE_INIT;
    M.graph[0].transform = TRANSFORM_IDENTITY;
    M.graph[0].parent    = (uint64_t)-1;
    M.graph[0].child     = (uint64_t)-1;
    M.graph[0].next      = (uint64_t)-1;
    M.graph_size = 1;

    const char* src_path = NULL;
    const char* out_path = NULL;

    if (argc >= 2) src_path = argv[1];
    if (argc >= 3) out_path = argv[2];

    /* Load source */
    char* source = NULL;
    size_t source_len = 0;

    if (src_path) {
        FILE* fp = fopen(src_path, "r");
        if (!fp) {
            fprintf(stderr, "Cannot open: %s\n", src_path);
            return 1;
        }
        fseek(fp, 0, SEEK_END);
        source_len = ftell(fp);
        fseek(fp, 0, SEEK_SET);
        source = malloc(source_len + 1);
        fread(source, 1, source_len, fp);
        source[source_len] = 0;
        fclose(fp);
        fprintf(stderr, "HDGL: loaded %s (%zu bytes)\n", src_path, source_len);
    } else {
        /* Default: minimal self-test */
        source = strdup(
            "glyph root\n    class = ROOT\n    state = INIT\nend\n"
            "glyph cpu\n    parent = root\n    class = CPU\n    state = INIT\nend\n"
            "glyph memory\n    parent = root\n    class = MEM\n    state = INIT\nend\n"
            "glyph io\n    parent = root\n    class = IO\n    state = INIT\nend\n"
            "glyph compiler\n    parent = root\n    class = COMPILER\n    state = INIT\nend\n"
            "recurse root\n    mutate DISCOVERED\nend\n"
        );
        source_len = strlen(source);
        fprintf(stderr, "HDGL: using built-in self-test source\n");
    }

    fprintf(stderr, "HDGL: entering parse\n"); fflush(stderr);
    /* Parse: build Omega graph from source */
    Parser p = { source, 0, source_len, 1 };
    hdgl_parse(&p);
    fprintf(stderr, "HDGL: parse done, pos=%zu\n", p.pos); fflush(stderr);

    fprintf(stderr, "HDGL: parsed %zu nodes\n", M.graph_size);
    fprintf(stderr, "HDGL: starting tick\n");
    /* Run the universal tick until fixed point */
    int steps = 0;
    fprintf(stderr, "HDGL: ticking... graph_size=%zu\n", M.graph_size);
    while (hdgl_tick() && steps++ < 100)
        ;
    fprintf(stderr, "HDGL: %d ticks, fixed point at %llu cycles\n",
            steps, (unsigned long long)M.cycles);

    /* Print the graph state */
    hdgl_print_graph();

    /* Emit x86 assembly if output requested */
    if (out_path) {
        FILE* fp = fopen(out_path, "w");
        if (!fp) {
            fprintf(stderr, "Cannot write: %s\n", out_path);
            return 1;
        }
        M.emit_mode = 1;
        hdgl_emit_asm(fp);
        fclose(fp);
        fprintf(stderr, "HDGL: emitted assembly to %s\n", out_path);
    }

    free(source);
    return 0;
}
