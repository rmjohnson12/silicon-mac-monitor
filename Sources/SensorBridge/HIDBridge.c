// Read-only temperature access using IOHID SPI. Interface reference:
// freedomtan/sensors (BSD-3-Clause); see THIRD_PARTY_NOTICES.md.
#include "SensorBridge.h"
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stdlib.h>
#include <math.h>

struct SiliconHID {
    CFTypeRef client;
    CFTypeRef (*create)(CFAllocatorRef);
    void (*match)(CFTypeRef, CFDictionaryRef);
    CFArrayRef (*services)(CFTypeRef);
    CFTypeRef (*event)(CFTypeRef, int64_t, int32_t, int64_t);
    CFTypeRef (*property)(CFTypeRef, CFStringRef);
    double (*number)(CFTypeRef, int32_t);
};

SiliconHIDRef silicon_hid_create(void) {
    SiliconHIDRef reader = calloc(1, sizeof(*reader));
    if (!reader) return NULL;
    // Resolve SPI at runtime so unavailable symbols disable this reader cleanly.
    reader->create = dlsym(RTLD_DEFAULT, "IOHIDEventSystemClientCreate");
    reader->match = dlsym(RTLD_DEFAULT, "IOHIDEventSystemClientSetMatching");
    reader->services = dlsym(RTLD_DEFAULT, "IOHIDEventSystemClientCopyServices");
    reader->event = dlsym(RTLD_DEFAULT, "IOHIDServiceClientCopyEvent");
    reader->property = dlsym(RTLD_DEFAULT, "IOHIDServiceClientCopyProperty");
    reader->number = dlsym(RTLD_DEFAULT, "IOHIDEventGetFloatValue");
    return reader;
}

void silicon_hid_destroy(SiliconHIDRef reader) {
    if (!reader) return;
    if (reader->client) CFRelease(reader->client);
    free(reader);
}

int silicon_hid_read(SiliconHIDRef r, SiliconHIDCallback callback, void *context,
                     uint32_t *matched_services, uint32_t *missing_events) {
    if (matched_services) *matched_services = 0;
    if (missing_events) *missing_events = 0;
    if (!r || !r->create || !r->match || !r->services || !r->event || !r->property || !r->number) return 1;
    if (!r->client) {
        r->client = r->create(kCFAllocatorDefault);
        if (!r->client) return 2;
        int32_t page = 0xff00, usage = 5;
        CFNumberRef p = CFNumberCreate(NULL, kCFNumberSInt32Type, &page);
        CFNumberRef u = CFNumberCreate(NULL, kCFNumberSInt32Type, &usage);
        const void *keys[] = { CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage") };
        const void *values[] = { p, u };
        CFDictionaryRef match = CFDictionaryCreate(NULL, keys, values, 2,
            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        r->match(r->client, match);
        CFRelease(match); CFRelease(p); CFRelease(u);
    }
    // Keep the client, but discover services each time so wake/reconnection recovers.
    CFArrayRef services = r->services(r->client);
    if (!services) return 3;
    CFIndex count = CFArrayGetCount(services);
    if (matched_services) *matched_services = (uint32_t)count;
    for (CFIndex i = 0; i < count; ++i) {
        CFTypeRef service = CFArrayGetValueAtIndex(services, i);
        CFTypeRef name = r->property(service, CFSTR("Product"));
        // kIOHIDEventTypeTemperature = 15; its level field is 15 << 16.
        CFTypeRef event = r->event(service, 15, 0, 0);
        if (!event && missing_events) ++*missing_events;
        if (name && CFGetTypeID(name) == CFStringGetTypeID()) {
            char text[256];
            if (callback && CFStringGetCString(name, text, sizeof(text), kCFStringEncodingUTF8))
                callback(text, event ? r->number(event, 15 << 16) : NAN, context);
        }
        if (event) CFRelease(event);
        if (name) CFRelease(name);
    }
    CFRelease(services);
    return 0;
}
