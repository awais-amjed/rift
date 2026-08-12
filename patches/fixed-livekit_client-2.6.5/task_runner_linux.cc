#include "task_runner_linux.h"

#include <glib.h>

#include <utility>

namespace livekit_client_plugin {

TaskRunnerLinux::TaskRunnerLinux() : state_(std::make_shared<State>()) {}

TaskRunnerLinux::~TaskRunnerLinux() {
  // A callback already handed to the GMainContext cannot be withdrawn, so the
  // state is marked dead rather than cancelled: whatever arrives after this
  // point returns without touching the runner, which is gone.
  std::lock_guard<std::mutex> lock(state_->mutex);
  state_->alive = false;
  std::queue<TaskClosure> discarded;
  discarded.swap(state_->tasks);
}

void TaskRunnerLinux::EnqueueTask(TaskClosure task) {
  {
    std::lock_guard<std::mutex> lock(state_->mutex);
    if (!state_->alive) {
      return;
    }
    state_->tasks.push(std::move(task));
  }

  GMainContext* context = g_main_context_default();
  if (!context) {
    return;
  }

  // The callback carries a weak reference to the shared state, not a raw
  // `this`. GLib may run it long after the runner is destroyed.
  auto* weak_state = new std::weak_ptr<State>(state_);

  const GSourceFunc drain = [](gpointer user_data) -> gboolean {
    auto state = static_cast<std::weak_ptr<State>*>(user_data)->lock();
    if (!state) {
      return G_SOURCE_REMOVE;
    }

    // Take the queue under the lock, then run the tasks with it released. The
    // lock was previously held across task(), so any task that enqueued
    // another one deadlocked on a non-recursive mutex.
    std::queue<TaskClosure> pending;
    {
      std::lock_guard<std::mutex> lock(state->mutex);
      if (!state->alive) {
        return G_SOURCE_REMOVE;
      }
      pending.swap(state->tasks);
    }

    while (!pending.empty()) {
      TaskClosure task = std::move(pending.front());
      pending.pop();
      task();
    }
    return G_SOURCE_REMOVE;
  };

  const GDestroyNotify release = [](gpointer user_data) {
    delete static_cast<std::weak_ptr<State>*>(user_data);
  };

  g_main_context_invoke_full(context, G_PRIORITY_DEFAULT, drain, weak_state,
                             release);
}

}  // namespace livekit_client_plugin
