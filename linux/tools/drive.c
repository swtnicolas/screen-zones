#include <libei.h>
#include <linux/input-event-codes.h>
#include <poll.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <systemd/sd-bus.h>
#include <time.h>
#include <unistd.h>

static struct ei *ei;
static struct ei_device *pointer;
static struct ei_device *keyboard;
static uint32_t sequence;

static void pump(int timeout) {
    struct pollfd fd = {.fd = ei_get_fd(ei), .events = POLLIN};
    if (poll(&fd, 1, timeout) > 0) ei_dispatch(ei);
    struct ei_event *event;
    while ((event = ei_get_event(ei))) {
        struct ei_device *device = ei_event_get_device(event);
        switch (ei_event_get_type(event)) {
        case EI_EVENT_SEAT_ADDED:
            ei_seat_bind_capabilities(ei_event_get_seat(event), EI_DEVICE_CAP_POINTER_ABSOLUTE, EI_DEVICE_CAP_BUTTON,
                                      EI_DEVICE_CAP_KEYBOARD, NULL);
            break;
        case EI_EVENT_DEVICE_RESUMED:
            if (!pointer && ei_device_has_capability(device, EI_DEVICE_CAP_POINTER_ABSOLUTE)) {
                pointer = ei_device_ref(device);
                ei_device_start_emulating(pointer, ++sequence);
            }
            if (!keyboard && ei_device_has_capability(device, EI_DEVICE_CAP_KEYBOARD)) {
                keyboard = ei_device_ref(device);
                ei_device_start_emulating(keyboard, ++sequence);
            }
            break;
        case EI_EVENT_DISCONNECT:
            fprintf(stderr, "drive: disconnected\n");
            exit(1);
        default:
            break;
        }
        ei_event_unref(event);
    }
}

static void pause_ms(int ms) {
    struct timespec end;
    clock_gettime(CLOCK_MONOTONIC, &end);
    end.tv_nsec += (long)ms * 1000000;
    end.tv_sec += end.tv_nsec / 1000000000;
    end.tv_nsec %= 1000000000;
    for (;;) {
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        long left = (end.tv_sec - now.tv_sec) * 1000 + (end.tv_nsec - now.tv_nsec) / 1000000;
        if (left <= 0) return;
        pump((int)left);
    }
}

static void move(double x, double y) {
    ei_device_pointer_motion_absolute(pointer, x, y);
    ei_device_frame(pointer, ei_now(ei));
    pause_ms(8);
}

static void button(uint32_t code, bool press) {
    ei_device_button_button(pointer, code, press);
    ei_device_frame(pointer, ei_now(ei));
    pause_ms(30);
}

static void key(uint32_t code) {
    ei_device_keyboard_key(keyboard, code, true);
    ei_device_frame(keyboard, ei_now(ei));
    pause_ms(15);
    ei_device_keyboard_key(keyboard, code, false);
    ei_device_frame(keyboard, ei_now(ei));
    pause_ms(15);
}

static uint32_t code_for(char c) {
    static const char *letters = "qwertyuiop\0\0\0\0asdfghjkl\0\0\0\0\0zxcvbnm";
    for (int i = 0; i < 35; i++)
        if (letters[i] == c) return KEY_Q + i;
    if (c >= '1' && c <= '9') return KEY_1 + (c - '1');
    if (c == '0') return KEY_0;
    if (c == ' ') return KEY_SPACE;
    return 0;
}

static uint32_t named(const char *name) {
    if (!strcmp(name, "enter")) return KEY_ENTER;
    if (!strcmp(name, "esc")) return KEY_ESC;
    if (!strcmp(name, "backspace")) return KEY_BACKSPACE;
    if (!strcmp(name, "down")) return KEY_DOWN;
    if (!strcmp(name, "right")) return KEY_RIGHT;
    if (!strcmp(name, "home")) return KEY_HOME;
    return (uint32_t)strtoul(name, NULL, 0);
}

int main(int argc, char **argv) {
    sd_bus *bus;
    sd_bus_message *reply = NULL;
    sd_bus_error error = SD_BUS_ERROR_NULL;
    if (sd_bus_open_user(&bus) < 0 ||
        sd_bus_call_method(bus, "org.kde.KWin", "/org/kde/KWin/EIS/RemoteDesktop", "org.kde.KWin.EIS.RemoteDesktop",
                           "connectToEIS", &error, &reply, "i", 3) < 0) {
        fprintf(stderr, "drive: connectToEIS failed: %s\n", error.message ? error.message : "no bus");
        return 1;
    }
    int fd, cookie;
    sd_bus_message_read(reply, "hi", &fd, &cookie);
    ei = ei_new_sender(NULL);
    ei_configure_name(ei, "screenzones-drive");
    if (ei_setup_backend_fd(ei, dup(fd)) < 0) {
        fprintf(stderr, "drive: EIS setup failed\n");
        return 1;
    }
    for (int i = 0; i < 200 && !(pointer && keyboard); i++) pump(10);
    if (!pointer || !keyboard) {
        fprintf(stderr, "drive: no devices\n");
        return 1;
    }
    pause_ms(50);
    for (int i = 1; i < argc; i++) {
        const char *op = argv[i];
        double a[5] = {0};
        int need = !strcmp(op, "move") || !strcmp(op, "click") || !strcmp(op, "rclick") || !strcmp(op, "dclick") ? 2
                 : !strcmp(op, "drag") ? 5 : !strcmp(op, "wait") ? 1 : 0;
        for (int j = 0; j < need && i + 1 < argc; j++) a[j] = atof(argv[++i]);
        if (!strcmp(op, "move")) move(a[0], a[1]);
        else if (!strcmp(op, "down")) button(BTN_LEFT, true);
        else if (!strcmp(op, "up")) button(BTN_LEFT, false);
        else if (!strcmp(op, "click")) { move(a[0], a[1]); pause_ms(100); button(BTN_LEFT, true); button(BTN_LEFT, false); }
        else if (!strcmp(op, "rclick")) { move(a[0], a[1]); pause_ms(100); button(BTN_RIGHT, true); button(BTN_RIGHT, false); }
        else if (!strcmp(op, "dclick")) {
            move(a[0], a[1]);
            pause_ms(100);
            for (int n = 0; n < 2; n++) { button(BTN_LEFT, true); button(BTN_LEFT, false); }
        } else if (!strcmp(op, "drag")) {
            int steps = a[4] > 0 ? (int)a[4] : 20;
            move(a[0], a[1]);
            pause_ms(100);
            button(BTN_LEFT, true);
            pause_ms(60);
            for (int s = 1; s <= steps; s++) move(a[0] + (a[2] - a[0]) * s / steps, a[1] + (a[3] - a[1]) * s / steps);
            pause_ms(60);
            button(BTN_LEFT, false);
        } else if (!strcmp(op, "wait")) pause_ms((int)a[0]);
        else if (!strcmp(op, "key") && i + 1 < argc) key(named(argv[++i]));
        else if (!strcmp(op, "type") && i + 1 < argc) {
            for (const char *c = argv[++i]; *c; c++) {
                uint32_t code = code_for(*c);
                if (code) key(code);
            }
        } else {
            fprintf(stderr, "drive: unknown command %s\n", op);
            return 1;
        }
    }
    pause_ms(50);
    ei_unref(ei);
    sd_bus_unref(bus);
    return 0;
}
