/*
 * hud_direct_test.c - Direct, readback-logged HUD display probe for Mazda CMU150.
 *
 * This is a diagnostic tool. It connects to the same OEM service-bus interface
 * used by libpatch-blmjcicarplay.so, sends a synthetic 60 km/h + right turn
 * HUD frame for 15 seconds, records all return codes, then clears the frame.
 *
 * Use only with the vehicle parked and Ignition ON / engine running.
 */

#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define LOG_PATH "/tmp/hud_direct_test.log"
#define SERVICE_BUS 0

struct VbsNaviHudDisplay {
    uint32_t nextManeuverInfo;
    uint16_t distanceValue;
    uint8_t  distanceUnit;
    uint16_t displaySpeedLimit;
    uint8_t  displaySpeedUnit;
    uint8_t  text_ID3;
};

struct VbsNaviHudMsg2 {
    const char *guidancePointName;
    uint8_t     syncBit;
};

typedef void *(*conn_create_fn)(void *error_cb, int reserved);
typedef int   (*conn_connect_fn)(void *conn, const char *name, int bus, void *reserved);
typedef int   (*worker_start_fn)(void *conn);
typedef void  (*worker_stop_fn)(void *conn);
typedef void  (*conn_disconnect_fn)(void *conn);
typedef void  (*conn_free_fn)(void *conn);
typedef int   (*set_hud_fn)(void *conn, struct VbsNaviHudDisplay *display,
                            void *unused, void *callback, void *user);
typedef int   (*set_msg2_fn)(void *conn, struct VbsNaviHudMsg2 *message,
                             void *unused, void *callback, void *user);
typedef int   (*get_status_fn)(void *conn, void *callback, void *user);

static FILE *g_log = NULL;
static volatile int g_hud_status = -1;

static void log_line(const char *text)
{
    fputs(text, stdout);
    fputc('\n', stdout);
    fflush(stdout);
    if (g_log) {
        fputs(text, g_log);
        fputc('\n', g_log);
        fflush(g_log);
    }
}

static void log_num(const char *label, long value)
{
    char line[160];
    snprintf(line, sizeof(line), "%s%ld", label, value);
    log_line(line);
}

static void bus_error_cb(void *conn, void *user)
{
    (void)conn;
    (void)user;
    log_line("BUS_ERROR_CALLBACK=1");
}

static void hud_status_cb(void *conn, unsigned char status, void *user)
{
    (void)conn;
    (void)user;
    g_hud_status = (int)status;
    log_num("HUD_STATUS_REPLY=", (long)status);
}

static void *resolve_or_fail(void *handle, const char *symbol)
{
    void *result = dlsym(handle, symbol);
    if (!result) {
        char line[256];
        snprintf(line, sizeof(line), "ERROR: dlsym(%s): %s", symbol, dlerror());
        log_line(line);
    }
    return result;
}

int main(void)
{
    if (sizeof(struct VbsNaviHudDisplay) != 12U ||
        sizeof(struct VbsNaviHudMsg2) != 8U) {
        log_line("ERROR: unexpected OEM wire-struct layout");
        return 20;
    }

    g_log = fopen(LOG_PATH, "w");
    log_line("=== MAZDA DIRECT HUD TEST START ===");
    log_num("HUD_DISPLAY_STRUCT_SIZE=", (long)sizeof(struct VbsNaviHudDisplay));
    log_num("HUD_MSG2_STRUCT_SIZE=", (long)sizeof(struct VbsNaviHudMsg2));

    void *bus_lib = dlopen("/jci/lib/libjcidbus.so", RTLD_NOW | RTLD_GLOBAL);
    if (!bus_lib) {
        log_line("ERROR: dlopen libjcidbus.so failed");
        return 21;
    }
    void *navi_lib = dlopen("/jci/lib/libjcivbsnaviclient.so", RTLD_NOW | RTLD_GLOBAL);
    if (!navi_lib) {
        log_line("ERROR: dlopen libjcivbsnaviclient.so failed");
        dlclose(bus_lib);
        return 22;
    }

    conn_create_fn conn_create = (conn_create_fn)resolve_or_fail(bus_lib, "JCIDBUS_conn_create");
    conn_connect_fn conn_connect = (conn_connect_fn)resolve_or_fail(bus_lib, "JCIDBUS_conn_connect");
    worker_start_fn worker_start = (worker_start_fn)resolve_or_fail(bus_lib, "JCIDBUS_worker_start");
    worker_stop_fn worker_stop = (worker_stop_fn)resolve_or_fail(bus_lib, "JCIDBUS_worker_stop");
    conn_disconnect_fn conn_disconnect = (conn_disconnect_fn)resolve_or_fail(bus_lib, "JCIDBUS_conn_disconnect");
    conn_free_fn conn_free = (conn_free_fn)resolve_or_fail(bus_lib, "JCIDBUS_conn_free");
    set_hud_fn set_hud = (set_hud_fn)resolve_or_fail(navi_lib, "VBS_NAVI_SetHUDDisplayMsgReq");
    set_msg2_fn set_msg2 = (set_msg2_fn)resolve_or_fail(navi_lib, "VBS_NAVI_TMC_SetHUD_Display_Msg2");
    get_status_fn get_status = (get_status_fn)resolve_or_fail(navi_lib, "VBS_NAVI_GetHUDStatus");

    if (!conn_create || !conn_connect || !worker_start || !worker_stop ||
        !conn_disconnect || !conn_free || !set_hud || !set_msg2 || !get_status) {
        log_line("ERROR: required OEM symbol unavailable");
        dlclose(navi_lib);
        dlclose(bus_lib);
        return 23;
    }

    void *conn = conn_create((void *)&bus_error_cb, 0);
    if (!conn) {
        log_line("ERROR: JCIDBUS_conn_create returned NULL");
        dlclose(navi_lib);
        dlclose(bus_lib);
        return 24;
    }

    int connect_rc = conn_connect(conn, "com.hoannguyen.hudtest", SERVICE_BUS, NULL);
    log_num("JCIDBUS_CONN_CONNECT_RC=", (long)connect_rc);
    if (connect_rc == 0) {
        log_line("ERROR: cannot connect to OEM service bus");
        conn_free(conn);
        dlclose(navi_lib);
        dlclose(bus_lib);
        return 25;
    }

    int worker_rc = worker_start(conn);
    log_num("JCIDBUS_WORKER_START_RC=", (long)worker_rc);
    int status_rc = get_status(conn, (void *)&hud_status_cb, NULL);
    log_num("GET_HUD_STATUS_CALL_RC=", (long)status_rc);
    sleep(1);
    log_num("HUD_STATUS_AFTER_WAIT=", (long)g_hud_status);

    struct VbsNaviHudDisplay display;
    memset(&display, 0, sizeof(display));
    display.nextManeuverInfo = 3; /* Mazda right turn icon */
    display.distanceValue = 500;
    display.distanceUnit = 1;     /* meters */
    display.displaySpeedLimit = 60;
    display.displaySpeedUnit = 1; /* km/h */

    struct VbsNaviHudMsg2 message;
    message.guidancePointName = "HUD_TEST";

    log_line("DISPLAY_WINDOW_SEC=15");
    for (int second = 1; second <= 15; ++second) {
        display.text_ID3 = (uint8_t)(((second - 1) % 7) + 1);
        message.syncBit = display.text_ID3;
        int frame_rc = set_hud(conn, &display, NULL, NULL, NULL);
        int text_rc = set_msg2(conn, &message, NULL, NULL, NULL);
        char line[160];
        snprintf(line, sizeof(line), "PULSE=%d SET_HUD_RC=%d SET_MSG2_RC=%d", second, frame_rc, text_rc);
        log_line(line);
        sleep(1);
    }

    memset(&display, 0, sizeof(display));
    message.guidancePointName = " ";
    message.syncBit = 1;
    int clear_frame_rc = set_hud(conn, &display, NULL, NULL, NULL);
    int clear_text_rc = set_msg2(conn, &message, NULL, NULL, NULL);
    char final_line[160];
    snprintf(final_line, sizeof(final_line),
             "CLEAR SET_HUD_RC=%d SET_MSG2_RC=%d", clear_frame_rc, clear_text_rc);
    log_line(final_line);

    worker_stop(conn);
    conn_disconnect(conn);
    conn_free(conn);
    dlclose(navi_lib);
    dlclose(bus_lib);
    log_line("=== MAZDA DIRECT HUD TEST END ===");
    if (g_log) fclose(g_log);
    return (g_hud_status == 1 && clear_frame_rc == 0 && clear_text_rc == 0) ? 0 : 26;
}
