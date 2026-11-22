/*
 * gmaphud-cmu-log-receiver.c - Native rootless iOS TCP/8890 CMU log receiver
 *
 * Replaces the legacy shell + GNU netcat + FIFO loop (which crashed with
 * SIGABRT / Abort trap: 6 on Dopamine iOS 15.8 ARM64 and forked processes
 * continuously). Runs as a single low-overhead daemon (~0% CPU when idle):
 *
 *  - Binds strictly to the active en3 private CarPlay/NCM IPv4 address
 *    (192.168.53/24, 192.168.100/24, 169.254/16, 172.20/16), never Tailscale
 *    or home Wi-Fi.
 *  - Periodically sends UDP/8888 SESSION_START + SYNC announcements over en3
 *    so Mazda CMU cmu_log_pusher learns the iPhone's NCM IP.
 *  - Accepts HTTP/1.1 POST chunks from cmu_log_pusher, verifies SHA-256 and
 *    monotone offset, appends atomically to dated cmu-push directories, logs
 *    to cmu-push-manifest.ndjson, and replies with JSON ack_offset.
 *  - Automatically prunes dated folders older than retention days.
 */
#include <arpa/inet.h>
#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#ifndef IP_BOUND_IF
#ifdef __APPLE__
#define IP_BOUND_IF 25
#endif
#endif

#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif

#define MAX_HEADER_BYTES 8192U
#define MAX_CHUNK_BYTES 65536U
#define DEFAULT_PORT 8890
#define DEFAULT_RETENTION_DAYS 7
#define DEFAULT_ANNOUNCE_INTERVAL 15
#define DEFAULT_ROOT "/var/mobile/Documents/GMapHUD/auto-sessions"
#define DEFAULT_CMU_IPS "169.254.53.1 192.168.53.1 192.168.100.1"

static volatile sig_atomic_t g_running = 1;

static void handle_signal(int sig) {
    (void)sig;
    g_running = 0;
}

/* ── Compact SHA-256 (zero external deps, identical on Linux & iOS) ──────── */
typedef struct {
    uint32_t h[8];
    uint64_t bits;
    unsigned char b[64];
    size_t n;
} sha256_t;

static const uint32_t SHA_K[64] = {
    0x428a2f98U,0x71374491U,0xb5c0fbcfU,0xe9b5dba5U,0x3956c25bU,0x59f111f1U,0x923f82a4U,0xab1c5ed5U,
    0xd807aa98U,0x12835b01U,0x243185beU,0x550c7dc3U,0x72be5d74U,0x80deb1feU,0x9bdc06a7U,0xc19bf174U,
    0xe49b69c1U,0xefbe4786U,0x0fc19dc6U,0x240ca1ccU,0x2de92c6fU,0x4a7484aaU,0x5cb0a9dcU,0x76f988daU,
    0x983e5152U,0xa831c66dU,0xb00327c8U,0xbf597fc7U,0xc6e00bf3U,0xd5a79147U,0x06ca6351U,0x14292967U,
    0x27b70a85U,0x2e1b2138U,0x4d2c6dfcU,0x53380d13U,0x650a7354U,0x766a0abbU,0x81c2c92eU,0x92722c85U,
    0xa2bfe8a1U,0xa81a664bU,0xc24b8b70U,0xc76c51a3U,0xd192e819U,0xd6990624U,0xf40e3585U,0x106aa070U,
    0x19a4c116U,0x1e376c08U,0x2748774cU,0x34b0bcb5U,0x391c0cb3U,0x4ed8aa4aU,0x5b9cca4fU,0x682e6ff3U,
    0x748f82eeU,0x78a5636fU,0x84c87814U,0x8cc70208U,0x90befffaU,0xa4506cebU,0xbef9a3f7U,0xc67178f2U
};

static uint32_t sha_ror(uint32_t x, int n) {
    return (x >> n) | (x << (32 - n));
}

static void sha_block(sha256_t *s, const unsigned char *p) {
    uint32_t w[64], a, b, c, d, e, f, g, h;
    for (int i = 0; i < 16; i++) {
        w[i] = ((uint32_t)p[i * 4] << 24) | ((uint32_t)p[i * 4 + 1] << 16) |
               ((uint32_t)p[i * 4 + 2] << 8) | (uint32_t)p[i * 4 + 3];
    }
    for (int i = 16; i < 64; i++) {
        uint32_t q = sha_ror(w[i - 15], 7) ^ sha_ror(w[i - 15], 18) ^ (w[i - 15] >> 3);
        uint32_t z = sha_ror(w[i - 2], 17) ^ sha_ror(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] + q + w[i - 7] + z;
    }
    a = s->h[0]; b = s->h[1]; c = s->h[2]; d = s->h[3];
    e = s->h[4]; f = s->h[5]; g = s->h[6]; h = s->h[7];
    for (int i = 0; i < 64; i++) {
        uint32_t S1 = sha_ror(e, 6) ^ sha_ror(e, 11) ^ sha_ror(e, 25);
        uint32_t ch = (e & f) ^ ((~e) & g);
        uint32_t t1 = h + S1 + ch + SHA_K[i] + w[i];
        uint32_t S0 = sha_ror(a, 2) ^ sha_ror(a, 13) ^ sha_ror(a, 22);
        uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
        uint32_t t2 = S0 + maj;
        h = g; g = f; f = e; e = d + t1;
        d = c; c = b; b = a; a = t1 + t2;
    }
    s->h[0] += a; s->h[1] += b; s->h[2] += c; s->h[3] += d;
    s->h[4] += e; s->h[5] += f; s->h[6] += g; s->h[7] += h;
}

static void sha_compute_hex(const unsigned char *data, size_t n, char out[65]) {
    static const uint32_t iv[8] = {
        0x6a09e667U, 0xbb67ae85U, 0x3c6ef372U, 0xa54ff53aU,
        0x510e527fU, 0x9b05688cU, 0x1f83d9abU, 0x5be0cd19U
    };
    static const char hex[] = "0123456789abcdef";
    sha256_t s;
    memcpy(s.h, iv, sizeof(iv));
    s.bits = (uint64_t)n * 8ULL;
    s.n = 0;
    while (n > 0) {
        size_t k = 64U - s.n;
        if (k > n) k = n;
        memcpy(s.b + s.n, data, k);
        s.n += k;
        data += k;
        n -= k;
        if (s.n == 64U) {
            sha_block(&s, s.b);
            s.n = 0;
        }
    }
    s.b[s.n++] = 0x80;
    while (s.n != 56U) {
        if (s.n == 64U) {
            sha_block(&s, s.b);
            s.n = 0;
        } else {
            s.b[s.n++] = 0;
        }
    }
    for (int i = 0; i < 8; i++) {
        s.b[56 + i] = (unsigned char)(s.bits >> (56 - 8 * i));
    }
    sha_block(&s, s.b);
    for (int i = 0; i < 8; i++) {
        unsigned char b0 = (unsigned char)(s.h[i] >> 24);
        unsigned char b1 = (unsigned char)(s.h[i] >> 16);
        unsigned char b2 = (unsigned char)(s.h[i] >> 8);
        unsigned char b3 = (unsigned char)(s.h[i]);
        out[i * 8 + 0] = hex[b0 >> 4]; out[i * 8 + 1] = hex[b0 & 15];
        out[i * 8 + 2] = hex[b1 >> 4]; out[i * 8 + 3] = hex[b1 & 15];
        out[i * 8 + 4] = hex[b2 >> 4]; out[i * 8 + 5] = hex[b2 & 15];
        out[i * 8 + 6] = hex[b3 >> 4]; out[i * 8 + 7] = hex[b3 & 15];
    }
    out[64] = '\0';
}

/* ── Filesystem & String Helpers ─────────────────────────────────────────── */
static int mkdir_p(const char *path, mode_t mode) {
    char tmp[1024];
    size_t len = strlen(path);
    if (len == 0 || len >= sizeof(tmp)) return -1;
    memcpy(tmp, path, len + 1);
    if (tmp[len - 1] == '/') tmp[len - 1] = '\0';
    for (char *p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            if (mkdir(tmp, mode) < 0 && errno != EEXIST) return -1;
            *p = '/';
        }
    }
    if (mkdir(tmp, mode) < 0 && errno != EEXIST) return -1;
    return 0;
}

static void rm_rf(const char *path) {
    struct stat st;
    if (lstat(path, &st) < 0) return;
    if (!S_ISDIR(st.st_mode)) {
        (void)unlink(path);
        return;
    }
    DIR *d = opendir(path);
    if (!d) return;
    struct dirent *ent;
    while ((ent = readdir(d)) != NULL) {
        if (strcmp(ent->d_name, ".") == 0 || strcmp(ent->d_name, "..") == 0) continue;
        char child[1024];
        int n = snprintf(child, sizeof(child), "%s/%s", path, ent->d_name);
        if (n > 0 && (size_t)n < sizeof(child)) rm_rf(child);
    }
    closedir(d);
    (void)rmdir(path);
}

static int is_day_dir_name(const char *name) {
    if (strlen(name) != 10) return 0;
    return name[0] == '2' && name[1] == '0' &&
           isdigit((unsigned char)name[2]) && isdigit((unsigned char)name[3]) &&
           name[4] == '-' &&
           isdigit((unsigned char)name[5]) && isdigit((unsigned char)name[6]) &&
           name[7] == '-' &&
           isdigit((unsigned char)name[8]) && isdigit((unsigned char)name[9]);
}

static void prune_old_days(const char *root, int retention_days) {
    if (retention_days <= 0) return;
    DIR *d = opendir(root);
    if (!d) return;
    time_t now = time(NULL);
    time_t cutoff = now - (time_t)retention_days * 86400;
    struct tm tm_today;
    char today_str[16] = "";
    if (localtime_r(&now, &tm_today)) {
        strftime(today_str, sizeof(today_str), "%Y-%m-%d", &tm_today);
    }
    struct dirent *ent;
    while ((ent = readdir(d)) != NULL) {
        if (!is_day_dir_name(ent->d_name)) continue;
        if (today_str[0] && strcmp(ent->d_name, today_str) == 0) continue;
        char full[1024];
        int n = snprintf(full, sizeof(full), "%s/%s", root, ent->d_name);
        if (n <= 0 || (size_t)n >= sizeof(full)) continue;
        struct stat st;
        if (lstat(full, &st) == 0 && S_ISDIR(st.st_mode) && st.st_mtime < cutoff) {
            rm_rf(full);
        }
    }
    closedir(d);
}

static void safe_component(const char *in, char *out, size_t out_sz, const char *fallback) {
    size_t j = 0;
    if (in) {
        for (size_t i = 0; in[i] && j + 1 < out_sz; i++) {
            unsigned char c = (unsigned char)in[i];
            if (isalnum(c) || c == '.' || c == '_' || c == '-') {
                out[j++] = (char)c;
            }
        }
    }
    out[j] = '\0';
    if (j == 0 || strcmp(out, ".") == 0 || strcmp(out, "..") == 0 || strstr(out, "..") != NULL) {
        snprintf(out, out_sz, "%s", fallback);
    }
}

static void write_status_file(const char *path, const char *line) {
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) return;
    size_t n = strlen(line);
    ssize_t unused = write(fd, line, n);
    (void)unused;
    close(fd);
}

static void utc_iso_now(char *out, size_t out_sz) {
    time_t now = time(NULL);
    struct tm tm_utc;
    gmtime_r(&now, &tm_utc);
    strftime(out, out_sz, "%Y-%m-%dT%H:%M:%SZ", &tm_utc);
}

/* ── Network / NCM Discovery & Announcements ─────────────────────────────── */
static int is_private_ncm_ip(uint32_t addr_host) {
    if ((addr_host & 0xffffff00U) == 0xc0a83500U) return 1; /* 192.168.53.0/24 */
    if ((addr_host & 0xffffff00U) == 0xc0a86400U) return 1; /* 192.168.100.0/24 */
    if ((addr_host & 0xffff0000U) == 0xa9fe0000U) return 1; /* 169.254.0.0/16 */
    if ((addr_host & 0xffff0000U) == 0xac140000U) return 1; /* 172.20.0.0/16 */
    return 0;
}

static int find_ncm_ip(char ip_out[INET_ADDRSTRLEN], unsigned int *ifindex_out) {
    struct ifaddrs *ifas = NULL;
    if (getifaddrs(&ifas) != 0 || !ifas) return 0;
    int found = 0;
    for (struct ifaddrs *ifa = ifas; ifa; ifa = ifa->ifa_next) {
        if (!ifa->ifa_name || !ifa->ifa_addr) continue;
        if (strcmp(ifa->ifa_name, "en3") != 0) continue;
        if ((ifa->ifa_flags & (IFF_UP | IFF_RUNNING)) != (IFF_UP | IFF_RUNNING)) continue;
        if (ifa->ifa_addr->sa_family != AF_INET) continue;
        struct sockaddr_in *sin = (struct sockaddr_in *)ifa->ifa_addr;
        uint32_t host_ip = ntohl(sin->sin_addr.s_addr);
        if (!is_private_ncm_ip(host_ip)) continue;
        if (inet_ntop(AF_INET, &sin->sin_addr, ip_out, INET_ADDRSTRLEN)) {
            if (ifindex_out) *ifindex_out = if_nametoindex("en3");
            found = 1;
            break;
        }
    }
    freeifaddrs(ifas);
    return found;
}

static void send_udp_packet(int fd, const char *dst_ip, uint16_t port, const char *msg, size_t len) {
    struct sockaddr_in dst;
    memset(&dst, 0, sizeof(dst));
    dst.sin_family = AF_INET;
    dst.sin_port = htons(port);
    if (inet_pton(AF_INET, dst_ip, &dst.sin_addr) != 1) return;
    ssize_t sent = sendto(fd, msg, len, MSG_NOSIGNAL, (struct sockaddr *)&dst, sizeof(dst));
    if (sent < 0 && (errno == ENETUNREACH || errno == EHOSTUNREACH || errno == EADDRNOTAVAIL)) {
        (void)sendto(fd, msg, len, MSG_NOSIGNAL | MSG_DONTROUTE, (struct sockaddr *)&dst, sizeof(dst));
    }
}

static void announce_once(const char *bind_ip, unsigned int ifindex, const char *session, const char *cmu_ips) {
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) return;
    int one = 1;
    (void)setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &one, sizeof(one));
#ifdef SO_NOSIGPIPE
    (void)setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
#endif
#ifdef IP_BOUND_IF
    if (ifindex > 0) {
        (void)setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &ifindex, sizeof(ifindex));
    }
#else
    (void)ifindex;
#endif
    struct sockaddr_in src;
    memset(&src, 0, sizeof(src));
    src.sin_family = AF_INET;
    src.sin_port = 0;
    if (inet_pton(AF_INET, bind_ip, &src.sin_addr) == 1) {
        (void)bind(fd, (struct sockaddr *)&src, sizeof(src));
    }

    struct timeval tv;
    gettimeofday(&tv, NULL);
    long long epoch_ms = (long long)tv.tv_sec * 1000LL + (long long)(tv.tv_usec / 1000);

    char sess_msg[160];
    char sync_msg[96];
    int slen = snprintf(sess_msg, sizeof(sess_msg), "SESSION_START %s\n", session);
    int tlen = snprintf(sync_msg, sizeof(sync_msg), "SYNC %lld 0\n", epoch_ms);
    if (slen <= 0 || tlen <= 0) { close(fd); return; }

    char ips_copy[512];
    snprintf(ips_copy, sizeof(ips_copy), "%s 169.254.255.255 192.168.53.255", cmu_ips);
    char *saveptr = NULL;
    for (char *tok = strtok_r(ips_copy, " \t\r\n", &saveptr); tok; tok = strtok_r(NULL, " \t\r\n", &saveptr)) {
        send_udp_packet(fd, tok, 8888, sess_msg, (size_t)slen);
        send_udp_packet(fd, tok, 8888, sync_msg, (size_t)tlen);
    }
    close(fd);
}

static int open_listener(const char *bind_ip, int port, unsigned int ifindex, int test_mode) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    int one = 1;
    (void)setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
#ifdef SO_NOSIGPIPE
    (void)setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
#endif
#ifdef IP_BOUND_IF
    if (!test_mode && ifindex > 0) {
        (void)setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &ifindex, sizeof(ifindex));
    }
#else
    (void)ifindex;
    (void)test_mode;
#endif
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, bind_ip, &addr.sin_addr) != 1) {
        close(fd);
        return -1;
    }
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(fd);
        return -1;
    }
    if (listen(fd, 16) < 0) {
        close(fd);
        return -1;
    }
    return fd;
}

/* ── HTTP Chunk Handling ─────────────────────────────────────────────────── */
static int send_all(int fd, const void *buf, size_t n) {
    const unsigned char *p = (const unsigned char *)buf;
    while (n > 0) {
        ssize_t k = send(fd, p, n, MSG_NOSIGNAL);
        if (k < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        if (k == 0) return -1;
        p += k;
        n -= (size_t)k;
    }
    return 0;
}

static int write_all_fd(int fd, const void *buf, size_t n) {
    const unsigned char *p = (const unsigned char *)buf;
    while (n > 0) {
        ssize_t k = write(fd, p, n);
        if (k < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        if (k == 0) return -1;
        p += k;
        n -= (size_t)k;
    }
    return 0;
}

static void send_http_json(int fd, const char *status, const char *body) {
    char hdr[512];
    size_t blen = strlen(body);
    int n = snprintf(hdr, sizeof(hdr),
                     "HTTP/1.1 %s\r\n"
                     "Content-Type: application/json\r\n"
                     "Content-Length: %zu\r\n"
                     "Connection: close\r\n\r\n",
                     status, blen);
    if (n > 0 && (size_t)n < sizeof(hdr)) {
        (void)send_all(fd, hdr, (size_t)n);
        (void)send_all(fd, body, blen);
    }
}

static int parse_u64_strict(const char *s, uint64_t *out) {
    if (!s || !*s) return 0;
    for (const char *p = s; *p; p++) {
        if (!isdigit((unsigned char)*p)) return 0;
    }
    errno = 0;
    char *end = NULL;
    unsigned long long v = strtoull(s, &end, 10);
    if (errno != 0 || !end || *end != '\0') return 0;
    *out = (uint64_t)v;
    return 1;
}

static void handle_client(int cfd, const char *root) {
    struct timeval tv = {5, 0};
    (void)setsockopt(cfd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    (void)setsockopt(cfd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
#ifdef SO_NOSIGPIPE
    int one = 1;
    (void)setsockopt(cfd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
#endif

    char hdr_buf[MAX_HEADER_BYTES + 1];
    size_t hdr_used = 0;
    char *body_start = NULL;
    while (hdr_used < MAX_HEADER_BYTES) {
        ssize_t n = recv(cfd, hdr_buf + hdr_used, MAX_HEADER_BYTES - hdr_used, 0);
        if (n < 0) {
            if (errno == EINTR) continue;
            return;
        }
        if (n == 0) break;
        hdr_used += (size_t)n;
        hdr_buf[hdr_used] = '\0';
        char *sep = strstr(hdr_buf, "\r\n\r\n");
        if (sep) {
            body_start = sep + 4;
            *sep = '\0';
            break;
        }
        sep = strstr(hdr_buf, "\n\n");
        if (sep) {
            body_start = sep + 2;
            *sep = '\0';
            break;
        }
    }
    if (hdr_used == 0) return;
    if (!body_start) {
        send_http_json(cfd, "413 Payload Too Large", "{\"error\":\"headers\"}");
        return;
    }

    size_t hdr_consumed = (size_t)(body_start - hdr_buf);
    size_t already_body = hdr_used - hdr_consumed;

    int has_length = 0;
    uint64_t content_length = 0;
    uint64_t inode = 0;
    uint64_t offset = 0;
    char session[96] = "unknown";
    char name[96] = "unknown.log";
    char expected_sha[65] = "";

    char *saveptr = NULL;
    int line_no = 0;
    for (char *line = strtok_r(hdr_buf, "\n", &saveptr); line; line = strtok_r(NULL, "\n", &saveptr)) {
        size_t l = strlen(line);
        if (l > 0 && line[l - 1] == '\r') line[--l] = '\0';
        if (line_no++ == 0) continue; /* request line */
        char *colon = strchr(line, ':');
        if (!colon) continue;
        *colon = '\0';
        char *val = colon + 1;
        while (*val == ' ' || *val == '\t') val++;
        size_t vl = strlen(val);
        while (vl > 0 && (val[vl - 1] == ' ' || val[vl - 1] == '\t')) val[--vl] = '\0';

        if (strcasecmp(line, "Content-Length") == 0) {
            has_length = parse_u64_strict(val, &content_length);
        } else if (strcasecmp(line, "X-CMU-Session") == 0) {
            safe_component(val, session, sizeof(session), "unknown");
        } else if (strcasecmp(line, "X-CMU-File") == 0) {
            safe_component(val, name, sizeof(name), "unknown.log");
        } else if (strcasecmp(line, "X-CMU-Inode") == 0) {
            if (!parse_u64_strict(val, &inode)) inode = 0;
        } else if (strcasecmp(line, "X-CMU-Offset") == 0) {
            if (!parse_u64_strict(val, &offset)) offset = 0;
        } else if (strcasecmp(line, "X-CMU-SHA256") == 0) {
            size_t j = 0;
            for (size_t i = 0; val[i] && j < 64; i++) {
                if (isxdigit((unsigned char)val[i])) {
                    expected_sha[j++] = (char)tolower((unsigned char)val[i]);
                }
            }
            expected_sha[j] = '\0';
        }
    }

    if (!has_length) {
        send_http_json(cfd, "400 Bad Request", "{\"error\":\"content-length\"}");
        return;
    }
    if (content_length > MAX_CHUNK_BYTES) {
        send_http_json(cfd, "413 Payload Too Large", "{\"error\":\"chunk-too-large\"}");
        return;
    }
    if (strlen(expected_sha) != 64) {
        send_http_json(cfd, "400 Bad Request", "{\"error\":\"sha256\"}");
        return;
    }

    unsigned char body[MAX_CHUNK_BYTES];
    size_t body_len = (size_t)content_length;
    size_t copied = already_body < body_len ? already_body : body_len;
    if (copied > 0) memcpy(body, body_start, copied);
    while (copied < body_len) {
        ssize_t n = recv(cfd, body + copied, body_len - copied, 0);
        if (n < 0) {
            if (errno == EINTR) continue;
            send_http_json(cfd, "400 Bad Request", "{\"error\":\"body-read\"}");
            return;
        }
        if (n == 0) {
            send_http_json(cfd, "400 Bad Request", "{\"error\":\"body-short\"}");
            return;
        }
        copied += (size_t)n;
    }

    char actual_sha[65];
    sha_compute_hex(body, body_len, actual_sha);
    if (strcmp(actual_sha, expected_sha) != 0) {
        send_http_json(cfd, "400 Bad Request", "{\"error\":\"sha256-mismatch\"}");
        return;
    }

    time_t now = time(NULL);
    struct tm tm_local;
    localtime_r(&now, &tm_local);
    char day[16];
    strftime(day, sizeof(day), "%Y-%m-%d", &tm_local);

    char push_root[1024];
    char dir[1024];
    char target[1024];
    int n1 = snprintf(push_root, sizeof(push_root), "%s/%s/cmu-push", root, day);
    int n2 = snprintf(dir, sizeof(dir), "%s/%s", push_root, session);
    int n3 = snprintf(target, sizeof(target), "%s/%s.inode-%llu", dir, name, (unsigned long long)inode);
    if (n1 <= 0 || (size_t)n1 >= sizeof(push_root) ||
        n2 <= 0 || (size_t)n2 >= sizeof(dir) ||
        n3 <= 0 || (size_t)n3 >= sizeof(target)) {
        send_http_json(cfd, "500 Internal Server Error", "{\"error\":\"path\"}");
        return;
    }
    if (mkdir_p(dir, 0700) < 0) {
        send_http_json(cfd, "507 Insufficient Storage", "{\"error\":\"mkdir\"}");
        return;
    }

    uint64_t current = 0;
    struct stat st;
    if (stat(target, &st) == 0 && st.st_size >= 0) {
        current = (uint64_t)st.st_size;
    }
    uint64_t end = offset + (uint64_t)body_len;
    if (current == offset) {
        int tfd = open(target, O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (tfd < 0) {
            send_http_json(cfd, "507 Insufficient Storage", "{\"error\":\"open\"}");
            return;
        }
        int wrc = write_all_fd(tfd, body, body_len);
        close(tfd);
        if (wrc < 0) {
            send_http_json(cfd, "507 Insufficient Storage", "{\"error\":\"append\"}");
            return;
        }
        current = end;
    } else if (current >= end) {
        /* idempotent retry; bytes already present */
    } else {
        char resp[128];
        snprintf(resp, sizeof(resp), "{\"error\":\"offset-gap\",\"current_offset\":%llu}",
                 (unsigned long long)current);
        send_http_json(cfd, "409 Conflict", resp);
        return;
    }

    char manifest[1024];
    int nm = snprintf(manifest, sizeof(manifest), "%s/cmu-push-manifest.ndjson", push_root);
    if (nm > 0 && (size_t)nm < sizeof(manifest)) {
        char iso[32];
        utc_iso_now(iso, sizeof(iso));
        char mline[512];
        int ml = snprintf(mline, sizeof(mline),
                          "%s session=%s file=%s inode=%llu offset=%llu bytes=%zu sha256=%s\n",
                          iso, session, name, (unsigned long long)inode,
                          (unsigned long long)offset, body_len, actual_sha);
        if (ml > 0 && (size_t)ml < sizeof(mline)) {
            int mfd = open(manifest, O_WRONLY | O_CREAT | O_APPEND, 0600);
            if (mfd >= 0) {
                (void)write_all_fd(mfd, mline, (size_t)ml);
                close(mfd);
            }
        }
    }

    char resp[192];
    snprintf(resp, sizeof(resp), "{\"ack_offset\":%llu,\"sha256\":\"%s\"}",
             (unsigned long long)current, actual_sha);
    send_http_json(cfd, "200 OK", resp);
}

static int env_int(const char *name, int fallback, int min_v, int max_v) {
    const char *v = getenv(name);
    if (!v || !*v) return fallback;
    char *end = NULL;
    long x = strtol(v, &end, 10);
    if (!end || *end != '\0' || x < min_v || x > max_v) return fallback;
    return (int)x;
}

int main(void) {
    umask(077);
    signal(SIGPIPE, SIG_IGN);
    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);

    const char *root = getenv("GVM_CMU_PUSH_ROOT");
    if (!root || !*root) root = DEFAULT_ROOT;
    int port = env_int("GVM_CMU_PUSH_PORT", DEFAULT_PORT, 1, 65535);
    int retention_days = env_int("GVM_CMU_PUSH_RETENTION_DAYS", DEFAULT_RETENTION_DAYS, 0, 365);
    int announce_interval = env_int("GVM_CMU_PUSH_ANNOUNCE_INTERVAL", DEFAULT_ANNOUNCE_INTERVAL, 2, 300);
    int test_mode = env_int("GVM_CMU_PUSH_TEST_MODE", 0, 0, 1);
    const char *bind_override = getenv("GVM_CMU_PUSH_BIND");
    const char *cmu_ips = getenv("GVM_CMU_PUSH_CMU_IP");
    if (!cmu_ips || !*cmu_ips) cmu_ips = DEFAULT_CMU_IPS;

    if (mkdir_p(root, 0700) < 0) {
        fprintf(stderr, "gmaphud-cmu-log-receiver: cannot create root %s: %s\n", root, strerror(errno));
        return 1;
    }

    char no_ncm_path[1024];
    char status_path[1024];
    snprintf(no_ncm_path, sizeof(no_ncm_path), "%s/receiver-no-ncm.txt", root);
    snprintf(status_path, sizeof(status_path), "%s/receiver-status.txt", root);

    int lfd = -1;
    char active_ip[INET_ADDRSTRLEN] = "";
    unsigned int active_ifindex = 0;
    char session[96] = "";
    time_t last_announce = 0;
    time_t last_prune = 0;
    time_t last_no_ncm_write = 0;

    while (g_running) {
        time_t now = time(NULL);
        if (now - last_prune >= 3600) {
            prune_old_days(root, retention_days);
            last_prune = now;
        }

        char bind_ip[INET_ADDRSTRLEN] = "";
        unsigned int ifindex = 0;
        int has_ip = 0;
        if (test_mode) {
            snprintf(bind_ip, sizeof(bind_ip), "%s",
                     (bind_override && *bind_override) ? bind_override : "127.0.0.1");
            has_ip = 1;
        } else {
            has_ip = find_ncm_ip(bind_ip, &ifindex);
        }

        if (!has_ip) {
            if (lfd >= 0) {
                close(lfd);
                lfd = -1;
            }
            if (active_ip[0] != '\0' || last_no_ncm_write == 0 || now - last_no_ncm_write >= 60) {
                char iso[32];
                utc_iso_now(iso, sizeof(iso));
                char line[64];
                snprintf(line, sizeof(line), "%s\n", iso);
                write_status_file(no_ncm_path, line);
                char sline[128];
                snprintf(sline, sizeof(sline), "state=waiting_ncm updated=%s\n", iso);
                write_status_file(status_path, sline);
                last_no_ncm_write = now;
            }
            active_ip[0] = '\0';
            active_ifindex = 0;
            session[0] = '\0';
            last_announce = 0;
            for (int i = 0; i < 5 && g_running; i++) sleep(1);
            continue;
        }

        if (lfd < 0 || strcmp(bind_ip, active_ip) != 0 || ifindex != active_ifindex) {
            if (lfd >= 0) {
                close(lfd);
                lfd = -1;
            }
            lfd = open_listener(bind_ip, port, ifindex, test_mode);
            if (lfd < 0) {
                for (int i = 0; i < 2 && g_running; i++) sleep(1);
                continue;
            }
            snprintf(active_ip, sizeof(active_ip), "%s", bind_ip);
            active_ifindex = ifindex;
            struct tm tm_local;
            localtime_r(&now, &tm_local);
            char stamp[32];
            strftime(stamp, sizeof(stamp), "%Y%m%d-%H%M%S", &tm_local);
            snprintf(session, sizeof(session), "gmaphud-push-%s", stamp);
            last_announce = 0;
            char iso[32];
            utc_iso_now(iso, sizeof(iso));
            char sline[256];
            snprintf(sline, sizeof(sline),
                     "state=listening ip=%s port=%d ifindex=%u session=%s updated=%s\n",
                     active_ip, port, active_ifindex, session, iso);
            write_status_file(status_path, sline);
        }

        if (!test_mode && (last_announce == 0 || now - last_announce >= announce_interval)) {
            announce_once(active_ip, active_ifindex, session, cmu_ips);
            last_announce = now;
        }

        struct pollfd pfd;
        pfd.fd = lfd;
        pfd.events = POLLIN;
        pfd.revents = 0;
        int prc = poll(&pfd, 1, 2000);
        if (prc > 0 && (pfd.revents & POLLIN)) {
            int cfd = accept(lfd, NULL, NULL);
            if (cfd >= 0) {
                handle_client(cfd, root);
                close(cfd);
            }
        } else if (prc < 0 && errno != EINTR) {
            close(lfd);
            lfd = -1;
        }
    }

    if (lfd >= 0) close(lfd);
    return 0;
}
