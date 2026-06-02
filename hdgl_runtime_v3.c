#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

typedef enum { OMEGA_ROOT = 0, OMEGA_CPU, OMEGA_MEM, OMEGA_IO, OMEGA_GPU, OMEGA_STORAGE } OmegaClass;
typedef enum { OMEGA_STATE_INIT = 0, OMEGA_STATE_DISCOVERED, OMEGA_STATE_CONFIGURED, OMEGA_STATE_READY, OMEGA_STATE_EXECUTED, OMEGA_STATE_MAX } OmegaState;

typedef struct Omega {
    uint64_t id; uint16_t class; uint16_t subtype; uint32_t state;
    uint64_t capabilities; struct Omega* parent; struct Omega* child;
    struct Omega* sibling; uint32_t flags;
} Omega;

typedef struct { const char* source; size_t pos; size_t len; } HDGLParser;

static Omega omega_root;
static Omega omega_devices[256];
static size_t omega_count = 0;

static inline void hdgl_print(const char* str) { printf("%s", str); }

static inline Omega* hdgl_glyph(OmegaClass cls, const char* name) {
    if (omega_count >= 256) return NULL;
    Omega* omega = &omega_devices[omega_count++];
    omega->id = omega_count; omega->class = cls; omega->state = OMEGA_STATE_INIT;
    omega->parent = NULL; omega->child = NULL; omega->sibling = NULL; omega->flags = 0;
    return omega;
}

static inline void hdgl_mutate(Omega* omega, OmegaState new_state) { omega->state = new_state; }

static inline Omega* hdgl_branch(Omega* parent, Omega* child) {
    child->parent = parent;
    if (!parent->child) parent->child = child;
    else {
        Omega* sibling = parent->child;
        while (sibling->sibling) sibling = sibling->sibling;
        sibling->sibling = child;
    }
    child->sibling = NULL;
    return child;
}

static inline void hdgl_recurse(Omega* root, void (*fn)(Omega*)) {
    Omega* current = root->child;
    while (current) { fn(current); current = current->sibling; }
}

static inline void hdgl_skip_whitespace(HDGLParser* p) {
    while (p->pos < p->len && (p->source[p->pos] == ' ' || p->source[p->pos] == '\t' || p->source[p->pos] == '\n' || p->source[p->pos] == '\r')) p->pos++;
}

static inline void hdgl_parse_glyph(HDGLParser* p) {
    char name[64] = {0}; OmegaClass cls = OMEGA_CPU;
    size_t i = 0;
    while (p->pos < p->len && p->source[p->pos] != '\n' && i < 63) name[i++] = p->source[p->pos++];
    name[i] = '\0';
    
    if (strstr(name, "ROOT") != NULL) cls = OMEGA_ROOT;
    else if (strstr(name, "CPU") != NULL) cls = OMEGA_CPU;
    else if (strstr(name, "MEM") != NULL) cls = OMEGA_MEM;
    else if (strstr(name, "IO") != NULL) cls = OMEGA_IO;
    else if (strstr(name, "GPU") != NULL) cls = OMEGA_GPU;
    else if (strstr(name, "STORAGE") != NULL) cls = OMEGA_STORAGE;
    
    Omega* parent = strstr(name, "root") != NULL ? &omega_root : strstr(name, "cpu") != NULL ? &omega_root : strstr(name, "io") != NULL ? &omega_root : NULL;
    Omega* new_glyph = hdgl_glyph(cls, name);
    if (new_glyph && parent) hdgl_branch(parent, new_glyph);
    hdgl_print(name); hdgl_print(": Created [class=");
    if (cls == OMEGA_ROOT) hdgl_print("ROOT"); else if (cls == OMEGA_CPU) hdgl_print("CPU"); else if (cls == OMEGA_MEM) hdgl_print("MEM"); else if (cls == OMEGA_IO) hdgl_print("IO"); else hdgl_print("OTHER");
    hdgl_print("]\n");
}

static inline void hdgl_parse_recurse(HDGLParser* p) {
    char name[64] = {0};
    size_t i = 0;
    while (p->pos < p->len && p->source[p->pos] != '\n' && i < 63) name[i++] = p->source[p->pos++];
    name[i] = '\0';
    
    Omega* found = NULL;
    Omega* current = omega_root.child;
    while (current) { current = current->sibling; }
    
    if (found) {
        hdgl_recurse(found, (void (*)(Omega*))hdgl_mutate);
        hdgl_mutate(found, OMEGA_STATE_DISCOVERED);
        hdgl_print(name); hdgl_print(": recursed and DISCOVERED\n");
    }
}

static inline void hdgl_parse_mutate(HDGLParser* p) {
    static const char* states[] = {"INIT", "DISCOVERED", "CONFIGURED", "READY", "EXECUTED"};
    char state_name[32] = {0};
    size_t i = 0;
    while (p->pos < p->len && p->source[p->pos] != '\n' && i < 31) state_name[i++] = p->source[p->pos++];
    state_name[i] = '\0';
    
    Omega* active = &omega_root;
    for (int s = 0; s < 5; s++) {
        if (strstr(state_name, states[s]) != NULL) {
            hdgl_mutate(active, OMEGA_STATE_INIT + s);
            hdgl_print("mutated to "); hdgl_print(states[s]); hdgl_print("\n");
            break;
        }
    }
}

static inline void hdgl_parse_branch(HDGLParser* p) {
    char parent_name[64] = {0}; char child_name[64] = {0};
    size_t i = 0;
    while (p->pos < p->len && p->source[p->pos] != '\t' && i < 63) parent_name[i++] = p->source[p->pos++];
    parent_name[i] = '\0';
    
    hdgl_skip_whitespace(p);
    
    i = 0;
    while (p->pos < p->len && p->source[p->pos] != '\n' && i < 63) child_name[i++] = p->source[p->pos++];
    child_name[i] = '\0';
    
    OmegaClass child_class = OMEGA_IO;
    if (strstr(child_name, "cpu") != NULL) child_class = OMEGA_CPU;
    if (strstr(child_name, "mem") != NULL) child_class = OMEGA_MEM;
    if (strstr(child_name, "io") != NULL) child_class = OMEGA_IO;
    if (strstr(child_name, "gpu") != NULL) child_class = OMEGA_GPU;
    if (strstr(child_name, "storage") != NULL) child_class = OMEGA_STORAGE;
    
    Omega* child = hdgl_glyph(child_class, child_name);
    if (child) {
        Omega* parent = strstr(parent_name, "root") != NULL ? &omega_root : strstr(parent_name, "cpu") != NULL ? &omega_root : strstr(parent_name, "io") != NULL ? &omega_root : &omega_root;
        if (parent) {
            hdgl_branch(parent, child);
            hdgl_print("branched "); hdgl_print(child_name); hdgl_print(" under "); hdgl_print(parent_name); hdgl_print("\n");
        }
    }
}

void hdgl_runtime_main(const char* source) {
    HDGLParser p; p.source = source; p.pos = 0; p.len = strlen(source);
    
    printf("\nHDGL RUNTIME - Pure Glyph Interpreter\n\n");
    
    while (p.pos < p.len) {
        hdgl_skip_whitespace(&p);
        if (p.pos >= p.len) break;
        
        if (p.source[p.pos] == '#') {
            while (p.pos < p.len && p.source[p.pos] != '\n') p.pos++;
            continue;
        }
        
        if (p.source[p.pos] == 'g') { hdgl_parse_glyph(&p); continue; }
        if (p.source[p.pos] == 'r' && strstr(&p.source[p.pos], "recurse")) { hdgl_parse_recurse(&p); continue; }
        if (p.source[p.pos] == 'm') { 
            if (strstr(&p.source[p.pos], "mutate")) { hdgl_parse_mutate(&p); continue; }
        }
        if (p.source[p.pos] == 'b') { 
            if (strstr(&p.source[p.pos], "branch")) { hdgl_parse_branch(&p); continue; }
        }
        
        p.pos++;
    }
    
    printf("\nHDGL Execution Complete\n");
}

int main(int argc, char* argv[]) {
    if (argc > 1) {
        FILE* fp = fopen(argv[1], "r");
        if (!fp) {
            printf("Error: Cannot open %s\n", argv[1]);
            return 1;
        }
        
        fseek(fp, 0, SEEK_END);
        long filesize = ftell(fp);
        fseek(fp, 0, SEEK_SET);
        
        char* source = malloc(filesize + 1);
        fread(source, 1, filesize, fp);
        source[filesize] = '\0';
        fclose(fp);
        
        printf("Loaded HDGL source: %s (%ld bytes)\n", argv[1], filesize);
        hdgl_runtime_main(source);
        free(source);
    } else {
        omega_root.id = 0; omega_root.class = OMEGA_ROOT; omega_root.state = OMEGA_STATE_INIT;
        
        const char* hdgl_source = "glyph root\nglyph cpu\nbranch cpu memory\nbranch io pci\nrecurse cpu\nmutate discovered\n";
        
        hdgl_runtime_main(hdgl_source);
    }
    
    return 0;
}
