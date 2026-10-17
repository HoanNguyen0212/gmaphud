/*
 * cmu_splim_listener.c - Enhanced UDP Telemetry & Navigation Receiver for Mazda CMU
 * Targets: Mazda Connect CMU150 (FW 74.00.324 / Linux ARMv7)
 *
 * Responsibilities:
 * 1. Binds UDP socket to 0.0.0.0:8888 (listens on USB CarPlay IP 192.168.53.1).
 * 2. Ingests Speed Limits from VietMap Live:
 *    "LIMIT <speed_limit> <camera_speed>"
 * 3. Ingests Turn-by-Turn Navigation from VietMap Live:
 *    "NAV <turn_icon> <distance_m> <road_name>"
 * 4. Atomic writes to /data_persist/splim (for speed limit) and
 *    /data_persist/nav (for turn-by-turn guidance and road names).
 * 5. Internal keepalive ticker (3s) to prevent 8s HUD TTL blanking.
 * 6. Debounced flash writes to prevent eMMC wear.
 * 7. Non-blocking drain loop with 0ms queue latency.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <time.h>
#include <unistd.h>
#include <signal.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#define LISTEN_PORT            8888
#define DIAG_PORT              8889
#define SPLIM_OUTPUT_PATH      "/data_persist/splim"
#define SPLIM_TMP_PATH         "/data_persist/.splim.tmp"
#define NAV_OUTPUT_PATH        "/data_persist/nav"
#define NAV_TMP_PATH           "/data_persist/.nav.tmp"

#define KEEPALIVE_INTERVAL_SEC 3
#define DATA_TIMEOUT_SEC       30

typedef struct {
    uint8_t speed_limit;
    uint8_t camera_speed;
    time_t  camera_expires;
    uint8_t last_written_limit;
    time_t  last_written_ts;
    time_t  last_rx_time;

    // Navigation state
    uint16_t nav_icon;
    uint32_t nav_distance;
    char     nav_road[128];
    time_t   nav_last_rx;
    time_t   nav_last_write_ts;
} cmu_receiver_state_t;

static cmu_receiver_state_t g_state;
static volatile bool g_running = true;

static void sig_handler(int sig) {
    (void)sig;
    g_running = false;
}

// Atomic file update on the SAME filesystem (/data_persist) - Guarantees NO EXDEV
static bool write_file_atomic(const char *out_path, const char *tmp_path, const char *content) {
    FILE *f = fopen(tmp_path, "w");
    if (!f) return false;

    fputs(content, f);
    fflush(f);
    fclose(f);

    return (rename(tmp_path, out_path) == 0);
}

static bool write_splim_atomic(const char *out_path, const char *tmp_path, uint8_t limit, time_t ts) {
    char buf[64];
    snprintf(buf, sizeof(buf), "%u %ld\n", (unsigned int)limit, (long)ts);
    if (write_file_atomic(out_path, tmp_path, buf)) {
        g_state.last_written_limit = limit;
        g_state.last_written_ts = ts;
        return true;
    }
    return false;
}

static bool write_nav_atomic(const char *out_path, const char *tmp_path,
                             uint16_t icon, uint32_t dist, const char *road, time_t ts) {
    char buf[256];
    snprintf(buf, sizeof(buf), "%u %u %ld %s\n", (unsigned int)icon, (unsigned int)dist, (long)ts, road);
    return write_file_atomic(out_path, tmp_path, buf);
}

static uint8_t get_effective_limit(time_t now) {
    if (g_state.last_rx_time == 0 || (now - g_state.last_rx_time >= DATA_TIMEOUT_SEC)) {
        return 0; // Clear display if disconnected
    }
    if (g_state.camera_speed > 0 && now < g_state.camera_expires) {
        return g_state.camera_speed;
    }
    return g_state.speed_limit;
}

static void update_hud_tick(time_t now, const char *out_path, const char *tmp_path,
                            const char *nav_out_path, const char *nav_tmp_path) {
    uint8_t eff = get_effective_limit(now);

    // Debounced write for Speed Limit
    if (eff != g_state.last_written_limit ||
        (now - g_state.last_written_ts >= KEEPALIVE_INTERVAL_SEC && eff > 0)) {
        write_splim_atomic(out_path, tmp_path, eff, now);
    }

    // Debounced write / timeout for Navigation
    if (g_state.nav_last_rx > 0 && (now - g_state.nav_last_rx < DATA_TIMEOUT_SEC)) {
        if (now - g_state.nav_last_write_ts >= KEEPALIVE_INTERVAL_SEC) {
            write_nav_atomic(nav_out_path, nav_tmp_path,
                             g_state.nav_icon, g_state.nav_distance, g_state.nav_road, now);
            g_state.nav_last_write_ts = now;
        }
    } else if (g_state.nav_last_rx > 0 && (now - g_state.nav_last_rx >= DATA_TIMEOUT_SEC)) {
        // Clear navigation display
        write_nav_atomic(nav_out_path, nav_tmp_path, 0, 0, "", now);
        g_state.nav_last_rx = 0;
    }
}

// Explicit VietMap Live Maneuver ID -> Mazda HUD Icon Mapping
static uint16_t map_vietmap_to_mazda_icon(int vm_icon) {
    switch (vm_icon) {
        case 1:  return 1;  // HUD_STRAIGHT
        case 2:  return 2;  // HUD_LEFT
        case 3:  return 3;  // HUD_RIGHT
        case 4:  return 4;  // HUD_SLIGHT_LEFT
        case 5:  return 5;  // HUD_SLIGHT_RIGHT
        case 6:  return 11; // HUD_SHARP_LEFT (Mazda: 11)
        case 7:  return 9;  // HUD_SHARP_RIGHT (Mazda: 9)
        case 8:  return 13; // HUD_U_TURN_LEFT (Mazda: 13)
        case 9:  return 16; // HUD_MERGE_LEFT (Mazda: 16)
        case 10: return 10; // HUD_U_TURN_RIGHT (Mazda: 10)
        case 11: return 8;  // HUD_DESTINATION (Mazda: 8)
        default: return 1;  // Fallback straight
    }
}

// Parse incoming packet from iPhone GMapHUD:
// 1. "LIMIT <speed_limit> <camera_speed>\n"
// 2. "NAV <turn_icon> <distance_m> <road_name>\n"
static void parse_telemetry_packet(const char *buf, size_t len, time_t now,
                                   const char *out_path, const char *tmp_path,
                                   const char *nav_out_path, const char *nav_tmp_path) {
    if (!buf || len == 0) return;

    static char last_logged_buf[256] = "";
    static time_t last_log_time = 0;
    if (strcmp(buf, last_logged_buf) != 0 || (now - last_log_time >= 3)) {
        FILE *logf = fopen("/tmp/cmu_listener.log", "a");
        if (logf) {
            fprintf(logf, "[%ld] RX: %s\n", (long)now, buf);
            fclose(logf);
        }
        strncpy(last_logged_buf, buf, sizeof(last_logged_buf) - 1);
        last_logged_buf[sizeof(last_logged_buf) - 1] = '\0';
        last_log_time = now;
    }

    if (strncmp(buf, "LIMIT", 5) == 0) {
        int limit = 0;
        int cam_spd = 0;
        int matched = sscanf(buf, "LIMIT %d %d", &limit, &cam_spd);
        if (matched >= 1) {
            if ((limit >= 5 && limit <= 140) || limit == 0) {
                g_state.speed_limit = (uint8_t)limit;
                g_state.last_rx_time = now;
            }
            if (matched >= 2 && cam_spd >= 20 && cam_spd <= 140) {
                g_state.camera_speed = (uint8_t)cam_spd;
                g_state.camera_expires = now + 15;
                g_state.last_rx_time = now;
            } else {
                g_state.camera_speed = 0;
                g_state.camera_expires = 0;
            }
            update_hud_tick(now, out_path, tmp_path, nav_out_path, nav_tmp_path);
        }
    } else if (strncmp(buf, "NAV", 3) == 0) {
        int icon = 0;
        unsigned int dist = 0;
        char road[128] = {0};
        // Use %127[^\r\n] to strictly prevent stack buffer overflow
        int matched = sscanf(buf, "NAV %d %u %127[^\r\n]", &icon, &dist, road);
        if (matched >= 2) {
            // If already a valid Mazda HUD icon ID (1..60), use directly without re-mapping
            if (icon >= 1 && icon <= 60) {
                g_state.nav_icon = (uint16_t)icon;
            } else {
                g_state.nav_icon = map_vietmap_to_mazda_icon(icon);
            }
            g_state.nav_distance = dist;
            snprintf(g_state.nav_road, sizeof(g_state.nav_road), "%s", road);
            g_state.nav_last_rx = now;
            write_nav_atomic(nav_out_path, nav_tmp_path,
                             g_state.nav_icon, g_state.nav_distance, g_state.nav_road, now);
            g_state.nav_last_write_ts = now;
        }
    }
}

// Mini HTTP/Diag server helper: streams a text file or status to the socket
static void dump_file_to_socket(int fd, const char *label, const char *path) {
    char sec_buf[256];
    snprintf(sec_buf, sizeof(sec_buf), "--- %s (%s) ---\n", label, path);
    send(fd, sec_buf, strlen(sec_buf), 0);
    FILE *f = fopen(path, "r");
    if (!f) {
        send(fd, "(file not found)\n\n", 18, 0);
        return;
    }
    char line[512];
    while (fgets(line, sizeof(line), f)) {
        send(fd, line, strlen(line), 0);
    }
    fclose(f);
    send(fd, "\n", 1, 0);
}

static void handle_diag_http_client(int client_fd, const char *splim_path, const char *nav_path) {
    char header[] = 
        "HTTP/1.0 200 OK\r\n"
        "Content-Type: text/plain; charset=utf-8\r\n"
        "Connection: close\r\n\r\n";
    send(client_fd, header, strlen(header), 0);

    time_t now = time(NULL);
    char status_buf[1024];
    int splim_age = (g_state.last_rx_time > 0) ? (int)(now - g_state.last_rx_time) : -1;
    int nav_age = (g_state.nav_last_rx > 0) ? (int)(now - g_state.nav_last_rx) : -1;

    snprintf(status_buf, sizeof(status_buf),
        "=== MAZDA CMU TELEMETRY LISTENER STATUS ===\n"
        "Time: %ld\n"
        "Speed Limit: %u km/h (cam: %u, last rx: %d sec ago)\n"
        "Nav Maneuver: icon=%u, dist=%u m, road=\"%s\" (last rx: %d sec ago)\n"
        "\n",
        (long)now,
        g_state.speed_limit, g_state.camera_speed, splim_age,
        g_state.nav_icon, g_state.nav_distance, g_state.nav_road, nav_age
    );
    send(client_fd, status_buf, strlen(status_buf), 0);

    dump_file_to_socket(client_fd, "Active Speed Limit File", splim_path);
    dump_file_to_socket(client_fd, "Active Navigation File", nav_path);
    dump_file_to_socket(client_fd, "CMU Listener Log", "/tmp/cmu_listener.log");
    dump_file_to_socket(client_fd, "CarPlay Bridge Log", "/tmp/carplay_bridge.log");
}

int main(int argc, char **argv) {
    const char *out_path = SPLIM_OUTPUT_PATH;
    const char *tmp_path = SPLIM_TMP_PATH;
    const char *nav_out_path = NAV_OUTPUT_PATH;
    const char *nav_tmp_path = NAV_TMP_PATH;
    int port = LISTEN_PORT;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--port") == 0 && i + 1 < argc) {
            port = atoi(argv[++i]);
        } else if (strcmp(argv[i], "--out") == 0 && i + 1 < argc) {
            out_path = argv[++i];
        } else if (strcmp(argv[i], "--tmp") == 0 && i + 1 < argc) {
            tmp_path = argv[++i];
        } else if (strcmp(argv[i], "--nav-out") == 0 && i + 1 < argc) {
            nav_out_path = argv[++i];
        } else if (strcmp(argv[i], "--nav-tmp") == 0 && i + 1 < argc) {
            nav_tmp_path = argv[++i];
        }
    }

    signal(SIGINT, sig_handler);
    signal(SIGTERM, sig_handler);

    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) {
        perror("socket");
        return 1;
    }

    int flags = fcntl(sock, F_GETFL, 0);
    fcntl(sock, F_SETFL, flags | O_NONBLOCK);

    int opt = 1;
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons(port);

    if (bind(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        perror("bind");
        close(sock);
        return 1;
    }

    // Micro HTTP / Diag server on TCP port 8889
    int diag_sock = socket(AF_INET, SOCK_STREAM, 0);
    if (diag_sock >= 0) {
        int dflags = fcntl(diag_sock, F_GETFL, 0);
        if (dflags >= 0) fcntl(diag_sock, F_SETFL, dflags | O_NONBLOCK);
        int dopt = 1;
        setsockopt(diag_sock, SOL_SOCKET, SO_REUSEADDR, &dopt, sizeof(dopt));
        struct sockaddr_in daddr;
        memset(&daddr, 0, sizeof(daddr));
        daddr.sin_family = AF_INET;
        daddr.sin_addr.s_addr = htonl(INADDR_ANY);
        daddr.sin_port = htons(DIAG_PORT);
        if (bind(diag_sock, (struct sockaddr *)&daddr, sizeof(daddr)) < 0 || listen(diag_sock, 4) < 0) {
            close(diag_sock);
            diag_sock = -1;
        }
    }

    // Write initial startup banner so /tmp/cmu_listener.log is guaranteed to exist
    FILE *init_f = fopen("/tmp/cmu_listener.log", "a");
    if (init_f) {
        time_t t0 = time(NULL);
        fprintf(init_f, "[%ld] cmu_splim_listener started (UDP :%d, HTTP Diag :%d)\n",
                (long)t0, port, DIAG_PORT);
        fclose(init_f);
    }

    memset(&g_state, 0, sizeof(g_state));
    char buf[512];

    while (g_running) {
        time_t now = time(NULL);
        struct sockaddr_in client_addr;
        socklen_t client_len;

        // Drain loop: zero latency ingestion of all pending datagrams
        ssize_t n;
        while (client_len = sizeof(client_addr),
               (n = recvfrom(sock, buf, sizeof(buf) - 1, 0,
                             (struct sockaddr *)&client_addr, &client_len)) > 0) {
            buf[n] = '\0';
            parse_telemetry_packet(buf, (size_t)n, now,
                                   out_path, tmp_path, nav_out_path, nav_tmp_path);
        }

        // Service any incoming HTTP / Diag requests
        if (diag_sock >= 0) {
            struct sockaddr_in client_tcp;
            socklen_t client_tcp_len = sizeof(client_tcp);
            int cfd = accept(diag_sock, (struct sockaddr *)&client_tcp, &client_tcp_len);
            if (cfd >= 0) {
                struct timeval tv;
                tv.tv_sec = 0;
                tv.tv_usec = 500000; // 500ms timeout to prevent slow/stalled clients from blocking HUD
                setsockopt(cfd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
                setsockopt(cfd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
                handle_diag_http_client(cfd, out_path, nav_out_path);
                close(cfd);
            }
        }

        update_hud_tick(now, out_path, tmp_path, nav_out_path, nav_tmp_path);
        usleep(250000); // 250ms event tick
    }

    close(sock);
    if (diag_sock >= 0) close(diag_sock);
    // Clean exit: clear HUD
    write_splim_atomic(out_path, tmp_path, 0, time(NULL));
    write_nav_atomic(nav_out_path, nav_tmp_path, 0, 0, "", time(NULL));
    return 0;
}
