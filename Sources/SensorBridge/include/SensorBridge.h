#ifndef SENSOR_BRIDGE_H
#define SENSOR_BRIDGE_H
#include <stdint.h>
uint32_t silicon_smc_open(void);
void silicon_smc_close(uint32_t connection);
int silicon_smc_read(uint32_t connection, const char *key, double *value);
#endif
