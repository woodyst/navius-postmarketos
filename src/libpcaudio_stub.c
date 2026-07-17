/* Stub libpcaudio.so.0 — no-ops because we use AUDIO_OUTPUT_SYNCHRONOUS */
typedef struct audio_object { int _dummy; } audio_object;
static audio_object _stub;

audio_object *create_audio_device_object(const char *d, const char *a, const char *b) { return &_stub; }
int  audio_object_open(audio_object *o, int fmt, int rate, int ch) { return 0; }
void audio_object_close(audio_object *o) {}
int  audio_object_write(audio_object *o, const char *data, int len) { return 0; }
int  audio_object_flush(audio_object *o) { return 0; }
int  audio_object_drain(audio_object *o) { return 0; }
void audio_object_destroy(audio_object *o) {}
const char *audio_object_strerror(audio_object *o, int e) { return ""; }
