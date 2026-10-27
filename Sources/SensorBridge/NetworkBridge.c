#include "NetworkBridge.h"
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <sys/ioctl.h>
#include <net/if.h>
#include <net/if_media.h>
#include <net/route.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int32_t link_active(const char *name) {
    int socket_fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (socket_fd < 0) return -1;
    struct ifmediareq media = {0};
    strlcpy(media.ifm_name, name, sizeof(media.ifm_name));
    int status = ioctl(socket_fd, SIOCGIFMEDIA, &media);
    close(socket_fd);
    if (status != 0 || !(media.ifm_status & IFM_AVALID)) return -1;
    return (media.ifm_status & IFM_ACTIVE) ? 1 : 0;
}

int silicon_network_counters(SiliconNetworkCallback callback, void *context) {
    int mib[] = { CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0 };
    // Interface hotplug can enlarge the list between sizing and reading.
    for (int attempt = 0; attempt < 3; ++attempt) {
        size_t size = 0;
        if (sysctl(mib, 6, NULL, &size, NULL, 0) != 0) return errno;
        if (size == 0) return 0;
        unsigned char *buffer = malloc(size);
        if (!buffer) return ENOMEM;
        if (sysctl(mib, 6, buffer, &size, NULL, 0) != 0) {
            int error = errno; free(buffer);
            if (error == ENOMEM) continue;
            return error;
        }
        size_t offset = 0;
        while (offset < size) {
            if (size - offset < 4) { free(buffer); return EINVAL; }
            uint16_t length; memcpy(&length, buffer + offset, sizeof(length));
            if (length < 4 || length > size - offset) { free(buffer); return EINVAL; }
            if (buffer[offset + 3] == RTM_IFINFO2) {
                if (length < sizeof(struct if_msghdr2)) { free(buffer); return EINVAL; }
                struct if_msghdr2 message;
                memcpy(&message, buffer + offset, sizeof(message));
                char name[IF_NAMESIZE];
                if (callback && if_indextoname(message.ifm_index, name))
                    callback(name, message.ifm_index, (uint32_t)message.ifm_flags, link_active(name),
                             message.ifm_data.ifi_ibytes, message.ifm_data.ifi_obytes, context);
            }
            offset += length;
        }
        free(buffer);
        return 0;
    }
    return ENOMEM;
}
