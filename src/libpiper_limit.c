#define _GNU_SOURCE
#include <unistd.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdlib.h>

#define LOG  "/home/phablet/.local/share/navius.woodyst/debug/piper_limit.log"
#define FLAG "/home/phablet/.local/share/navius.woodyst/debug/.traces_enabled"

static int traces_on(void) { return access(FLAG, F_OK) == 0; }

static void wlog(const char *msg) {
    if (!traces_on()) return;
    int fd = open(LOG, O_CREAT|O_WRONLY|O_APPEND, 0644);
    if (fd >= 0) { write(fd, msg, __builtin_strlen(msg)); close(fd); }
}

static void __attribute__((constructor)) piper_limit_init(void) {
    nice(10);
    if (!traces_on()) return;
    int fd = open(LOG, O_CREAT|O_WRONLY|O_TRUNC, 0644);
    if (fd >= 0) { write(fd, "loaded\n", 7); close(fd); }
}

typedef struct { void *(*fn)(void *); void *arg; } wrap_t;

static void *thread_nice(void *raw) {
    wrap_t *w = (wrap_t *)raw;
    void *(*fn)(void *) = w->fn;
    void *arg = w->arg;
    free(w);
    nice(10);
    return fn(arg);
}

int pthread_create(pthread_t *t, const pthread_attr_t *a,
                   void *(*fn)(void *), void *arg) {
    static int (*real)(pthread_t*, const pthread_attr_t*, void*(*)(void*), void*) = NULL;
    if (!real) real = dlsym(RTLD_NEXT, "pthread_create");
    wlog("pthread_create nice+10\n");
    wrap_t *w = malloc(sizeof(*w));
    if (!w) return real(t, a, fn, arg);
    w->fn = fn; w->arg = arg;
    return real(t, a, thread_nice, w);
}
