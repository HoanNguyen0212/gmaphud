#define _DEFAULT_SOURCE 1
#define _POSIX_C_SOURCE 200809L

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <netdb.h>
#include <net/if.h>
#include <netinet/in.h>
#include <poll.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#ifdef __linux__
#ifndef SO_BINDTODEVICE
#define SO_BINDTODEVICE 25
#endif
#endif
#ifdef __APPLE__
#ifndef IPV6_BOUND_IF
#define IPV6_BOUND_IF 125
#endif
#endif

#define RESPONSE_LIMIT (1024 * 1024)
#define DEFAULT_TIMEOUT_MS 1500
#define PROBE_FAILURE_IFACE 3
#define PROBE_FAILURE_SOCKET 4
#define PROBE_FAILURE_CONNECT 5
#define PROBE_FAILURE_SEND 6
#define PROBE_FAILURE_HTTP 7
#define PROBE_FAILURE_USAGE 2
#define AUTO_USB_FAILURE_SUBNET 9
#define AUTO_USB_FAILURE_MISSING 10

typedef struct {
    char interface_name[IFNAMSIZ];
    unsigned int interface_index;
    struct in_addr source_address;
    bool has_ipv4;
    struct in6_addr source_address6;
    bool has_ipv6_link_local;
} interface_choice_t;

static void usage(const char *program) {
    fprintf(stderr, "usage: %s --auto-usb --port PORT --path PATH --output FILE [--timeout-ms N]\n"
                    "       %s --interface IFACE --host IPV4 --port PORT --path PATH --output FILE [--timeout-ms N]\n",
            program, program);
}

static bool parse_port(const char *text, uint16_t *port) {
    char *end = NULL;
    errno = 0;
    long value = strtol(text, &end, 10);
    if (errno || !end || *end || value < 1 || value > 65535) return false;
    *port = (uint16_t)value;
    return true;
}

static bool parse_uint(const char *text, unsigned int *value) {
    char *end = NULL;
    errno = 0;
    unsigned long parsed = strtoul(text, &end, 10);
    if (errno || !end || *end || parsed == 0 || parsed > UINT32_MAX) return false;
    *value = (unsigned int)parsed;
    return true;
}

static bool choose_interface(const char *name, interface_choice_t *choice) {
    struct ifaddrs *addresses = NULL;
    if (getifaddrs(&addresses) != 0) return false;
    bool found = false;
    memset(choice, 0, sizeof(*choice));
    for (const struct ifaddrs *item = addresses; item; item = item->ifa_next) {
        if (!item->ifa_name || strcmp(item->ifa_name, name) != 0 || !item->ifa_addr) continue;
        if ((item->ifa_flags & (IFF_UP | IFF_RUNNING)) != (IFF_UP | IFF_RUNNING)) continue;
        if (item->ifa_addr->sa_family == AF_INET) {
            const struct sockaddr_in *address = (const struct sockaddr_in *)item->ifa_addr;
            choice->source_address = address->sin_addr;
            choice->has_ipv4 = true;
            found = true;
        } else if (item->ifa_addr->sa_family == AF_INET6) {
            const struct sockaddr_in6 *address6 = (const struct sockaddr_in6 *)item->ifa_addr;
            if (IN6_IS_ADDR_LINKLOCAL(&address6->sin6_addr)) {
                choice->source_address6 = address6->sin6_addr;
                choice->has_ipv6_link_local = true;
                found = true;
            }
        }
        if (!found) continue;
        unsigned int index = if_nametoindex(item->ifa_name);
        if (!index) continue;
        strncpy(choice->interface_name, name, sizeof(choice->interface_name) - 1);
        choice->interface_index = index;
        break;
    }
    freeifaddrs(addresses);
    return found;
}

static bool ipv4_on_subnet(uint32_t address, uint32_t network) {
    return (address & 0xffffff00U) == network;
}

static bool choose_usb_interface(interface_choice_t *choice, uint32_t required_subnet) {
    struct ifaddrs *addresses = NULL;
    if (getifaddrs(&addresses) != 0) return false;
    int best_score = 0;
    memset(choice, 0, sizeof(*choice));
    for (const struct ifaddrs *item = addresses; item; item = item->ifa_next) {
        if (!item->ifa_name || !item->ifa_addr || strncmp(item->ifa_name, "en", 2) != 0 ||
            strcmp(item->ifa_name, "en0") == 0) continue;
        if ((item->ifa_flags & (IFF_UP | IFF_RUNNING)) != (IFF_UP | IFF_RUNNING)) continue;
        unsigned int index = if_nametoindex(item->ifa_name);
        if (!index) continue;
        if (item->ifa_addr->sa_family == AF_INET) {
            const struct sockaddr_in *address = (const struct sockaddr_in *)item->ifa_addr;
            uint32_t host_order = ntohl(address->sin_addr.s_addr);
            int score = ipv4_on_subnet(host_order, required_subnet) ? 4 :
                        ((host_order & 0xffff0000U) == 0xa9fe0000U ? 2 : 0);
            if (score <= best_score) continue;
            strncpy(choice->interface_name, item->ifa_name, sizeof(choice->interface_name) - 1);
            choice->interface_index = index;
            choice->source_address = address->sin_addr;
            choice->has_ipv4 = true;
            choice->has_ipv6_link_local = false;
            best_score = score;
        } else if (item->ifa_addr->sa_family == AF_INET6 && best_score < 4) {
            const struct sockaddr_in6 *address6 = (const struct sockaddr_in6 *)item->ifa_addr;
            if (!IN6_IS_ADDR_LINKLOCAL(&address6->sin6_addr)) continue;
            if (best_score == 0 || strcmp(choice->interface_name, item->ifa_name) == 0) {
                strncpy(choice->interface_name, item->ifa_name, sizeof(choice->interface_name) - 1);
                choice->interface_index = index;
                choice->source_address6 = address6->sin6_addr;
                choice->has_ipv6_link_local = true;
            }
        }
    }
    freeifaddrs(addresses);
    if (!choice->interface_index || (!choice->has_ipv4 && !choice->has_ipv6_link_local)) {
        fprintf(stderr, "error=no_active_usb_ncm_interface\\n");
        return false;
    }
    if (choice->has_ipv4) {
        char source_text[INET_ADDRSTRLEN] = {0};
        inet_ntop(AF_INET, &choice->source_address, source_text, sizeof(source_text));
        fprintf(stderr, "usb_interface=%s index=%u source=%s\\n", choice->interface_name, choice->interface_index, source_text);
    } else {
        char source_text[INET6_ADDRSTRLEN] = {0};
        inet_ntop(AF_INET6, &choice->source_address6, source_text, sizeof(source_text));
        fprintf(stderr, "usb_interface=%s index=%u source_v6=%s\\n", choice->interface_name, choice->interface_index, source_text);
    }
    return true;
}

static bool safe_http_token(const char *text, bool path) {
    if (!text || !*text) return false;
    for (const unsigned char *cursor = (const unsigned char *)text; *cursor; ++cursor) {
        if (*cursor <= 0x20 || *cursor >= 0x7f || *cursor == '\r' || *cursor == '\n') return false;
        if (path && *cursor == '#') return false;
    }
    return true;
}

static int set_timeout(int fd, unsigned int timeout_ms) {
    struct timeval timeout = {
        .tv_sec = (time_t)(timeout_ms / 1000),
        .tv_usec = (suseconds_t)((timeout_ms % 1000) * 1000),
    };
    if (setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)) != 0) return -1;
    if (setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout)) != 0) return -1;
    return 0;
}

static int receive_response(int fd, const char *output_path, long *status_code,
                            size_t *body_bytes, bool *listener_marker) {
    char *response = calloc(1, RESPONSE_LIMIT + 1);
    if (!response) return -1;
    size_t received = 0;
    while (received < RESPONSE_LIMIT) {
        ssize_t count = recv(fd, response + received, RESPONSE_LIMIT - received, 0);
        if (count == 0) break;
        if (count < 0) {
            if (errno == EINTR) continue;
            if (errno == EAGAIN || errno == EWOULDBLOCK) break;
            perror("recv"); free(response); return -1;
        }
        received += (size_t)count;
    }
    response[received] = '\0';
    char *separator = strstr(response, "\r\n\r\n");
    size_t separator_length = 4;
    if (!separator) { separator = strstr(response, "\n\n"); separator_length = 2; }
    if (!separator) {
        fprintf(stderr, "http_error=missing_header_separator bytes=%zu\n", received);
        free(response); return -1;
    }
    *separator = '\0';
    char *body = separator + separator_length;
    *status_code = 0;
    char *line_end = strchr(response, '\n');
    if (line_end) *line_end = '\0';
    if (sscanf(response, "HTTP/%*u.%*u %ld", status_code) != 1) {
        fprintf(stderr, "http_error=invalid_status_line\n"); free(response); return -1;
    }
    size_t body_length = received - (size_t)(body - response);
    *body_bytes = body_length;
    *listener_marker = strstr(body, "MAZDA CMU TELEMETRY LISTENER STATUS") != NULL;
    fprintf(stderr, "http_status=%ld body_bytes=%zu listener_marker=%s truncated=%s\n",
            *status_code, body_length, *listener_marker ? "yes" : "no",
            received == RESPONSE_LIMIT ? "yes" : "no");
    if (*status_code != 200) { free(response); return -1; }
    if (!body_length) { fprintf(stderr, "http_error=empty_body\n"); free(response); return -1; }
    if (!*listener_marker) { fprintf(stderr, "http_error=cmu_listener_marker_missing\n"); free(response); return -1; }
    FILE *file = fopen(output_path, "wb");
    if (!file) { perror("fopen output"); free(response); return -1; }
    size_t written = fwrite(body, 1, body_length, file);
    bool failed = written != body_length || fflush(file) != 0 || fsync(fileno(file)) != 0;
    if (fclose(file) != 0) failed = true;
    if (failed) { perror("write output"); unlink(output_path); free(response); return -1; }
    free(response);
    return 0;
}

static int connect_with_timeout(int fd, const struct sockaddr *destination, socklen_t destination_length,
                                unsigned int timeout_ms) {
    int original_flags = fcntl(fd, F_GETFL, 0);
    if (original_flags < 0 || fcntl(fd, F_SETFL, original_flags | O_NONBLOCK) != 0) return -1;
    int result = connect(fd, destination, destination_length);
    if (result == 0) {
        (void)fcntl(fd, F_SETFL, original_flags);
        return 0;
    }
    if (errno != EINPROGRESS && errno != EWOULDBLOCK) {
        int saved_errno = errno;
        (void)fcntl(fd, F_SETFL, original_flags);
        errno = saved_errno;
        return -1;
    }
    struct pollfd descriptor = {.fd = fd, .events = POLLOUT};
    int ready;
    do { ready = poll(&descriptor, 1, (int)timeout_ms); } while (ready < 0 && errno == EINTR);
    if (ready <= 0) {
        int saved_errno = ready == 0 ? ETIMEDOUT : errno;
        (void)fcntl(fd, F_SETFL, original_flags);
        errno = saved_errno;
        return -1;
    }
    int socket_error = 0;
    socklen_t error_length = sizeof(socket_error);
    if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &socket_error, &error_length) != 0) {
        int saved_errno = errno;
        (void)fcntl(fd, F_SETFL, original_flags);
        errno = saved_errno;
        return -1;
    }
    (void)fcntl(fd, F_SETFL, original_flags);
    if (socket_error) { errno = socket_error; return -1; }
    return 0;
}

static int open_bound_socket(int family, const interface_choice_t *choice, bool direct_route, unsigned int timeout_ms) {
    int fd = socket(family, SOCK_STREAM, 0);
    if (fd < 0) { perror("socket"); return -1; }
    if (set_timeout(fd, timeout_ms) != 0) { perror("setsockopt timeout"); close(fd); return -1; }
#ifdef __APPLE__
    int no_sigpipe = 1;
    if (setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &no_sigpipe, sizeof(no_sigpipe)) != 0) {
        perror("SO_NOSIGPIPE"); close(fd); return -1;
    }
    if (direct_route) {
        int one = 1;
        if (setsockopt(fd, SOL_SOCKET, SO_DONTROUTE, &one, sizeof(one)) != 0) {
            perror("SO_DONTROUTE"); close(fd); return -1;
        }
    }
    if (family == AF_INET) {
        if (setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &choice->interface_index,
                       sizeof(choice->interface_index)) != 0) {
            fprintf(stderr, "interface=%s error=bind_ipv4 errno=%d (%s)\n", choice->interface_name, errno, strerror(errno));
            close(fd); return -1;
        }
    } else {
        int index = (int)choice->interface_index;
        if (setsockopt(fd, IPPROTO_IPV6, IPV6_BOUND_IF, &index, sizeof(index)) != 0) {
            fprintf(stderr, "interface=%s error=bind_ipv6 errno=%d (%s)\n", choice->interface_name, errno, strerror(errno));
            close(fd); return -1;
        }
    }
#endif
#ifdef __linux__
    if (setsockopt(fd, SOL_SOCKET, SO_BINDTODEVICE, choice->interface_name,
                   (socklen_t)(strlen(choice->interface_name) + 1)) != 0) {
        fprintf(stderr, "interface=%s error=bind errno=%d (%s)\n", choice->interface_name, errno, strerror(errno));
        close(fd); return -1;
    }
    if (direct_route) {
        int one = 1;
        if (setsockopt(fd, SOL_SOCKET, SO_DONTROUTE, &one, sizeof(one)) != 0) {
            perror("SO_DONTROUTE"); close(fd); return -1;
        }
    }
#endif
    return fd;
}

static int send_request(int fd, const char *path, const char *output_path, const char *hostname) {
    char request[1024];
    int request_length = snprintf(request, sizeof(request),
                                  "GET %s HTTP/1.0\r\nHost: %s\r\nConnection: close\r\n\r\n", path, hostname);
    if (request_length <= 0 || (size_t)request_length >= sizeof(request)) {
        fprintf(stderr, "error=request_too_large\n"); return PROBE_FAILURE_USAGE;
    }
    size_t sent = 0;
    while (sent < (size_t)request_length) {
        ssize_t count = send(fd, request + sent, (size_t)request_length - sent, 0);
        if (count < 0) { if (errno == EINTR) continue; perror("send"); return PROBE_FAILURE_SEND; }
        if (count == 0) { fprintf(stderr, "send_error=zero_write\n"); return PROBE_FAILURE_SEND; }
        sent += (size_t)count;
    }
    long status = 0; size_t bytes = 0; bool marker = false;
    if (receive_response(fd, output_path, &status, &bytes, &marker) != 0) return PROBE_FAILURE_HTTP;
    fprintf(stderr, "result=success endpoint=%s bytes=%zu\n", path, bytes);
    return 0;
}

static int probe_ipv4(const interface_choice_t *choice, const char *host, uint16_t port,
                      const char *path, const char *output_path, unsigned int timeout_ms,
                      bool direct_route) {
    struct in_addr target;
    if (!choice->has_ipv4 || inet_pton(AF_INET, host, &target) != 1) return PROBE_FAILURE_CONNECT;
    int fd = open_bound_socket(AF_INET, choice, direct_route, timeout_ms);
    if (fd < 0) return PROBE_FAILURE_SOCKET;
    struct sockaddr_in source = {.sin_family = AF_INET, .sin_addr = choice->source_address};
#ifdef __APPLE__
    source.sin_len = (uint8_t)sizeof(source);
#endif
    if (bind(fd, (struct sockaddr *)&source, sizeof(source)) != 0) {
        fprintf(stderr, "interface=%s error=bind_source errno=%d (%s)\n", choice->interface_name, errno, strerror(errno));
        close(fd); return PROBE_FAILURE_SOCKET;
    }
    char source_text[INET_ADDRSTRLEN] = {0};
    inet_ntop(AF_INET, &choice->source_address, source_text, sizeof(source_text));
    fprintf(stderr, "transport=ipv4 interface=%s index=%u source=%s target=%s:%u direct_route=%s\n",
            choice->interface_name, choice->interface_index, source_text, host, port, direct_route ? "yes" : "no");
    struct sockaddr_in destination = {.sin_family = AF_INET, .sin_port = htons(port), .sin_addr = target};
#ifdef __APPLE__
    destination.sin_len = (uint8_t)sizeof(destination);
#endif
    if (connect_with_timeout(fd, (const struct sockaddr *)&destination, sizeof(destination), timeout_ms) != 0) {
        fprintf(stderr, "connect_error_ipv4=errno_%d (%s)\n", errno, strerror(errno)); close(fd); return PROBE_FAILURE_CONNECT;
    }
    int result = send_request(fd, path, output_path, host);
    close(fd);
    return result;
}

static int probe_ipv6(const interface_choice_t *choice, const char *hostname, uint16_t port,
                      const char *path, const char *output_path, unsigned int timeout_ms) {
    struct addrinfo hints = {0};
    hints.ai_family = AF_INET6;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;
    struct addrinfo *addresses = NULL;
    int gai = getaddrinfo(hostname, NULL, &hints, &addresses);
    if (gai != 0) { fprintf(stderr, "ipv6_resolve_error=%s\n", gai_strerror(gai)); return PROBE_FAILURE_CONNECT; }
    int final_rc = PROBE_FAILURE_CONNECT;
    for (struct addrinfo *item = addresses; item; item = item->ai_next) {
        if (item->ai_family != AF_INET6 || item->ai_addrlen < sizeof(struct sockaddr_in6)) continue;
        struct sockaddr_in6 destination = *(const struct sockaddr_in6 *)item->ai_addr;
        destination.sin6_port = htons(port);
        if (IN6_IS_ADDR_LINKLOCAL(&destination.sin6_addr)) destination.sin6_scope_id = choice->interface_index;
#ifdef __APPLE__
        destination.sin6_len = (uint8_t)sizeof(destination);
#endif
        char address_text[INET6_ADDRSTRLEN] = {0};
        inet_ntop(AF_INET6, &destination.sin6_addr, address_text, sizeof(address_text));
        int fd = open_bound_socket(AF_INET6, choice, false, timeout_ms);
        if (fd < 0) { final_rc = PROBE_FAILURE_SOCKET; continue; }
        if (choice->has_ipv6_link_local && IN6_IS_ADDR_LINKLOCAL(&destination.sin6_addr)) {
            struct sockaddr_in6 source = {0};
#ifdef __APPLE__
            source.sin6_len = (uint8_t)sizeof(source);
#endif
            source.sin6_family = AF_INET6;
            source.sin6_addr = choice->source_address6;
            source.sin6_scope_id = choice->interface_index;
            if (bind(fd, (struct sockaddr *)&source, sizeof(source)) != 0) {
                fprintf(stderr, "interface=%s error=bind_source_ipv6 errno=%d (%s)\n", choice->interface_name, errno, strerror(errno));
                close(fd); final_rc = PROBE_FAILURE_SOCKET; continue;
            }
        }
        fprintf(stderr, "transport=ipv6 interface=%s index=%u target=[%s%%%s]:%u\n",
                choice->interface_name, choice->interface_index, address_text,
                destination.sin6_scope_id ? choice->interface_name : "global", port);
        if (connect_with_timeout(fd, (const struct sockaddr *)&destination, sizeof(destination), timeout_ms) != 0) {
            fprintf(stderr, "connect_error_ipv6=errno_%d (%s)\n", errno, strerror(errno)); close(fd); continue;
        }
        int result = send_request(fd, path, output_path, hostname);
        close(fd);
        if (result == 0) { freeaddrinfo(addresses); return 0; }
        final_rc = result;
    }
    freeaddrinfo(addresses);
    return final_rc;
}

static int probe(const interface_choice_t *choice, const char *host, uint16_t port,
                 const char *path, const char *output_path, unsigned int timeout_ms, bool auto_usb) {
    int result = PROBE_FAILURE_CONNECT;
    struct in_addr ipv4_test;
    if (host && inet_pton(AF_INET, host, &ipv4_test) == 1) {
        result = probe_ipv4(choice, host, port, path, output_path, timeout_ms, auto_usb);
    } else if (host) {
        result = probe_ipv6(choice, host, port, path, output_path, timeout_ms);
    }
    if (result == 0 || !auto_usb) return result;
    int v6_result = probe_ipv6(choice, "cmu.local", port, path, output_path, timeout_ms);
    return v6_result;
}

int main(int argc, char **argv) {
    const char *interface = NULL, *host = NULL, *path = NULL, *output_path = NULL;
    uint16_t port = 0;
    unsigned int timeout_ms = DEFAULT_TIMEOUT_MS;
    bool auto_usb = false;
    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--auto-usb") == 0) auto_usb = true;
        else if (strcmp(argv[i], "--interface") == 0 && i + 1 < argc) interface = argv[++i];
        else if (strcmp(argv[i], "--host") == 0 && i + 1 < argc) host = argv[++i];
        else if (strcmp(argv[i], "--path") == 0 && i + 1 < argc) path = argv[++i];
        else if (strcmp(argv[i], "--output") == 0 && i + 1 < argc) output_path = argv[++i];
        else if (strcmp(argv[i], "--port") == 0 && i + 1 < argc) {
            if (!parse_port(argv[++i], &port)) { usage(argv[0]); return PROBE_FAILURE_USAGE; }
        } else if (strcmp(argv[i], "--timeout-ms") == 0 && i + 1 < argc) {
            if (!parse_uint(argv[++i], &timeout_ms)) { usage(argv[0]); return PROBE_FAILURE_USAGE; }
        } else { usage(argv[0]); return PROBE_FAILURE_USAGE; }
    }
    if (!path || !output_path || !port || path[0] != '/' || !safe_http_token(path, true) ||
        (auto_usb ? (interface || host) : (!interface || !host))) {
        usage(argv[0]); return PROBE_FAILURE_USAGE;
    }
    interface_choice_t choice;
    uint32_t required_subnet = ntohl(inet_addr("192.168.53.0"));
    if (auto_usb) {
        if (!choose_usb_interface(&choice, required_subnet)) return AUTO_USB_FAILURE_MISSING;
        int result = probe(&choice, "192.168.53.1", port, path, output_path, timeout_ms, true);
        return result;
    }
    if (!choose_interface(interface, &choice)) {
        fprintf(stderr, "interface=%s error=not_active_ipv4_or_ipv6\\n", interface);
        return PROBE_FAILURE_IFACE;
    }
    return probe(&choice, host, port, path, output_path, timeout_ms, false);
}
