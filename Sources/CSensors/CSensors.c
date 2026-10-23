#include "CSensors.h"
#include <string.h>
#include <stdio.h>
#include <ctype.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>

// ---------------------------------------------------------------------------
// Sıcaklık — IOHIDEventSystemClient (özel API, IOKit'ten zayıf bağlanır)
// ---------------------------------------------------------------------------
typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern void IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef match);
extern CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
extern CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef property);
extern IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timestamp);
extern double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

#define kIOHIDEventTypeTemperature 15
#define FIELD_BASE(t) ((t) << 16)

static IOHIDEventSystemClientRef gTempClient = NULL;

static CFDictionaryRef makeMatch(int page, int usage) {
    CFNumberRef p = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &page);
    CFNumberRef u = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &usage);
    const void *keys[] = { CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage") };
    const void *vals[] = { p, u };
    CFDictionaryRef d = CFDictionaryCreate(kCFAllocatorDefault, keys, vals, 2,
                                           &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFRelease(p);
    CFRelease(u);
    return d;
}

int cs_read_thermal(CThermal *out) {
    out->cpuTemp = 0; out->maxTemp = 0; out->batteryTemp = 0; out->sensorCount = 0;

    if (gTempClient == NULL) {
        gTempClient = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
        if (gTempClient == NULL) return 0;
        CFDictionaryRef m = makeMatch(0xff00, 5);  // sıcaklık sensörleri
        IOHIDEventSystemClientSetMatching(gTempClient, m);
        CFRelease(m);
    }

    CFArrayRef services = IOHIDEventSystemClientCopyServices(gTempClient);
    if (!services) return 0;

    long n = CFArrayGetCount(services);
    double dieSum = 0; int dieN = 0;
    double maxT = 0, batt = 0;
    int total = 0;

    for (long i = 0; i < n; i++) {
        IOHIDServiceClientRef s = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
        IOHIDEventRef e = IOHIDServiceClientCopyEvent(s, kIOHIDEventTypeTemperature, 0, 0);
        if (!e) continue;
        double v = IOHIDEventGetFloatValue(e, FIELD_BASE(kIOHIDEventTypeTemperature));
        CFRelease(e);
        if (v <= 5.0 || v >= 130.0) continue;   // çöp/geçersiz değerleri ele

        char name[64] = {0};
        CFStringRef prod = (CFStringRef)IOHIDServiceClientCopyProperty(s, CFSTR("Product"));
        if (prod) {
            CFStringGetCString(prod, name, sizeof(name), kCFStringEncodingUTF8);
            CFRelease(prod);
        }
        char lc[64] = {0};
        for (int j = 0; name[j] && j < 63; j++) lc[j] = (char)tolower((unsigned char)name[j]);

        total++;
        if (v > maxT) maxT = v;
        if (strstr(lc, "battery")) { if (v > batt) batt = v; }
        // SoC die sensörleri: "PMU tdie...", "tcal", "soc"
        if (strstr(lc, "tdie") || strstr(lc, "tcal") || strstr(lc, "soc")) {
            dieSum += v; dieN++;
        }
    }
    CFRelease(services);

    out->cpuTemp = dieN > 0 ? dieSum / dieN : 0;
    out->maxTemp = maxT;
    out->batteryTemp = batt;
    out->sensorCount = total;
    return total > 0 ? 1 : 0;
}

// ---------------------------------------------------------------------------
// Fan — AppleSMC (IOConnectCallStructMethod)
// ---------------------------------------------------------------------------
typedef struct { unsigned char major, minor, build, reserved[1]; unsigned short release; } SMCVers;
typedef struct { unsigned short version, length; unsigned int cpuPLimit, gpuPLimit, memPLimit; } SMCPLimit;
typedef struct { unsigned int dataSize, dataType; unsigned char dataAttributes; } SMCKeyInfo;
typedef struct {
    unsigned int key;
    SMCVers vers;
    SMCPLimit plimit;
    SMCKeyInfo keyInfo;
    unsigned char result, status, data8;
    unsigned int data32;
    unsigned char bytes[32];
} SMCParam;

static io_connect_t gSMC = 0;

static int smcOpen(void) {
    if (gSMC != 0) return 1;
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!svc) return 0;
    kern_return_t r = IOServiceOpen(svc, mach_task_self(), 0, &gSMC);
    IOObjectRelease(svc);
    return r == 0 ? 1 : 0;
}

static unsigned int keyOf(const char *s) {
    return ((unsigned int)s[0] << 24) | ((unsigned int)s[1] << 16) |
           ((unsigned int)s[2] << 8) | (unsigned int)s[3];
}

static int smcCall(SMCParam *in, SMCParam *out) {
    size_t size = sizeof(SMCParam);
    return IOConnectCallStructMethod(gSMC, 2, in, size, out, &size);
}

static int smcRead(const char *key, SMCParam *out) {
    SMCParam in;
    memset(&in, 0, sizeof(in));
    memset(out, 0, sizeof(*out));
    in.key = keyOf(key);
    in.data8 = 9;  // kSMCGetKeyInfo
    if (smcCall(&in, out) != 0) return 0;
    unsigned int size = out->keyInfo.dataSize;
    unsigned int type = out->keyInfo.dataType;

    memset(&in, 0, sizeof(in));
    in.key = keyOf(key);
    in.keyInfo.dataSize = size;
    in.data8 = 5;  // kSMCReadKey
    memset(out, 0, sizeof(*out));
    if (smcCall(&in, out) != 0) return 0;
    out->keyInfo.dataSize = size;
    out->keyInfo.dataType = type;
    return 1;
}

int cs_read_fans(double *outRPM, int maxFans) {
    if (!smcOpen()) return 0;
    SMCParam out;
    if (!smcRead("FNum", &out)) return 0;
    int fans = out.bytes[0];
    if (fans <= 0) return 0;

    int count = 0;
    for (int i = 0; i < fans && count < maxFans; i++) {
        char key[5];
        snprintf(key, sizeof(key), "F%dAc", i);
        if (!smcRead(key, &out)) continue;

        unsigned int t = out.keyInfo.dataType;
        char tb[5] = {0};
        tb[0] = (char)((t >> 24) & 0xff);
        tb[1] = (char)((t >> 16) & 0xff);
        tb[2] = (char)((t >> 8) & 0xff);
        tb[3] = (char)(t & 0xff);

        float val = 0;
        if (memcmp(tb, "flt ", 4) == 0) {
            memcpy(&val, out.bytes, 4);
        } else if (memcmp(tb, "fpe2", 4) == 0) {
            val = (float)(((out.bytes[0] << 8) | out.bytes[1]) / 4.0);
        }
        outRPM[count++] = (double)val;
    }
    return count;
}
