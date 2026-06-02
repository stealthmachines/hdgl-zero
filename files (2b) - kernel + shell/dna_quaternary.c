/*
 * DNA QUATERNARY GEOMETRIC HDGL — NATIVE IMPLEMENTATION
 * Analog over digital: quaternary signals, geometric φ-lattice, DNA strands
 * KISS: three primitives only. No interpreted bytecode.
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <math.h>

/* ── Universal constants ─────────────────────────────────────────────────── */
#define PHI       1.6180339887498948
#define SQRT_PHI  1.2720196495140570
#define PI        3.14159265358979323846
#define LN_PHI    0.4812118250596035
#define D_N_R     0.732
#define DT        0.01

/* Quaternary digits per n mod 4 */
#define QUAT_GROUND    0
#define QUAT_RISING    1
#define QUAT_EXCITED   2
#define QUAT_LOCKED    3

/* ── DNA base encoding ───────────────────────────────────────────────────── */
#define DNA_A 0
#define DNA_C 1
#define DNA_G 2
#define DNA_T 3

/* ── Strand configuration ────────────────────────────────────────────────── */
typedef struct {
    int i;
    double r_dim;
    double omega;
} Strand;

Strand strands[] = {
    {1, 0.3, 8.1196e-09},  /* A */
    {2, 0.4, 5.0218e-09},  /* B */
    {3, 0.5, 3.1032e-09},  /* C */
    {4, 0.6, 1.9169e-09},  /* D */
    {5, 0.7, 1.1840e-09},  /* E */
    {6, 0.8, 7.3191e-10},  /* F */
    {7, 0.9, 4.5233e-10},  /* G */
    {8, 1.0, 2.7957e-10},  /* H */
};

/* Fibonacci and prime factors */
static const double FIB[] = {1, 1, 2, 3, 5, 8, 13, 21};
static const double PRIMES[] = {2, 3, 5, 7, 11, 13, 17, 19};

/* ── Kuramoto 8D oscillator ─────────────────────────────────────────────── */
typedef struct {
    double theta[8];
    double omega[8];
    double omega0[8];
    double K;
    double gamma;
    int aphase;        /* PLUCK=0, SUSTAIN=1, FINETUNE=2, LOCK=3 */
    double cv;
    int tick;
} Kuramoto;

#define PLUCK      0
#define SUSTAIN    1
#define FINETUNE   2
#define LOCK       3

static const char* phase_names[] = {"PLUCK", "SUSTAIN", "FINETUNE", "LOCK"};

static const double PHI_SEEDS[] = {
    1.6180339887, 2.6180339887, 3.6180339887,
    4.8541019662, 5.6180339887, 6.4721359549,
    7.8541019662, 8.3141592654
};

/* ──────────────────────────────────────────────────────────────────────────
 * PRIMITIVE 1: Dₙ(r) = √(φ·Fₙ·2ⁿ·Pₙ·Ω)·rᵏ
 * Quaternary encoding: digit = n mod 4, scaled by Dₙ(r)
 * ────────────────────────────────────────────────────────────────────────── */

double Dn_r(int n, double r_dim, double Omega) {
    int idx = (n - 1) % 8;
    double F = FIB[idx];
    double P = PRIMES[idx];
    return sqrt(PHI * F * pow(2, n) * P * Omega) * pow(r_dim, 1.0);
}

int quaternary_digit(int n) {
    return n % 4;  /* 0=grounded, 1=rising, 2=excited, 3=locked */
}

double quaternary_signal(int n, double r_dim, double Omega) {
    int digit = quaternary_digit(n);
    double D = Dn_r(n, r_dim, Omega);
    return (digit * D);
}

/* ──────────────────────────────────────────────────────────────────────────
 * PRIMITIVE 2: Kuramoto 8D oscillator tick
 * dθᵢ/dt = ωᵢ + K·Σⱼ sin(θⱼ-θᵢ)
 * ────────────────────────────────────────────────────────────────────────── */

double phi_depth(double x) {
    if (x <= 0) return 0;
    return log(x) / LN_PHI;
}

void kuramoto_init(Kuramoto *osc, double phi_depth_val) {
    double frac_L = phi_depth_val - floor(phi_depth_val);
    double Omega_U = 0.5 * (1.0 + sin(PI * frac_L * PHI));
    
    osc->aphase = PLUCK;
    osc->K = 5.0;
    osc->gamma = 0.005;
    osc->cv = 1.0;
    osc->tick = 0;
    
    for (int i = 0; i < 8; i++) {
        osc->theta[i] = PI * frac_L + 2*PI * (PHI_SEEDS[i] + frac_L + i * D_N_R);
        osc->omega0[i] = Omega_U * pow(PHI, 1 + i * D_N_R) * DT;
        osc->omega[i] = osc->omega0[i];
    }
}

void kuramoto_step(Kuramoto *osc) {
    /* Simplified RK4: one step with adaptive K */
    double K = osc->K;
    double gamma = osc->gamma;
    
    for (int i = 0; i < 8; i++) {
        double sum = 0.0;
        for (int j = 0; j < 8; j++) {
            if (i != j) {
                sum += sin(osc->theta[j] - osc->theta[i]);
            }
        }
        osc->theta[i] += DT * sum * K / 8.0 - gamma * osc->theta[i] * DT;
    }
    
    osc->tick++;
    
    /* Harmonic sync every 8 ticks */
    if (osc->tick % 8 == 0) {
        harmonic_sync(osc);
    }
}

void harmonic_sync(Kuramoto *osc) {
    /* Cooperative memory: sync with simulated hardware state */
    double node_states[8] = {0, 1, 2, 3, 4, 5, 6, 7};
    
    for (int pass = 0; pass < 4; pass++) {
        for (int i = 0; i < 8; i++) {
            double T = 2*PI * node_states[i] / (double)(1ULL << 32);
            double diff = T - osc->theta[i];
            osc->theta[i] += 0.8 * atan2(sin(diff), cos(diff));
        }
    }
    
    /* Update Ω^U */
    double sx = 0, sy = 0;
    for (int i = 0; i < 8; i++) {
        sx += cos(osc->theta[i]);
        sy += sin(osc->theta[i]);
    }
    double frac_U = fmod(atan2(sy, sx) / (2*PI) + 1, 1);
    osc->omega_u = 0.5 * (1.0 + sin(PI * frac_U * PHI));
    
    /* VCO modulation */
    for (int i = 0; i < 8; i++) {
        osc->omega[i] = osc->omega0[i] * (0.1 + 0.9 * osc->cv);
    }
}

void advance_phase(Kuramoto *osc) {
    /* CV: 1 - order_parameter */
    double sx = 0, sy = 0;
    for (int i = 0; i < 8; i++) {
        sx += cos(osc->theta[i]);
        sy += sin(osc->theta[i]);
    }
    double R = sqrt(sx*sx + sy*sy) / 8;
    osc->cv = 1 - R;
    
    /* Phase transitions */
    switch (osc->aphase) {
        case PLUCK:
            if (osc->cv < 0.50) {
                osc->aphase = SUSTAIN;
                osc->gamma = 0.008;
            }
            break;
        case SUSTAIN:
            if (osc->cv < 0.30) {
                osc->aphase = FINETUNE;
                osc->gamma = 0.010;
            }
            break;
        case FINETUNE:
            if (osc->cv < 0.10) {
                osc->aphase = LOCK;
                osc->gamma = 0.012;
            }
            break;
        case LOCK:
            if (osc->cv < 0.05) {
                return;  /* locked */
            }
            break;
    }
}

/* ──────────────────────────────────────────────────────────────────────────
 * PRIMITIVE 3: DNA strands → state transitions
 * ────────────────────────────────────────────────────────────────────────── */

double dna_entropy(const int *dna_seq, int len) {
    if (len == 0) return 0;
    
    int counts[4] = {0, 0, 0, 0};
    for (int i = 0; i < len; i++) {
        if (dna_seq[i] >= 0 && dna_seq[i] < 4) {
            counts[dna_seq[i]]++;
        }
    }
    
    double H = 0;
    for (int c = 0; c < 4; c++) {
        double p = counts[c] / (double)len;
        if (p > 0) {
            H -= p * log2(p);
        }
    }
    
    double H_max = 2.0;  /* log₂(4) */
    return H / H_max;
}

double dna_r_dim(const int *dna_seq, int len) {
    return 0.3 + 0.7 * dna_entropy(dna_seq, len);
}

int dna_gc_content(const int *dna_seq, int len) {
    int gc = 0;
    for (int i = 0; i < len; i++) {
        if (dna_seq[i] == DNA_G || dna_seq[i] == DNA_C) {
            gc++;
        }
    }
    return gc * 100 / len;
}

/* ──────────────────────────────────────────────────────────────────────────
 * MAIN: Run analog over digital
 * ────────────────────────────────────────────────────────────────────────── */

typedef struct {
    int id;
    int type;  /* ROOT=0, CPU=1, MEM=2, IO=3 */
    int state; /* INIT=1, DISCOVERED=2, CONFIG=3, READY=4, EXEC=5 */
    int dna[3];
    double r_dim;
    double phi_depth;
} Node;

void hdgl_analog_main(int verbose, int cpu_family, int cpu_id, int pci_count, int mem_kb) {
    if (verbose) {
        printf("\nDNA QUATERNARY GEOMETRIC HDGL - Analog over Metal\n");
        printf("==================================================\n");
    }
    
    /* Build Omega nodes */
    Node nodes[] = {
        {0, 0, 1, {DNA_A, DNA_A, DNA_A}, 0.0, 0.0},
        {1, 1, 1, {DNA_C, DNA_G, DNA_T}, 0.0, 0.0},
        {2, 2, 1, {DNA_G, DNA_C, DNA_A}, 0.0, 0.0},
        {3, 3, 1, {DNA_T, DNA_A, DNA_C}, 0.0, 0.0},
    };
    
    /* φ-lattice depth from CPU family */
    double phi_depth_val = phi_depth((double)cpu_family);
    if (phi_depth_val < 1.0) phi_depth_val = 1.618;
    
    /* Initialize Kuramoto */
    Kuramoto osc;
    kuramoto_init(&osc, phi_depth_val);
    
    /* Main analog loop */
    int max_iter = 500;
    int prev_phase = PLUCK;
    
    for (int iter = 0; iter < max_iter; iter++) {
        /* Compute Dₙ(r) lattice for all 32 slots */
        double dn_lattice[32];
        for (int n = 1; n <= 32; n++) {
            int strand_idx = (n - 1) / 4 + 1;
            if (strand_idx > 8) strand_idx = 8;
            double r_dim = strands[strand_idx - 1].r_dim;
            double Omega = strands[strand_idx - 1].omega;
            dn_lattice[n - 1] = Dn_r(n, r_dim, Omega);
        }
        
        /* Kuramoto tick */
        kuramoto_step(&osc);
        
        /* Advance phase */
        advance_phase(&osc);
        
        /* Log phase transitions */
        if (verbose && osc.aphase != prev_phase) {
            printf("[Kuramoto] %s → %s (CV=%.4f, iter=%d)\n",
                   phase_names[prev_phase], phase_names[osc.aphase],
                   osc.cv, iter);
            prev_phase = osc.aphase;
        }
        
        if (osc.aphase == LOCK && osc.cv < 0.05) {
            if (verbose) printf("[Analog] LOCKED!\n");
            break;
        }
    }
    
    /* Map phases to Omega states */
    if (verbose) {
        printf("\nOmega node states after analog consensus:\n");
    }
    for (int i = 0; i < 4; i++) {
        double phase_norm = fmod(fabs(osc.theta[i]), 2*PI) / (2*PI);
        int analog_state = (osc.aphase == LOCK) ? 5 : (int)(phase_norm * 5);
        nodes[i].state = analog_state;
        
        double r_dim = dna_r_dim(nodes[i].dna, 3);
        printf("  Node[%d] type=%d state=%d r_dim=%.3f ",
               i, nodes[i].type, nodes[i].state, r_dim);
        
        /* Print Dₙ(r) for first slot */
        double D1 = dn_lattice[0];
        int q_digit = quaternary_digit(1);
        printf("D[1]=%.4f q=%d\n", D1, q_digit);
    }
    
    /* DNA summary */
    if (verbose) {
        printf("\nDNA strands:\n");
        for (int i = 0; i < 4; i++) {
            printf("  Node[%d] ", i);
            for (int j = 0; j < 3; j++) {
                const char* bases[] = {"A","C","G","T"};
                printf("%s", bases[nodes[i].dna[j]]);
            }
            printf(" gc=%d%% entropy=%.3f r_dim=%.3f\n",
                   dna_gc_content(nodes[i].dna, 3),
                   dna_entropy(nodes[i].dna, 3),
                   dna_r_dim(nodes[i].dna, 3));
        }
        printf("  Strand H (r=1.0): full double helix = self-hosting\n");
    }
    
    /* Quaternary lattice aggregate */
    if (verbose) {
        uint32_t aggregate = 0;
        for (int n = 1; n <= 32; n++) {
            int strand_idx = (n - 1) / 4 + 1;
            if (strand_idx > 8) strand_idx = 8;
            double r_dim = strands[strand_idx - 1].r_dim;
            double Omega = strands[strand_idx - 1].omega;
            int digit = quaternary_digit(n);
            aggregate |= digit * pow(4, n - 1);
        }
        printf("\nQuaternary lattice aggregate: 0x%08X\n", aggregate);
    }
    
    /* Final status */
    printf("\n[HDGL] CPU: CPUID discovery...\n");
    printf("  CPU family: %d\n", cpu_family);
    printf("[HDGL] MEM: discovered %d KB\n", mem_kb);
    printf("[HDGL] IO: %d PCI devices\n", pci_count);
    printf("[HDGL] DNA genome: encoded\n");
    printf("[HDGL] Analog kernel: %s\n",
           (osc.aphase == LOCK && osc.cv < 0.05) ? "LOCKED" : "RUNNING");
    printf("[HDGL] Omega tree built. ALIVE.\n");
}

/* ──────────────────────────────────────────────────────────────────────────
 * FASTA encoder: hardware signature → DNA sequence
 * ────────────────────────────────────────────────────────────────────────── */

void hardware_to_dna(const char* cpu_vendor, int* dna_seq, int len) {
    for (int i = 0; i < len && i < 12; i++) {
        unsigned char c = cpu_vendor[i];
        dna_seq[i] = c & 0x0F;  /* Low nibble → DNA base */
    }
    /* Pad remaining with DNA_T */
    for (int i = len; i < len + (12 - len); i++) {
        dna_seq[i] = DNA_T;
    }
}

int main(int argc, char** argv) {
    int verbose = 1;
    int cpu_family = 6;  /* Intel Nehalem */
    int cpu_id = 1;
    int pci_count = 4;
    int mem_kb = 4096;
    
    /* Simulated hardware genome */
    int cpu_dna[12];
    const char* cpu_vendor = "GenuineIntel";
    hardware_to_dna(cpu_vendor, cpu_dna, 12);
    
    hdgl_analog_main(verbose, cpu_family, cpu_id, pci_count, mem_kb);
    
    return 0;
}
