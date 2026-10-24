// Read-only AppleSMC transport. Protocol layout informed by MIT-licensed
// beltex/SMCKit; see THIRD_PARTY_NOTICES.md. No write operations are implemented.
#include "SensorBridge.h"
#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <string.h>
#include <math.h>

typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } SMCVersion;
typedef struct { uint16_t version, length; uint32_t cpu, gpu, memory; } SMCLimits;
typedef struct { uint32_t size, type; uint8_t attributes; } SMCKeyInfo;
typedef struct {
    uint32_t key;
    SMCVersion version;
    SMCLimits limits;
    SMCKeyInfo info;
    uint8_t result, status, command;
    uint32_t index;
    uint8_t bytes[32];
} SMCMessage;
_Static_assert(sizeof(SMCMessage) == 80, "SMC protocol requires an 80-byte message");

static uint32_t fourcc(const char *s) {
    return ((uint32_t)(uint8_t)s[0] << 24) | ((uint32_t)(uint8_t)s[1] << 16) |
           ((uint32_t)(uint8_t)s[2] << 8) | (uint8_t)s[3];
}
static int exchange(uint32_t connection, SMCMessage *input, SMCMessage *output) {
    size_t size = sizeof(*output);
    kern_return_t result = IOConnectCallStructMethod(connection, 2, input, sizeof(*input), output, &size);
    return result == KERN_SUCCESS && size == sizeof(*output) && output->result == 0;
}
uint32_t silicon_smc_open(void) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return 0;
    io_connect_t connection = 0;
    kern_return_t status = IOServiceOpen(service, mach_task_self(), 0, &connection);
    IOObjectRelease(service);
    return status == KERN_SUCCESS ? connection : 0;
}
void silicon_smc_close(uint32_t connection) { if (connection) IOServiceClose(connection); }
int silicon_smc_read(uint32_t connection, const char *key, double *value) {
    if (!connection || !key || strlen(key) != 4 || !value) return 0;
    SMCMessage request = {0}, info = {0}, output = {0};
    request.key = fourcc(key);
    request.command = 9; // Read key metadata
    if (!exchange(connection, &request, &info) || info.info.size == 0 || info.info.size > 32) return 0;
    request.info.size = info.info.size;
    request.command = 5; // Read key bytes
    if (!exchange(connection, &request, &output)) return 0;
    uint8_t *b = output.bytes;
    if (info.info.type == fourcc("flt ") && info.info.size == 4) {
        float f; memcpy(&f, b, 4); *value = f;
    } else if (info.info.type == fourcc("sp78") && info.info.size == 2) {
        *value = (double)(int16_t)((b[0] << 8) | b[1]) / 256.0;
    } else if (info.info.type == fourcc("fpe2") && info.info.size == 2) {
        *value = (double)((b[0] << 8) | b[1]) / 4.0;
    } else if (info.info.type == fourcc("ui8 ") && info.info.size == 1) {
        *value = b[0];
    } else { return 0; }
    return isfinite(*value);
}
