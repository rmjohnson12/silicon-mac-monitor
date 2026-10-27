#ifndef SENSOR_BRIDGE_H
#define SENSOR_BRIDGE_H
#include <stdint.h>
#include "NetworkBridge.h"
uint32_t silicon_smc_open(void);
void silicon_smc_close(uint32_t connection);
int silicon_smc_read(uint32_t connection, const char *key, double *value);
typedef struct {
    double value;
    uint32_t data_type;
    uint32_t data_size;
    int32_t status; // 0 success; 1 connection; 2 argument; 3 metadata; 4 size; 5 bytes; 6 format; 7 nonfinite
} SiliconSMCReading;
SiliconSMCReading silicon_smc_probe(uint32_t connection, const char *key);

typedef struct SiliconHID *SiliconHIDRef;
typedef void (*SiliconHIDCallback)(const char *name, double celsius, void *context);
SiliconHIDRef silicon_hid_create(void);
void silicon_hid_destroy(SiliconHIDRef reader);
// Reads only vendor temperature services. Status: 0 success; 1 API unavailable;
// 2 client unavailable; 3 service list unavailable. Missing events are not zeroes.
int silicon_hid_read(SiliconHIDRef reader, SiliconHIDCallback callback, void *context,
                     uint32_t *matched_services, uint32_t *missing_events);
#endif
