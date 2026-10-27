#ifndef NETWORK_BRIDGE_H
#define NETWORK_BRIDGE_H
#include <stdint.h>
typedef void (*SiliconNetworkCallback)(const char *name, uint32_t index, uint32_t flags,
                                       int32_t link_active, uint64_t received, uint64_t sent, void *context);
// Local kernel counters only. Returns 0 on success, errno on failure.
int silicon_network_counters(SiliconNetworkCallback callback, void *context);
#endif
