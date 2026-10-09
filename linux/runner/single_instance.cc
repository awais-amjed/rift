#include "single_instance.h"

#include <gio/gunixsocketaddress.h>
#include <glib/gstdio.h>
#include <string.h>
#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif

namespace rift {
namespace {

// The longest activation token taken from a later launch.
constexpr gsize kTokenMax = 512;

// The running copy's listener, for the life of the process.
GSocketService* service = nullptr;
GtkWindow* listening_window = nullptr;

// `com.codingfries.rift.<profile>.sock` in the runtime directory, which only
// this user can reach.
gchar* SocketPath() {
  const gchar* profile = g_getenv("RIFT_PROFILE");
  if (profile == nullptr || *profile == '\0') {
#ifdef NDEBUG
    profile = "";
#else
    profile = "dev";
#endif
  }
  g_autofree gchar* name =
      g_strdup_printf("%s.%s.sock", APPLICATION_ID, profile);
  g_strdelimit(name, "/", '_');
  return g_build_filename(g_get_user_runtime_dir(), name, nullptr);
}

// What the desktop gave this launch to bring a window forward with: GNOME
// on Wayland refuses focus to a window that asks without one.
const gchar* LaunchToken() {
  const gchar* token = g_getenv("XDG_ACTIVATION_TOKEN");
  if (token == nullptr || *token == '\0') token = g_getenv("DESKTOP_STARTUP_ID");
  return token != nullptr ? token : "";
}

// Asks the copy listening at |address| to show itself. False when nothing
// listens there.
bool HandOver(GSocketAddress* address) {
  g_autoptr(GSocketClient) client = g_socket_client_new();
  g_socket_client_set_timeout(client, 2);
  g_autoptr(GSocketConnection) connection = g_socket_client_connect(
      client, G_SOCKET_CONNECTABLE(address), nullptr, nullptr);
  if (connection == nullptr) return false;
  const gchar* token = LaunchToken();
  GOutputStream* out = g_io_stream_get_output_stream(G_IO_STREAM(connection));
  g_output_stream_write_all(out, token, strlen(token), nullptr, nullptr,
                            nullptr);
  g_io_stream_close(G_IO_STREAM(connection), nullptr, nullptr);
  return true;
}

void Show(GtkWindow* window, const gchar* token) {
  if (*token != '\0') {
#ifdef GDK_WINDOWING_WAYLAND
    GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
    if (GDK_IS_WAYLAND_DISPLAY(display)) {
      gdk_wayland_display_set_startup_notification_id(display, token);
    } else {
      gtk_window_set_startup_id(window, token);
    }
#else
    gtk_window_set_startup_id(window, token);
#endif
  }
  // Shows a window hidden in the tray as well as raising one behind others.
  gtk_window_present(window);
}

gboolean OnLaunch(GSocketService* /*service*/, GSocketConnection* connection,
                  GObject* /*source*/, gpointer /*data*/) {
  // The launch writes its token and closes at once; one that does not is
  // given up on rather than left holding the UI thread.
  g_socket_set_timeout(g_socket_connection_get_socket(connection), 1);
  gchar token[kTokenMax + 1];
  gsize length = 0;
  g_input_stream_read_all(g_io_stream_get_input_stream(G_IO_STREAM(connection)),
                          token, kTokenMax, &length, nullptr, nullptr);
  token[length] = '\0';
  if (listening_window != nullptr) Show(listening_window, token);
  return TRUE;
}

}  // namespace

bool AcquireSingleInstance() {
  g_autofree gchar* path = SocketPath();
  g_autoptr(GSocketAddress) address = g_unix_socket_address_new(path);
  if (HandOver(address)) return false;

  // Nothing listening: no file, or one left by a copy that did not exit
  // cleanly, which would stop this one listening.
  g_unlink(path);
  service = g_socket_service_new();
  g_autoptr(GError) error = nullptr;
  if (!g_socket_listener_add_address(G_SOCKET_LISTENER(service), address,
                                     G_SOCKET_TYPE_STREAM,
                                     G_SOCKET_PROTOCOL_DEFAULT, nullptr,
                                     nullptr, &error)) {
    g_warning("A later launch will not reach this copy: %s", error->message);
    g_clear_object(&service);
    return true;
  }
  g_signal_connect(service, "incoming", G_CALLBACK(OnLaunch), nullptr);
  return true;
}

void ListenForLaunches(GtkWindow* window) { listening_window = window; }

}  // namespace rift
