// ============================================================================
// k6bus.h — C ABI (PROTOTIPO)
// ============================================================================
//
// Espejo MANUAL de src/core/exports_c.zig.
//
// Zig 0.15.2 NO genera el header con -femit-h (verificado 2026-09-04: los
// simbolos exportados entran en libk6bus.a pero el .h no se emite). Mientras
// tanto este fichero es la contrapartida C de exports_c.zig y debe mantenerse
// en sync a mano (son 3 funciones + codigos de resultado).
//
// exports_c.zig es un prototipo experimental (Directrices seccion 8): la C
// ABI definitiva se disenara de cabo a rabo tras estabilizar la v1 Zig.
// ============================================================================

#ifndef K6BUS_C_H
#define K6BUS_C_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Handle opaco. Internamente apunta a C_Domain (ver exports_c.zig).
struct C_Domain;
typedef struct C_Domain K6B_Domain;

// Codigos de resultado (k6b_domain_send_raw).
enum {
    K6B_OK = 0,
    K6B_ERR_NULL = -1,
    K6B_ERR_ALLOC = -2,
    K6B_ERR_DOMAIN = -3,
    K6B_ERR_SEND = -4,
    K6B_ERR_INVALID_ARG = -5,
};

// Crea un dominio con allocator interno (GPA). Devuelve NULL en error.
K6B_Domain *k6b_domain_create(uint32_t domain_id);

// Cierra el dominio y libera el handle. NULL es no-op.
void k6b_domain_close(K6B_Domain *handle);

// Envia payload crudo por el canal dado (hash interno). Devuelve K6B_OK o un
// K6B_ERR_*.
int k6b_domain_send_raw(
    K6B_Domain *handle,
    const char *channel,
    const uint8_t *data,
    size_t data_len
);

#ifdef __cplusplus
}
#endif

#endif // K6BUS_C_H
