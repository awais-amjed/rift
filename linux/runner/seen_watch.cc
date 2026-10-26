#include "seen_watch.h"

#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#include <wayland-client.h>
#endif

namespace rift {
namespace {

#ifdef GDK_WINDOWING_WAYLAND

// How often the watch looks.
constexpr guint kTickMs = 500;
// A frame asked for and not given for this long: nobody can see Rift.
constexpr gint64 kUnseenAfterUs = 1500 * G_TIME_SPAN_MILLISECOND;
// Two frames given this close together: Rift can be seen again.
constexpr gint64 kSeenPairUs = 600 * G_TIME_SPAN_MILLISECOND;

struct Watch {
  GtkWidget* window = nullptr;
  FlEventChannel* channel = nullptr;
  guint timer = 0;
  wl_callback* frame = nullptr;
  gint64 asked = 0;
  gint64 last_given = 0;
  bool seen = true;
  bool reported = false;
};

Watch watch;

void Report(bool seen) {
  if (watch.reported && watch.seen == seen) return;
  watch.seen = seen;
  watch.reported = true;
  g_autoptr(FlValue) value = fl_value_new_bool(seen);
  g_autoptr(GError) error = nullptr;
  if (!fl_event_channel_send(watch.channel, value, nullptr, &error)) {
    g_warning("rift/window_seen: %s", error->message);
  }
}

void AskForFrame();

void OnFrame(void*, wl_callback* frame, uint32_t) {
  wl_callback_destroy(frame);
  watch.frame = nullptr;
  gint64 now = g_get_monotonic_time();
  if (watch.seen) {
    if (!watch.reported) Report(true);
  } else if (now - watch.last_given < kSeenPairUs) {
    Report(true);
  } else {
    // Perhaps GNOME's one frame for a hidden window; ask again at once, and
    // a second soon after says Rift is back.
    AskForFrame();
  }
  watch.last_given = now;
}

const wl_callback_listener kFrameListener = {OnFrame};

// The request goes out with the window's next commit, so a pixel is
// repainted to make one: an idle Rift commits nothing, and a request
// nothing carries is never answered.
void AskForFrame() {
  GdkWindow* window = gtk_widget_get_window(watch.window);
  if (!window || watch.frame) return;
  wl_surface* surface = gdk_wayland_window_get_wl_surface(window);
  if (!surface) return;
  watch.frame = wl_surface_frame(surface);
  wl_callback_add_listener(watch.frame, &kFrameListener, nullptr);
  watch.asked = g_get_monotonic_time();
  GdkRectangle pixel = {0, 0, 1, 1};
  gdk_window_invalidate_rect(window, &pixel, FALSE);
}

gboolean OnTick(gpointer) {
  if (!gtk_widget_get_mapped(watch.window)) {
    Report(false);  // In the tray, or started there.
  } else if (!watch.frame) {
    AskForFrame();
  } else if (g_get_monotonic_time() - watch.asked > kUnseenAfterUs) {
    Report(false);
  }
  return G_SOURCE_CONTINUE;
}

// Hiding the window to the tray destroys its surface, and the request with
// it; once it is shown, the next tick asks on the new one.
void OnUnmap(GtkWidget*, gpointer) {
  g_clear_pointer(&watch.frame, wl_callback_destroy);
  if (watch.timer) Report(false);
}

void Stop() {
  g_clear_handle_id(&watch.timer, g_source_remove);
  g_clear_pointer(&watch.frame, wl_callback_destroy);
}

FlMethodErrorResponse* OnListen(FlEventChannel*, FlValue*, gpointer) {
  if (!GDK_IS_WAYLAND_DISPLAY(gdk_display_get_default())) return nullptr;
  Stop();
  watch.seen = true;
  watch.reported = false;
  AskForFrame();
  watch.timer = g_timeout_add(kTickMs, OnTick, nullptr);
  return nullptr;
}

FlMethodErrorResponse* OnCancel(FlEventChannel*, FlValue*, gpointer) {
  Stop();
  return nullptr;
}

#else

FlMethodErrorResponse* OnListen(FlEventChannel*, FlValue*, gpointer) {
  return nullptr;
}

FlMethodErrorResponse* OnCancel(FlEventChannel*, FlValue*, gpointer) {
  return nullptr;
}

#endif

}  // namespace

void WatchSeen(GtkWindow* window, FlView* view) {
  FlBinaryMessenger* messenger =
      fl_engine_get_binary_messenger(fl_view_get_engine(view));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlEventChannel* channel = fl_event_channel_new(
      messenger, "rift/window_seen", FL_METHOD_CODEC(codec));
#ifdef GDK_WINDOWING_WAYLAND
  watch.window = GTK_WIDGET(window);
  watch.channel = channel;
  g_signal_connect(window, "unmap", G_CALLBACK(OnUnmap), nullptr);
#endif
  fl_event_channel_set_stream_handlers(channel, OnListen, OnCancel, nullptr,
                                       nullptr);
}

}  // namespace rift
